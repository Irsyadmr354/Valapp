import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../core/storage/cache_storage.dart';
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
    int endIndex = 15,
    String? queue,
  }) async {
    final cleanShard = shard.toLowerCase();
    final params = <String, dynamic>{
      'startIndex': startIndex,
      'endIndex': endIndex,
      if (queue != null && queue.isNotEmpty) 'queue': queue,
    };
    final response = await _dio.get<dynamic>(
      'https://pd.$cleanShard.a.pvp.net/match-history/v1/history/$puuid',
      queryParameters: params,
    );
    return MatchHistoryResult.fromJson(_toMap(response.data));
  }

  Future<MatchDetails> fetchMatchDetails(
      String shard, String matchId) async {
    final cleanShard = shard.toLowerCase();
    final response = await _dio.get<dynamic>(
      'https://pd.$cleanShard.a.pvp.net/match-details/v1/matches/$matchId',
    );
    final details = MatchDetails.fromJson(_toMap(response.data));
    if (details.matchInfo.mapId.isNotEmpty) {
      CacheStorage.instance.saveMatchMap(matchId, details.matchInfo.mapId);
    }
    return details;
  }
}

