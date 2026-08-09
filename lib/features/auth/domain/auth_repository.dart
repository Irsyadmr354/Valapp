import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../core/storage/secure_storage.dart';
import '../data/auth_remote_source.dart';
import '../data/credentials_local_source.dart';
import '../data/silent_webview_reauth.dart';
import '../data/oauth_flow.dart';
import '../domain/models/credentials.dart';
import '../../../core/exceptions/auth_exception.dart';
import '../../../shared/utils/valorant_assets.dart';
import '../../loadout/data/loadout_remote_source.dart';
import '../../loadout/domain/models/player_loadout.dart';
import '../../profile/data/account_remote_source.dart';

/// Orchestrates the full RSO auth flow and token lifecycle.
class AuthRepository {
  const AuthRepository({
    required AuthRemoteSource remoteSource,
    required CredentialsLocalSource localSource,
  })  : _remote = remoteSource,
        _local = localSource;

  final AuthRemoteSource _remote;
  final CredentialsLocalSource _local;

  Future<Credentials> completeLoginFromRedirectUrl(
    String redirectUrl,
    OAuthAttempt attempt,
  ) async {
    final tokens = OAuthFlow.parseTokenRedirect(
      redirectUrl,
      expectedState: attempt.state,
      expectedNonce: attempt.nonce,
    );
    final accessToken = tokens['access_token']!;
    final idToken = tokens['id_token']!;
    final expiresIn = int.parse(tokens['expires_in']!);

    return completeLoginFromWebView(
      accessToken: accessToken,
      idToken: idToken,
      expiresIn: expiresIn,
    );
  }

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

  /// Resolves the real Riot ID display name and Player Card avatar,
  /// then persists the updated profile metadata.
  Future<void> resolveAndSaveMetadata(
    Credentials creds, {
    required AccountRemoteSource accountSource,
    required LoadoutRemoteSource loadoutSource,
    required ValorantAssets assets,
  }) async {
    String? realName;
    String? avatarUrl;
    String? cardId;

    try {
      realName = await accountSource.fetchDisplayName(
        creds.shard,
        creds.puuid,
        accessToken: creds.accessToken,
      );
    } catch (_) {}

    try {
      final rawLoadout =
          await loadoutSource.fetchLoadoutRaw(creds.shard, creds.puuid);
      cardId = PlayerLoadout.extractPlayerCardId(rawLoadout);
      if (cardId != null && cardId.isNotEmpty) {
        final cardsMap = await assets.getPlayerCardsMap();
        final art = PlayerLoadout.resolveCardArtUrls(cardId, cardsMap);
        avatarUrl = art.smallArt;
      }
    } catch (_) {}

    await _local.save(
      creds,
      displayName:
          (realName != null && realName.isNotEmpty) ? realName : null,
      playerCardId: cardId,
      avatarUrl: avatarUrl,
    );
  }

  // ── Silent token refresh ───────────────────────────────────────────────────

  /// Refreshes tokens silently using Dio HTTP cookie reauth (primary - ultra fast)
  /// or WebView session cookies (fallback).
  Future<Credentials> reauth() async {
    final old = await _local.load();
    if (old == null) throw const TokenExpiredException();

    String? uri;
    final attempt = OAuthAttempt.create();

    // PRIMARY: WebView-based silent reauth — uses shared OS native cookie store (WKWebsiteDataStore / CookieManager)
    try {
      uri = await SilentWebviewReauth.instance.refreshTokens(attempt);
    } catch (e) {
      debugPrint('[AuthRepo] Silent WebView reauth failed: $e');

      // FALLBACK: Dio HTTP cookie reauth
      try {
        uri = await _remote.cookieReauth(attempt);
      } catch (e2) {
        debugPrint('[AuthRepo] Dio cookie reauth also failed: $e2');
        if (e is InvalidSessionException || e2 is InvalidSessionException) {
          throw const InvalidSessionException();
        }
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
      debugPrint('[AuthRepo] Reauth returned a token for another account — purging stale cookies');
      try {
        await WebViewCookieManager().clearCookies();
      } catch (_) {}
      throw const InvalidSessionException();
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

  /// Checks if active credentials are expired or near expiry (within 5 minutes).
  /// If so, triggers proactive [reauth()]. Returns null if active session was cleared.
  Future<Credentials?> ensureValidSession() async {
    final creds = await _local.load();
    if (creds == null) return null;

    if (creds.isExpired ||
        creds.expiresAt.difference(DateTime.now()).inMinutes < 5) {
      debugPrint(
          '[AuthRepo] Session expired or near expiry, triggering proactive reauth...');
      try {
        return await reauth();
      } catch (e) {
        debugPrint('[AuthRepo] Proactive reauth failed: $e');
        if (e is InvalidSessionException || e is TokenExpiredException) {
          await _local.clearActiveSessionOnly();
          return null;
        }
        rethrow;
      }
    }
    return creds;
  }

  // ── Logout ─────────────────────────────────────────────────────────────────

  Future<void> logout() => _local.clear();
}

