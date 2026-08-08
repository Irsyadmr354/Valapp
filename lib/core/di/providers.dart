import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../network/auth_dio.dart';
import '../network/api_dio.dart';
import '../network/cookie_service.dart';
import '../network/interceptors/valorant_interceptor.dart';
import '../storage/secure_storage.dart';
import '../storage/cache_storage.dart';
import '../storage/cached_fetch_result.dart';
import '../utils/async_lock.dart';
import '../../shared/utils/version_service.dart';
import '../../shared/utils/valorant_assets.dart';
import '../../shared/utils/display_name_util.dart';

// ── Auth & Session ─────────────────────────────────────────────────────────────

import '../../features/auth/data/auth_remote_source.dart';
import '../../features/auth/data/credentials_local_source.dart';
import '../../features/auth/domain/auth_repository.dart';

// ── Shop ───────────────────────────────────────────────────────────────────────

import '../../features/shop/data/store_remote_source.dart';
import '../../features/shop/data/store_local_cache.dart';
import '../../features/shop/domain/store_repository.dart';

import '../../features/match/data/match_remote_source.dart';
import '../../features/match/data/match_local_cache.dart';
import '../../features/match/domain/models/match_history.dart';
import '../../features/match/domain/models/match_details.dart';

// ── Rank ───────────────────────────────────────────────────────────────────────

import '../../features/rank/data/mmr_remote_source.dart';
import '../../features/rank/data/mmr_local_cache.dart';
import '../../features/rank/domain/models/player_mmr.dart';

// ── Contracts ─────────────────────────────────────────────────────────────────

import '../../features/contracts/data/contracts_remote_source.dart';
import '../../features/contracts/data/contracts_local_cache.dart';

// ── Profile ───────────────────────────────────────────────────────────────────

import '../../features/profile/data/account_remote_source.dart';
import '../../features/profile/data/account_local_cache.dart';
import '../../features/profile/data/restrictions_remote_source.dart';
import '../../features/profile/domain/models/account_xp.dart';

// ── Loadout ───────────────────────────────────────────────────────────────

import '../../features/loadout/data/loadout_remote_source.dart';
import '../../features/loadout/data/loadout_local_cache.dart';

// ── News ──────────────────────────────────────────────────────────────────

import '../../features/news/data/news_remote_source.dart';

// ═════════════════════════════════════════════════════════════════════════════
// Core singletons
// ═════════════════════════════════════════════════════════════════════════════

final secureStorageProvider =
    Provider<SecureStorage>((_) => SecureStorage.instance);

final cacheStorageProvider =
    Provider<CacheStorage>((_) => CacheStorage.instance);

final versionServiceProvider =
    Provider<VersionService>((_) => VersionService.instance);

final valorantAssetsProvider =
    Provider<ValorantAssets>((_) => ValorantAssets.instance);

// ── Cookie jar (async init via FutureProvider) ─────────────────────────────

final cookieJarProvider = FutureProvider<CookieJar>((_) => createCookieJar());

// ── Auth Dio ───────────────────────────────────────────────────────────────

final authDioProvider = FutureProvider<Dio>((ref) async {
  final jar = await ref.watch(cookieJarProvider.future);
  return createAuthDio(jar);
});

// ── Credentials local source ───────────────────────────────────────────────

final credentialsLocalSourceProvider = Provider<CredentialsLocalSource>((ref) {
  return CredentialsLocalSource(
    ref.watch(secureStorageProvider),
    ref.watch(cacheStorageProvider),
  );
});

// ── Auth remote source ─────────────────────────────────────────────────────

final authRemoteSourceProvider = FutureProvider<AuthRemoteSource>((ref) async {
  final authDio = await ref.watch(authDioProvider.future);
  return AuthRemoteSource(
    authDio,
    Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    )),
  );
});

// ── Auth repository ────────────────────────────────────────────────────────

final authRepositoryProvider = FutureProvider<AuthRepository>((ref) async {
  final remote = await ref.watch(authRemoteSourceProvider.future);
  final local = ref.watch(credentialsLocalSourceProvider);
  return AuthRepository(remoteSource: remote, localSource: local);
});

// ── Valorant API Dio ───────────────────────────────────────────────────────

