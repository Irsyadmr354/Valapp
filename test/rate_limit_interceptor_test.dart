import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:valorant_app/core/network/interceptors/rate_limit_interceptor.dart';

void main() {
  group('RateLimitInterceptor', () {
    test('serializes requests and enforces minimum spacing between requests',
        () async {
      final dio = Dio();
      dio.interceptors.add(RateLimitInterceptor());

      // Mock adapter to complete instantly
      dio.httpClientAdapter = HttpClientAdapter();

      final requestTimes = <DateTime>[];

      // Add a custom interceptor to record when onRequest runs
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requestTimes.add(DateTime.now());
            handler.resolve(Response<dynamic>(
              requestOptions: options,
              data: {'ok': true},
              statusCode: 200,
            ));
          },
        ),
      );

      final req1 = dio.get<dynamic>('https://example.com/1');
      final req2 = dio.get<dynamic>('https://example.com/2');

      await Future.wait([req1, req2]);

      expect(requestTimes.length, 2);
      final difference = requestTimes[1].difference(requestTimes[0]);
      expect(difference.inMilliseconds, greaterThanOrEqualTo(80));
    });
  });
}
