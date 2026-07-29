import 'dart:async';
import 'package:dio/dio.dart';
import '../../exceptions/api_exception.dart';

/// Retries requests that receive HTTP 429 with exponential backoff.
/// Delays: 1s → 2s → 4s → 8s (max 4 retries).
class RetryInterceptor extends Interceptor {
  static const _maxRetries = 4;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final statusCode = err.response?.statusCode;

    if (statusCode == 429) {
      final retryCount =
          (err.requestOptions.extra['retryCount'] as int?) ?? 0;

      if (retryCount < _maxRetries) {
        final delay = Duration(seconds: 1 << retryCount); // 1,2,4,8
        await Future.delayed(delay);

        err.requestOptions.extra['retryCount'] = retryCount + 1;

        try {
          final dio = Dio();
          final response = await dio.fetch(err.requestOptions);
          handler.resolve(response);
          return;
        } catch (e) {
          // Fall through to propagate
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
}
