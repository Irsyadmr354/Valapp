import 'package:dio/dio.dart';
import '../../../core/network/api_response_decoder.dart';
import '../../../core/storage/cache_storage.dart';
import '../../../shared/constants/valorant_constants.dart';
import '../domain/models/player_mmr.dart';

class MmrRemoteSource {
  const MmrRemoteSource(this._dio);
  final Dio _dio;

  Future<Map<String, dynamic>> fetchMmrRaw(String shard, String puuid) async {
    final url = '${RiotEndpoints.pd(shard)}/mmr/v1/players/$puuid';
    final response = await _dio.get<dynamic>(url);
    final data = ApiResponseDecoder.decodeMap(response.data, source: url);
    return ApiResponseDecoder.requireShape(
      data,
      source: url,
      maps: ['QueueSkills'],
      strings: ['Subject'],
    );
  }

  Future<List<CompetitiveUpdate>> fetchCompetitiveUpdates(
    String shard,
    String puuid, {
    int startIndex = 0,
    int endIndex = 20,
  }) async {
    final raw = await fetchCompetitiveUpdatesRaw(
      shard,
      puuid,
      startIndex: startIndex,
      endIndex: endIndex,
    );
    final list = parseCompetitiveUpdates(raw);
    await _cacheMatchMaps(list);
    return list;
  }

  Future<Map<String, dynamic>> fetchCompetitiveUpdatesRaw(
    String shard,
    String puuid, {
    int startIndex = 0,
    int endIndex = 20,
  }) async {
    final url =
        '${RiotEndpoints.pd(shard)}/mmr/v1/players/$puuid/competitiveupdates';
    final response = await _dio.get<dynamic>(
      url,
      queryParameters: {
        'startIndex': startIndex,
        'endIndex': endIndex,
      },
    );
    final data = ApiResponseDecoder.decodeMap(response.data, source: url);
    return ApiResponseDecoder.requireShape(data,
        source: url, lists: ['Matches']);
  }

  List<CompetitiveUpdate> parseCompetitiveUpdates(Map<String, dynamic> data) {
    final matches = data['Matches'];
    if (matches is! List) return const [];
    return matches
        .whereType<Map>()
        .map((e) => CompetitiveUpdate.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> _cacheMatchMaps(List<CompetitiveUpdate> list) async {
    final futures = <Future<void>>[];
    for (final update in list) {
      final mapId = update.mapId;
      if (update.matchId.isNotEmpty && mapId != null && mapId.isNotEmpty) {
        futures.add(CacheStorage.instance.saveMatchMap(update.matchId, mapId));
      }
    }
    if (futures.isNotEmpty) {
      try {
        await Future.wait(futures);
      } catch (_) {}
    }
  }
}
