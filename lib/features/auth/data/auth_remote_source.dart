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
  }

  // ── Step 2: Submit Username & Password ────────────────────────────────────

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

    final type = data['type'] as String?;
    final error = data['error'] as String?;

    // CAPTCHA detected
    if (type == 'auth' && error == 'captcha_not_solved') {
      throw const CaptchaRequiredException();
    }

    // Wrong username/password
    if (error == 'auth_failure') {
      throw const InvalidCredentialsException();
    }

    // Rate limited by Riot
    if (error == 'rate_limited') {
      throw const AuthException('Too many login attempts. Wait a few minutes.');
    }

    // Any other error on type=auth
    if (type == 'auth' && error != null) {
      // Could be CAPTCHA disguised as auth_failure from new IP
      // Give a more helpful message
      throw AuthException(
        'Login blocked by Riot (error: $error).\n'
        'This usually means CAPTCHA. Try again in 2-3 minutes.',
      );
    }

    if (type == 'multifactor') {
      final mf = data['multifactor'] as Map<String, dynamic>? ?? {};
      return {
        'type': 'multifactor',
        'email': mf['email'] ?? '',
        'method': mf['method'] ?? 'email',
      };
    }

    if (type == 'response') {
      final uri = data['response']?['parameters']?['uri'] as String?;
      if (uri == null) throw const AuthException('Missing redirect URI');
      return {'type': 'response', 'uri': uri};
    }

    // Unknown response — show raw for debugging
    throw AuthException(
      'Unexpected response from Riot: type=$type, error=$error\n'
      'Full: ${jsonEncode(data)}',
    );
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

    final error = data['error'] as String?;
    if (error != null) throw const InvalidMfaCodeException();

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

    final location = response.headers['location']?.first;
    if (location != null && location.contains('access_token')) {
      return location;
    }

    if (response.data is Map) {
      final uri =
          (response.data as Map)['response']?['parameters']?['uri'] as String?;
      if (uri != null && uri.contains('access_token')) return uri;
    }

    throw const TokenExpiredException();
  }

  // ── URI Parsing Helpers ───────────────────────────────────────────────────

  static Map<String, String> parseTokensFromUri(String redirectUri) {
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
    payload += '=' * ((4 - payload.length % 4) % 4);

    final decoded = utf8.decode(base64Url.decode(payload));
    final json = jsonDecode(decoded) as Map<String, dynamic>;
    final puuid = json['sub'] as String?;
    if (puuid == null) throw const AuthException('sub not found in JWT');
    return puuid;
  }
}
