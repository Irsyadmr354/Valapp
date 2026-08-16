import 'package:dio/dio.dart';
import '../../../core/network/api_response_decoder.dart';
import '../../../shared/constants/valorant_constants.dart';

class LoadoutRemoteSource {
  const LoadoutRemoteSource(this._dio);
  final Dio _dio;

  Future<Map<String, dynamic>> fetchLoadoutRaw(
      String shard, String puuid) async {
    // Riot's personalization endpoint returns the active loadout
    // v3 is the current endpoint as confirmed from ShooterGame.log
    final url =
        '${RiotEndpoints.pd(shard)}/personalization/v3/players/$puuid/playerloadout';
    final response = await _dio.get<dynamic>(url);
    final data = ApiResponseDecoder.decodeMap(response.data, source: url);
    final root = data['Loadout'] is Map
        ? Map<String, dynamic>.from(data['Loadout'] as Map)
        : data;
    ApiResponseDecoder.requireShape(
      root,
      source: url,
      lists: ['Guns'],
      strings: ['Subject'],
    );
    return data;
  }
}
