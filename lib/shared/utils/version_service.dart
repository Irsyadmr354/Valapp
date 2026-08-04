import 'package:dio/dio.dart';
import '../../core/storage/cache_storage.dart';

/// Fetches and caches the current Riot Client version string.
/// Refreshes every 24 hours from `valorant-api.com`.
class VersionService {
  VersionService._();
  static final VersionService instance = VersionService._();

  /// Single reusable Dio instance — avoids allocating a new client on
  /// every cache miss (which would also leak the underlying HttpClient).
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  static const _versionUrl = 'https://valorant-api.com/v1/version';
  static const _cacheDuration = Duration(hours: 24);

  /// In-flight fetch future — shared so concurrent callers await one request.
  Future<String>? _inFlight;

  /// Invalidate version cache so fresh version is fetched next time.
  Future<void> invalidate() async {
    await CacheStorage.instance.remove(CacheStorage.keyClientVersion);
    await CacheStorage.instance.remove(CacheStorage.keyClientVersionFetchedAt);
  }

  /// Returns the current Riot client version, cached for 24 hours.
  Future<String> get() async {
    // Deduplicate concurrent calls — return the same in-flight future
    // to all callers so only one network request is made.
    _inFlight ??= _fetch().whenComplete(() => _inFlight = null);
    return _inFlight!;
  }

  Future<String> _fetch() async {
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
      final response = await _dio.get<Map<String, dynamic>>(_versionUrl);
      final version = response.data?['data']?['riotClientVersion'] as String?;
      if (version == null ||
          version.isEmpty ||
          !version.startsWith('release-')) {
        throw const FormatException('Invalid Riot client version response');
      }

      await cache.setString(CacheStorage.keyClientVersion, version);
      await cache.setTimestamp(CacheStorage.keyClientVersionFetchedAt);

      return version;
    } catch (_) {
      final cached = await cache.getString(CacheStorage.keyClientVersion);
      if (cached != null && cached.isNotEmpty) return cached;
      throw StateError('No verified Riot client version is available');
    }
  }
}
