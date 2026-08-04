import '../../../core/storage/cache_storage.dart';
import '../../../core/utils/async_lock.dart';
import '../domain/models/match_history.dart';

class MatchHistoryLocalCache {
  final CacheStorage _cache;
  const MatchHistoryLocalCache(this._cache);

  String _cacheKey(String? queue) =>
      queue == null || queue.isEmpty ? 'all' : queue;

  Future<void> saveHistory(MatchHistoryResult result,
      {String? queue,
      required String puuid,
      required CacheTransaction transaction}) async {
    // The history blob is stored per-user; a stale write from a request that
    // was in-flight during an account switch must never land here.
    final baseKey =
        CacheStorage.userKeyFor(CacheStorage.keyMatchHistoryCache, puuid);
    await _cache.runUserTransaction(transaction, () async {
      await AsyncLock.run('match_history_cache/$puuid', () async {
        final all = await _cache.getJson(baseKey) ?? {};
        all[_cacheKey(queue)] = {
          'Subject': result.puuid,
          'Total': result.total,
          'BeginIndex': result.start,
          'EndIndex': result.end,
          'History': result.matches
              .map((e) => {
                    'MatchID': e.matchId,
                    'GameStartTime': e.gameStartMillis,
                    'QueueID': e.queueId,
                    'TeamID': e.teamId,
                    'IsRanked': e.isRanked,
                    'MapID': e.mapId,
                  })
              .toList(),
        };
        await _cache.setJson(baseKey, all);
        await _cache.setTimestamp(CacheStorage.userKeyFor(
            CacheStorage.keyMatchHistoryCacheFetchedAt, puuid));
      });
    });
  }

  Future<MatchHistoryResult?> loadHistory(
      {String? queue, required String puuid}) async {
    final all = await _cache.getJson(
        CacheStorage.userKeyFor(CacheStorage.keyMatchHistoryCache, puuid));
    if (all == null) return null;
    final value = all[_cacheKey(queue)];
    if (value is! Map) return null;
    try {
      return MatchHistoryResult.fromJson(Map<String, dynamic>.from(value));
    } catch (_) {
      all.remove(_cacheKey(queue));
      if (all.isEmpty) {
        await _cache.remove(
            CacheStorage.userKeyFor(CacheStorage.keyMatchHistoryCache, puuid));
      } else {
        await _cache.setJson(
            CacheStorage.userKeyFor(CacheStorage.keyMatchHistoryCache, puuid),
            all);
      }
      return null;
    }
  }
}

class MatchDetailLocalCache {
  final CacheStorage _cache;
  const MatchDetailLocalCache(this._cache);

  Future<void> saveMatchDetail(String matchId, Map<String, dynamic> raw,
      {required String puuid, required CacheTransaction transaction}) async {
    final key =
        CacheStorage.userKeyFor(CacheStorage.keyMatchDetailCache, puuid);
    await _cache.runUserTransaction(transaction, () async {
      await AsyncLock.run('match_detail_cache/$puuid', () async {
        final all = await _cache.getJson(key) ?? {};
        final isNew = !all.containsKey(matchId);
        all[matchId] = raw;
        const maxEntries = 30;
        if (isNew && all.length > maxEntries) {
          final toRemove = all.length - maxEntries;
          final keysToRemove = all.keys.take(toRemove).toList();
          for (final k in keysToRemove) {
            all.remove(k);
          }
        }
        await _cache.setJson(key, all);
      });
    });
  }

  Future<Map<String, dynamic>?> loadMatchDetailRaw(String matchId,
      {required String puuid}) async {
    final all = await _cache.getJson(
        CacheStorage.userKeyFor(CacheStorage.keyMatchDetailCache, puuid));
    if (all == null) return null;
    final raw = all[matchId];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }
}
