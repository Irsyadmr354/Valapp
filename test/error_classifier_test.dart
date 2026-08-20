import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:valorant_app/core/exceptions/api_exception.dart';
import 'package:valorant_app/core/exceptions/auth_exception.dart';
import 'package:valorant_app/shared/utils/error_classifier.dart';

void main() {
  group('ErrorClassifier Tests', () {
    test(
        'classifies TokenExpiredException and InvalidSessionException as authPermanent',
        () {
      expect(classifyError(const TokenExpiredException()),
          ErrorCategory.authPermanent);
      expect(classifyError(const InvalidSessionException()),
          ErrorCategory.authPermanent);
    });

    test('classifies TransientReauthException as authTransient', () {
      expect(classifyError(const TransientReauthException()),
          ErrorCategory.authTransient);
    });

    test('classifies RateLimitedException and 429 as rateLimit', () {
      expect(
          classifyError(const RateLimitedException()), ErrorCategory.rateLimit);
      expect(
        classifyError(
          DioException(
            requestOptions: RequestOptions(path: '/'),
            response: Response(
              statusCode: 429,
              requestOptions: RequestOptions(path: '/'),
            ),
          ),
        ),
        ErrorCategory.rateLimit,
      );
    });

    test('classifies 401 and 403 DioException as authPermanent', () {
      expect(
        classifyError(
          DioException(
            requestOptions: RequestOptions(path: '/'),
            response: Response(
              statusCode: 401,
              requestOptions: RequestOptions(path: '/'),
            ),
          ),
        ),
        ErrorCategory.authPermanent,
      );
      expect(
        classifyError(
          DioException(
            requestOptions: RequestOptions(path: '/'),
            response: Response(
              statusCode: 403,
              requestOptions: RequestOptions(path: '/'),
            ),
          ),
        ),
        ErrorCategory.authPermanent,
      );
    });

    test('classifies network and timeout exceptions as network', () {
      expect(
        classifyError(const SocketException('No route to host')),
        ErrorCategory.network,
      );
      expect(
        classifyError(TimeoutException('Request timed out')),
        ErrorCategory.network,
      );
      expect(
        classifyError(
          DioException(
            requestOptions: RequestOptions(path: '/'),
            type: DioExceptionType.connectionTimeout,
          ),
        ),
        ErrorCategory.network,
      );
      expect(
        classifyError(
          DioException(
            requestOptions: RequestOptions(path: '/'),
            type: DioExceptionType.connectionError,
          ),
        ),
        ErrorCategory.network,
      );
    });

    test(
        'classifies unexpected 400 or other errors as unknown rather than auth',
        () {
      expect(
        classifyError(
          DioException(
            requestOptions: RequestOptions(path: '/'),
            response: Response(
              statusCode: 400,
              data: {'message': 'bad parameter 400'},
              requestOptions: RequestOptions(path: '/'),
            ),
          ),
        ),
        ErrorCategory.unknown,
      );
      expect(classifyError(const FormatException('bad format')),
          ErrorCategory.unknown);
    });
  });
}
