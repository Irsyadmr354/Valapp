import '../../../core/storage/cache_storage.dart';
import '../data/contracts_local_cache.dart';
import '../data/contracts_remote_source.dart';
import 'models/contracts.dart';

/// Repository handling contracts and battle pass data fetching and caching.
class ContractsRepository {
  const ContractsRepository({
    required ContractsRemoteSource remoteSource,
    required ContractsLocalCache localCache,
  })  : _remote = remoteSource,
        _cache = localCache;

  final ContractsRemoteSource _remote;
  final ContractsLocalCache _cache;

  /// Fetches live contracts data and commits to cache if within active session.
  Future<PlayerContracts> fetchContracts(String shard, String puuid) async {
    final transaction = CacheStorage.instance.beginUserTransaction(puuid);
    final raw = await _remote.fetchContractsRaw(shard, puuid);
    final data = PlayerContracts.fromJson(raw);
    if (transaction != null) {
      await _cache.saveContracts(
        raw,
        puuid: puuid,
        transaction: transaction,
      );
    }
    return data;
  }

  /// Loads cached contracts data for [puuid].
  Future<PlayerContracts?> loadCachedContracts(String puuid) {
    return _cache.loadContracts(puuid: puuid);
  }
}