final apiDioProvider = FutureProvider<Dio>((ref) async {
  final secureStorage = ref.watch(secureStorageProvider);
  final versionService = ref.watch(versionServiceProvider);

  late AuthRepository? authRepo;

  final interceptor = ValorantInterceptor(
    secureStorage: secureStorage,
    versionService: versionService,
    onReauth: () async {
      authRepo ??= await ref.read(authRepositoryProvider.future);
      await authRepo!.reauth();
    },
    onAuthFailed: () async {
      // Reauth failed for the active session (e.g. cookie expired or 401).
      // We clear the active session tokens so the app falls back to the
      // unauthenticated/expired state, but we PRESERVE all saved account profiles
      // in Multi-Account Manager so the user can reconnect or switch accounts.
      final local = ref.read(credentialsLocalSourceProvider);
      await ref.read(cacheStorageProvider).clearUserCache();
      await local.clearActiveSessionOnly();

      // Trigger re-read of credentials — routes to /login cleanly if no active token
      ref.invalidate(currentCredentialsProvider);
    },
  );

  return createApiDio(interceptor);
});

// ── Store ──────────────────────────────────────────────────────────────────

final storeRemoteSourceProvider =
    FutureProvider<StoreRemoteSource>((ref) async {
  final dio = await ref.watch(apiDioProvider.future);
  return StoreRemoteSource(dio);
});

final storeLocalCacheProvider = Provider<StoreLocalCache>((ref) {
  return StoreLocalCache(ref.watch(cacheStorageProvider));
});

final storeRepositoryProvider = FutureProvider<StoreRepository>((ref) async {
  final remote = await ref.watch(storeRemoteSourceProvider.future);
  final local = ref.watch(storeLocalCacheProvider);
  final assets = ref.watch(valorantAssetsProvider);
  return StoreRepository(
      remoteSource: remote, localCache: local, assets: assets);
});

// ── Match ──────────────────────────────────────────────────────────────────

final matchRemoteSourceProvider =
    FutureProvider<MatchRemoteSource>((ref) async {
  final dio = await ref.watch(apiDioProvider.future);
  return MatchRemoteSource(dio);
});

final matchHistoryLocalCacheProvider = Provider<MatchHistoryLocalCache>((ref) {
  return MatchHistoryLocalCache(ref.watch(cacheStorageProvider));
});

final matchDetailLocalCacheProvider = Provider<MatchDetailLocalCache>((ref) {
  return MatchDetailLocalCache(ref.watch(cacheStorageProvider));
});

// ── Rank ───────────────────────────────────────────────────────────────────

final mmrRemoteSourceProvider = FutureProvider<MmrRemoteSource>((ref) async {
  final dio = await ref.watch(apiDioProvider.future);
  return MmrRemoteSource(dio);
});

final mmrLocalCacheProvider = Provider<MmrLocalCache>((ref) {
  return MmrLocalCache(ref.watch(cacheStorageProvider));
});

// ── Contracts ─────────────────────────────────────────────────────────────

final contractsRemoteSourceProvider =
    FutureProvider<ContractsRemoteSource>((ref) async {
  final dio = await ref.watch(apiDioProvider.future);
  return ContractsRemoteSource(dio);
});

final contractsLocalCacheProvider = Provider<ContractsLocalCache>((ref) {
  return ContractsLocalCache(ref.watch(cacheStorageProvider));
});

// ── Profile ───────────────────────────────────────────────────────────────

final accountRemoteSourceProvider =
    FutureProvider<AccountRemoteSource>((ref) async {
  final dio = await ref.watch(apiDioProvider.future);
  return AccountRemoteSource(dio);
});

final accountLocalCacheProvider = Provider<AccountLocalCache>((ref) {
  return AccountLocalCache(ref.watch(cacheStorageProvider));
});

final restrictionsRemoteSourceProvider =
    FutureProvider<RestrictionsRemoteSource>((ref) async {
  final dio = await ref.watch(apiDioProvider.future);
  return RestrictionsRemoteSource(dio);
});

// ── Current credentials (reactive) ────────────────────────────────────────

final currentCredentialsProvider = FutureProvider((ref) async {
  final local = ref.watch(credentialsLocalSourceProvider);
  final creds = await local.load();
  // Sync the active session scope so every user-scoped cache is namespaced
  // (and guarded) against the currently-active account. This runs on every
  // credential change (login, switch, logout, reauth-invalidate) because this
  // provider is invalidated in all those flows.
  await ref
      .read(cacheStorageProvider)
      .initializeActiveSession(creds?.puuid ?? '');
  return creds;
});

