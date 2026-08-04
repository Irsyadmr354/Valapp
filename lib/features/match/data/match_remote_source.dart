import 'package:dio/dio.dart';
import '../../../core/network/api_response_decoder.dart';
import '../../../core/storage/cache_storage.dart';
import '../domain/models/match_details.dart';

class MatchRemoteSource {
  const MatchRemoteSource(this._dio);
  final Dio _dio;

  Future<Map<String, dynamic>> fetchHistoryRaw(
    String shard,
    String puuid, {
    int startIndex = 0,
    int endIndex = 15,
    String? queue,
  }) async {
    final cleanShard = shard.toLowerCase();
    final params = <String, dynamic>{
      'startIndex': startIndex,
      'endIndex': endIndex,
      if (queue != null && queue.isNotEmpty) 'queue': queue,
    };
    final url =
        'https://pd.$cleanShard.a.pvp.net/match-history/v1/history/$puuid';
    final response = await _dio.get<dynamic>(url, queryParameters: params);
    final data = ApiResponseDecoder.decodeMap(response.data, source: url);
    return ApiResponseDecoder.requireShape(
      data,
      source: url,
      lists: ['History'],
      strings: ['Subject'],
    );
  }

  Future<Map<String, dynamic>> fetchMatchDetailsRaw(
      String shard, String matchId) async {
    final cleanShard = shard.toLowerCase();
    final url =
        'https://pd.$cleanShard.a.pvp.net/match-details/v1/matches/$matchId';
    final response = await _dio.get<dynamic>(url);
    final raw = ApiResponseDecoder.decodeMap(response.data, source: url);
    ApiResponseDecoder.requireShape(
      raw,
      source: url,
      maps: ['matchInfo'],
      lists: ['players', 'roundResults'],
    );
    final details = MatchDetails.fromJson(raw);
    if (details.matchInfo.mapId.isNotEmpty) {
      CacheStorage.instance.saveMatchMap(matchId, details.matchInfo.mapId);
    }
    return raw;
  }
}
