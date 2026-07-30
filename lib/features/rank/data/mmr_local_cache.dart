import '../../../core/storage/cache_storage.dart';
import '../domain/models/player_mmr.dart';

class MmrLocalCache {
  final CacheStorage _cache;
  const MmrLocalCache(this._cache);

  Future<void> saveMmr(Map<String, dynamic> raw) async {
    await _cache.setJson(CacheStorage.keyMmrCache, raw);
    await _cache.setTimestamp(CacheStorage.keyMmrCacheFetchedAt);
  }

  Future<PlayerMmr?> loadMmr() async {
    final raw = await _cache.getJson(CacheStorage.keyMmrCache);
    if (raw == null) return null;
    return PlayerMmr.fromJson(raw);
  }

  Future<void> saveCompetitiveUpdates(Map<String, dynamic> raw) async {
    await _cache.setJson(CacheStorage.keyCompetitiveUpdatesCache, raw);
    await _cache.setTimestamp(CacheStorage.keyCompetitiveUpdatesCacheFetchedAt);
  }

  Future<List<CompetitiveUpdate>?> loadCompetitiveUpdates() async {
    final raw = await _cache.getJson(CacheStorage.keyCompetitiveUpdatesCache);
    if (raw == null) return null;
    final matches = (raw['Matches'] as List<dynamic>?) ?? [];
    return matches
        .whereType<Map>()
        .map((e) => CompetitiveUpdate.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}
