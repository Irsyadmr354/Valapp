import 'package:dio/dio.dart';
import '../domain/models/contracts.dart';

class ContractsRemoteSource {
  const ContractsRemoteSource(this._dio);
  final Dio _dio;

  Future<PlayerContracts> fetchContracts(
      String shard, String puuid) async {
    final response = await _dio.get<Map<String, dynamic>>(
      'https://pd.$shard.a.pvp.net/contracts/v1/contracts/$puuid',
    );
    return PlayerContracts.fromJson(response.data ?? {});
  }
}
