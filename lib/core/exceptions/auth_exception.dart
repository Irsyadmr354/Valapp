/// Exceptions related to authentication flow.
class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => 'AuthException: $message';
}

/// Thrown when access token and cookies are both expired — user must re-login.
class TokenExpiredException extends AuthException {
  const TokenExpiredException() : super('Token expired. Please login again.');
}

/// A definitive server rejection. The stored session must not be retried.
class InvalidSessionException extends AuthException {
  const InvalidSessionException(
      [super.message = 'Session is no longer valid.']);
}

/// Reauthentication may succeed later; stored credentials must be preserved.
class TransientReauthException extends AuthException {
  const TransientReauthException(
      [super.message = 'Reauthentication unavailable.']);
}
