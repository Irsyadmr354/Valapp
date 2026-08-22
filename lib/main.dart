import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/services/notification_service.dart';
import 'core/services/background_service.dart';
import 'core/utils/app_logger.dart';

Future<void> main() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      AppLogger.error('FlutterError', details.exception, details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      AppLogger.error('PlatformDispatcher', error, stack);
      return true;
    };

    runApp(
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
    } catch (error, st) {
      AppLogger.warn('Optional service initialization failed: ');
      if (kDebugMode) debugPrint(st.toString());
    }
  }, (error, stack) {
    AppLogger.error('Uncaught zone', error, stack);
  });
}
