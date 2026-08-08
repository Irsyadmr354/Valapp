import 'package:dio/dio.dart';
import '../../../core/exceptions/auth_exception.dart';
import '../domain/models/credentials.dart';
import '../domain/models/rso_auth_result.dart';
import 'oauth_flow.dart';

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

  // ── Native RSO Authentication ─────────────────────────────────────────────

  Future<void> initRsoAuthorization(OAuthAttempt attempt) async {
    try {
      await _authDio.post<Map<String, dynamic>>(
        _authBase,
        data: {
          'client_id': OAuthFlow.clientId,
          'nonce': attempt.nonce,
          'redirect_uri': OAuthFlow.redirectUri.toString(),
          'response_type': 'token id_token',
          'scope': 'account openid',
        },
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );
    } on DioException catch (e) {
      throw AuthException('Failed to initialize Riot login: ${e.message}');
    }
  }

  Future<RsoAuthResult> submitRsoCredentials(
    String username,
    String password,
    bool rememberMe,
  ) async {
    try {
      final response = await _authDio.put<Map<String, dynamic>>(
        _authBase,
        data: {
          'type': 'auth',
          'username': username,
          'password': password,
          'remember': rememberMe,
        },
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      return _parseRsoResponse(response.data);
    } on DioException catch (e) {
      return RsoAuthError('Network error during login: ${e.message}');
    }
  }

  Future<RsoAuthResult> submitRsoMultifactor(
    String code,
    bool rememberDevice,
  ) async {
    try {
      final response = await _authDio.put<Map<String, dynamic>>(
        _authBase,
        data: {
          'type': 'multifactor',
          'code': code,
          'rememberDevice': rememberDevice,
        },
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      return _parseRsoResponse(response.data);
    } on DioException catch (e) {
      return RsoAuthError('Network error during 2FA verification: ${e.message}');
    }
  }

  RsoAuthResult _parseRsoResponse(Map<String, dynamic>? data) {
    if (data == null) {
      return const RsoAuthError('Empty response from Riot authentication server.');
    }

    final type = data['type'] as String?;

    if (type == 'response') {
      final uri = data['response']?['parameters']?['uri'] as String?;
      if (uri != null && uri.isNotEmpty) {
        return RsoAuthSuccess(uri);
      }
      return const RsoAuthError('Authentication succeeded but redirect URI missing.');
    }

    if (type == 'multifactor') {
      final mf = data['multifactor'] as Map<String, dynamic>? ?? {};
      final method = mf['method'] as String? ?? 'email';
      final methodsList = (mf['methods'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [method];
      final email = mf['email'] as String?;
      final codeLength = (mf['multiFactorCodeLength'] as int?) ?? 6;

      return RsoAuthMultifactor(
        method: method,
        methods: methodsList,
        email: email,
        codeLength: codeLength,
      );
    }

    if (type == 'error') {
      final error = data['error'] as String? ?? '';
      if (error == 'auth_failure') {
        return const RsoAuthError('Invalid username or password. Please check your credentials.');
      } else if (error == 'rate_limited') {
        return const RsoAuthError('Too many login attempts. Please wait a few minutes and try again.');
      } else if (error == 'captcha_needed' || error == 'cloudflare_challenge') {
        return const RsoAuthError('Captcha security check required.', isCaptcha: true);
      } else if (error == 'multifactor_attempt_failed') {
        return const RsoAuthError('Invalid 2FA verification code. Please try again.');
      }
      return RsoAuthError('Riot login error: $error');
    }

    return RsoAuthError('Unexpected response from Riot servers ($type).');
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
    final token = response.data?['entitlements_token'];
    if (token is! String || token.trim().isEmpty) {
      throw const AuthException('Missing entitlement token');
    }
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
    final affinities = response.data?['affinities'];
    final region =
        affinities is Map<String, dynamic> ? affinities['live'] : null;
    if (region is! String || !Credentials.isSupportedRegion(region)) {
      throw const AuthException('Invalid region response');
    }
    final shard = Credentials.shardForRegion(region);
    return {'region': region, 'shard': shard};
  }

  // ── Cookie Reauth ─────────────────────────────────────────────────────────

  Future<String> cookieReauth(OAuthAttempt attempt) async {
    late final Response<dynamic> response;
    try {
      response = await _authDio.get<dynamic>(
        _authBase,
        queryParameters: attempt.authorizeUri.queryParameters,
        options: Options(
          followRedirects: false,
          validateStatus: (status) => status != null && status < 500,
        ),
      );
    } on DioException catch (e) {
      throw TransientReauthException(
          'Reauthentication request failed: ${e.type.name}');
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const InvalidSessionException();
    }
    if (response.statusCode == null || response.statusCode! >= 400) {
      throw const TransientReauthException();
    }

    final location = response.headers['location']?.first;
    if (location != null &&
        OAuthFlow.isRedirectUri(Uri.tryParse(location) ?? Uri())) {
      return location;
    }

    if (response.data is Map) {
      final uri =
          (response.data as Map)['response']?['parameters']?['uri'] as String?;
      if (uri != null && OAuthFlow.isRedirectUri(Uri.tryParse(uri) ?? Uri())) {
        return uri;
      }
    }

    throw const InvalidSessionException();
  }

  // ── URI Parsing Helpers ───────────────────────────────────────────────────

  static String extractPuuid(String accessToken) {
    final puuid = OAuthFlow.decodeJwtPayload(accessToken)['sub'];
    if (puuid is! String || puuid.trim().isEmpty) {
      throw const AuthException('sub not found in JWT');
    }
    return puuid;
  }
}
