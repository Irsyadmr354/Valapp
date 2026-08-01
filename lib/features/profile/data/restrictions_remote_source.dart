import 'dart:convert';
import 'package:dio/dio.dart';
import '../domain/models/account_health.dart';

class RestrictionsRemoteSource {
  const RestrictionsRemoteSource(this._dio);
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

  Future<AccountHealth> fetchAccountHealth(String shard, String puuid) async {
    final cleanShard = shard.toLowerCase();

    // Fetch penalties & avoid list concurrently
    final responses = await Future.wait([
      _dio
          .get<dynamic>(
            'https://pd.$cleanShard.a.pvp.net/restrictions/v3/penalties',
          )
          .then((r) => _toMap(r.data))
          .catchError((_) => <String, dynamic>{}),
      _dio
          .get<dynamic>(
            'https://pd.$cleanShard.a.pvp.net/restrictions/v1/avoidList',
          )
          .then((r) => _toMap(r.data))
          .catchError((_) => <String, dynamic>{}),
    ]);

    return AccountHealth.fromJson(
      penaltiesJson: responses[0],
      avoidListJson: responses[1],
    );
  }
}
