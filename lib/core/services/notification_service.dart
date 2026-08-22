import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../storage/cache_storage.dart';

/// Helper service for triggering native system smartphone notifications.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  static const _wishlistChannelId = 'valapp_wishlist_channel';
  static const _shopChannelId = 'valapp_shop_channel';

  Future<void> init() async {
    if (_isInitialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      defaultPresentAlert: true,
      defaultPresentSound: true,
      defaultPresentBadge: true,
      defaultPresentBanner: true,
      defaultPresentList: true,
    );

    await _notifications.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

    final androidImpl = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      await androidImpl
          .createNotificationChannel(const AndroidNotificationChannel(
        _wishlistChannelId,
        'Wishlist Alerts',
        description: 'Alerts when your wishlisted skin appears in the shop',
        importance: Importance.max,
      ));
      await androidImpl
          .createNotificationChannel(const AndroidNotificationChannel(
        _shopChannelId,
        'Shop Reset',
        description: 'Notification when your daily shop resets',
        importance: Importance.high,
      ));
    }

    _isInitialized = true;
  }

  Future<bool?> requestPermissions() async {
    await init();
    final androidImpl = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final androidGranted = await androidImpl?.requestNotificationsPermission();

    final iosImpl = _notifications.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    final iosGranted = await iosImpl?.requestPermissions(
        alert: true, badge: true, sound: true);

    return iosGranted ?? androidGranted;
  }

  /// Direct test notification that ignores deduplication.
  Future<bool> showTestNotification() async {
    await init();
    final granted = await requestPermissions();
    await _notifications.show(
      999999,
      '🔔 TEST NOTIFICATION',
      'If you see this, local notifications are working perfectly!',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _wishlistChannelId,
          'Wishlist Alerts',
          channelDescription: 'Test notifications channel',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          presentBanner: true,
          presentList: true,
        ),
      ),
    );
    return granted ?? true;
  }

  // ── Wishlist match alert ───────────────────────────────────────────────────

  Future<void> showWishlistAlert({
    required String skinName,
    required int price,
    String? skinId,
    String? puuid,
  }) async {
    await init();
    final notifId = (puuid != null && skinId != null)
        ? '$puuid:$skinId'.hashCode & 0x7FFFFFFF
        : (skinId != null
            ? skinId.hashCode & 0x7FFFFFFF
            : skinName.hashCode & 0x7FFFFFFF);

    await _notifications.show(
      notifId,
      '🌟 WISHLIST SKIN IN SHOP!',
      '$skinName is available today for ${price > 0 ? '$price VP' : 'an unknown price'}!',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _wishlistChannelId,
          'Wishlist Alerts',
          channelDescription:
              'Alerts when your wishlisted skin appears in the shop',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          presentBanner: true,
          presentList: true,
        ),
      ),
    );
  }

  Future<bool> showWishlistAlertOnce({
    required String shopIdentity,
    required String skinId,
    required String skinName,
    required int price,
    String? puuid,
  }) async {
    final account = puuid ?? CacheStorage.instance.activePuuid;
    final claimed = await CacheStorage.instance.claimWishlistNotification(
      puuid: account,
      shopIdentity: shopIdentity,
      skinId: skinId,
    );
    if (!claimed) return false;
    try {
      await showWishlistAlert(
        skinName: skinName,
        price: price,
        skinId: skinId,
        puuid: account,
      );
      return true;
    } catch (e) {
      // The claim was consumed but the alert never surfaced — roll the slot
      // back so a later check can still notify for this rotation.
      debugPrint('[NotificationService] Wishlist alert failed, rolling back claim: $e');
      await CacheStorage.instance.rollbackWishlistNotificationClaim(
        puuid: account,
        shopIdentity: shopIdentity,
        skinId: skinId,
      );
      return false;
    }
  }

  // ── Daily shop reset notification ─────────────────────────────────────────

  /// Show a notification when the daily shop resets listing the new skins.
  Future<void> showShopResetAlert({
    required List<String> skinNames,
    int wishlistMatchCount = 0,
  }) async {
    await init();

    final title = wishlistMatchCount > 0
        ? '🌟 YOUR SHOP IS LIVE — $wishlistMatchCount WISHLIST MATCH!'
        : '🛒 YOUR DAILY SHOP IS LIVE';

    final body = skinNames.isNotEmpty
        ? skinNames.take(4).join(' · ')
        : 'Open the app to check your new skins.';

    await _notifications.show(
      20250101, // fixed ID so repeated calls replace the same notification
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _shopChannelId,
          'Shop Reset',
          channelDescription: 'Notification when your daily shop resets',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          styleInformation: BigTextStyleInformation(
            skinNames.join('\n'),
            contentTitle: title,
          ),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: false,
          presentBanner: true,
          presentList: true,
        ),
      ),
    );
  }
}
