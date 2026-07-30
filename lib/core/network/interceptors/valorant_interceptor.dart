import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
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
      // Proactive silent refresh: if token is near expiration (<5 mins remaining), refresh before sending
      final expiresAtStr = await _secureStorage.read(SecureStorage.keyExpiresAt);
      if (expiresAtStr != null) {
        final expiresAt = DateTime.tryParse(expiresAtStr);
        if (expiresAt != null &&
            DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 5)))) {
          debugPrint('[ValorantInterceptor] Token near expiry, triggering proactive reauth...');
          try {
            await onReauth();
            debugPrint('[ValorantInterceptor] Proactive reauth completed');
          } catch (e) {
            debugPrint('[ValorantInterceptor] Proactive reauth failed: $e');
          }
        }
      }

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
      if (options.data != null || (options.method.toUpperCase() != 'GET' && options.method.toUpperCase() != 'HEAD')) {
        options.headers['Content-Type'] = 'application/json';
      }
    } catch (e) {
      debugPrint('[ValorantInterceptor] Error injecting headers: $e');
    }

    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final status = err.response?.statusCode;
    // ONLY 401 Unauthorized indicates an expired access_token needing reauth
    if (status == 401) {
      final alreadyRetried =
          err.requestOptions.extra['authRetried'] as bool? ?? false;

      if (!alreadyRetried) {
        debugPrint('[ValorantInterceptor] Got 401 — attempting reauth...');
        try {
          await onReauth();
          err.requestOptions.extra['authRetried'] = true;

          // Re-read fresh tokens from storage and update headers
          final freshAccessToken =
              await _secureStorage.read(SecureStorage.keyAccessToken);
          final freshEntitlement =
              await _secureStorage.read(SecureStorage.keyEntitlementToken);
          if (freshAccessToken != null) {
            err.requestOptions.headers['Authorization'] =
                'Bearer $freshAccessToken';
          }
          if (freshEntitlement != null) {
            err.requestOptions.headers['X-Riot-Entitlements-JWT'] =
                freshEntitlement;
          }

          // Retry the request with a minimal Dio that includes JSON parsing
          // (do NOT use the original Dio — it would re-trigger all interceptors)
          final retryDio = Dio();
          retryDio.interceptors.add(_JsonDecodeInterceptor());
          final response = await retryDio.fetch(err.requestOptions);
          debugPrint('[ValorantInterceptor] 401 retry succeeded');
          handler.resolve(response);
          return;
        } catch (e) {
          debugPrint('[ValorantInterceptor] 401 reauth failed — triggering onAuthFailed: $e');
          await onAuthFailed();
        }
      }
    }

    handler.next(err);
  }
}

/// Minimal interceptor that decodes string JSON responses into Maps/Lists,
/// needed for the retry Dio instance used after 401 reauth.
class _JsonDecodeInterceptor extends Interceptor {
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (response.data is String) {
      final str = (response.data as String).trim();
      if (str.startsWith('{') || str.startsWith('[')) {
        try {
          response.data = _jsonDecode(str);
        } catch (_) {}
      }
    }
    handler.next(response);
  }

  dynamic _jsonDecode(String str) {
    // Import-free JSON decode using dart:convert
    return (const JsonDecoder()).convert(str);
  }
}
