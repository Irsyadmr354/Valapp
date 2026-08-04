import 'dart:convert';
import 'dart:math';

import '../../../core/exceptions/auth_exception.dart';

class OAuthAttempt {
  OAuthAttempt._({required this.state, required this.nonce});

  factory OAuthAttempt.create() => OAuthAttempt._(
        state: _randomValue(),
        nonce: _randomValue(),
      );

  final String state;
  final String nonce;

  Uri get authorizeUri => Uri.https(
        OAuthFlow.authHost,
        '/authorize',
        {
          'client_id': OAuthFlow.clientId,
          'nonce': nonce,
          'redirect_uri': OAuthFlow.redirectUri.toString(),
          'response_type': 'token id_token',
          'scope': 'account openid',
          'state': state,
        },
      );

  static String _randomValue() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}

class OAuthFlow {
  static const authHost = 'auth.riotgames.com';
  static const clientId = 'play-valorant-web-prod';
  static final redirectUri = Uri.https('playvalorant.com', '/opt_in');

  static bool isRedirectUri(Uri uri) =>
      uri.scheme == redirectUri.scheme &&
      uri.host == redirectUri.host &&
      uri.port == redirectUri.port &&
      uri.path == redirectUri.path &&
      uri.userInfo.isEmpty;

  static Map<String, String> parseTokenRedirect(
    String value, {
    required String expectedState,
    required String expectedNonce,
  }) {
    final uri = Uri.tryParse(value);
    if (uri == null || !isRedirectUri(uri)) {
      throw const AuthException('Invalid OAuth redirect URI');
    }
    if (uri.query.isNotEmpty || uri.fragment.isEmpty) {
      throw const AuthException('Invalid OAuth redirect response');
    }

    final params = Uri.splitQueryString(uri.fragment);
    if (params['state'] != expectedState) {
      throw const AuthException('OAuth state validation failed');
    }

    final accessToken = _required(params, 'access_token');
    final idToken = _required(params, 'id_token');
    final expiresIn = int.tryParse(_required(params, 'expires_in'));
    if (expiresIn == null || expiresIn <= 0 || expiresIn > 86400) {
      throw const AuthException('Invalid token expiry');
    }

    final idPayload = decodeJwtPayload(idToken, name: 'ID token');
    if (idPayload['nonce'] != expectedNonce) {
      throw const AuthException('OAuth nonce validation failed');
    }
    final accessPayload = decodeJwtPayload(accessToken, name: 'access token');
    final accessSubject = accessPayload['sub'];
    if (accessSubject is! String || accessSubject.isEmpty) {
      throw const AuthException('Invalid access token subject');
    }
    final idSubject = idPayload['sub'];
    if (idSubject is String &&
        idSubject.isNotEmpty &&
        idSubject != accessSubject) {
      throw const AuthException('OAuth token subjects do not match');
    }

    return {
      'access_token': accessToken,
      'id_token': idToken,
      'expires_in': expiresIn.toString(),
    };
  }

  static Map<String, dynamic> decodeJwtPayload(String token,
      {String name = 'JWT'}) {
    final parts = token.split('.');
    if (parts.length != 3 || parts.any((part) => part.isEmpty)) {
      throw AuthException('Invalid $name format');
    }
    try {
      final decoded =
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final value = jsonDecode(decoded);
      if (value is! Map<String, dynamic>) throw const FormatException();
      return value;
    } catch (_) {
      throw AuthException('Invalid $name payload');
    }
  }

  static String _required(Map<String, String> params, String name) {
    final value = params[name];
    if (value == null || value.trim().isEmpty) {
      throw AuthException('$name not found in redirect URI');
    }
    return value;
  }
}
