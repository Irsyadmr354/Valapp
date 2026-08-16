import 'package:flutter/foundation.dart';
import '../../../core/storage/cache_storage.dart';
import '../domain/models/player_mmr.dart';

class MmrLocalCache {
  final CacheStorage _cache;
  const MmrLocalCache(this._cache);

  Future<void> saveMmr(Map<String, dynamic> raw,
      {required String puuid, required CacheTransaction transaction}) async {
    // Drop writes from requests that were in-flight during an account switch
    // so the old account's data never lands in the new account's namespace.
    await _cache.runUserTransaction(transaction, () async {
      await _cache.setJson(
          CacheStorage.userKeyFor(CacheStorage.keyMmrCache, puuid), raw);
      await _cache.setTimestamp(
          CacheStorage.userKeyFor(CacheStorage.keyMmrCacheFetchedAt, puuid));
    });
  }

  Future<PlayerMmr?> loadMmr({required String puuid}) async {
    final raw = await _cache
        .getJson(CacheStorage.userKeyFor(CacheStorage.keyMmrCache, puuid));
    if (raw == null) return null;
    try {
      return PlayerMmr.fromJson(raw);
    } catch (e) {
      debugPrint('[MmrLocalCache] Error parsing cached PlayerMmr: $e');
      await _cache
          .remove(CacheStorage.userKeyFor(CacheStorage.keyMmrCache, puuid));
      await _cache.remove(
          CacheStorage.userKeyFor(CacheStorage.keyMmrCacheFetchedAt, puuid));
      return null;
    }
  }

  Future<void> saveCompetitiveUpdates(Map<String, dynamic> raw,
      {required String puuid, required CacheTransaction transaction}) async {
    await _cache.runUserTransaction(transaction, () async {
      await _cache.setJson(
          CacheStorage.userKeyFor(
              CacheStorage.keyCompetitiveUpdatesCache, puuid),
          raw);
      await _cache.setTimestamp(CacheStorage.userKeyFor(
          CacheStorage.keyCompetitiveUpdatesCacheFetchedAt, puuid));
    });
  }

  Future<List<CompetitiveUpdate>?> loadCompetitiveUpdates(
      {required String puuid}) async {
    final raw = await _cache.getJson(CacheStorage.userKeyFor(
        CacheStorage.keyCompetitiveUpdatesCache, puuid));
    if (raw == null) return null;
    final matches = raw['Matches'];
    if (matches is! List) {
      await _evictCompetitiveUpdates(puuid);
      return null;
    }
    try {
      return matches
          .whereType<Map>()
          .map((e) => CompetitiveUpdate.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      debugPrint('[MmrLocalCache] Error parsing cached CompetitiveUpdates: $e');
      await _evictCompetitiveUpdates(puuid);
      return null;
    }
  }

  Future<void> _evictCompetitiveUpdates(String puuid) async {
    await _cache.remove(CacheStorage.userKeyFor(
        CacheStorage.keyCompetitiveUpdatesCache, puuid));
    await _cache.remove(CacheStorage.userKeyFor(
        CacheStorage.keyCompetitiveUpdatesCacheFetchedAt, puuid));
  }
}
