import 'package:dio/dio.dart';
import '../../../core/network/api_response_decoder.dart';
import '../../../shared/constants/valorant_constants.dart';

class ContractsRemoteSource {
  const ContractsRemoteSource(this._dio);
  final Dio _dio;

  Future<Map<String, dynamic>> fetchContractsRaw(
      String shard, String puuid) async {
    final url = '${RiotEndpoints.pd(shard)}/contracts/v1/contracts/$puuid';
    final response = await _dio.get<dynamic>(url);
    final data = ApiResponseDecoder.decodeMap(response.data, source: url);
    return ApiResponseDecoder.requireShape(
      data,
      source: url,
      lists: ['Contracts', 'Missions'],
    );
  }
}