/// Serializes account changes and invalidates every session-bound dependency
/// as one operation. Widgets should not perform these steps independently.
final sessionActionsProvider = Provider<SessionActions>(SessionActions.new);

class SessionActions {
  SessionActions(this._ref);

  final Ref _ref;

  Future<void> switchAccount(SavedAccountProfile account) {
    return AsyncLock.run('active_session_action', () async {
      final local = _ref.read(credentialsLocalSourceProvider);
      final current = await local.load();
      if (current?.puuid == account.puuid) return;

      // Purge old account's webview & HTTP cookies to prevent cookie bleed
      try {
        final jar = await _ref.read(cookieJarProvider.future);
        await jar.deleteAll();
      } catch (_) {}
      try {
        await WebViewCookieManager().clearCookies();
      } catch (_) {}

      await local.save(
        account.credentials,
        displayName: account.displayName,
        playerCardId: account.playerCardId,
        avatarUrl: account.avatarUrl,
      );
      invalidateSession();
    });
  }

  Future<void> removeAccount(String puuid) {
    return AsyncLock.run('active_session_action', () async {
      await _ref.read(credentialsLocalSourceProvider).removeAccount(puuid);
      invalidateSession();
    });
  }

  void invalidateSession() {
    _ref.invalidate(currentCredentialsProvider);
    _ref.invalidate(apiDioProvider);
    _ref.invalidate(storeRemoteSourceProvider);
    _ref.invalidate(storeRepositoryProvider);
    _ref.invalidate(matchRemoteSourceProvider);
    _ref.invalidate(mmrRemoteSourceProvider);
    _ref.invalidate(contractsRemoteSourceProvider);
    _ref.invalidate(accountRemoteSourceProvider);
    _ref.invalidate(restrictionsRemoteSourceProvider);
    _ref.invalidate(loadoutRemoteSourceProvider);
  }
}

// ── Loadout ────────────────────────────────────────────────────────────────

final loadoutRemoteSourceProvider =
    FutureProvider<LoadoutRemoteSource>((ref) async {
  final dio = await ref.watch(apiDioProvider.future);
  return LoadoutRemoteSource(dio);
});

final loadoutLocalCacheProvider = Provider<LoadoutLocalCache>((ref) {
  return LoadoutLocalCache(ref.watch(cacheStorageProvider));
});

// ── News ───────────────────────────────────────────────────────────────────

final newsRemoteSourceProvider = Provider<NewsRemoteSource>((ref) {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
  ));
  return NewsRemoteSource(dio);
});

// ── Shared account data pipelines ──────────────────────────────────────────

final accountXpProvider =
    FutureProvider<CachedFetchResult<AccountXp>?>((ref) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return null;
  final source = await ref.watch(accountRemoteSourceProvider.future);
  final cache = ref.watch(accountLocalCacheProvider);
  final transaction =
      ref.read(cacheStorageProvider).beginUserTransaction(creds.puuid);
  try {
    final raw = await source.fetchAccountXpRaw(creds.shard, creds.puuid);
    final value = AccountXp.fromJson(raw);
    if (transaction != null) {
      await cache.saveAccountXp(raw,
          puuid: creds.puuid, transaction: transaction);
    }
    if (!ref.read(cacheStorageProvider).isActiveSession(creds.puuid)) {
      return null;
    }
    return CachedFetchResult(value);
  } catch (_) {
    final value = await cache.loadAccountXp(puuid: creds.puuid);
    if (value != null) return CachedFetchResult(value, fromCache: true);
    rethrow;
  }
});

