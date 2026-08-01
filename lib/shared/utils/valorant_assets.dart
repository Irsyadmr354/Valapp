import 'package:dio/dio.dart';
import '../../core/storage/cache_storage.dart';

/// Fetches and caches metadata from `valorant-api.com`.
/// All data is refreshed once every 24 hours.
class ValorantAssets {
  ValorantAssets._();
  static final ValorantAssets instance = ValorantAssets._();

  static const _base = 'https://valorant-api.com/v1';
  static const _cacheDuration = Duration(hours: 24);

  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
  ));

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
            'skinUuid': skin['uuid'],
            'themeUuid': skin['themeUuid'],
            'contentTierUuid': skin['contentTierUuid'],
            'wallpaper': skin['wallpaper'],
            'chromas': skin['chromas'],
            'levels': skin['levels'],
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
    final item = map[uuid] as Map<String, dynamic>?;
    if (item != null && item['chromas'] != null) {
      return item;
    }

    // Failsafe fallback: clear stale cache and re-fetch if chromas key was missing
    final cache = CacheStorage.instance;
    await cache.remove(CacheStorage.keySkinMetadata);
    await cache.remove(CacheStorage.keySkinMetadataFetchedAt);
    final freshMap = await getSkinLevelsMap();
    return freshMap[uuid] as Map<String, dynamic>?;
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

  // ── Bundles ────────────────────────────────────────────────────────────────

  /// Returns a map of bundle UUID → bundle metadata (name, icons, promo images).
  Future<Map<String, dynamic>> getBundlesMap() async {
    final cache = CacheStorage.instance;
    const keyBundles = 'bundles_metadata';
    const keyBundlesFetchedAt = 'bundles_metadata_fetched_at';

    final isStale = await cache.isStale(keyBundlesFetchedAt, _cacheDuration);
    if (!isStale) {
      final cached = await cache.getJson(keyBundles);
      if (cached != null) return cached;
    }

    try {
      final response =
          await _dio.get<Map<String, dynamic>>('$_base/bundles');
      final bundles = (response.data?['data'] as List<dynamic>?) ?? [];

      final map = <String, dynamic>{};
      for (final b in bundles) {
        final uuid = b['uuid'] as String?;
        if (uuid != null) {
          final info = {
            'displayName': b['displayName'],
            'displayIcon': b['displayIcon'],
            'displayIcon2': b['displayIcon2'],
            'verticalPromoImage': b['verticalPromoImage'],
          };
          map[uuid] = info;
          map[uuid.toLowerCase()] = info;
        }
      }

      await cache.setJson(keyBundles, map);
      await cache.setTimestamp(keyBundlesFetchedAt);
      return map;
    } catch (_) {
      final cached = await cache.getJson(keyBundles);
      return cached ?? {};
    }
  }

  // ── Maps ───────────────────────────────────────────────────────────────────

  /// Returns a map of map name / path / codename → map metadata (splash image, icons).
  Future<Map<String, dynamic>> getMapsMap() async {
    final cache = CacheStorage.instance;
    const keyMaps = 'maps_metadata';
    const keyMapsFetchedAt = 'maps_metadata_fetched_at';
    // Version bump — forces re-fetch when map indexing logic changes
    const mapsVersion = 'v3';
    const keyMapsVersion = 'maps_metadata_version';

    final storedVersion = await cache.getString(keyMapsVersion);
    final isStale = await cache.isStale(keyMapsFetchedAt, _cacheDuration);
    if (!isStale && storedVersion == mapsVersion) {
      final cached = await cache.getJson(keyMaps);
      if (cached != null) return cached;
    }

    try {
      final response = await _dio.get<Map<String, dynamic>>('$_base/maps');
      final maps = (response.data?['data'] as List<dynamic>?) ?? [];

      final map = <String, dynamic>{};

      // Hardcoded codename overrides for Riot internal map paths
      final codenameMap = {
        'plummet': 'abyss',
        'infinity': 'abyss',
        'jam': 'lotus',
        'juliett': 'sunset',
        'canyon': 'fracture',
        'port': 'icebox',
        'lowpe': 'pearl',
        'pitt': 'pearl',
        'foxtrot': 'drift',
        'triad': 'haven',
        'bonsai': 'split',
        'duality': 'bind',
      };

      for (final m in maps) {
        final displayName = m['displayName']?.toString() ?? '';
        final mapUrl = m['mapUrl']?.toString() ?? '';
        final splash = m['splash']?.toString() ?? m['listViewIcon']?.toString() ?? '';
        final displayIcon = m['displayIcon']?.toString() ?? '';

        final info = {
          'displayName': displayName,
          'splash': splash,
          'displayIcon': displayIcon,
          'listViewIcon': m['listViewIcon']?.toString() ?? splash,
        };

        // Index by display name (e.g. "bind")
        if (displayName.isNotEmpty) {
          map[displayName.toLowerCase()] = info;
        }

        if (mapUrl.isNotEmpty) {
          final lowerUrl = mapUrl.toLowerCase();

          // Index by full URL
          map[lowerUrl] = info;

          // Index by every path segment (handles /Game/Maps/Duality/Duality)
          final segments = lowerUrl.split('/').where((s) => s.isNotEmpty).toList();
          for (final seg in segments) {
            if (seg.isEmpty) continue;
            map[seg] = info;

            // Strip common Riot suffix variants:
            // _wp (WorldPartition), _wip, _p, _p0, _test, _playtest, _dev, numeric suffix
            final cleaned = seg
                .replaceAll(RegExp(r'_wp$'), '')
                .replaceAll(RegExp(r'_wip$'), '')
                .replaceAll(RegExp(r'_p\d*$'), '')
                .replaceAll(RegExp(r'_test$'), '')
                .replaceAll(RegExp(r'_playtest$'), '')
                .replaceAll(RegExp(r'_dev$'), '')
                .replaceAll(RegExp(r'_\d+$'), '');
            if (cleaned.isNotEmpty && cleaned != seg) {
              map[cleaned] = info;
            }
          }
        }
      }

      // Alias internal codenames to their official map metadata
      codenameMap.forEach((code, official) {
        final officialInfo = map[official];
        if (officialInfo != null) {
          map[code] = officialInfo;
        }
      });

      await cache.setJson(keyMaps, map);
      await cache.setTimestamp(keyMapsFetchedAt);
      await cache.setString(keyMapsVersion, mapsVersion);
      return map;
    } catch (_) {
      final cached = await cache.getJson(keyMaps);
      return cached ?? {};
    }
  }

  // ── Contracts / Battle Pass ───────────────────────────────────────────────

  /// Returns contract metadata including chapters, levels, and reward items.
  Future<Map<String, dynamic>?> getContract(String contractUuid) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('$_base/contracts/$contractUuid');
      return response.data?['data'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  // ── Agents ─────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getAgentsMap() async {
    final cache = CacheStorage.instance;
    const keyAgents = 'agents_metadata';
    const keyAgentsFetchedAt = 'agents_metadata_fetched_at';

    final isStale = await cache.isStale(keyAgentsFetchedAt, _cacheDuration);
    if (!isStale) {
      final cached = await cache.getJson(keyAgents);
      if (cached != null) return cached;
    }
    try {
      final response = await _dio.get<Map<String, dynamic>>(
          '$_base/agents?isPlayableCharacter=true');
      final agents = (response.data?['data'] as List<dynamic>?) ?? [];
      final map = <String, dynamic>{};
      for (final a in agents) {
        final uuid = a['uuid'] as String?;
        if (uuid != null) {
          map[uuid] = {
            'displayName': a['displayName'],
            'displayIcon': a['displayIcon'],
            'fullPortrait': a['fullPortraitV2'] ?? a['fullPortrait'],
            'background': a['background'],
            'role': (a['role'] as Map<String, dynamic>?)?['displayName'],
            'roleIcon': (a['role'] as Map<String, dynamic>?)?['displayIcon'],
          };
        }
      }
      await cache.setJson(keyAgents, map);
      await cache.setTimestamp(keyAgentsFetchedAt);
      return map;
    } catch (_) {
      return await cache.getJson(keyAgents) ?? {};
    }
  }

  // ── Player Cards ───────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getPlayerCardsMap() async {
    final cache = CacheStorage.instance;
    const keyCards = 'player_cards_metadata';
    const keyCardsFetchedAt = 'player_cards_metadata_fetched_at';

    final isStale = await cache.isStale(keyCardsFetchedAt, _cacheDuration);
    if (!isStale) {
      final cached = await cache.getJson(keyCards);
      if (cached != null) return cached;
    }
    try {
      final response =
          await _dio.get<Map<String, dynamic>>('$_base/playercards');
      final cards = (response.data?['data'] as List<dynamic>?) ?? [];
      final map = <String, dynamic>{};
      for (final c in cards) {
        final uuid = c['uuid'] as String?;
        if (uuid != null) {
          map[uuid] = {
            'displayName': c['displayName'],
            'smallArt': c['smallArt'],
            'wideArt': c['wideArt'],
            'largeArt': c['largeArt'],
            'displayIcon': c['displayIcon'],
          };
        }
      }
      await cache.setJson(keyCards, map);
      await cache.setTimestamp(keyCardsFetchedAt);
      return map;
    } catch (_) {
      return await cache.getJson(keyCards) ?? {};
    }
  }

  // ── Sprays ─────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getSpraysMap() async {
    final cache = CacheStorage.instance;
    const keySprays = 'sprays_metadata';
    const keySpraysFetchedAt = 'sprays_metadata_fetched_at';

    final isStale = await cache.isStale(keySpraysFetchedAt, _cacheDuration);
    if (!isStale) {
      final cached = await cache.getJson(keySprays);
      if (cached != null) return cached;
    }
    try {
      final response =
          await _dio.get<Map<String, dynamic>>('$_base/sprays');
      final sprays = (response.data?['data'] as List<dynamic>?) ?? [];
      final map = <String, dynamic>{};
      for (final s in sprays) {
        final uuid = s['uuid'] as String?;
        if (uuid != null) {
          map[uuid] = {
            'displayName': s['displayName'],
            'displayIcon': s['displayIcon'],
            'fullIcon': s['fullIcon'],
            'animationPng': s['animationPng'],
          };
        }
      }
      await cache.setJson(keySprays, map);
      await cache.setTimestamp(keySpraysFetchedAt);
      return map;
    } catch (_) {
      return await cache.getJson(keySprays) ?? {};
    }
  }

  // ── Player Titles ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getPlayerTitlesMap() async {
    final cache = CacheStorage.instance;
    const keyTitles = 'player_titles_metadata';
    const keyTitlesFetchedAt = 'player_titles_metadata_fetched_at';

    final isStale = await cache.isStale(keyTitlesFetchedAt, _cacheDuration);
    if (!isStale) {
      final cached = await cache.getJson(keyTitles);
      if (cached != null) return cached;
    }
    try {
      final response =
          await _dio.get<Map<String, dynamic>>('$_base/playertitles');
      final titles = (response.data?['data'] as List<dynamic>?) ?? [];
      final map = <String, dynamic>{};
      for (final t in titles) {
        final uuid = t['uuid'] as String?;
        if (uuid != null) {
          map[uuid] = {
            'displayName': t['displayName'],
            'titleText': t['titleText'],
          };
        }
      }
      await cache.setJson(keyTitles, map);
      await cache.setTimestamp(keyTitlesFetchedAt);
      return map;
    } catch (_) {
      return await cache.getJson(keyTitles) ?? {};
    }
  }

  // ── Seasons ────────────────────────────────────────────────────────────────

  /// Returns the active episode and act display names as a map:
  /// { 'episode': 'EPISODE 8', 'act': 'ACT 3', 'label': 'EPISODE 8 // ACT 3' }
  Future<Map<String, String>> getActiveSeason() async {
    final cache = CacheStorage.instance;
    const keySeasons = 'seasons_metadata';
    const keySeasonsFetchedAt = 'seasons_metadata_fetched_at';

    final isStale = await cache.isStale(keySeasonsFetchedAt, _cacheDuration);
    if (!isStale) {
      final cached = await cache.getJson(keySeasons);
      if (cached != null) {
        return Map<String, String>.from(cached.map(
            (k, v) => MapEntry(k, v?.toString() ?? '')));
      }
    }
    try {
      final response = await _dio.get<Map<String, dynamic>>('$_base/seasons');
      final seasons = (response.data?['data'] as List<dynamic>?) ?? [];
      final now = DateTime.now();

      String episode = '';
      String act = '';

      for (final s in seasons) {
        final start = DateTime.tryParse(s['startTime']?.toString() ?? '') ??
            DateTime(2020);
        final end = DateTime.tryParse(s['endTime']?.toString() ?? '') ??
            DateTime(2099);
        if (!now.isAfter(start) || !now.isBefore(end)) continue;

        final type = s['type']?.toString() ?? '';
        final name = s['displayName']?.toString() ?? '';
        if (type.toLowerCase().contains('episode') || type == 'EAresSeasonType::Episode') {
          final num = RegExp(r'\d+').firstMatch(name)?.group(0) ?? '';
          episode = num.isNotEmpty ? 'EPISODE $num' : name.toUpperCase();
        } else if (type.toLowerCase().contains('act') || type == 'EAresSeasonType::Act') {
          final num = RegExp(r'\d+').firstMatch(name)?.group(0) ?? '';
          act = num.isNotEmpty ? 'ACT $num' : name.toUpperCase();
        }
      }

      // Fallback
      if (episode.isEmpty) episode = 'EPISODE 9';
      if (act.isEmpty) act = 'ACT 1';

      final result = {
        'episode': episode,
        'act': act,
        'label': '$episode // $act',
      };
      await cache.setJson(keySeasons, result);
      await cache.setTimestamp(keySeasonsFetchedAt);
      return result;
    } catch (_) {
      final cached = await cache.getJson(keySeasons);
      if (cached != null) {
        return Map<String, String>.from(
            cached.map((k, v) => MapEntry(k, v?.toString() ?? '')));
      }
      return {'episode': 'EPISODE 9', 'act': 'ACT 1', 'label': 'EPISODE 9 // ACT 1'};
    }
  }

  // ── Themes (Skin Collections) ─────────────────────────────────────────────

  /// Returns a map of theme UUID → { 'displayName', 'displayIcon' }
  Future<Map<String, dynamic>> getThemesMap() async {
    final cache = CacheStorage.instance;
    const keyThemes = 'themes_metadata';
    const keyThemesFetchedAt = 'themes_metadata_fetched_at';

    final isStale = await cache.isStale(keyThemesFetchedAt, _cacheDuration);
    if (!isStale) {
      final cached = await cache.getJson(keyThemes);
      if (cached != null) return cached;
    }
    try {
      final response = await _dio.get<Map<String, dynamic>>('$_base/themes');
      final themes = (response.data?['data'] as List<dynamic>?) ?? [];
      final map = <String, dynamic>{};
      for (final t in themes) {
        final uuid = t['uuid'] as String?;
        if (uuid != null) {
          map[uuid] = {
            'displayName': t['displayName'],
            'displayIcon': t['displayIcon'],
            'storeFeaturedImage': t['storeFeaturedImage'],
          };
        }
      }
      await cache.setJson(keyThemes, map);
      await cache.setTimestamp(keyThemesFetchedAt);
      return map;
    } catch (_) {
      return await cache.getJson(keyThemes) ?? {};
    }
  }

  // ── Weapons (base weapon data, not skins) ─────────────────────────────────

  /// Returns a map of weapon UUID → { 'displayName', 'displayIcon', 'killStreamIcon' }
  Future<Map<String, dynamic>> getWeaponsMap() async {
    final cache = CacheStorage.instance;
    const keyWeapons = 'weapons_base_metadata';
    const keyWeaponsFetchedAt = 'weapons_base_metadata_fetched_at';

    final isStale = await cache.isStale(keyWeaponsFetchedAt, _cacheDuration);
    if (!isStale) {
      final cached = await cache.getJson(keyWeapons);
      if (cached != null) return cached;
    }
    try {
      final response = await _dio.get<Map<String, dynamic>>('$_base/weapons');
      final weapons = (response.data?['data'] as List<dynamic>?) ?? [];
      final map = <String, dynamic>{};
      for (final w in weapons) {
        final uuid = w['uuid'] as String?;
        if (uuid != null) {
          map[uuid] = {
            'displayName': w['displayName'],
            'displayIcon': w['displayIcon'],
            'killStreamIcon': w['killStreamIcon'],
            'category': w['shopData']?['category'] ?? w['category'],
          };
          // Also index by lowercased display name for easy lookup
          final name = (w['displayName'] as String?)?.toLowerCase();
          if (name != null) map[name] = map[uuid];
        }
      }
      await cache.setJson(keyWeapons, map);
      await cache.setTimestamp(keyWeaponsFetchedAt);
      return map;
    } catch (_) {
      return await cache.getJson(keyWeapons) ?? {};
    }
  }

  // ── Currencies (VP / RP / KC icons) ───────────────────────────────────────

  /// Returns a map of currency UUID → { 'displayName', 'displayIcon', 'largeIcon' }
  /// VP UUID: 85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741
  /// RP UUID: e59aa87c-4cbf-517a-5983-6e81511be9b7
  /// KC UUID: 85ca954a-41f2-ce94-9b45-8ca3dd39a00d
  Future<Map<String, dynamic>> getCurrenciesMap() async {
    final cache = CacheStorage.instance;
    const keyCurrencies = 'currencies_metadata';
    const keyCurrenciesFetchedAt = 'currencies_metadata_fetched_at';

    final isStale = await cache.isStale(keyCurrenciesFetchedAt, _cacheDuration);
    if (!isStale) {
      final cached = await cache.getJson(keyCurrencies);
      if (cached != null) return cached;
    }
    try {
      final response =
          await _dio.get<Map<String, dynamic>>('$_base/currencies');
      final currencies = (response.data?['data'] as List<dynamic>?) ?? [];
      final map = <String, dynamic>{};
      for (final c in currencies) {
        final uuid = c['uuid'] as String?;
        if (uuid != null) {
          map[uuid] = {
            'displayName': c['displayName'],
            'displayIcon': c['displayIcon'],
            'largeIcon': c['largeIcon'],
          };
        }
      }
      await cache.setJson(keyCurrencies, map);
      await cache.setTimestamp(keyCurrenciesFetchedAt);
      return map;
    } catch (_) {
      return await cache.getJson(keyCurrencies) ?? {};
    }
  }

  // ── Contract Definitions (UUID → agent UUID mapping) ──────────────────────

  /// Returns a map of contract UUID → { 'displayName', 'agentUuid', 'displayIcon', 'isFreeToPlay' }
  /// Used to properly resolve agent contracts on the Progress screen.
  Future<Map<String, dynamic>> getContractDefsMap() async {
    final cache = CacheStorage.instance;
    const keyContractDefs = 'contract_defs_metadata';
    const keyContractDefsFetchedAt = 'contract_defs_metadata_fetched_at';

    final isStale =
        await cache.isStale(keyContractDefsFetchedAt, _cacheDuration);
    if (!isStale) {
      final cached = await cache.getJson(keyContractDefs);
      if (cached != null) return cached;
    }
    try {
      final response =
          await _dio.get<Map<String, dynamic>>('$_base/contracts');
      final contracts = (response.data?['data'] as List<dynamic>?) ?? [];
      final map = <String, dynamic>{};
      for (final c in contracts) {
        final uuid = c['uuid'] as String?;
        if (uuid != null) {
          // shipIt: agent UUID lives in c['content']['relationType'] == 'Agent'
          // and c['content']['relationUuid']
          final content = c['content'] as Map<String, dynamic>? ?? {};
          final relationType = content['relationType'] as String?;
          final agentUuid = relationType == 'Agent'
              ? content['relationUuid'] as String?
              : null;
          map[uuid] = {
            'displayName': c['displayName'],
            'displayIcon': c['displayIcon'],
            'agentUuid': agentUuid,
            'isFreeToPlay': c['freeRewardScheduleUuid'] != null,
          };
        }
      }
      await cache.setJson(keyContractDefs, map);
      await cache.setTimestamp(keyContractDefsFetchedAt);
      return map;
    } catch (_) {
      return await cache.getJson(keyContractDefs) ?? {};
    }
  }

  // ── Level Borders ──────────────────────────────────────────────────────────

  /// Returns a list of level border entries sorted by startingLevel ascending:
  /// [{ 'uuid', 'displayName', 'startingLevel', 'displayIcon', 'smallPlayerCardAppearance' }]
  Future<List<Map<String, dynamic>>> getLevelBordersList() async {
    final cache = CacheStorage.instance;
    const keyBorders = 'level_borders_metadata_v2'; // v2 — fixes displayIcon field
    const keyBordersFetchedAt = 'level_borders_metadata_v2_fetched_at';

    final isStale = await cache.isStale(keyBordersFetchedAt, _cacheDuration);
    if (!isStale) {
      final cached = await cache.getJsonList(keyBorders);
      if (cached != null) {
        return cached.whereType<Map<String, dynamic>>().toList();
      }
    }
    try {
      final response =
          await _dio.get<Map<String, dynamic>>('$_base/levelborders');
      final borders = (response.data?['data'] as List<dynamic>?) ?? [];
      final list = borders
          .whereType<Map<String, dynamic>>()
          .map((b) => {
                'uuid': b['uuid'],
                'displayName': b['displayName'],
                'startingLevel': b['startingLevel'] ?? 0,
                // levelNumberAppearance = the glowing border ring icon (best for display)
                // smallPlayerCardAppearance = transparent frame overlay (for card UI)
                'levelNumberAppearance': b['levelNumberAppearance'],
                'smallPlayerCardAppearance': b['smallPlayerCardAppearance'],
                'displayIcon': b['levelNumberAppearance'] ??
                    b['smallPlayerCardAppearance'],
              })
          .toList()
        ..sort((a, b) => ((a['startingLevel'] as int?) ?? 0)
            .compareTo((b['startingLevel'] as int?) ?? 0));
      await cache.setJson(keyBorders, list);
      await cache.setTimestamp(keyBordersFetchedAt);
      return list;
    } catch (_) {
      final cached = await cache.getJsonList(keyBorders);
      if (cached != null) {
        return cached.whereType<Map<String, dynamic>>().toList();
      }
      return [];
    }
  }

  Future<Map<String, dynamic>> getBuddiesMap() async {
    final cache = CacheStorage.instance;
    const keyBuddies = 'buddies_metadata';
    const keyBuddiesFetchedAt = 'buddies_metadata_fetched_at';

    final isStale = await cache.isStale(keyBuddiesFetchedAt, _cacheDuration);
    if (!isStale) {
      final cached = await cache.getJson(keyBuddies);
      if (cached != null) return cached;
    }
    try {
      final response =
          await _dio.get<Map<String, dynamic>>('$_base/buddies');
      final buddies = (response.data?['data'] as List<dynamic>?) ?? [];
      final map = <String, dynamic>{};
      for (final b in buddies) {
        final levels = b['levels'] as List<dynamic>? ?? [];
        // Index each buddy level UUID
        for (final level in levels) {
          final uuid = level['uuid'] as String?;
          if (uuid != null) {
            map[uuid] = {
              'displayName': b['displayName'],
              'displayIcon': level['displayIcon'],
              'buddyUuid': b['uuid'],
            };
          }
        }
        // Also index by parent buddy UUID for convenience
        final buddyUuid = b['uuid'] as String?;
        if (buddyUuid != null && levels.isNotEmpty) {
          final firstLevel = levels.first as Map<String, dynamic>;
          map[buddyUuid] = {
            'displayName': b['displayName'],
            'displayIcon': firstLevel['displayIcon'],
            'buddyUuid': buddyUuid,
          };
        }
      }
      await cache.setJson(keyBuddies, map);
      await cache.setTimestamp(keyBuddiesFetchedAt);
      return map;
    } catch (_) {
      return await cache.getJson(keyBuddies) ?? {};
    }
  }
}



