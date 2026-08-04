import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import '../../features/shop/domain/models/wallet.dart';
import '../storage/secure_storage.dart';
import '../storage/cache_storage.dart';
import '../../features/auth/data/credentials_local_source.dart';
import 'notification_service.dart';

const String taskWishlistBackgroundCheck = 'valapp_background_wishlist_check';
const String iosWishlistBackgroundTask =
    'com.personal.valorant-shop-monitor.wishlist-refresh';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint('[BackgroundService] task: $task');
    if (task == taskWishlistBackgroundCheck ||
        task == iosWishlistBackgroundTask ||
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
        Platform.isIOS
            ? iosWishlistBackgroundTask
            : 'valapp_wishlist_periodic_task',
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
/// 3. Fires wishlist match notifications when shop changes
/// 4. Fires shop reset summary notification when the shop changes
class BackgroundShopChecker {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 25),
    sendTimeout: const Duration(seconds: 15),
  ));

  static const _lastShopKey = 'background_last_shop_ids';

  Future<void> runCheck() async {
    final storage = SecureStorage.instance;
    final cache = CacheStorage.instance;

    final credentials = await CredentialsLocalSource(storage).load();
    if (credentials == null) return;
    final accessToken = credentials.accessToken;
    final entitlementToken = credentials.entitlementToken;
    final puuid = credentials.puuid;
    final shard = credentials.shard;

    // Skip if the access token is clearly expired — the background task cannot
    // perform a WebView-based reauth, so a known-expired token will always
    // produce a 401. Bailing early avoids a wasteful network round-trip.
    if (DateTime.now().isAfter(credentials.expiresAt)) {
      debugPrint('[BackgroundShopChecker] Token expired — skipping check');
      return;
    }

    // ── Fetch storefront ────────────────────────────────────────────────────
    final Map<String, dynamic> storefront;

    // X-Riot-ClientVersion is required by several Riot PD endpoints.
    // Use the cached version (set by the main app); fall back to a known
    // stable value so the background task does not produce 400s.
    final clientVersion = await cache.getString(CacheStorage.keyClientVersion);
    if (clientVersion == null || clientVersion.isEmpty) {
      throw StateError('No verified Riot client version is cached');
    }

    final headers = {
      'Authorization': 'Bearer $accessToken',
      'X-Riot-Entitlements-JWT': entitlementToken,
      'X-Riot-ClientVersion': clientVersion,
      'X-Riot-ClientPlatform':
          'ew0KCSJwbGF0Zm9ybVR5cGUiOiAiUEMiLA0KCSJwbGF0Zm9ybU9TIjogIldpbmRvd3MiLA0KCSJwbGF0Zm9ybU9TVmVyc2lvbiI6ICIxMC4wLjE5MDQyLjEuMjU2LjY0Yml0IiwNCgkicGxhdGZvcm1DaGlwc2V0IjogIlVua25vd24iDQp9',
      'Content-Type': 'application/json',
    };
    try {
      dynamic rawData;
      try {
        final resp = await _dio.post<dynamic>(
          'https://pd.$shard.a.pvp.net/store/v3/storefront/$puuid',
          options: Options(headers: headers),
          data: {},
        );
        rawData = resp.data;
      } on DioException catch (error) {
        if (error.response?.statusCode != 404 &&
            error.response?.statusCode != 405) {
          rethrow;
        }
        final resp = await _dio.post<dynamic>(
          'https://pd.$shard.a.pvp.net/store/v2/storefront/$puuid',
          options: Options(headers: headers),
          data: {},
        );
        rawData = resp.data;
      }

      if (rawData is Map<String, dynamic>) {
        storefront = rawData;
      } else if (rawData is String) {
        storefront = jsonDecode(rawData) as Map<String, dynamic>;
      } else {
        return;
      }
    } catch (_) {
      rethrow;
    }

    // ── Extract offers with prices ──────────────────────────────────────────
    final skinPanel =
        storefront['SkinsPanelLayout'] as Map<String, dynamic>? ?? {};
    final offerIds =
        (skinPanel['SingleItemOffers'] as List<dynamic>?)?.cast<String>() ?? [];
    final storeOffers =
        skinPanel['SingleItemStoreOffers'] as List<dynamic>? ?? [];

    // Build price map: offerId → price
    final priceMap = <String, int>{};
    for (final o in storeOffers) {
      if (o is! Map) continue;
      final oid = o['OfferID'] as String?;
      if (oid == null) continue;
      final cost = o['Cost'] as Map<String, dynamic>? ?? {};
      final price = (cost[ValorantCurrency.vpUuid] as num?)?.toInt() ?? 0;
      priceMap[oid] = price;
    }

    if (offerIds.isEmpty) return;

    // ── Detect shop reset ───────────────────────────────────────────────────
    final lastShopRaw = await cache.getJson(_lastShopKey);
    final lastOffers =
        (lastShopRaw?['ids'] as List<dynamic>?)?.cast<String>() ?? [];
    final isNewShop = !_setsEqual(offerIds.toSet(), lastOffers.toSet());
    final sortedOfferIds = List<String>.from(offerIds)..sort();
    final shopIdentity = sortedOfferIds.join(',');

    // ── Resolve skin names from valorant-api.com ────────────────────────────
    final skinNameMap = await _buildSkinNameMap(cache);

    final wishlist = await cache.getWishlist();

    // ── Fire notifications ─────────────────────────────────────────────────

    // Wishlist matches — only notify when the shop is actually new,
    // so the same skin never triggers two notifications in one day.
    final matchedOffers =
        offerIds.where((id) => wishlist.contains(id)).toList();

    if (isNewShop) {
      for (final id in matchedOffers) {
        final name = skinNameMap[id] ?? 'Wishlist Skin';
        final price = priceMap[id] ?? 0;
        await NotificationService.instance.showWishlistAlertOnce(
          shopIdentity: shopIdentity,
          skinId: id,
          skinName: name,
          price: price,
          puuid: puuid,
        );
      }

      final skinNames = offerIds
          .map((id) =>
              skinNameMap[id] ?? (id.length > 8 ? id.substring(0, 8) : id))
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
      final resp = await _dio.get<Map<String, dynamic>>(
          'https://valorant-api.com/v1/weapons/skins');
      final skins = resp.data?['data'] as List<dynamic>? ?? [];
      final map = <String, String>{};
      for (final skin in skins) {
        if (skin is! Map) continue;
        final name = skin['displayName'] as String? ?? '';
        final levels = skin['levels'] as List<dynamic>? ?? [];
        for (final lvl in levels) {
          if (lvl is! Map) continue;
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
