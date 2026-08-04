import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/services/notification_service.dart';
import 'core/services/background_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    // ProviderScope enables Riverpod throughout the app
    const ProviderScope(
      child: ValorantShopApp(),
    ),
  );

  // Optional native services must never prevent the first frame from loading.
  try {
    await Future.wait([
      NotificationService.instance.init(),
      BackgroundService.instance.init(),
    ]);
  } catch (error) {
    debugPrint('[Startup] Optional service initialization failed: $error');
  }
}
