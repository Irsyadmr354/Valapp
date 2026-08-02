import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../core/exceptions/auth_exception.dart';
import '../../storage/secure_storage.dart';
import '../../../shared/utils/version_service.dart';

/// Automatically injects Valorant auth headers on every API request:
/// - Authorization: Bearer <access_token>
/// - X-Riot-Entitlements-JWT
/// - X-Riot-ClientVersion (fetched & cached)
/// - X-Riot-ClientPlatform (static base64 value)
///
/// Handles 401 and auth-related 400 by triggering token refresh and retrying once.
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

  /// Shared Dio instance used when retrying a request after reauth.
  /// Created lazily and reused to avoid allocating a new instance per retry.
  late final Dio _retryDio = Dio()
    ..interceptors.add(_JsonDecodeInterceptor());

  /// Tracks when we last ran the proactive reauth check so we don't re-read
  /// SecureStorage on every single API request. The check is skipped if it
  /// ran within the last 60 seconds.
  DateTime? _lastReauthCheckAt;
  static const _reauthCheckCooldown = Duration(seconds: 60);

  /// In-flight reauth future. When one request is already performing the
  /// proactive reauth, every other concurrent request awaits this same
  /// future instead of starting a duplicate reauth round-trip.
  Future<void>? _reauthInFlight;

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    try {
      await _maybeProactiveReauth();

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
      if (options.data != null ||
          (options.method.toUpperCase() != 'GET' &&
              options.method.toUpperCase() != 'HEAD')) {
        options.headers['Content-Type'] = 'application/json';
      }
    } catch (e) {
      debugPrint('[ValorantInterceptor] Error injecting headers: $e');
    }

    handler.next(options);
  }

  Future<void> _maybeProactiveReauth() async {
    // If another request already kicked off the reauth, piggyback on it
    // instead of starting a second one in parallel.
    if (_reauthInFlight != null) {
      await _reauthInFlight;
      return;
    }

    // Skip if we already checked recently — avoids two SecureStorage reads
    // and a potential reauth round-trip on every concurrent API call.
    final now = DateTime.now();
    if (_lastReauthCheckAt != null &&
        now.difference(_lastReauthCheckAt!) < _reauthCheckCooldown) {
      return;
    }
    // Claim the slot immediately before any await so no other concurrent
    // caller can slip past the cooldown check while we're doing I/O.
    _lastReauthCheckAt = now;

    final expiresAtStr = await _secureStorage.read(SecureStorage.keyExpiresAt);
    final entitlementExpiresAtStr =
        await _secureStorage.read(SecureStorage.keyEntitlementExpiresAt);

    var needsReauth = false;

    if (expiresAtStr != null) {
      final expiresAt = DateTime.tryParse(expiresAtStr);
      if (expiresAt != null &&
          DateTime.now().isAfter(
              expiresAt.subtract(SecureStorage.proactiveRefreshWindow))) {
        needsReauth = true;
      }
    }

    if (entitlementExpiresAtStr != null) {
      final entitlementExpiresAt =
          DateTime.tryParse(entitlementExpiresAtStr);
      if (entitlementExpiresAt != null &&
          DateTime.now().isAfter(entitlementExpiresAt
              .subtract(SecureStorage.proactiveRefreshWindow))) {
        needsReauth = true;
      }
    } else {
      // No entitlement expiry tracked — treat as potentially stale.
      needsReauth = true;
    }

    if (!needsReauth) return;

    debugPrint(
        '[ValorantInterceptor] Token near expiry, triggering proactive reauth...');

    // Store the in-flight future so concurrent callers await the same work.
    _reauthInFlight = _doProactiveReauth();
    try {
      await _reauthInFlight;
    } finally {
      _reauthInFlight = null;
    }
  }

  Future<void> _doProactiveReauth() async {
    try {
      await onReauth();
      debugPrint('[ValorantInterceptor] Proactive reauth completed');
    } catch (e) {
      debugPrint('[ValorantInterceptor] Proactive reauth failed: $e');
    }
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final status = err.response?.statusCode;

    if (status == 401) {
      final handled = await _attemptReauthAndRetry(
        err,
        handler,
        retryFlag: 'authRetried',
      );
      if (handled) return;
    }

    // Riot often returns 400 (not 401) when entitlement token is stale.
    if (status == 400 && _isLikelyAuthError(err)) {
      final handled = await _attemptReauthAndRetry(
        err,
        handler,
        retryFlag: 'entitlementRetried',
      );
      if (handled) return;
    }

    handler.next(err);
  }

  /// Heuristic: only treat 400 as auth-related when the body hints at token/entitlement issues.
  bool _isLikelyAuthError(DioException err) {
    final data = err.response?.data;
    if (data == null) {
      // Empty 400 on pd.* endpoints is commonly a stale entitlement token.
      return true;
    }

    final body = data is String
        ? data.toLowerCase()
        : jsonEncode(data).toLowerCase();

    const authHints = [
      'entitlement',
      'unauthorized',
      'bad_claims',
      'bad claims',
      'invalid_token',
      'invalid token',
      'token',
      'forbidden',
      'authentication',
      'auth',
    ];

    return authHints.any(body.contains);
  }

  Future<bool> _attemptReauthAndRetry(
    DioException err,
    ErrorInterceptorHandler handler, {
    required String retryFlag,
  }) async {
    final alreadyRetried = err.requestOptions.extra[retryFlag] as bool? ?? false;
    if (alreadyRetried) return false;

    debugPrint(
        '[ValorantInterceptor] Got ${err.response?.statusCode} (auth) — attempting reauth...');
    try {
      await onReauth();
      err.requestOptions.extra[retryFlag] = true;

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

      final retryDio = _retryDio;
      final response = await retryDio.fetch(err.requestOptions);
      debugPrint(
          '[ValorantInterceptor] ${err.response?.statusCode} retry succeeded');
      handler.resolve(response);
      return true;
    } catch (e) {
      debugPrint(
          '[ValorantInterceptor] Reauth failed (will preserve session for retry): $e');
      // Do not clear credentials on transient errors or timeouts — keep session intact.
      // Only clear if error is explicitly an unrecoverable auth rejection.
      if (e is AuthException && e.message.contains('invalid_grant')) {
        await onAuthFailed();
      }
      return false;
    }
  }
}

/// Minimal interceptor that decodes string JSON responses into Maps/Lists,
/// needed for the retry Dio instance used after reauth.
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
    return (const JsonDecoder()).convert(str);
  }
}
