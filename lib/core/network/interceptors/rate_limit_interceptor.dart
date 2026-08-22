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

  /// When the last request was dispatched. Used to compute the REMAINING
  /// gap instead of imposing a fixed sleep — an idle client must not pay a
  /// 500 ms tax on every single request.
  DateTime _lastSentAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    // Capture the current tail, then immediately extend it so the next
    // concurrent caller waits for *this* request's slot too.
    final previous = _tail;
    final completer = Completer<void>();
    _tail = completer.future;

    try {
      // Wait for all preceding requests to finish their delay slots, ignoring
      // previous errors so one failing request never blocks the entire pipeline.
      try {
        await previous;
      } catch (_) {}

      // Enforce only the REMAINING inter-request gap.
      final elapsed = DateTime.now().difference(_lastSentAt);
      if (elapsed < _minInterval) {
        await Future.delayed(_minInterval - elapsed);
      }
      _lastSentAt = DateTime.now();
      handler.next(options);
    } catch (e, st) {
      handler.reject(
        DioException(
          requestOptions: options,
          error: e,
          stackTrace: st,
        ),
      );
    } finally {
      // Release our slot so the next queued request can proceed.
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }
}
