import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../core/exceptions/auth_exception.dart';
import '../../storage/secure_storage.dart';
import '../../../features/auth/data/credentials_local_source.dart';
import '../../../shared/utils/version_service.dart';

import '../valorant_headers.dart';
import 'rate_limit_interceptor.dart';
import 'retry_interceptor.dart';

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
  late final CredentialsLocalSource _credentials =
      CredentialsLocalSource(_secureStorage);

  /// Callback invoked when a 401 cannot be recovered — triggers re-login.
  final Future<void> Function() onAuthFailed;

  /// Callback invoked to silently refresh tokens via cookie reauth.
  final Future<void> Function() onReauth;

  /// Callback invoked to refresh only the entitlement token using valid accessToken.
  final Future<void> Function()? onRefreshEntitlement;

  ValorantInterceptor({
    required SecureStorage secureStorage,
    required VersionService versionService,
    required this.onReauth,
    required this.onAuthFailed,
    this.onRefreshEntitlement,
  })  : _secureStorage = secureStorage,
        _versionService = versionService;

  /// Shared Dio instance used when retrying a request after reauth.
  /// Created lazily and reused to avoid allocating a new instance per retry.
  /// Timeouts mirror createApiDio — a bare Dio() would default to no timeout
  /// and let a hung retry connection block forever.
  late final Dio _retryDio = () {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ));
    dio.interceptors.addAll([
      RateLimitInterceptor(),
      RetryInterceptor(dio),
    ]);
    return dio;
  }();

  /// Tracks when we last ran the proactive reauth check so we don't re-read
  /// SecureStorage on every single API request. The check is skipped if it
  /// ran within the last 60 seconds.
  DateTime? _lastReauthCheckAt;
  static const _reauthCheckCooldown = Duration(seconds: 60);

  /// In-flight reauth future. When one request is already performing the
  /// proactive reauth, every other concurrent request awaits this same
  /// future instead of starting a duplicate reauth round-trip.
  Future<void>? _reauthInFlight;
  Future<void>? _proactiveCheckInFlight;

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    try {
      await _maybeProactiveReauth();
    } catch (_) {
      // The proactive check logs and recovers internally; never let it
      // block or crash the request pipeline.
    }

    await _injectHeaders(options);

    handler.next(options);
  }

  /// Injects auth/version headers with ONE bounded retry.
  ///
  /// Previously any exception here was swallowed and the request continued
  /// WITHOUT auth headers — guaranteeing a 401 and a needless full WebView
  /// reauth round-trip for what is usually a transient platform-channel
  /// hiccup while reading SecureStorage.
  Future<void> _injectHeaders(RequestOptions options) async {
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        final credentials = await _credentials.loadCached();
        final clientVersion = await _versionService.get();

        if (credentials != null) {
          options.headers['Authorization'] =
              'Bearer ${credentials.accessToken}';
          options.headers['X-Riot-Entitlements-JWT'] =
              credentials.entitlementToken;
        }
        options.headers['X-Riot-ClientVersion'] = clientVersion;
        options.headers['X-Riot-ClientPlatform'] =
            ValorantHeaders.clientPlatform;
        if (options.data != null ||
            (options.method.toUpperCase() != 'GET' &&
                options.method.toUpperCase() != 'HEAD')) {
          options.headers['Content-Type'] = 'application/json';
        }
        return;
      } catch (e) {
        if (attempt == 2) {
          debugPrint(
              '[ValorantInterceptor] Header injection failed after retry: $e');
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }
  }

  Future<void> _maybeProactiveReauth() async {
    final reauth = _reauthInFlight;
    if (reauth != null) return reauth;

    final existingCheck = _proactiveCheckInFlight;
    if (existingCheck != null) return existingCheck;

    // Skip if we already checked recently — avoids two SecureStorage reads
    // and a potential reauth round-trip on every concurrent API call.
    final now = DateTime.now();
    if (_lastReauthCheckAt != null &&
        now.difference(_lastReauthCheckAt!) < _reauthCheckCooldown) {
      return;
    }

    final operation = _checkAndMaybeReauth();
    _proactiveCheckInFlight = operation;
    try {
      await operation;
    } finally {
      if (identical(_proactiveCheckInFlight, operation)) {
        _proactiveCheckInFlight = null;
      }
    }
  }

  Future<void> _checkAndMaybeReauth() async {
    final credentials = await _credentials.loadCached();
    if (credentials == null) {
      _lastReauthCheckAt = DateTime.now();
      return;
    }

    final accessValid = !credentials.isExpired;
    final entitlementStale = credentials.isEntitlementExpired;

    if (accessValid && !entitlementStale) {
      // Tokens are still valid — set cooldown so we don't re-check for 60s.
      _lastReauthCheckAt = DateTime.now();
      return;
    }

    // Fast path: if accessToken is still valid and only entitlement is expired/stale,
    // refresh only the entitlement token (< 200ms) without triggering WebView reauth (~15s).
    if (entitlementStale && accessValid && onRefreshEntitlement != null) {
      debugPrint(
          '[ValorantInterceptor] Entitlement token near expiry, refreshing entitlement only...');
      try {
        await onRefreshEntitlement!();
        _lastReauthCheckAt = DateTime.now();
        debugPrint(
            '[ValorantInterceptor] Proactive entitlement refresh completed');
        return;
      } catch (e) {
        debugPrint(
            '[ValorantInterceptor] Proactive entitlement refresh failed, falling back to full reauth: $e');
      }
    }

    debugPrint(
        '[ValorantInterceptor] Token near expiry, triggering proactive reauth...');
    try {
      await _runSharedReauth();
      // Reauth succeeded — set cooldown with fresh timestamp.
      _lastReauthCheckAt = DateTime.now();
      debugPrint('[ValorantInterceptor] Proactive reauth completed');
    } catch (e) {
      // Reauth failed — do NOT set cooldown so the next request retries
      // instead of being blocked for 60 seconds with expired tokens.
      _lastReauthCheckAt = null;
      debugPrint('[ValorantInterceptor] Proactive reauth failed: $e');
    }
  }

  Future<void> _runSharedReauth() async {
    final inFlight = _reauthInFlight;
    if (inFlight != null) return inFlight;

    final operation = onReauth();
    _reauthInFlight = operation;
    try {
      await operation;
    } finally {
      if (identical(_reauthInFlight, operation)) {
        _reauthInFlight = null;
      }
    }
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    try {
      final status = err.response?.statusCode;

      if (status == 401 || status == 403) {
        final handled = await _attemptReauthAndRetry(
          err,
          handler,
          retryFlag: 'authRetried',
        );
        if (handled) return;
      }

      // Riot often returns 400 (not 401) when entitlement token is stale or desynced.
      // On pd.*.a.pvp.net endpoints (storefront, wallet, MMR, etc.) a 400
      // almost always means the entitlement token needs renewal.
      if (status == 400 && _isLikelyAuthError(err)) {
        // Step 1: Fast entitlement refresh if accessToken is still valid (< 200ms, no cookies needed)
        final handledEntitlement = await _attemptEntitlementRefreshAndRetry(
          err,
          handler,
        );
        if (handledEntitlement) return;

        // Step 2: Fallback to full reauth if fast entitlement refresh was unable to resolve
        final handled = await _attemptReauthAndRetry(
          err,
          handler,
          retryFlag: 'entitlementRetried',
        );
        if (handled) return;
      }

      handler.next(err);
    } catch (_) {
      // Ensure handler is always resolved even if SecureStorage or helper throws
      // synchronously (e.g. platform channel failure) — otherwise request hangs.
      try {
        handler.next(err);
      } catch (_) {}
    }
  }

  /// Determines whether a 400 response is likely caused by expired auth tokens.
  ///
  /// Two strategies:
  /// 1. **Endpoint heuristic** — requests to `pd.*.a.pvp.net` (Riot game API)
  ///    always require valid auth. A 400 on these endpoints is almost certainly
  ///    an auth rejection (Riot returns 400 instead of 401 for stale entitlement
  ///    tokens, and the body is often empty or `{}`).
  /// 2. **Body keyword heuristic** — for other endpoints, check the response
  ///    body for auth-related keywords.
  bool _isLikelyAuthError(DioException err) {
    final data = err.response?.data;
    if (data != null) {
      // toString() instead of jsonEncode: jsonEncode throws on non-encodable
      // bodies, and an exception escaping this method inside onError would
      // leave the handler unresolved (request hangs forever).
      final body = data is String
          ? data.toLowerCase()
          : data.toString().toLowerCase();

      // Explicit non-auth error indicators returned by Riot API
      const nonAuthHints = [
        'validation_issue',
        'invalid_argument',
        'bad_request_body',
        'not_found',
        'resource_not_found',
        'invalid query',
      ];
      if (nonAuthHints.any(body.contains)) return false;

      const authHints = [
        'entitlement',
        'unauthorized',
        'bad_claims',
        'bad claims',
        'invalid_token',
        'invalid token',
        'forbidden',
        'authentication',
        'token_expired',
        'token expired',
        'session_expired',
        'expired',
      ];

      if (authHints.any(body.contains)) return true;
    }

    final url = err.requestOptions.uri;
    if (_isRiotGameApiEndpoint(url)) {
      return true;
    }

    return false;
  }

  /// Returns true for Riot PD (player data) endpoints that always require
  /// valid auth headers. Pattern: `pd.<shard>.a.pvp.net`.
  static bool _isRiotGameApiEndpoint(Uri url) {
    final host = url.host;
    return host.endsWith('.a.pvp.net') || host.endsWith('.pvp.net');
  }

  Future<bool> _attemptEntitlementRefreshAndRetry(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final alreadyRetried =
        err.requestOptions.extra['entitlementRefreshRetried'] as bool? ?? false;
    if (alreadyRetried) return false;
    if (onRefreshEntitlement == null) return false;

    debugPrint(
        '[ValorantInterceptor] Got 400 on PD endpoint — attempting fast entitlement refresh...');
    try {
      final creds = await _credentials.load();
      if (creds == null || creds.isExpired) return false;
      err.requestOptions.extra['entitlementRefreshRetried'] = true;
      await onRefreshEntitlement!();

      final freshCredentials = await _credentials.load();
      if (freshCredentials != null) {
        err.requestOptions.headers['Authorization'] =
            'Bearer ${freshCredentials.accessToken}';
        err.requestOptions.headers['X-Riot-Entitlements-JWT'] =
            freshCredentials.entitlementToken;
      }

      final retryDio = _retryDio;
      final response = await retryDio.fetch(err.requestOptions);
      debugPrint(
          '[ValorantInterceptor] 400 fast entitlement refresh retry succeeded');
      handler.resolve(response);
      return true;
    } catch (e) {
      debugPrint(
          '[ValorantInterceptor] Fast entitlement refresh retry failed: $e');
      return false;
    }
  }

  Future<bool> _attemptReauthAndRetry(
    DioException err,
    ErrorInterceptorHandler handler, {
    required String retryFlag,
  }) async {
    final alreadyRetried =
        err.requestOptions.extra[retryFlag] as bool? ?? false;
    if (alreadyRetried) return false;

    debugPrint(
        '[ValorantInterceptor] Got ${err.response?.statusCode} (auth) — attempting reauth...');
    try {
      await _runSharedReauth();

      // Reactive reauth succeeded — clear proactive cooldown so subsequent
      // requests use the freshly-set timestamp instead of a stale one.
      _lastReauthCheckAt = DateTime.now();

      err.requestOptions.extra[retryFlag] = true;

      final freshCredentials = await _credentials.load();
      if (freshCredentials != null) {
        err.requestOptions.headers['Authorization'] =
            'Bearer ${freshCredentials.accessToken}';
        err.requestOptions.headers['X-Riot-Entitlements-JWT'] =
            freshCredentials.entitlementToken;
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
      // Clear cooldown so next request can retry proactive reauth.
      _lastReauthCheckAt = null;
      // Do not clear credentials on transient errors or timeouts — keep session intact.
      // Only clear if error is explicitly an unrecoverable auth rejection.
      if (e is TokenExpiredException || e is InvalidSessionException) {
        await onAuthFailed();
      }
      return false;
    }
  }
}