final displayNameProvider =
    FutureProvider<CachedFetchResult<String>?>((ref) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return null;
  final local = ref.watch(credentialsLocalSourceProvider);
  final source = await ref.watch(accountRemoteSourceProvider.future);
  final cache = ref.watch(accountLocalCacheProvider);
  final transaction =
      ref.read(cacheStorageProvider).beginUserTransaction(creds.puuid);

  Future<String?> savedProfileName() async {
    final profiles = await local.getSavedAccounts();
    final idx = profiles.indexWhere((p) => p.puuid == creds.puuid);
    if (idx == -1) return null;
    final name = profiles[idx].displayName;
    return DisplayNameUtil.isPlaceholder(name) ? null : name;
  }

  try {
    final name = await source.fetchDisplayName(
      creds.shard,
      creds.puuid,
      accessToken: creds.accessToken,
    );
    if (name == null || name.isEmpty) {
      throw StateError('Display name unavailable');
    }
    if (transaction != null) {
      await cache.saveDisplayName(creds.puuid, name, transaction);
    }
    await local.updateAccountMetadata(creds.puuid, displayName: name);
    if (!ref.read(cacheStorageProvider).isActiveSession(creds.puuid)) {
      return null;
    }
    return CachedFetchResult(name);
  } catch (_) {
    final cached = await cache.loadDisplayName(creds.puuid);
    if (cached != null &&
        cached.isNotEmpty &&
        !DisplayNameUtil.isPlaceholder(cached)) {
      return CachedFetchResult(cached, fromCache: true);
    }
    final saved = await savedProfileName();
    if (saved != null) {
      return CachedFetchResult(saved, fromCache: true);
    }
    final fallback = creds.puuid.length >= 8
        ? 'Player (${creds.puuid.substring(0, 6)}...)'
        : 'Valorant Player';
    return CachedFetchResult(fallback);
  }
});

final playerMmrProvider =
    FutureProvider<CachedFetchResult<PlayerMmr>?>((ref) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return null;
  final source = await ref.watch(mmrRemoteSourceProvider.future);
  final cache = ref.watch(mmrLocalCacheProvider);
  final transaction =
      ref.read(cacheStorageProvider).beginUserTransaction(creds.puuid);
  try {
    final raw = await source.fetchMmrRaw(creds.shard, creds.puuid);
    final value = PlayerMmr.fromJson(raw);
    if (transaction != null) {
      await cache.saveMmr(raw, puuid: creds.puuid, transaction: transaction);
    }
    if (!ref.read(cacheStorageProvider).isActiveSession(creds.puuid)) {
      return null;
    }
    return CachedFetchResult(value);
  } catch (_) {
    final value = await cache.loadMmr(puuid: creds.puuid);
    if (value != null) return CachedFetchResult(value, fromCache: true);
    rethrow;
  }
});

final competitiveUpdatesProvider =
    FutureProvider<CachedFetchResult<List<CompetitiveUpdate>>>((ref) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return const CachedFetchResult([]);
  final source = await ref.watch(mmrRemoteSourceProvider.future);
  final cache = ref.watch(mmrLocalCacheProvider);
  final transaction =
      ref.read(cacheStorageProvider).beginUserTransaction(creds.puuid);
  try {
    final raw =
        await source.fetchCompetitiveUpdatesRaw(creds.shard, creds.puuid);
    final list = source.parseCompetitiveUpdates(raw);
    if (transaction != null) {
      await cache.saveCompetitiveUpdates(raw,
          puuid: creds.puuid, transaction: transaction);
    }
    if (!ref.read(cacheStorageProvider).isActiveSession(creds.puuid)) {
      return const CachedFetchResult([]);
    }
    return CachedFetchResult(list);
  } catch (_) {
    final cached = await cache.loadCompetitiveUpdates(puuid: creds.puuid);
    if (cached != null) return CachedFetchResult(cached, fromCache: true);
    rethrow;
  }
});

/// Resolves the equipped player card art URLs from the player's loadout.
/// Returns both [smallArt] (used in avatars) and [wideArt] (used in headers).
/// Shared by ShopScreen and ProfileScreen to avoid duplicating the
/// loadout-fetch → player-cards-lookup pipeline.
class PlayerCardArtInfo {
  final String? smallArt;
  final String? wideArt;
  const PlayerCardArtInfo({this.smallArt, this.wideArt});
}

