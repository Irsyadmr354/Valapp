import 'package:dio/dio.dart';
import '../../core/storage/cache_storage.dart';

/// Fetches and caches metadata from `valorant-api.com`.
/// All data is refreshed once every 24 hours.
class ValorantAssets {
  ValorantAssets._();
  static final ValorantAssets instance = ValorantAssets._();

  static const _base = 'https://valorant-api.com/v1';
  static const _cacheDuration = Duration(hours: 24);

  final _dio = Dio();

  // ── Skin Levels ────────────────────────────────────────────────────────────

  /// Returns a map of skinLevel UUID → skin metadata.
  Future<Map<String, dynamic>> getSkinLevelsMap() async {
    final cache = CacheStorage.instance;
    final isStale = await cache.isStale(
      CacheStorage.keySkinMetadataFetchedAt,
      _cacheDuration,
    );

    if (!isStale) {
      final cached = await cache.getJson(CacheStorage.keySkinMetadata);
      if (cached != null) return cached;
    }

    final response =
        await _dio.get<Map<String, dynamic>>('$_base/weapons/skins');
    final skins = (response.data?['data'] as List<dynamic>?) ?? [];

    final map = <String, dynamic>{};
    for (final skin in skins) {
      final levels = skin['levels'] as List<dynamic>? ?? [];
      for (final level in levels) {
        final uuid = level['uuid'] as String?;
        if (uuid != null) {
          map[uuid] = {
            'displayName': level['displayName'],
            'displayIcon': level['displayIcon'],
            'skinName': skin['displayName'],
            'themeUuid': skin['themeUuid'],
            'contentTierUuid': skin['contentTierUuid'],
          };
        }
      }
    }

    await cache.setJson(CacheStorage.keySkinMetadata, map);
    await cache.setTimestamp(CacheStorage.keySkinMetadataFetchedAt);
    return map;
  }

  /// Returns metadata for a single skin level UUID.
  Future<Map<String, dynamic>?> getSkinLevel(String uuid) async {
    final map = await getSkinLevelsMap();
    return map[uuid] as Map<String, dynamic>?;
  }

  // ── Content Tiers ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getContentTiersMap() async {
    final cache = CacheStorage.instance;
    final isStale = await cache.isStale(
      CacheStorage.keyContentTiersFetchedAt,
      _cacheDuration,
    );

    if (!isStale) {
      final cached = await cache.getJson(CacheStorage.keyContentTiers);
      if (cached != null) return cached;
    }

    final response =
        await _dio.get<Map<String, dynamic>>('$_base/contenttiers');
    final tiers = (response.data?['data'] as List<dynamic>?) ?? [];

    final map = <String, dynamic>{};
    for (final tier in tiers) {
      final uuid = tier['uuid'] as String?;
      if (uuid != null) {
        map[uuid] = {
          'displayName': tier['displayName'],
          'displayIcon': tier['displayIcon'],
          'highlightColor': tier['highlightColor'],
          'rank': tier['rank'],
        };
      }
    }

    await cache.setJson(CacheStorage.keyContentTiers, map);
    await cache.setTimestamp(CacheStorage.keyContentTiersFetchedAt);
    return map;
  }

  // ── Competitive Tiers ──────────────────────────────────────────────────────

  /// Returns the latest competitive tier list (rank names, icons, colors).
  Future<List<dynamic>> getCompetitiveTiers() async {
    final cache = CacheStorage.instance;
    final isStale = await cache.isStale(
      CacheStorage.keyCompetitiveTiersFetchedAt,
      _cacheDuration,
    );

    if (!isStale) {
      final cached = await cache.getJsonList(CacheStorage.keyCompetitiveTiers);
      if (cached != null) return cached;
    }

    final response =
        await _dio.get<Map<String, dynamic>>('$_base/competitivetiers');
    // Last item in the list is the most recent season's tiers
    final allSeasons = (response.data?['data'] as List<dynamic>?) ?? [];
    final tiers = allSeasons.isNotEmpty
        ? (allSeasons.last['tiers'] as List<dynamic>? ?? [])
        : <dynamic>[];

    await cache.setJson(
        CacheStorage.keyCompetitiveTiers, {'tiers': tiers});
    await cache.setTimestamp(CacheStorage.keyCompetitiveTiersFetchedAt);
    return tiers;
  }

  /// Returns a tier map keyed by tier number.
  Future<Map<int, Map<String, dynamic>>> getCompetitiveTiersMap() async {
    final tiers = await getCompetitiveTiers();
    final map = <int, Map<String, dynamic>>{};
    for (final t in tiers) {
      final tier = t['tier'] as int?;
      if (tier != null) {
        map[tier] = Map<String, dynamic>.from(t as Map);
      }
    }
    return map;
  }
}
