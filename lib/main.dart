import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    // ProviderScope enables Riverpod throughout the app
    const ProviderScope(
      child: ValorantShopApp(),
    ),
  );
}
