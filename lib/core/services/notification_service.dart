import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
    );

    await _notifications.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );
    _isInitialized = true;
  }

  Future<void> requestPermissions() async {
    await init();
    final androidImpl = _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();

    final iosImpl = _notifications
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    await iosImpl?.requestPermissions(
        alert: true, badge: true, sound: true);
  }

  // ── Wishlist match alert ───────────────────────────────────────────────────

  Future<void> showWishlistAlert({
    required String skinName,
    required int price,
  }) async {
    await init();
    await _notifications.show(
      skinName.hashCode & 0x7FFFFFFF,
      '🌟 WISHLIST SKIN IN SHOP!',
      '$skinName is available today for ${price > 0 ? '$price VP' : 'an unknown price'}!',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _wishlistChannelId, 'Wishlist Alerts',
          channelDescription:
              'Alerts when your wishlisted skin appears in the shop',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
            presentAlert: true, presentBadge: true, presentSound: true),
      ),
    );
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
          _shopChannelId, 'Shop Reset',
          channelDescription: 'Notification when your daily shop resets',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          icon: '@mipmap/ic_launcher',
          styleInformation: BigTextStyleInformation(
            skinNames.join('\n'),
            contentTitle: title,
          ),
        ),
        iOS: const DarwinNotificationDetails(
            presentAlert: true, presentBadge: false, presentSound: false),
      ),
    );
  }
}
