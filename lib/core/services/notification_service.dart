import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Helper service for triggering native system smartphone notifications.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  /// Initializes local notifications for Android & iOS.
  Future<void> init() async {
    if (_isInitialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(initSettings);
    _isInitialized = true;
  }

  /// Request permissions on Android / iOS
  Future<void> requestPermissions() async {
    await init();
    final androidImpl = _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      await androidImpl.requestNotificationsPermission();
    }

    final iosImpl = _notifications
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    if (iosImpl != null) {
      await iosImpl.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  }

  /// Trigger native notification when a wishlisted skin appears in shop
  Future<void> showWishlistAlert({
    required String skinName,
    required int price,
  }) async {
    await init();

    const androidDetails = AndroidNotificationDetails(
      'valapp_wishlist_channel',
      'Wishlist Alerts',
      channelDescription:
          'Notifications when your wishlisted Valorant skin appears in shop',
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'Wishlist Match!',
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      skinName.hashCode,
      '🌟 WISHLIST SKIN IN SHOP!',
      '$skinName is available in your shop today for $price VP!',
      details,
    );
  }
}
