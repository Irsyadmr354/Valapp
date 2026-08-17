import 'package:dio/dio.dart';
import '../../../core/exceptions/auth_exception.dart';
import '../domain/models/credentials.dart';
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

    throw const TransientReauthException(
        'No redirect received during cookie reauth');
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
