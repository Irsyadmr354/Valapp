import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import '../../core/exceptions/auth_exception.dart';
import '../../core/exceptions/api_exception.dart';

/// Categories of errors encountered across the app.
enum ErrorCategory {
  /// Unrecoverable auth failures where stored credentials/tokens are completely invalid.
  /// Requires the user to log in again via OAuth.
  authPermanent,

  /// Temporary auth/network-handshake disruption.
  /// Stored credentials must NOT be wiped; user can reconnect.
  authTransient,

  /// Internet connectivity / DNS / timeout failures.
  network,

  /// HTTP 429 rate limiting by Riot servers.
  rateLimit,

  /// Other server-side errors, format errors, or unexpected exceptions.
  unknown,
}

/// Classifies an arbitrary [error] object into a semantic [ErrorCategory]
/// using strict type checking rather than fragile string-matching.
ErrorCategory classifyError(Object error) {
  // 1. Domain Auth Exceptions
  if (error is InvalidSessionException || error is TokenExpiredException) {
    return ErrorCategory.authPermanent;
  }
  if (error is TransientReauthException) {
    return ErrorCategory.authTransient;
  }

  // 2. Domain API Exceptions
  if (error is RateLimitedException) {
    return ErrorCategory.rateLimit;
  }
  if (error is ApiException) {
    if (error.statusCode == 401 || error.statusCode == 403) {
      return ErrorCategory.authPermanent;
    }
    if (error.statusCode == 429) {
      return ErrorCategory.rateLimit;
    }
  }

  // 3. Dio Exceptions
  if (error is DioException) {
    final status = error.response?.statusCode;
    if (status == 401 || status == 403) {
      return ErrorCategory.authPermanent;
    }
    if (status == 429) {
      return ErrorCategory.rateLimit;
    }
    if (_isNetworkDio(error)) {
      return ErrorCategory.network;
    }
    // Note: 400 on Riot game endpoints should NOT be classified as permanent auth here
    // unless the interceptor confirms it.
  }

  // 4. Core Dart IO / Network Exceptions
  if (error is SocketException ||
      error is TimeoutException ||
      error is HandshakeException) {
    return ErrorCategory.network;
  }

  // 5. Fallback string check for wrapped / unhandled errors
  final errorStr = error.toString().toLowerCase();
  if (errorStr.contains('socketexception') ||
      errorStr.contains('network is unreachable') ||
      errorStr.contains('connection refused') ||
      errorStr.contains('connection timed out') ||
      errorStr.contains('handshakeexception')) {
    return ErrorCategory.network;
  }
  if (errorStr.contains('ratelimited') || errorStr.contains('429')) {
    return ErrorCategory.rateLimit;
  }
  if (errorStr.contains('invalidsessionexception') ||
      errorStr.contains('tokenexpiredexception')) {
    return ErrorCategory.authPermanent;
  }
  if (errorStr.contains('transientreauthexception')) {
    return ErrorCategory.authTransient;
  }

  return ErrorCategory.unknown;
}

bool _isNetworkDio(DioException e) {
  return e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.sendTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.badCertificate ||
      (e.type == DioExceptionType.unknown && e.error is SocketException);
}
