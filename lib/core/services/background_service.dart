import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import '../storage/secure_storage.dart';
import '../storage/cache_storage.dart';
import 'notification_service.dart';

const String taskWishlistBackgroundCheck = 'valapp_background_wishlist_check';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint('[BackgroundService] task: $task');
    if (task == taskWishlistBackgroundCheck ||
        task == Workmanager.iOSBackgroundTask) {
      try {
        await BackgroundShopChecker().runCheck();
        return true;
      } catch (e) {
        debugPrint('[BackgroundService] error: $e');
        return false;
      }
    }
    return true;
  });
}

class BackgroundService {
  BackgroundService._();
  static final instance = BackgroundService._();
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: kDebugMode,
      );
      await Workmanager().registerPeriodicTask(
        'valapp_wishlist_periodic_task',
        taskWishlistBackgroundCheck,
        frequency: const Duration(hours: 3),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );
      _isInitialized = true;
    } catch (e) {
      debugPrint('[BackgroundService] init error: $e');
    }
  }
}

/// Performs the background shop check:
/// 1. Fetches the live storefront
/// 2. Resolves skin names + actual prices
/// 3. Fires wishlist match notification if any matched
/// 4. Fires shop reset notification when the shop changes
class BackgroundShopChecker {
  final Dio _dio = Dio();

  static const _vpCurrencyId = '85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741';
  static const _lastShopKey = 'background_last_shop_ids';

  Future<void> runCheck() async {
    final storage = SecureStorage.instance;
    final cache = CacheStorage.instance;

    final accessToken = await storage.read(SecureStorage.keyAccessToken);
    final entitlementToken =
        await storage.read(SecureStorage.keyEntitlementToken);
    final puuid = await storage.read(SecureStorage.keyPuuid);
    final shard = await storage.read(SecureStorage.keyShard);

    if (accessToken == null ||
        entitlementToken == null ||
        puuid == null ||
        shard == null) {
      return;
    }

    // ── Fetch storefront ────────────────────────────────────────────────────
    final Map<String, dynamic> storefront;
    try {
      final resp = await _dio.post<dynamic>(
        'https://pd.$shard.a.pvp.net/store/v2/storefront/$puuid',
        options: Options(headers: {
          'Authorization': 'Bearer $accessToken',
          'X-Riot-Entitlements-JWT': entitlementToken,
          'Content-Type': 'application/json',
        }),
        data: {},
      );
      final raw = resp.data;
      if (raw is Map<String, dynamic>) {
        storefront = raw;
      } else if (raw is String) {
        storefront = jsonDecode(raw) as Map<String, dynamic>;
      } else {
        return;
      }
    } catch (_) {
      return;
    }

    // ── Extract offers with prices ──────────────────────────────────────────
    final skinPanel =
        storefront['SkinsPanelLayout'] as Map<String, dynamic>? ?? {};
    final offerIds =
        (skinPanel['SingleItemOffers'] as List<dynamic>?)
            ?.cast<String>() ?? [];
    final storeOffers =
        skinPanel['SingleItemStoreOffers'] as List<dynamic>? ?? [];

    // Build price map: offerId → price
    final priceMap = <String, int>{};
    for (final o in storeOffers) {
      if (o is! Map) continue;
      final oid = o['OfferID'] as String?;
      if (oid == null) continue;
      final cost = o['Cost'] as Map<String, dynamic>? ?? {};
      final price = (cost[_vpCurrencyId] as num?)?.toInt() ?? 0;
      priceMap[oid] = price;
    }

    if (offerIds.isEmpty) return;

    // ── Detect shop reset ───────────────────────────────────────────────────
    final lastShopRaw = await cache.getJson(_lastShopKey);
    final lastOffers =
        (lastShopRaw?['ids'] as List<dynamic>?)?.cast<String>() ?? [];
    final isNewShop = !_setsEqual(offerIds.toSet(), lastOffers.toSet());

    // ── Resolve skin names from valorant-api.com ────────────────────────────
    final skinNameMap = await _buildSkinNameMap(cache);

    final wishlist = await cache.getWishlist();

    // ── Fire notifications ─────────────────────────────────────────────────

    // Wishlist matches
    final matchedOffers = offerIds
        .where((id) => wishlist.contains(id))
        .toList();
    for (final id in matchedOffers) {
      final name = skinNameMap[id] ?? 'Wishlist Skin';
      final price = priceMap[id] ?? 0;
      await NotificationService.instance.showWishlistAlert(
        skinName: name,
        price: price,
      );
    }

    // Shop reset — fire once per new rotation
    if (isNewShop) {
      final skinNames = offerIds
          .map((id) => skinNameMap[id] ?? id.substring(0, 8))
          .toList();
      await NotificationService.instance.showShopResetAlert(
        skinNames: skinNames,
        wishlistMatchCount: matchedOffers.length,
      );
      // Save current offer IDs so we don't re-notify for same shop
      await cache.setJson(_lastShopKey, {'ids': offerIds});
    }
  }

  bool _setsEqual(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }

  Future<Map<String, String>> _buildSkinNameMap(CacheStorage cache) async {
    // Try local cache first
    const keyNames = 'skin_name_map_bg';
    const keyNamesFetchedAt = 'skin_name_map_bg_fetched_at';
    final isStale =
        await cache.isStale(keyNamesFetchedAt, const Duration(hours: 24));
    if (!isStale) {
      final cached = await cache.getJson(keyNames);
      if (cached != null) {
        return cached.map((k, v) => MapEntry(k, v.toString()));
      }
    }
    try {
      final resp = await _dio
          .get<Map<String, dynamic>>('https://valorant-api.com/v1/weapons/skins');
      final skins = resp.data?['data'] as List<dynamic>? ?? [];
      final map = <String, String>{};
      for (final skin in skins) {
        final name = skin['displayName'] as String? ?? '';
        final levels = skin['levels'] as List<dynamic>? ?? [];
        for (final lvl in levels) {
          final uuid = lvl['uuid'] as String?;
          if (uuid != null) map[uuid] = name;
        }
      }
      await cache.setJson(keyNames, map);
      await cache.setTimestamp(keyNamesFetchedAt);
      return map;
    } catch (_) {
      return {};
    }
  }
}