final playerCardArtProvider = FutureProvider<PlayerCardArtInfo>((ref) async {
  try {
    final creds = await ref.watch(currentCredentialsProvider.future);
    if (creds == null) return const PlayerCardArtInfo();

    final cache = ref.watch(loadoutLocalCacheProvider);
    final transaction =
        ref.read(cacheStorageProvider).beginUserTransaction(creds.puuid);
    Map<String, dynamic>? raw = await cache.loadLoadoutRaw(puuid: creds.puuid);
    if (raw == null) {
      final source = await ref.watch(loadoutRemoteSourceProvider.future);
      raw = await source.fetchLoadoutRaw(creds.shard, creds.puuid);
      if (transaction != null) {
        await cache.saveLoadout(raw,
            puuid: creds.puuid, transaction: transaction);
      }
    }

    // v3 wraps fields under 'Loadout' key; v2 exposes them at root.
    final loadoutRoot = raw.containsKey('Loadout')
        ? (raw['Loadout'] as Map<String, dynamic>? ?? {})
        : raw;
    final identity = loadoutRoot['Identity'] as Map<String, dynamic>? ??
        raw['Identity'] as Map<String, dynamic>? ??
        {};
    final cardId = identity['PlayerCardID'] as String? ??
        loadoutRoot['PlayerCardID'] as String? ??
        raw['PlayerCardID'] as String?;
    if (cardId == null) return const PlayerCardArtInfo();

    final cardsMap =
        await ref.watch(valorantAssetsProvider).getPlayerCardsMap();
    final cardInfo = (cardsMap[cardId] ?? cardsMap[cardId.toLowerCase()])
        as Map<String, dynamic>?;

    return PlayerCardArtInfo(
      smallArt: cardInfo?['smallArt'] as String? ??
          cardInfo?['displayIcon'] as String?,
      wideArt: cardInfo?['largeArt'] as String? ??
          cardInfo?['wideArt'] as String? ??
          cardInfo?['displayIcon'] as String?,
    );
  } catch (_) {
    return const PlayerCardArtInfo();
  }
});

// ── Enriched Match History (shared) ───────────────────────────────────────────

/// Fetches the player's recent match history and enriches each entry
/// with KDA / result / agent data from the local detail cache (zero
/// extra network calls — background enrichment fills the cache separately).
///
/// Used by HomeScreen and ProfileScreen so neither file duplicates the
/// ~40-line fetch + cache-only enrich loop.
final enrichedMatchHistoryProvider =
    FutureProvider<MatchHistoryResult?>((ref) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return null;

  final source = await ref.watch(matchRemoteSourceProvider.future);
  final historyCache = ref.watch(matchHistoryLocalCacheProvider);
  final detailCache = ref.watch(matchDetailLocalCacheProvider);
  final transaction =
      ref.read(cacheStorageProvider).beginUserTransaction(creds.puuid);

  // ── 1. Fetch / load raw history ──────────────────────────────────────────
  MatchHistoryResult raw;
  try {
    final rawJson = await source.fetchHistoryRaw(creds.shard, creds.puuid);
    raw = MatchHistoryResult.fromJson(rawJson);
    if (transaction != null) {
      await historyCache.saveHistory(raw,
          puuid: creds.puuid, transaction: transaction);
    }
  } catch (_) {
    final cached = await historyCache.loadHistory(puuid: creds.puuid);
    if (cached != null) {
      raw = cached;
    } else {
      return null;
    }
  }

  // ── 2. Enrich from detail cache (no network) ─────────────────────────────
  final enriched = <MatchHistoryEntry>[];
  for (final entry in raw.matches) {
    final detailRaw =
        await detailCache.loadMatchDetailRaw(entry.matchId, puuid: creds.puuid);
    if (detailRaw == null) {
      enriched.add(entry);
      continue;
    }
    try {
      final details = MatchDetails.fromJson(detailRaw);
      final player = details.players
          .cast<PlayerStats?>()
          .firstWhere((p) => p?.puuid == creds.puuid, orElse: () => null);
      if (player == null) {
        enriched.add(entry);
        continue;
      }

      MatchResult matchResult = details.resultForPlayer(creds.puuid);

      final sorted = List<PlayerStats>.from(details.players)
        ..sort((a, b) => b.score.compareTo(a.score));
      final isMvp = sorted.isNotEmpty && sorted.first.puuid == creds.puuid;

      // Build score string (e.g. "13 – 8") via the shared helper.
      final scoreStr = details.scoreStringForPlayer(creds.puuid);

      enriched.add(entry.copyWithStats(
        kills: player.kills,
        deaths: player.deaths,
        assists: player.assists,
        isMvp: isMvp,
        matchScore: scoreStr,
        result: matchResult,
        agentId: player.agentId,
        mapId: details.mapId,
      ));
    } catch (_) {
      enriched.add(entry);
    }
  }

  if (!ref.read(cacheStorageProvider).isActiveSession(creds.puuid)) return null;
  return MatchHistoryResult(
    puuid: raw.puuid,
    total: raw.total,
    start: raw.start,
    end: raw.end,
    matches: enriched,
  );
});
