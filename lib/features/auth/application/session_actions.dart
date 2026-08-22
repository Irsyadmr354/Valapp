import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

// NOTE(ARCH-06): This application-layer file imports core/di/providers.dart
// because SessionActions must reference the provider objects it reads and
// invalidates, and they all live there today. The reverse edge
// (providers.dart importing this file to re-export SessionActions) forms an
// import cycle, which Dart resolves safely here: neither side runs top-level
// initializers that depend on the other — Riverpod providers build lazily and
// this file only declares a plain class plus an unmutated provider list.
// Do not widen this surface further (no presentation imports on either side);
// new dependencies should arrive via Ref or constructor parameters instead.
import '../../../core/di/providers.dart';
import '../../../core/storage/cache_storage.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/utils/async_lock.dart';
import '../data/credentials_local_source.dart';

/// ARCH-04: every dependency whose cached state must not survive an account
/// change (switch / logout / removal / reauth). Single source of truth for
/// [SessionActions.invalidateSession] — when adding a new session-bound
/// provider, register it here instead of growing a manual invalidate list.
///
/// Most entries already transitively `watch` [currentCredentialsProvider] or
/// [apiDioProvider], so Riverpod's rebuild cascade would refresh them anyway;
/// they are invalidated explicitly as belt-and-braces so a broken watch chain
/// (e.g. state captured via `ref.read`) can never leak across accounts.
final List<ProviderOrFamily> _sessionBoundProviders = [
  // Reactive session root + authenticated HTTP stack.
  currentCredentialsProvider,
  apiDioProvider,
  // Remote sources & repositories bound to the authenticated Dio.
  storeRemoteSourceProvider,
  storeRepositoryProvider,
  matchRemoteSourceProvider,
  matchRepositoryProvider,
  mmrRemoteSourceProvider,
  contractsRemoteSourceProvider,
  contractsRepositoryProvider,
  accountRemoteSourceProvider,
  restrictionsRemoteSourceProvider,
  loadoutRemoteSourceProvider,
  loadoutRepositoryProvider,
  // User-scoped shared data pipelines (watch currentCredentialsProvider).
  accountXpProvider,
  displayNameProvider,
  playerMmrProvider,
  competitiveUpdatesProvider,
  playerCardArtProvider,
  enrichedMatchHistoryProvider,
];

/// Serializes account changes and invalidates every session-bound dependency
/// as one operation. Widgets should not perform these steps independently.
class SessionActions {
  SessionActions(this._ref);

  final Ref _ref;

  /// Restores saved Riot session cookies for [puuid] into the native
  /// WebView cookie store. Caller must have cleared stale cookies first.
  Future<void> _restoreWebViewCookies(String puuid) async {
    try {
      final savedRaw = await SecureStorage.instance.read(
        SecureStorage.keyRiotCookiesFor(puuid),
      );
      if (savedRaw != null && savedRaw.isNotEmpty) {
        final cookieMgr = WebViewCookieManager();
        final pairs = savedRaw.split(';');
        for (final pair in pairs) {
          final parts = pair.split('=');
          if (parts.length >= 2) {
            final name = parts[0].trim();
            final value = parts.sublist(1).join('=').trim();
            if (name.isNotEmpty && value.isNotEmpty) {
              await cookieMgr.setCookie(
                WebViewCookie(
                  name: name,
                  value: value,
                  domain: 'auth.riotgames.com',
                  path: '/',
                ),
              );
              await cookieMgr.setCookie(
                WebViewCookie(
                  name: name,
                  value: value,
                  domain: '.riotgames.com',
                  path: '/',
                ),
              );
            }
          }
        }
      }
    } catch (_) {}
  }

  /// Purges every cookie source so no previous account's session can leak
  /// into a silent reauth for the new account.
  Future<void> _purgeCookieStores() async {
    try {
      final jar = await _ref.read(cookieJarProvider.future);
      await jar.deleteAll();
    } catch (_) {}
    // Clear native cookies BEFORE restoring the target's backup — otherwise a
    // leftover `ssid` from the previous account can authenticate the WRONG
    // account when the target has no stored backup.
    try {
      await WebViewCookieManager().clearCookies();
    } catch (_) {}
  }

  /// Shared activation pipeline for explicit switches AND the auto-switch
  /// after removing the active account: purge cookie stores → restore the
  /// target's backup cookies → optional entitlement refresh → persist snapshot.
  Future<void> _activateProfile(
    SavedAccountProfile account,
    CredentialsLocalSource local,
  ) async {
    await _purgeCookieStores();
    await _restoreWebViewCookies(account.puuid);

    var creds = account.credentials;
    // If accessToken is still valid, proactively refresh entitlement token to sync with Riot PD
    if (!creds.isExpired) {
      try {
        final authRepo = await _ref.read(authRepositoryProvider.future);
        creds = await authRepo.refreshEntitlementOnly(creds);
      } catch (e) {
        debugPrint(
            '[SessionActions] Proactive entitlement refresh warning: $e');
      }
    }

    await local.save(
      creds,
      displayName: account.displayName,
      playerCardId: account.playerCardId,
      avatarUrl: account.avatarUrl,
    );
  }

  Future<void> switchAccount(SavedAccountProfile account) {
    return AsyncLock.run('active_session_action', () async {
      final local = _ref.read(credentialsLocalSourceProvider);
      final current = await local.load();
      if (current?.puuid == account.puuid) return;

      await _activateProfile(account, local);
      invalidateSession();
    });
  }

  Future<void> removeAccount(String puuid) {
    return AsyncLock.run('active_session_action', () async {
      final local = _ref.read(credentialsLocalSourceProvider);
      final current = await local.load();
      final wasActive = current?.puuid == puuid;
      // Capture the next candidate BEFORE removal (list minus removed entry).
      final remaining = (await local.getSavedAccounts())
          .where((a) => a.puuid != puuid)
          .toList();

      // Tears down profile + caches; if it was active it also clears the
      // active-session keys (activation of the next account happens below).
      await local.removeAccount(puuid);

      // Purge file-backed match details so removed accounts leave nothing
      // behind on disk either.
      try {
        await _ref.read(matchDetailLocalCacheProvider).purgeAccount(puuid);
      } catch (_) {}

      if (wasActive) {
        if (remaining.isNotEmpty) {
          await _activateProfile(remaining.first, local);
        } else {
          // Last active account removed — ensure no stale cookies leak to next login
          await _purgeCookieStores();
        }
      }
      invalidateSession();
    });
  }

  Future<void> logout() {
    return AsyncLock.run('active_session_action', () async {
      try {
        final jar = await _ref.read(cookieJarProvider.future);
        await jar.deleteAll();
      } catch (_) {}
      try {
        await WebViewCookieManager().clearCookies();
      } catch (_) {}
      try {
        await CacheStorage.instance.clearAll();
      } catch (_) {}
      await _ref.read(credentialsLocalSourceProvider).clear();
      invalidateSession();
    });
  }

  /// Tears down every session-scoped dependency so no cached data from the
  /// previous account leaks into the next one. See [_sessionBoundProviders]
  /// for the authoritative list and rationale.
  void invalidateSession() {
    for (final provider in _sessionBoundProviders) {
      _ref.invalidate(provider);
    }
  }
}
