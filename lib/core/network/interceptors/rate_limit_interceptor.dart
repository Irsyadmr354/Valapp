import 'dart:async';
import 'package:dio/dio.dart';

/// Enforces a minimum delay of 500ms between consecutive API requests
/// to avoid hitting Riot's rate limits.
///
/// Uses a future-chain mutex so concurrent calls are properly serialised —
/// each incoming request waits for the previous one to finish its delay
/// before proceeding.  This eliminates the race window where multiple
/// callers could all pass the lock check before any of them set it.
class RateLimitInterceptor extends Interceptor {
  static const _minInterval = Duration(milliseconds: 500);

  /// Tail of the serialisation chain.  Every new request appends itself
  /// after the current tail, so all requests execute in arrival order.
  Future<void> _tail = Future.value();

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    // Capture the current tail, then immediately extend it so the next
    // concurrent caller waits for *this* request's slot too.
    final previous = _tail;
    final completer = Completer<void>();
    _tail = completer.future;

    try {
      // Wait for all preceding requests to finish their delay slots.
      await previous;

      // Enforce the minimum inter-request gap.
      await Future.delayed(_minInterval);
    } finally {
      // Release our slot so the next queued request can proceed.
      completer.complete();
    }

    handler.next(options);
  }
}
