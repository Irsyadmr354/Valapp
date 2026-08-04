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
