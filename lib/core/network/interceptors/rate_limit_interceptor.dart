import 'package:dio/dio.dart';

/// Enforces a minimum delay of 500ms between consecutive API requests
/// to avoid hitting Riot's rate limits.
class RateLimitInterceptor extends Interceptor {
  static DateTime? _lastRequestTime;
  static const _minInterval = Duration(milliseconds: 500);

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    final now = DateTime.now();
    if (_lastRequestTime != null) {
      final elapsed = now.difference(_lastRequestTime!);
      if (elapsed < _minInterval) {
        await Future.delayed(_minInterval - elapsed);
      }
    }
    _lastRequestTime = DateTime.now();
    handler.next(options);
  }
}
