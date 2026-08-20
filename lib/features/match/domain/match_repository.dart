import '../../../core/storage/cache_storage.dart';
import '../data/match_local_cache.dart';
import '../data/match_remote_source.dart';
import 'models/match_history.dart';

/// Repository handling match history and match details fetching, caching, and enrichment.
class MatchRepository {
  const MatchRepository({
    required MatchRemoteSource remoteSource,
    required MatchHistoryLocalCache historyCache,
    required MatchDetailLocalCache detailCache,
  })  : _remote = remoteSource,
        _historyCache = historyCache,
        _detailCache = detailCache;

  final MatchRemoteSource _remote;
  final MatchHistoryLocalCache _historyCache;
  final MatchDetailLocalCache _detailCache;

  /// Fetches live match history and commits to cache if within active session.
  Future<MatchHistoryResult> fetchHistory(
    String shard,
    String puuid, {
    String? queue,
  }) async {
    final transaction = CacheStorage.instance.beginUserTransaction(puuid);
    final raw = await _remote.fetchHistoryRaw(
      shard,
      puuid,
      queue: queue,
    );
    final result = MatchHistoryResult.fromJson(raw);
    if (transaction != null) {
      await _historyCache.saveHistory(
        result,
        queue: queue,
        puuid: puuid,
        transaction: transaction,
      );
    }
    return result;
  }

  /// Loads cached match history for [puuid].
  Future<MatchHistoryResult?> loadCachedHistory({
    required String puuid,
    String? queue,
  }) {
    return _historyCache.loadHistory(queue: queue, puuid: puuid);
  }

  /// Fetches raw match details and commits to cache if within active session.
  Future<Map<String, dynamic>> fetchMatchDetailsRaw(
    String shard,
    String matchId, {
    required String puuid,
  }) async {
    final transaction = CacheStorage.instance.beginUserTransaction(puuid);
    final raw = await _remote.fetchMatchDetailsRaw(shard, matchId);
    if (transaction != null) {
      await _detailCache.saveMatchDetail(
        matchId,
        raw,
        puuid: puuid,
        transaction: transaction,
      );
    }
    return raw;
  }

  /// Loads cached match details raw map.
  Future<Map<String, dynamic>?> loadCachedMatchDetailRaw(
    String matchId, {
    required String puuid,
  }) {
    return _detailCache.loadMatchDetailRaw(matchId, puuid: puuid);
  }
}
