import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/auth_dio.dart';
import '../network/api_dio.dart';
import '../network/cookie_service.dart';
import '../network/interceptors/valorant_interceptor.dart';
import '../storage/secure_storage.dart';
import '../storage/cache_storage.dart';
import '../../shared/utils/version_service.dart';
import '../../shared/utils/valorant_assets.dart';

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

// ── Loadout ───────────────────────────────────────────────────────────────

import '../../features/loadout/data/loadout_remote_source.dart';
import '../../features/loadout/data/loadout_local_cache.dart';

// ── News ──────────────────────────────────────────────────────────────────

import '../../features/news/data/news_remote_source.dart';

// ═════════════════════════════════════════════════════════════════════════════
// Core singletons
// ═════════════════════════════════════════════════════════════════════════════

final secureStorageProvider = Provider<SecureStorage>((_) => SecureStorage.instance);

final cacheStorageProvider = Provider<CacheStorage>((_) => CacheStorage.instance);

final versionServiceProvider = Provider<VersionService>((_) => VersionService.instance);

final valorantAssetsProvider = Provider<ValorantAssets>((_) => ValorantAssets.instance);

// ── Cookie jar (async init via FutureProvider) ─────────────────────────────

final cookieJarProvider = FutureProvider<PersistCookieJar>((_) => createCookieJar());

// ── Auth Dio ───────────────────────────────────────────────────────────────

final authDioProvider = FutureProvider<Dio>((ref) async {
  final jar = await ref.watch(cookieJarProvider.future);
  return createAuthDio(jar);
});

// ── Credentials local source ───────────────────────────────────────────────

final credentialsLocalSourceProvider = Provider<CredentialsLocalSource>((ref) {
  return CredentialsLocalSource(ref.watch(secureStorageProvider));
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
      // A permanent reauth failure for the current account.
      // Opsi A: remove the failed account's entry from saved list,
      // then switch to the next account if one exists — other saved
      // accounts are NOT wiped (unlike the old local.clear() approach).
      final local = ref.read(credentialsLocalSourceProvider);
      final failedPuuid = await ref.read(secureStorageProvider).read(SecureStorage.keyPuuid);

      // Remove only the active session tokens (not the full accounts list)
      await local.clearActiveSessionOnly();

      if (failedPuuid != null) {
        // Remove the failed account's entry from the saved list (Opsi A)
        final remaining = await local.getSavedAccounts();
        final others = remaining.where((a) => a.puuid != failedPuuid).toList();

        // Rewrite the saved list without the failed account
        if (others.length < remaining.length) {
          // Re-save the trimmed list by removing the failed puuid entry
          await local.removeAccount(failedPuuid);
        }

        // Auto-switch to another account if available
        final updated = await local.getSavedAccounts();
        if (updated.isNotEmpty) {
          await local.save(updated.first.credentials,
              displayName: updated.first.displayName);
          ref.invalidate(currentCredentialsProvider);
          return;
        }
      }

      // No other accounts — redirect to login
      ref.invalidate(currentCredentialsProvider);
    },
  );

  return createApiDio(interceptor);
});

// ── Store ──────────────────────────────────────────────────────────────────

final storeRemoteSourceProvider = FutureProvider<StoreRemoteSource>((ref) async {
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

final matchRemoteSourceProvider = FutureProvider<MatchRemoteSource>((ref) async {
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
  return local.load();
});

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

// ── Shared Competitive Updates ─────────────────────────────────────────────

/// Shared competitive updates provider so Home Screen and Rank Screen
/// both use the same cached data — no duplicate network fetches.
final competitiveUpdatesProvider =
    FutureProvider.autoDispose<List<CompetitiveUpdate>>((ref) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return [];
  final source = await ref.watch(mmrRemoteSourceProvider.future);
  final cache = ref.watch(mmrLocalCacheProvider);
  try {
    final raw = await source.fetchCompetitiveUpdatesRaw(creds.shard, creds.puuid);
    final list = source.parseCompetitiveUpdates(raw);
    await cache.saveCompetitiveUpdates(raw);
    return list;
  } catch (_) {
    return await cache.loadCompetitiveUpdates() ?? [];
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

final playerCardArtProvider =
    FutureProvider.autoDispose<PlayerCardArtInfo>((ref) async {
  try {
    final creds = await ref.watch(currentCredentialsProvider.future);
    if (creds == null) return const PlayerCardArtInfo();

    final cache = ref.watch(loadoutLocalCacheProvider);
    Map<String, dynamic>? raw = await cache.loadLoadoutRaw();
    if (raw == null) {
      final source = await ref.watch(loadoutRemoteSourceProvider.future);
      raw = await source.fetchLoadoutRaw(creds.shard, creds.puuid);
      await cache.saveLoadout(raw);
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

    final cardsMap = await ref.watch(valorantAssetsProvider).getPlayerCardsMap();
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
    FutureProvider.autoDispose<MatchHistoryResult?>((ref) async {
  final creds = await ref.watch(currentCredentialsProvider.future);
  if (creds == null) return null;

  final source      = await ref.watch(matchRemoteSourceProvider.future);
  final historyCache = ref.watch(matchHistoryLocalCacheProvider);
  final detailCache  = ref.watch(matchDetailLocalCacheProvider);

  // ── 1. Fetch / load raw history ──────────────────────────────────────────
  MatchHistoryResult raw;
  try {
    final rawJson = await source.fetchHistoryRaw(creds.shard, creds.puuid);
    raw = MatchHistoryResult.fromJson(rawJson);
    await historyCache.saveHistory(raw);
  } catch (_) {
    final cached = await historyCache.loadHistory();
    if (cached != null) {
      raw = cached;
    } else {
      return null;
    }
  }

  // ── 2. Enrich from detail cache (no network) ─────────────────────────────
  final enriched = <MatchHistoryEntry>[];
  for (final entry in raw.matches) {
    final detailRaw = await detailCache.loadMatchDetailRaw(entry.matchId);
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

      enriched.add(entry.copyWithStats(
        kills: player.kills,
        deaths: player.deaths,
        assists: player.assists,
        isMvp: isMvp,
        result: matchResult,
        agentId: player.agentId,
        mapId: details.mapId,
      ));
    } catch (_) {
      enriched.add(entry);
    }
  }

  return MatchHistoryResult(
    puuid: raw.puuid,
    total: raw.total,
    start: raw.start,
    end: raw.end,
    matches: enriched,
  );
});
