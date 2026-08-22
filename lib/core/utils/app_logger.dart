import 'package:flutter/foundation.dart';

/// Centralized logger with level awareness and secret redaction.
class AppLogger {
  AppLogger._();
  static const _redacted = '[REDACTED]';

  static void info(String msg) {
    if (kDebugMode) debugPrint('[INFO] $msg');
  }

  static void warn(String msg) {
    debugPrint('[WARN] $msg');
  }

  static void error(String msg, [Object? err, StackTrace? st]) {
    debugPrint('[ERROR] $msg${err != null ? ": $err" : ""}');
    if (st != null && kDebugMode) debugPrint(st.toString());
  }

  /// Sanitizes a URL by stripping puuid segments for safe logging/UI.
  static String sanitizeUrl(String url) {
    return url
        .replaceAll(RegExp(r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'), _redacted)
        .replaceAll(RegExp(r'/players/[^/?#]+'), '/players/' + _redacted); // ignore: prefer_interpolation_to_compose_strings
  }

  static String sanitize(String input) {
    if (input.contains('Bearer ') || input.contains('ssid') || input.contains('entitlement')) return _redacted;
    return input;
  }
}
