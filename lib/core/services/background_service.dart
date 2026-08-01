import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import '../../features/shop/domain/models/wallet.dart';
import '../../features/shop/presentation/notification_rule_service.dart';
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
/// 4. Evaluates smart category rules (melee, vandal, phantom, operator, sheriff)
/// 5. Fires shop reset notification when the shop changes
class BackgroundShopChecker {
  final Dio _dio = Dio();

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
    final headers = {
      'Authorization': 'Bearer $accessToken',
      'X-Riot-Entitlements-JWT': entitlementToken,
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
      } catch (_) {
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
      return;
    }
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
      final price = (cost[ValorantCurrency.vpUuid] as num?)?.toInt() ?? 0;
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

    // Evaluate smart notification category rules for new shop
    if (isNewShop) {
      final rulesList = await cache.getJsonList(keyNotificationRules);
      final activeRules = rulesList != null
          ? rulesList.map((e) => e.toString()).toSet()
          : <String>{
              NotificationCategory.wishlist,
              NotificationCategory.melee,
              NotificationCategory.vandal,
              NotificationCategory.phantom,
            };

      final dailySkinNames = offerIds
          .map((id) => skinNameMap[id] ?? '')
          .where((n) => n.isNotEmpty)
          .toList();

      final categoryAlerts = <String>[];

      if (activeRules.contains(NotificationCategory.melee)) {
        final melees = dailySkinNames.where((n) {
          final l = n.toLowerCase();
          return l.contains('knife') ||
              l.contains('karambit') ||
              l.contains('blade') ||
              l.contains('dagger') ||
              l.contains('axe') ||
              l.contains('sword') ||
              l.contains('scythe') ||
              l.contains('hammer') ||
              l.contains('mace') ||
              l.contains('butterfly') ||
              l.contains('onimaru') ||
              l.contains('fan');
        }).toList();
        if (melees.isNotEmpty) {
          categoryAlerts.add('🔪 Melee in shop: ${melees.join(', ')}');
        }
      }

      if (activeRules.contains(NotificationCategory.vandal)) {
        final vandals = dailySkinNames
            .where((n) => n.toLowerCase().contains('vandal'))
            .toList();
        if (vandals.isNotEmpty) {
          categoryAlerts.add('🔫 Vandal in shop: ${vandals.join(', ')}');
        }
      }

      if (activeRules.contains(NotificationCategory.phantom)) {
        final phantoms = dailySkinNames
            .where((n) => n.toLowerCase().contains('phantom'))
            .toList();
        if (phantoms.isNotEmpty) {
          categoryAlerts.add('👻 Phantom in shop: ${phantoms.join(', ')}');
        }
      }

      if (activeRules.contains(NotificationCategory.operator)) {
        final ops = dailySkinNames
            .where((n) => n.toLowerCase().contains('operator'))
            .toList();
        if (ops.isNotEmpty) {
          categoryAlerts.add('🎯 Operator in shop: ${ops.join(', ')}');
        }
      }

      if (activeRules.contains(NotificationCategory.sheriff)) {
        final sheriffs = dailySkinNames
            .where((n) => n.toLowerCase().contains('sheriff'))
            .toList();
        if (sheriffs.isNotEmpty) {
          categoryAlerts.add('🤠 Sheriff in shop: ${sheriffs.join(', ')}');
        }
      }

      for (final alertMsg in categoryAlerts) {
        await NotificationService.instance.showCategoryAlert(
          title: '🛒 SHOP ALERT',
          body: alertMsg,
        );
      }

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
