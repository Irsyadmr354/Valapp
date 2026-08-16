import 'package:flutter/foundation.dart';
import '../../../core/storage/cache_storage.dart';
import '../domain/models/player_loadout.dart';

class LoadoutLocalCache {
  const LoadoutLocalCache(this._cache);
  final CacheStorage _cache;

  Future<void> saveLoadout(Map<String, dynamic> raw,
      {required String puuid, required CacheTransaction transaction}) async {
    await _cache.runUserTransaction(transaction, () async {
      await _cache.setJson(
          CacheStorage.userKeyFor(LoadoutLocalCache.keyLoadout, puuid), raw);
    });
  }

  Future<Map<String, dynamic>?> loadLoadoutRaw({required String puuid}) async {
    return _cache
        .getJson(CacheStorage.userKeyFor(LoadoutLocalCache.keyLoadout, puuid));
  }

  Future<PlayerLoadout?> loadLoadout({required String puuid}) async {
    final raw = await _cache
        .getJson(CacheStorage.userKeyFor(LoadoutLocalCache.keyLoadout, puuid));
    if (raw == null) return null;
    try {
      return PlayerLoadout.fromJson(raw);
    } catch (e) {
      debugPrint('[LoadoutLocalCache] Error parsing cached PlayerLoadout: $e');
      await _cache
          .remove(CacheStorage.userKeyFor(LoadoutLocalCache.keyLoadout, puuid));
      return null;
    }
  }

  static const keyLoadout = 'player_loadout';
}
