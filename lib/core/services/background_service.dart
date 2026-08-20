import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import '../../features/shop/domain/models/wallet.dart';
import '../network/valorant_headers.dart';
import '../storage/secure_storage.dart';
import '../storage/cache_storage.dart';
import '../../features/auth/data/auth_remote_source.dart';
import '../../features/auth/data/credentials_local_source.dart';
import 'notification_service.dart';

const String taskWishlistBackgroundCheck = 'valapp_background_wishlist_check';
const String iosWishlistBackgroundTask = 'com.valapp.mobile.wishlist-refresh';

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
        frequency: const Duration(hours: 2),
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

    var credentials = await CredentialsLocalSource(storage).load();
    if (credentials == null) return;

    // Skip if accessToken is expired — background task cannot trigger interactive reauth
    if (credentials.isExpired) {
      debugPrint(
          '[BackgroundShopChecker] Access token expired — skipping background check');
      return;
    }

    // Proactively refresh entitlement token if expired while accessToken is still valid
    if (credentials.isEntitlementExpired) {
      debugPrint(
          '[BackgroundShopChecker] Entitlement token expired, refreshing non-interactively...');
      try {
        final remote = AuthRemoteSource(_dio, _dio);
        final freshEntitlement =
            await remote.fetchEntitlementToken(credentials.accessToken);
        final updated = credentials.copyWith(
          entitlementToken: freshEntitlement,
          entitlementExpiresAt: DateTime.now().add(
            SecureStorage.entitlementTokenLifetime,
          ),
        );
        await CredentialsLocalSource(storage)
            .saveIfCurrent(credentials, updated);
        credentials = updated;
        debugPrint(
            '[BackgroundShopChecker] Refreshed entitlement token successfully');
      } catch (e) {
        debugPrint(
            '[BackgroundShopChecker] Failed to refresh entitlement in background: $e');
        return;
      }
    }

    final accessToken = credentials.accessToken;
    final entitlementToken = credentials.entitlementToken;
    final puuid = credentials.puuid;
    final shard = credentials.shard;

    // ── Fetch storefront ────────────────────────────────────────────────────
    final Map<String, dynamic> storefront;

    final clientVersion =
        (await cache.getString(CacheStorage.keyClientVersion)) ??
            ValorantHeaders.defaultClientVersion;

    final headers = {
      ValorantHeaders.headerAuth: 'Bearer $accessToken',
      ValorantHeaders.headerEntitlement: entitlementToken,
      ValorantHeaders.headerClientVersion: clientVersion,
      ValorantHeaders.headerClientPlatform: ValorantHeaders.clientPlatform,
      'Content-Type': 'application/json',
    };
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
    final lastShopKey = CacheStorage.userKeyFor(_lastShopKey, puuid);
    final lastShopRaw = await cache.getJson(lastShopKey);
    final lastOffers =
        (lastShopRaw?['ids'] as List<dynamic>?)?.cast<String>() ?? [];
    final isNewShop = !_setsEqual(offerIds.toSet(), lastOffers.toSet());
    final sortedOfferIds = List<String>.from(offerIds)..sort();
    final shopIdentity = sortedOfferIds.join(',');

    // ── Resolve skin names from valorant-api.com ────────────────────────────
    final skinNameMap = await _buildSkinNameMap(cache);

    final wishlist = await cache.getWishlist(puuid);

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
      await cache.setJson(lastShopKey, {'ids': offerIds});
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
