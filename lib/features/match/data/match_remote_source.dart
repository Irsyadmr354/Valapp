import 'dart:convert';
import 'package:dio/dio.dart';
import '../domain/models/match_history.dart';
import '../domain/models/match_details.dart';

class MatchRemoteSource {
  const MatchRemoteSource(this._dio);
  final Dio _dio;

  Map<String, dynamic> _toMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return {};
  }

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
    final response = await _dio.get<dynamic>(
      'https://pd.$shard.a.pvp.net/match-history/v1/history/$puuid',
      queryParameters: params,
    );
    return MatchHistoryResult.fromJson(_toMap(response.data));
  }

  Future<MatchDetails> fetchMatchDetails(
      String shard, String matchId) async {
    final response = await _dio.get<dynamic>(
      'https://pd.$shard.a.pvp.net/match-details/v1/matches/$matchId',
    );
    return MatchDetails.fromJson(_toMap(response.data));
  }
}

