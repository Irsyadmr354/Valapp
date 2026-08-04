import 'dart:async';
import 'package:dio/dio.dart';
import '../../exceptions/api_exception.dart';

/// Retries requests that receive HTTP 429 with exponential backoff.
class RetryInterceptor extends Interceptor {
  RetryInterceptor(
    this._dio, {
    int maxRetries = 4,
    Future<void> Function(Duration)? delay,
  })  : _maxRetries = maxRetries,
        _delay = delay ?? Future<void>.delayed;

  final Dio _dio;
  final int _maxRetries;
  final Future<void> Function(Duration) _delay;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final statusCode = err.response?.statusCode;

    if (statusCode == 429) {
      final retryCount = (err.requestOptions.extra['retryCount'] as int?) ?? 0;

      if (retryCount < _maxRetries) {
        final delay = _retryDelay(err.response, retryCount);
        await _delay(delay);

        err.requestOptions.extra['retryCount'] = retryCount + 1;

        try {
          final response = await _dio.fetch(err.requestOptions);
          handler.resolve(response);
          return;
        } on DioException catch (retryError) {
          // Preserve the final retry failure (including cancellation/timeouts)
          // rather than replacing it with the original 429.
          handler.next(retryError);
          return;
        }
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
