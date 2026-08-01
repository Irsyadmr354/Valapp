import 'package:dio/dio.dart';
import '../../core/storage/cache_storage.dart';

/// Fetches and caches the current Riot Client version string.
/// Refreshes every 24 hours from `valorant-api.com`.
class VersionService {
  VersionService._();
  static final VersionService instance = VersionService._();

  static const _versionUrl = 'https://valorant-api.com/v1/version';
  static const _cacheDuration = Duration(hours: 24);
  static const _fallback = 'release-13.02-shipping-7-5092570';

  /// Invalidate version cache so fresh version is fetched next time.
  Future<void> invalidate() async {
    await CacheStorage.instance.remove(CacheStorage.keyClientVersion);
    await CacheStorage.instance.remove(CacheStorage.keyClientVersionFetchedAt);
  }

  /// Returns the current Riot client version, cached for 24 hours.
  Future<String> get() async {
    final cache = CacheStorage.instance;

    // Return cached version if still fresh
    final isStale = await cache.isStale(
      CacheStorage.keyClientVersionFetchedAt,
      _cacheDuration,
    );
    if (!isStale) {
      final cached = await cache.getString(CacheStorage.keyClientVersion);
      if (cached != null && cached.isNotEmpty) return cached;
    }

    // Fetch fresh version
    try {
      final response = await Dio().get<Map<String, dynamic>>(_versionUrl);
      final version =
          response.data?['data']?['riotClientVersion'] as String? ?? _fallback;

      await cache.setString(CacheStorage.keyClientVersion, version);
      await cache.setTimestamp(CacheStorage.keyClientVersionFetchedAt);

      return version;
    } catch (_) {
      // Return cached even if stale, or fallback
      final cached = await cache.getString(CacheStorage.keyClientVersion);
      return cached ?? _fallback;
    }
  }
}
