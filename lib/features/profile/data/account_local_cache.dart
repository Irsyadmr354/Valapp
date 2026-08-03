import '../../../core/storage/cache_storage.dart';
import '../domain/models/account_xp.dart';

class AccountLocalCache {
  final CacheStorage _cache;
  const AccountLocalCache(this._cache);

  Future<void> saveAccountXp(Map<String, dynamic> raw) async {
    await _cache.setJson(CacheStorage.keyAccountXpCache, raw);
    await _cache.setTimestamp(CacheStorage.keyAccountXpCacheFetchedAt);
  }

  Future<AccountXp?> loadAccountXp() async {
    final raw = await _cache.getJson(CacheStorage.keyAccountXpCache);
    if (raw == null) return null;
    return AccountXp.fromJson(raw);
  }

  Future<void> saveDisplayName(String puuid, String name) async {
    // Store per-puuid so multi-account switching doesn't overwrite each other
    final existing = await _cache.getJson(CacheStorage.keyDisplayNameCache) ?? {};
    existing[puuid] = name;
    await _cache.setJson(CacheStorage.keyDisplayNameCache, existing);
    await _cache.setTimestamp(CacheStorage.keyDisplayNameCacheFetchedAt);
  }

  Future<String?> loadDisplayName(String puuid) async {
    final raw = await _cache.getJson(CacheStorage.keyDisplayNameCache);
    if (raw == null) return null;
    // Support both old single-entry format {'puuid':..,'name':..} and
    // new per-puuid map format {puuid: name}
    if (raw.containsKey('name') && raw['puuid'] == puuid) {
      return raw['name'] as String?;
    }
    return raw[puuid] as String?;
  }
}
