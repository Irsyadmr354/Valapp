import 'dart:async';
import 'package:dio/dio.dart';
import '../../exceptions/api_exception.dart';

/// Retries requests that receive HTTP 429 with exponential backoff.
///
/// EH-06: bounded by a total deadline of [_maxTotalRetryWindow] from the
/// first attempt, plus a simple circuit breaker that stops retrying once
/// [_circuitThreshold] consecutive 429s have been observed (opens for
/// [_circuitOpenDuration]).
class RetryInterceptor extends Interceptor {
  RetryInterceptor(
    this._dio, {
    int maxRetries = 4,
    Future<void> Function(Duration)? delay,
  })  : _maxRetries = maxRetries,
        _delay = delay ?? Future<void>.delayed;

  static const _maxTotalRetryWindow = Duration(seconds: 90);
  static const _circuitThreshold = 3;
  static const _circuitOpenDuration = Duration(seconds: 60);

  final Dio _dio;
  final int _maxRetries;
  final Future<void> Function(Duration) _delay;

  /// Consecutive 429s seen across all request chains.
  static int _consecutive429 = 0;

  /// Until when the circuit stays open (no retries issued).
  static DateTime _circuitOpenUntil = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final statusCode = err.response?.statusCode;

    if (statusCode == 429) {
      _consecutive429++;
      final circuitOpen = DateTime.now().isBefore(_circuitOpenUntil);

      final retryCount = (err.requestOptions.extra['retryCount'] as int?) ?? 0;
      // Per-request-chain deadline start (stored on extra so concurrent
      // chains do not share one clock).
      final firstRetryAtMs =
          (err.requestOptions.extra['firstRetryAt'] as int?) ??
              DateTime.now().millisecondsSinceEpoch;
      err.requestOptions.extra['firstRetryAt'] = firstRetryAtMs;
      final elapsed =
          DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(
        firstRetryAtMs,
      ));
      final deadlineExceeded = elapsed >= _maxTotalRetryWindow;

      if (!circuitOpen && !deadlineExceeded && retryCount < _maxRetries) {
        final delay = _retryDelay(err.response, retryCount);
        if (elapsed + delay < _maxTotalRetryWindow) {
          await _delay(delay);

          err.requestOptions.extra['retryCount'] = retryCount + 1;

          try {
            final response = await _dio.fetch(err.requestOptions);
            _consecutive429 = 0;
            handler.resolve(response);
            return;
          } on DioException catch (retryError) {
            // Preserve the final retry failure (including cancellation/timeouts)
            // rather than replacing it with the original 429.
            handler.next(retryError);
            return;
          } catch (e, st) {
            handler.reject(
              DioException(
                requestOptions: err.requestOptions,
                error: e,
                stackTrace: st,
              ),
            );
            return;
          }
        }
      }

      if (_consecutive429 > _circuitThreshold && !circuitOpen) {
        _circuitOpenUntil = DateTime.now().add(_circuitOpenDuration);
      }

      handler.reject(
        DioException(
          requestOptions: err.requestOptions,
          error: const RateLimitedException(),
          type: DioExceptionType.badResponse,
          response: err.response,
        ),
      );
      return;
    }

    _consecutive429 = 0;
    handler.next(err);
  }

  Duration _retryDelay(Response<dynamic>? response, int retryCount) {
    final retryAfter = response?.headers.value('retry-after');
    final seconds = int.tryParse(retryAfter ?? '');
    if (seconds != null && seconds >= 0) {
      return Duration(seconds: seconds.clamp(0, 60));
    }
    return Duration(seconds: 1 << retryCount);
  }
}
