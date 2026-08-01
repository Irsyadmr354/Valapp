import '../../../core/storage/cache_storage.dart';
import '../domain/models/player_loadout.dart';

class LoadoutLocalCache {
  const LoadoutLocalCache(this._cache);
  final CacheStorage _cache;

  static const _keyLoadout = 'player_loadout';

  Future<void> saveLoadout(Map<String, dynamic> raw) =>
      _cache.setJson(_keyLoadout, raw);

  Future<Map<String, dynamic>?> loadLoadoutRaw() =>
      _cache.getJson(_keyLoadout);

  Future<PlayerLoadout?> loadLoadout() async {
    final raw = await _cache.getJson(_keyLoadout);
    if (raw == null) return null;
    try {
      return PlayerLoadout.fromJson(raw);
    } catch (_) {
      return null;
    }
  }
}
