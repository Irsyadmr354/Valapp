import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../core/storage/cache_storage.dart';
import '../domain/models/player_mmr.dart';

class MmrRemoteSource {
  const MmrRemoteSource(this._dio);
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

  Future<Map<String, dynamic>> fetchMmrRaw(String shard, String puuid) async {
    final cleanShard = shard.toLowerCase();
    final response = await _dio.get<dynamic>(
      'https://pd.$cleanShard.a.pvp.net/mmr/v1/players/$puuid',
    );
    return _toMap(response.data);
  }

  Future<List<CompetitiveUpdate>> fetchCompetitiveUpdates(
    String shard,
    String puuid, {
    int startIndex = 0,
    int endIndex = 20,
  }) async {
    final data = await fetchCompetitiveUpdatesRaw(
      shard,
      puuid,
      startIndex: startIndex,
      endIndex: endIndex,
    );
    return _parseCompetitiveUpdates(data);
  }

  List<CompetitiveUpdate> parseCompetitiveUpdates(Map<String, dynamic> data) =>
      _parseCompetitiveUpdates(data);

  Future<Map<String, dynamic>> fetchCompetitiveUpdatesRaw(
    String shard,
    String puuid, {
    int startIndex = 0,
    int endIndex = 20,
  }) async {
    final cleanShard = shard.toLowerCase();
    final response = await _dio.get<dynamic>(
      'https://pd.$cleanShard.a.pvp.net/mmr/v1/players/$puuid/competitiveupdates',
      queryParameters: {
        'startIndex': startIndex,
        'endIndex': endIndex,
      },
    );
    return _toMap(response.data);
  }

  List<CompetitiveUpdate> _parseCompetitiveUpdates(Map<String, dynamic> data) {
    final matches = (data['Matches'] as List<dynamic>?) ?? [];
    final list = matches
        .whereType<Map>()
        .map((e) => CompetitiveUpdate.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    for (final update in list) {
      final mapId = update.mapId;
      if (update.matchId.isNotEmpty && mapId != null && mapId.isNotEmpty) {
        CacheStorage.instance.saveMatchMap(update.matchId, mapId);
      }
    }

    return list;
  }
}

