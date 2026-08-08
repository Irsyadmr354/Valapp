import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../core/exceptions/auth_exception.dart';
import '../../storage/secure_storage.dart';
import '../../../features/auth/data/credentials_local_source.dart';
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
  late final CredentialsLocalSource _credentials =
      CredentialsLocalSource(_secureStorage);

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
  late final Dio _retryDio = Dio();

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

      final credentials = await _credentials.load();
      final clientVersion = await _versionService.get();

      if (credentials != null) {
        options.headers['Authorization'] = 'Bearer ${credentials.accessToken}';
        options.headers['X-Riot-Entitlements-JWT'] =
            credentials.entitlementToken;
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
    final credentials = await _credentials.load();
    if (credentials == null) {
      _lastReauthCheckAt = DateTime.now();
      return;
    }

    final needsReauth =
        credentials.isExpired || credentials.isEntitlementExpired;

    if (!needsReauth) {
      // Tokens are still valid — set cooldown so we don't re-check for 60s.
      _lastReauthCheckAt = DateTime.now();
      return;
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
    final status = err.response?.statusCode;

    if (status == 401 || status == 403) {
      final handled = await _attemptReauthAndRetry(
        err,
        handler,
        retryFlag: 'authRetried',
      );
      if (handled) return;
    }

    // Riot often returns 400 (not 401) when entitlement token is stale.
    // On pd.*.a.pvp.net endpoints (storefront, wallet, MMR, etc.) a 400
    // almost always means the access/entitlement token is expired — the
    // response body is frequently empty or generic with no auth hints.
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
      final body =
          data is String ? data.toLowerCase() : jsonEncode(data).toLowerCase();

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
      ];

      if (authHints.any(body.contains)) return true;
    }

    // Strategy 2: Riot PD endpoints returning empty body on 400 are usually stale tokens.
    final url = err.requestOptions.uri;
    if (_isRiotGameApiEndpoint(url) && (data == null || (data is Map && data.isEmpty))) {
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
