/// Exceptions related to authentication flow.
class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => 'AuthException: $message';
}

/// Thrown when access token and cookies are both expired — user must re-login.
class TokenExpiredException extends AuthException {
  const TokenExpiredException()
      : super('Token expired. Please login again.');
}

/// Thrown when Riot returns a CAPTCHA challenge.
class CaptchaRequiredException extends AuthException {
  const CaptchaRequiredException()
      : super('CAPTCHA required. Please try again later.');
}

/// Thrown when username or password is incorrect.
class InvalidCredentialsException extends AuthException {
  const InvalidCredentialsException()
      : super('Invalid username or password.');
}

/// Thrown when 2FA code is wrong or expired.
class InvalidMfaCodeException extends AuthException {
  const InvalidMfaCodeException()
      : super('Invalid or expired 2FA code.');
}

/// Thrown when cookie reauth fails and cookies are expired.
class CookiesExpiredException extends AuthException {
  const CookiesExpiredException()
      : super('Session cookies have expired. Please login again.');
}
