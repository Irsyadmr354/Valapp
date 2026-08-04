import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:valorant_app/core/exceptions/api_exception.dart';
import 'package:valorant_app/core/network/interceptors/retry_interceptor.dart';

void main() {
  test('retries 429 using Retry-After and resolves the retried response',
      () async {
    final adapter = _SequenceAdapter([429, 200]);
    final delays = <Duration>[];
    final dio = Dio()..httpClientAdapter = adapter;
    dio.interceptors.add(RetryInterceptor(
      dio,
      delay: (delay) async => delays.add(delay),
    ));

    final response = await dio.get<dynamic>('https://example.test/data');

    expect(response.statusCode, 200);
    expect(adapter.requests, 2);
    expect(delays, [const Duration(seconds: 3)]);
  });

  test('returns RateLimitedException after the retry budget is exhausted',
      () async {
    final adapter = _SequenceAdapter([429, 429]);
    final dio = Dio()..httpClientAdapter = adapter;
    dio.interceptors.add(RetryInterceptor(
      dio,
      maxRetries: 1,
      delay: (_) async {},
    ));

    await expectLater(
      dio.get<dynamic>('https://example.test/data'),
      throwsA(isA<DioException>().having(
        (error) => error.error,
        'error',
        isA<RateLimitedException>(),
      )),
    );
    expect(adapter.requests, 2);
  });
}

class _SequenceAdapter implements HttpClientAdapter {
  _SequenceAdapter(this._statuses);

  final List<int> _statuses;
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final status = _statuses[requests++];
    return ResponseBody.fromString(
      status == 200 ? '{"ok":true}' : '{"error":"rate limited"}',
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
        if (status == 429) 'retry-after': ['3'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
