import 'dart:async';
import 'package:dio/dio.dart';

/// Enforces a minimum delay of 500ms between consecutive API requests
/// to avoid hitting Riot's rate limits. Uses a Completer-based lock
/// to properly handle concurrent requests.
class RateLimitInterceptor extends Interceptor {
  DateTime? _lastRequestTime;
  static const _minInterval = Duration(milliseconds: 500);
  Completer<void>? _lock;

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    // Wait for any pending rate-limit delay to finish
    if (_lock != null && !_lock!.isCompleted) {
      await _lock!.future;
    }

    final now = DateTime.now();
    if (_lastRequestTime != null) {
      final elapsed = now.difference(_lastRequestTime!);
      if (elapsed < _minInterval) {
        _lock = Completer<void>();
        await Future.delayed(_minInterval - elapsed);
        _lock!.complete();
      }
    }
    _lastRequestTime = DateTime.now();
    handler.next(options);
  }
}
