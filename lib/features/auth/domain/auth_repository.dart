import 'package:flutter/foundation.dart';
import '../../../core/storage/secure_storage.dart';
import '../data/auth_remote_source.dart';
import '../data/credentials_local_source.dart';
import '../data/silent_webview_reauth.dart';
import '../data/oauth_flow.dart';
import '../domain/models/credentials.dart';
import '../../../core/exceptions/auth_exception.dart';

/// Orchestrates the full RSO auth flow and token lifecycle.
class AuthRepository {
  const AuthRepository({
    required AuthRemoteSource remoteSource,
    required CredentialsLocalSource localSource,
  })  : _remote = remoteSource,
        _local = localSource;

  final AuthRemoteSource _remote;
  final CredentialsLocalSource _local;

  // ── Login from WebView ─────────────────────────────────────────────────────

  /// Called after WebView login — tokens already parsed, just fetch
  /// entitlement + geo and save credentials.
  Future<Credentials> completeLoginFromWebView({
    required String accessToken,
    required String idToken,
    required int expiresIn,
  }) async {
    final entitlementToken = await _remote.fetchEntitlementToken(accessToken);
    final geoData = await _remote.fetchRegionAndShard(accessToken, idToken);
    final puuid = AuthRemoteSource.extractPuuid(accessToken);

    final credentials = Credentials(
      accessToken: accessToken,
      idToken: idToken,
      entitlementToken: entitlementToken,
      puuid: puuid,
      region: geoData['region']!,
      shard: geoData['shard']!,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      entitlementExpiresAt: DateTime.now().add(
        SecureStorage.entitlementTokenLifetime,
      ),
    );

    await _local.save(credentials);
    return credentials;
  }

  // ── Silent token refresh ───────────────────────────────────────────────────

  /// Refreshes tokens silently using background WebView session cookies (primary)
  /// or Dio cookie reauth (fallback).
  ///
  /// On iOS, WKWebView instances share cookies via the default WKWebsiteDataStore,
  /// so the `ssid` session cookie from the initial WebView login is automatically
  /// available to SilentWebviewReauth. This is why WebView reauth is tried FIRST.
  Future<Credentials> reauth() async {
    final old = await _local.load();
    if (old == null) throw const TokenExpiredException();

    String? uri;
    final attempt = OAuthAttempt.create();

    // PRIMARY: WebView-based reauth — uses shared WKWebView cookie store (ssid)
    try {
      uri = await SilentWebviewReauth.instance.refreshTokens(attempt);
    } catch (e) {
      debugPrint('[AuthRepo] WebView reauth failed: $e');

      // FALLBACK: Dio HTTP cookie reauth — uses PersistCookieJar
      try {
        uri = await _remote.cookieReauth(attempt);
      } on InvalidSessionException {
        rethrow;
      } catch (e2) {
        debugPrint('[AuthRepo] Dio cookie reauth also failed: $e2');
        throw const TransientReauthException();
      }
    }

    final tokens = OAuthFlow.parseTokenRedirect(
      uri,
      expectedState: attempt.state,
      expectedNonce: attempt.nonce,
    );
    final accessToken = tokens['access_token']!;
    final idToken = tokens['id_token']!;
    final expiresIn = int.parse(tokens['expires_in']!);
    final refreshedPuuid = AuthRemoteSource.extractPuuid(accessToken);
    if (refreshedPuuid != old.puuid) {
      debugPrint('[AuthRepo] Reauth returned a token for another account');
      throw StateError('Reauth returned credentials for another account');
    }

    final entitlementToken = await _remote.fetchEntitlementToken(accessToken);

    final updated = old.copyWith(
      accessToken: accessToken,
      idToken: idToken,
      entitlementToken: entitlementToken,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      entitlementExpiresAt: DateTime.now().add(
        SecureStorage.entitlementTokenLifetime,
      ),
    );

    final saved = await _local.saveIfCurrent(old, updated);
    if (!saved) {
      debugPrint('[AuthRepo] Active session changed during reauth');
      throw StateError('Active session changed during reauth');
    }
    debugPrint(
        '[AuthRepo] Reauth SUCCESS — new token expires at ${updated.expiresAt}');
    return updated;
  }

  // ── Logout ─────────────────────────────────────────────────────────────────

  Future<void> logout() => _local.clear();
}
