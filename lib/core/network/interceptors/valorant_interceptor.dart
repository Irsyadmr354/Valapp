import 'package:dio/dio.dart';
import '../../storage/secure_storage.dart';
import '../../../shared/utils/version_service.dart';

/// Automatically injects Valorant auth headers on every API request:
/// - Authorization: Bearer <access_token>
/// - X-Riot-Entitlements-JWT
/// - X-Riot-ClientVersion (fetched & cached)
/// - X-Riot-ClientPlatform (static base64 value)
///
/// Also handles 401 by triggering a token refresh and retrying once.
class ValorantInterceptor extends Interceptor {
  final SecureStorage _secureStorage;
  final VersionService _versionService;

  /// Callback invoked when a 401 cannot be recovered — triggers re-login.
  final Future<void> Function() onAuthFailed;

  /// Callback invoked to silently refresh tokens via cookie reauth.
  final Future<void> Function() onReauth;

  ValorantInterceptor({
    required SecureStorage secureStorage,
    required VersionService versionService,
    required this.onReauth,
    required this.onAuthFailed,
  })  : _secureStorage = secureStorage,
        _versionService = versionService;

  static const _clientPlatform =
      'ew0KCSJwbGF0Zm9ybVR5cGUiOiAiUEMiLA0KCSJwbGF0Zm9ybU9TIjogIldpbmRvd3MiLA0KCSJwbGF0Zm9ybU9TVmVyc2lvbiI6ICIxMC4wLjE5MDQyLjEuMjU2LjY0Yml0IiwNCgkicGxhdGZvcm1DaGlwc2V0IjogIlVua25vd24iDQp9';

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    try {
      final accessToken = await _secureStorage.read(SecureStorage.keyAccessToken);
      final entitlementToken =
          await _secureStorage.read(SecureStorage.keyEntitlementToken);
      final clientVersion = await _versionService.get();

      if (accessToken != null) {
        options.headers['Authorization'] = 'Bearer $accessToken';
      }
      if (entitlementToken != null) {
        options.headers['X-Riot-Entitlements-JWT'] = entitlementToken;
      }
      options.headers['X-Riot-ClientVersion'] = clientVersion;
      options.headers['X-Riot-ClientPlatform'] = _clientPlatform;
      options.headers['Content-Type'] = 'application/json';
    } catch (_) {
      // Best effort — missing headers will surface as 401 anyway.
    }

    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      final alreadyRetried =
          err.requestOptions.extra['authRetried'] as bool? ?? false;

      if (!alreadyRetried) {
        try {
          await onReauth();
          err.requestOptions.extra['authRetried'] = true;

          final dio = Dio();
          final response = await dio.fetch(err.requestOptions);
          handler.resolve(response);
          return;
        } catch (_) {
          await onAuthFailed();
        }
      } else {
        await onAuthFailed();
      }
    }

    handler.next(err);
  }
}
