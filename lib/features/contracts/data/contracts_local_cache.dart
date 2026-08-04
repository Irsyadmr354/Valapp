import '../../../core/storage/cache_storage.dart';
import '../domain/models/contracts.dart';

class ContractsLocalCache {
  final CacheStorage _cache;
  const ContractsLocalCache(this._cache);

  Future<void> saveContracts(Map<String, dynamic> raw,
      {required String puuid, required CacheTransaction transaction}) async {
    await _cache.runUserTransaction(transaction, () async {
      await _cache.setJson(
          CacheStorage.userKeyFor(CacheStorage.keyContractsCache, puuid), raw);
      await _cache.setTimestamp(CacheStorage.userKeyFor(
          CacheStorage.keyContractsCacheFetchedAt, puuid));
    });
  }

  Future<PlayerContracts?> loadContracts({required String puuid}) async {
    final raw = await _cache.getJson(
        CacheStorage.userKeyFor(CacheStorage.keyContractsCache, puuid));
    if (raw == null) return null;
    try {
      return PlayerContracts.fromJson(raw);
    } catch (_) {
      await _cache.remove(
          CacheStorage.userKeyFor(CacheStorage.keyContractsCache, puuid));
      await _cache.remove(CacheStorage.userKeyFor(
          CacheStorage.keyContractsCacheFetchedAt, puuid));
      return null;
    }
  }
}
