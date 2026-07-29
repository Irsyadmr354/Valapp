import 'dart:convert';
import 'package:dio/dio.dart';
import '../domain/models/contracts.dart';

class ContractsRemoteSource {
  const ContractsRemoteSource(this._dio);
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

  Future<PlayerContracts> fetchContracts(
      String shard, String puuid) async {
    final cleanShard = shard.toLowerCase();
    final response = await _dio.get<dynamic>(
      'https://pd.$cleanShard.a.pvp.net/contracts/v1/contracts/$puuid',
    );
    return PlayerContracts.fromJson(_toMap(response.data));
  }
}

