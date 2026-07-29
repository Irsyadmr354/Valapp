import 'package:dio/dio.dart';
import 'interceptors/retry_interceptor.dart';
import 'interceptors/valorant_interceptor.dart';

/// Creates the [Dio] instance used for all `pvp.net` and game API endpoints.
/// Injects auth headers via [ValorantInterceptor] and handles rate-limiting
/// via [RetryInterceptor].
Dio createApiDio(ValorantInterceptor valorantInterceptor) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  dio.interceptors.addAll([
    valorantInterceptor,
    RetryInterceptor(),
  ]);

  return dio;
}
