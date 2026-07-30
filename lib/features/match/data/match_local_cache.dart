import '../../../core/storage/cache_storage.dart';
import '../domain/models/match_history.dart';

class MatchHistoryLocalCache {
  final CacheStorage _cache;
  const MatchHistoryLocalCache(this._cache);

  String _cacheKey(String? queue) =>
      queue == null || queue.isEmpty ? 'all' : queue;

  Future<void> saveHistory(MatchHistoryResult result, {String? queue}) async {
    final all = await _cache.getJson(CacheStorage.keyMatchHistoryCache) ?? {};
    all[_cacheKey(queue)] = {
      'History': result.matches
          .map((e) => {
                'MatchID': e.matchId,
                'GameStartTime': e.gameStartMillis,
                'QueueID': e.queueId,
                'MapID': e.mapId,
              })
          .toList(),
    };
    await _cache.setJson(CacheStorage.keyMatchHistoryCache, all);
    await _cache.setTimestamp(CacheStorage.keyMatchHistoryCacheFetchedAt);
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
    final all = await _cache.getJson(CacheStorage.keyMatchDetailCache) ?? {};
    all[matchId] = raw;
    await _cache.setJson(CacheStorage.keyMatchDetailCache, all);
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
