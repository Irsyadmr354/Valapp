/// Exceptions related to Valorant API calls.
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// HTTP 429 — too many requests.
class RateLimitedException extends ApiException {
  const RateLimitedException()
      : super('Too many requests. Please wait a moment.', statusCode: 429);
}

/// HTTP 404 — resource not found.
class NotFoundException extends ApiException {
  const NotFoundException([String? resource])
      : super(
          resource != null ? '$resource not found.' : 'Resource not found.',
          statusCode: 404,
        );
}

/// No internet connection or network timeout.
class NetworkException extends ApiException {
  const NetworkException()
      : super('No internet connection. Showing cached data.');
}
