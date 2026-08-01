import 'dart:convert';
import 'package:dio/dio.dart';
import '../domain/models/player_loadout.dart';

class LoadoutRemoteSource {
  const LoadoutRemoteSource(this._dio);
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

  Future<PlayerLoadout> fetchLoadout(String shard, String puuid) async {
    return PlayerLoadout.fromJson(await fetchLoadoutRaw(shard, puuid));
  }

  Future<Map<String, dynamic>> fetchLoadoutRaw(
      String shard, String puuid) async {
    final cleanShard = shard.toLowerCase();
    // Riot's personalization endpoint returns the active loadout
    // v3 is the current endpoint as confirmed from ShooterGame.log
    final response = await _dio.get<dynamic>(
      'https://pd.$cleanShard.a.pvp.net/personalization/v3/players/$puuid/playerloadout',
    );
    return _toMap(response.data);
  }
}
