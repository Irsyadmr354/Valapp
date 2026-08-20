import '../../../core/storage/cache_storage.dart';
import '../data/loadout_local_cache.dart';
import '../data/loadout_remote_source.dart';
import 'models/player_loadout.dart';

/// Repository handling player loadout data fetching and caching.
class LoadoutRepository {
  const LoadoutRepository({
    required LoadoutRemoteSource remoteSource,
    required LoadoutLocalCache localCache,
  })  : _remote = remoteSource,
        _cache = localCache;

  final LoadoutRemoteSource _remote;
  final LoadoutLocalCache _cache;

  /// Fetches live player loadout and commits to cache if within active session.
  Future<PlayerLoadout> fetchLoadout(String shard, String puuid) async {
    final transaction = CacheStorage.instance.beginUserTransaction(puuid);
    final raw = await _remote.fetchLoadoutRaw(shard, puuid);
    final loadout = PlayerLoadout.fromJson(raw);
    if (transaction != null) {
      await _cache.saveLoadout(
        raw,
        puuid: puuid,
        transaction: transaction,
      );
    }
    return loadout;
  }

  /// Loads cached player loadout for [puuid].
  Future<PlayerLoadout?> loadCachedLoadout(String puuid) async {
    final raw = await _cache.loadLoadoutRaw(puuid: puuid);
    if (raw == null) return null;
    try {
      return PlayerLoadout.fromJson(raw);
    } catch (_) {
      return null;
    }
  }

  /// Loads cached raw loadout map for card extraction or quick inspection.
  Future<Map<String, dynamic>?> loadCachedLoadoutRaw(String puuid) {
    return _cache.loadLoadoutRaw(puuid: puuid);
  }
}
