import '../../../core/storage/cache_storage.dart';
import '../domain/models/contracts.dart';

class ContractsLocalCache {
  final CacheStorage _cache;
  const ContractsLocalCache(this._cache);

  Future<void> saveContracts(Map<String, dynamic> raw) async {
    await _cache.setJson(CacheStorage.keyContractsCache, raw);
    await _cache.setTimestamp(CacheStorage.keyContractsCacheFetchedAt);
  }

  Future<PlayerContracts?> loadContracts() async {
    final raw = await _cache.getJson(CacheStorage.keyContractsCache);
    if (raw == null) return null;
    return PlayerContracts.fromJson(raw);
  }
}
