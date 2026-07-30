import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import '../storage/secure_storage.dart';
import '../storage/cache_storage.dart';
import 'notification_service.dart';

const String taskWishlistBackgroundCheck = 'valapp_background_wishlist_check';

/// Top-level entry point required by Workmanager for background execution.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint('[BackgroundService] Running background task: $task');
    if (task == taskWishlistBackgroundCheck || task == Workmanager.iOSBackgroundTask) {
      try {
        final service = BackgroundWishlistChecker();
        await service.runCheck();
        return true;
      } catch (e) {
        debugPrint('[BackgroundService] Error during background check: $e');
        return false;
      }
    }
    return true;
  });
}

/// Helper to initialize and manage Workmanager background monitoring.
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

      // Register periodic background task running every 3 hours (minimum interval enforced by OS)
      await Workmanager().registerPeriodicTask(
        'valapp_wishlist_periodic_task',
        taskWishlistBackgroundCheck,
        frequency: const Duration(hours: 3),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
        existingWorkPolicy: ExistingPeriodicTaskPolicy.replace,
      );

      _isInitialized = true;
      debugPrint('[BackgroundService] Background task registered successfully');
    } catch (e) {
      debugPrint('[BackgroundService] Failed to initialize Workmanager: $e');
    }
  }
}

/// Performs silent background shop check and triggers wishlist notification.
class BackgroundWishlistChecker {
  final Dio _dio = Dio();

  Future<void> runCheck() async {
    final storage = SecureStorage.instance;
    final cache = CacheStorage.instance;

    final accessToken = await storage.read(SecureStorage.keyAccessToken);
    final entitlementToken = await storage.read(SecureStorage.keyEntitlementToken);
    final puuid = await storage.read(SecureStorage.keyPuuid);
    final shard = await storage.read(SecureStorage.keyShard);

    if (accessToken == null || entitlementToken == null || puuid == null || shard == null) {
      debugPrint('[BackgroundChecker] Missing credentials, skipping check');
      return;
    }

    final wishlist = await cache.getWishlist();
    if (wishlist.isEmpty) {
      debugPrint('[BackgroundChecker] Wishlist is empty, skipping check');
      return;
    }

    // 1. Fetch storefront directly
    final storefrontResponse = await _dio.post<dynamic>(
      'https://pd.$shard.a.pvp.net/store/v2/storefront/$puuid',
      options: Options(
        headers: {
          'Authorization': 'Bearer $accessToken',
          'X-Riot-Entitlements-JWT': entitlementToken,
          'Content-Type': 'application/json',
        },
      ),
      data: {},
    );

    final rawData = storefrontResponse.data;
    Map<String, dynamic> storefrontMap = {};
    if (rawData is Map<String, dynamic>) {
      storefrontMap = rawData;
    } else if (rawData is String) {
      try {
        storefrontMap = jsonDecode(rawData) as Map<String, dynamic>;
      } catch (_) {}
    }

    final singleItemStore =
        storefrontMap['SkinsPanelLayout']?['SingleItemOffers'] as List<dynamic>? ?? [];
    final dailyOfferUuids = singleItemStore.map((e) => e.toString()).toList();

    // Check matches
    final matchedUuids = dailyOfferUuids.where((id) => wishlist.contains(id)).toList();
    if (matchedUuids.isEmpty) {
      debugPrint('[BackgroundChecker] No wishlist matches found today');
      return;
    }

    // 2. Fetch skin metadata for matched names
    final skinsResponse =
        await _dio.get<Map<String, dynamic>>('https://valorant-api.com/v1/weapons/skins');
    final skinsData = skinsResponse.data?['data'] as List<dynamic>? ?? [];

    final skinNameMap = <String, String>{};
    for (final skin in skinsData) {
      final levels = skin['levels'] as List<dynamic>? ?? [];
      for (final lvl in levels) {
        final uuid = lvl['uuid'] as String?;
        if (uuid != null) {
          skinNameMap[uuid] = skin['displayName'] as String? ?? 'Skin';
        }
      }
    }

    // 3. Trigger native notification for each match
    for (final matchedUuid in matchedUuids) {
      final skinName = skinNameMap[matchedUuid] ?? 'Wishlist Skin';
      debugPrint('[BackgroundChecker] Wishlist MATCH FOUND: $skinName ($matchedUuid)');
      await NotificationService.instance.showWishlistAlert(
        skinName: skinName,
        price: 1775, // Standard VP estimate for notification payload
      );
    }
  }
}
