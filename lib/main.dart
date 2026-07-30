import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/services/notification_service.dart';
import 'core/services/background_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize native notifications & background wishlist monitoring
  await NotificationService.instance.init();
  await BackgroundService.instance.init();

  runApp(
    // ProviderScope enables Riverpod throughout the app
    const ProviderScope(
      child: ValorantShopApp(),
    ),
  );
}
