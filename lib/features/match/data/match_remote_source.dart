import 'package:dio/dio.dart';
import '../domain/models/match_history.dart';
import '../domain/models/match_details.dart';

class MatchRemoteSource {
  const MatchRemoteSource(this._dio);
  final Dio _dio;

  Future<MatchHistoryResult> fetchHistory(
    String shard,
    String puuid, {
    int startIndex = 0,
    int endIndex = 20,
    String? queue,
  }) async {
    final params = <String, dynamic>{
      'startIndex': startIndex,
      'endIndex': endIndex,
      if (queue != null) 'queue': queue,
    };
    final response = await _dio.get<Map<String, dynamic>>(
      'https://pd.$shard.a.pvp.net/match-history/v1/history/$puuid',
      queryParameters: params,
    );
    return MatchHistoryResult.fromJson(response.data ?? {});
  }

  Future<MatchDetails> fetchMatchDetails(
      String shard, String matchId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      'https://pd.$shard.a.pvp.net/match-details/v1/matches/$matchId',
    );
    return MatchDetails.fromJson(response.data ?? {});
  }
}
