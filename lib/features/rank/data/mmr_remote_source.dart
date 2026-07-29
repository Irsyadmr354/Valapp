import 'package:dio/dio.dart';
import '../domain/models/player_mmr.dart';

class MmrRemoteSource {
  const MmrRemoteSource(this._dio);
  final Dio _dio;

  Future<PlayerMmr> fetchMmr(String shard, String puuid) async {
    final response = await _dio.get<Map<String, dynamic>>(
      'https://pd.$shard.a.pvp.net/mmr/v1/players/$puuid',
    );
    return PlayerMmr.fromJson(response.data ?? {});
  }

  Future<List<CompetitiveUpdate>> fetchCompetitiveUpdates(
    String shard,
    String puuid, {
    int startIndex = 0,
    int endIndex = 20,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      'https://pd.$shard.a.pvp.net/mmr/v1/players/$puuid/competitiveupdates',
      queryParameters: {
        'startIndex': startIndex,
        'endIndex': endIndex,
      },
    );
    final matches =
        (response.data?['Matches'] as List<dynamic>?) ?? [];
    return matches
        .map((e) =>
            CompetitiveUpdate.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
