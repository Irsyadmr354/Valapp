import '../../../core/storage/cache_storage.dart';
import '../domain/models/account_xp.dart';

class AccountLocalCache {
  final CacheStorage _cache;
  const AccountLocalCache(this._cache);

  Future<void> saveAccountXp(Map<String, dynamic> raw,
      {required String puuid, required CacheTransaction transaction}) async {
    await _cache.runUserTransaction(transaction, () async {
      await _cache.setJson(
          CacheStorage.userKeyFor(CacheStorage.keyAccountXpCache, puuid), raw);
      await _cache.setTimestamp(CacheStorage.userKeyFor(
          CacheStorage.keyAccountXpCacheFetchedAt, puuid));
    });
  }

  Future<AccountXp?> loadAccountXp({required String puuid}) async {
    final raw = await _cache.getJson(
        CacheStorage.userKeyFor(CacheStorage.keyAccountXpCache, puuid));
    if (raw == null) return null;
    try {
      return AccountXp.fromJson(raw);
    } catch (_) {
      await _cache.remove(
          CacheStorage.userKeyFor(CacheStorage.keyAccountXpCache, puuid));
      await _cache.remove(CacheStorage.userKeyFor(
          CacheStorage.keyAccountXpCacheFetchedAt, puuid));
      return null;
    }
  }

  Future<void> saveDisplayName(
      String puuid, String name, CacheTransaction transaction) async {
    await _cache.runUserTransaction(transaction, () async {
      await _cache.setJson(
        CacheStorage.userKeyFor(CacheStorage.keyDisplayNameCache, puuid),
        {'name': name},
      );
      await _cache.setTimestamp(CacheStorage.userKeyFor(
          CacheStorage.keyDisplayNameCacheFetchedAt, puuid));
    });
  }

  Future<String?> loadDisplayName(String puuid) async {
    final raw = await _cache.getJson(
        CacheStorage.userKeyFor(CacheStorage.keyDisplayNameCache, puuid));
    return raw?['name'] as String?;
  }
}
