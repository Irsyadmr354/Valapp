import 'dart:convert';
import 'package:dio/dio.dart';
import 'interceptors/rate_limit_interceptor.dart';
import 'interceptors/retry_interceptor.dart';
import 'interceptors/valorant_interceptor.dart';

/// Decodes string JSON responses into Maps or Lists automatically,
/// preventing type cast errors when Riot API returns Content-Type text/plain.
class JsonResponseInterceptor extends Interceptor {
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (response.data is String) {
      final str = (response.data as String).trim();
      if (str.startsWith('{') || str.startsWith('[')) {
        try {
          response.data = jsonDecode(str);
        } catch (_) {}
      }
    }
    handler.next(response);
  }
}

/// Creates the [Dio] instance used for all `pvp.net` and game API endpoints.
/// Injects auth headers via [ValorantInterceptor] and handles rate-limiting
/// via [RetryInterceptor] and [RateLimitInterceptor].
Dio createApiDio(ValorantInterceptor valorantInterceptor) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  dio.interceptors.addAll([
    RateLimitInterceptor(),
    valorantInterceptor,
    JsonResponseInterceptor(),
    RetryInterceptor(dio),
  ]);

  return dio;
}

