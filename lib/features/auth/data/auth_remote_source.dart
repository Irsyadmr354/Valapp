import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../core/exceptions/auth_exception.dart';
import '../domain/models/credentials.dart';

/// All HTTP calls for the RSO authentication flow.
class AuthRemoteSource {
  const AuthRemoteSource(this._authDio, this._plainDio);

  final Dio _authDio; // Dio with cookie manager + Riot UA
  final Dio _plainDio; // Plain Dio for non-auth endpoints

  static const _authBase = 'https://auth.riotgames.com/api/v1/authorization';
  static const _entitlementUrl =
      'https://entitlements.auth.riotgames.com/api/token/v1';
  static const _geoUrl =
      'https://riot-geo.pas.si.riotgames.com/pas/v1/product/valorant';

  // ── Step 1: Init Cookie Session ───────────────────────────────────────────

  Future<void> initSession() async {
    await _authDio.post<dynamic>(
      _authBase,
      data: {
        'client_id': 'play-valorant-web-prod',
        'nonce': '1',
        'redirect_uri': 'https://playvalorant.com/opt_in',
        'response_type': 'token id_token',
        'scope': 'account openid',
      },
    );
    // Cookies are stored automatically by CookieManager — no body needed.
  }

  // ── Step 2: Submit Username & Password ────────────────────────────────────

  /// Returns:
  /// - `{'type': 'response', 'uri': '...'}` on success without 2FA
  /// - `{'type': 'multifactor', 'email': 'a***@gmail.com'}` when 2FA required
  Future<Map<String, dynamic>> submitCredentials(
      String username, String password) async {
    final response = await _authDio.put<Map<String, dynamic>>(
      _authBase,
      data: {
        'type': 'auth',
        'username': username,
        'password': password,
        'remember': true,
      },
    );

    final data = response.data;
    if (data == null) throw const AuthException('Empty response from auth');

    if (data['error'] == 'auth_failure') {
      throw const InvalidCredentialsException();
    }
    if (data['type'] == 'auth' && data['error'] != null) {
      throw const InvalidCredentialsException();
    }

    if (data['type'] == 'multifactor') {
      final mf = data['multifactor'] as Map<String, dynamic>? ?? {};
      return {
        'type': 'multifactor',
        'email': mf['email'] ?? '',
      };
    }

    if (data['type'] == 'response') {
      final uri = data['response']?['parameters']?['uri'] as String?;
      if (uri == null) throw const AuthException('Missing redirect URI');
      return {'type': 'response', 'uri': uri};
    }

    throw AuthException('Unexpected auth response type: ${data['type']}');
  }

  // ── Step 3: Submit 2FA Code ───────────────────────────────────────────────

  Future<String> submitMfaCode(String code) async {
    final response = await _authDio.put<Map<String, dynamic>>(
      _authBase,
      data: {
        'type': 'multifactor',
        'code': code,
        'rememberDevice': true,
      },
    );

    final data = response.data;
    if (data == null) throw const AuthException('Empty response from MFA');

    if (data['error'] != null) throw const InvalidMfaCodeException();

    final uri = data['response']?['parameters']?['uri'] as String?;
    if (uri == null) throw const AuthException('Missing redirect URI in MFA');
    return uri;
  }

  // ── Step 4: Entitlement Token ─────────────────────────────────────────────

  Future<String> fetchEntitlementToken(String accessToken) async {
    final response = await _plainDio.post<Map<String, dynamic>>(
      _entitlementUrl,
      options: Options(
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
      ),
      data: {},
    );
    final token = response.data?['entitlements_token'] as String?;
    if (token == null) throw const AuthException('Missing entitlement token');
    return token;
  }

  // ── Step 5: Region / Shard via Riot Geo ───────────────────────────────────

  Future<Map<String, String>> fetchRegionAndShard(
      String accessToken, String idToken) async {
    final response = await _plainDio.put<Map<String, dynamic>>(
      _geoUrl,
      options: Options(
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
      ),
      data: {'id_token': idToken},
    );
    final region =
        response.data?['affinities']?['live'] as String? ?? 'ap';
    final shard = Credentials.shardForRegion(region);
    return {'region': region, 'shard': shard};
  }

  // ── Cookie Reauth ─────────────────────────────────────────────────────────

  /// Attempts a silent token refresh using persisted cookies.
  /// Returns the new redirect URI on success, or throws [TokenExpiredException].
  Future<String> cookieReauth() async {
    final response = await _authDio.get<dynamic>(
      _authBase,
      queryParameters: {
        'client_id': 'play-valorant-web-prod',
        'nonce': '1',
        'redirect_uri': 'https://playvalorant.com/opt_in',
        'response_type': 'token id_token',
        'scope': 'openid',
      },
      options: Options(
        followRedirects: false,
        validateStatus: (status) => status != null && status < 400,
      ),
    );

    // Token arrives either in Location header (3xx) or response body (2xx)
    final location = response.headers['location']?.first;
    if (location != null && location.contains('access_token')) {
      return location;
    }

    // Some responses carry token in body
    if (response.data is Map) {
      final uri =
          (response.data as Map)['response']?['parameters']?['uri'] as String?;
      if (uri != null && uri.contains('access_token')) return uri;
    }

    throw const TokenExpiredException();
  }

  // ── URI Parsing Helpers ───────────────────────────────────────────────────

  static Map<String, String> parseTokensFromUri(String redirectUri) {
    // Fragment comes after '#', treat it as query params
    final normalized = redirectUri.contains('#')
        ? redirectUri.replaceFirst('#', '?')
        : redirectUri;
    final uri = Uri.parse(normalized);
    final params = uri.queryParameters;

    final accessToken = params['access_token'];
    final idToken = params['id_token'];
    final expiresIn = int.tryParse(params['expires_in'] ?? '3600') ?? 3600;

    if (accessToken == null) {
      throw const AuthException('access_token not found in redirect URI');
    }

    return {
      'access_token': accessToken,
      'id_token': idToken ?? '',
      'expires_in': expiresIn.toString(),
    };
  }

  static String extractPuuid(String accessToken) {
    final parts = accessToken.split('.');
    if (parts.length < 2) throw const AuthException('Invalid JWT format');

    String payload = parts[1];
    // Add padding
    payload += '=' * ((4 - payload.length % 4) % 4);

    final decoded = utf8.decode(base64Url.decode(payload));
    final json = jsonDecode(decoded) as Map<String, dynamic>;
    final puuid = json['sub'] as String?;
    if (puuid == null) throw const AuthException('sub not found in JWT');
    return puuid;
  }
}
