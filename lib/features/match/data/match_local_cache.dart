import '../../../core/storage/cache_storage.dart';
import '../../../core/utils/async_lock.dart';
import '../domain/models/match_history.dart';

class MatchHistoryLocalCache {
  final CacheStorage _cache;
  const MatchHistoryLocalCache(this._cache);

  String _cacheKey(String? queue) =>
      queue == null || queue.isEmpty ? 'all' : queue;

  Future<void> saveHistory(MatchHistoryResult result, {String? queue}) async {
    await AsyncLock.run('match_history_cache', () async {
      final all = await _cache.getJson(CacheStorage.keyMatchHistoryCache) ?? {};
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
      await _cache.setJson(CacheStorage.keyMatchHistoryCache, all);
      await _cache.setTimestamp(CacheStorage.keyMatchHistoryCacheFetchedAt);
    });
  }

  Future<MatchHistoryResult?> loadHistory({String? queue}) async {
    final all = await _cache.getJson(CacheStorage.keyMatchHistoryCache);
    if (all == null) return null;
    final raw = all[_cacheKey(queue)] as Map<String, dynamic>?;
    if (raw == null) return null;
    return MatchHistoryResult.fromJson(raw);
  }
}

class MatchDetailLocalCache {
  final CacheStorage _cache;
  const MatchDetailLocalCache(this._cache);

  Future<void> saveMatchDetail(
      String matchId, Map<String, dynamic> raw) async {
    await AsyncLock.run('match_detail_cache', () async {
      final all = await _cache.getJson(CacheStorage.keyMatchDetailCache) ?? {};
      // Only count as a new entry if matchId doesn't already exist
      final isNew = !all.containsKey(matchId);
      all[matchId] = raw;
      // Evict oldest entries only when we've actually exceeded the cap
      const maxEntries = 30;
      if (isNew && all.length > maxEntries) {
        final toRemove = all.length - maxEntries;
        final keysToRemove = all.keys.take(toRemove).toList();
        for (final k in keysToRemove) {
          all.remove(k);
        }
      }
      await _cache.setJson(CacheStorage.keyMatchDetailCache, all);
    });
  }

  Future<Map<String, dynamic>?> loadMatchDetailRaw(String matchId) async {
    final all = await _cache.getJson(CacheStorage.keyMatchDetailCache);
    if (all == null) return null;
    final raw = all[matchId];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }
}
