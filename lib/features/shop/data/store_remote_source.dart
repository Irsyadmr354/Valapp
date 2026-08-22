import 'package:dio/dio.dart';
import '../../../core/network/api_response_decoder.dart';
import '../../../shared/constants/valorant_constants.dart';
import '../domain/models/wallet.dart';

class StoreRemoteSource {
  const StoreRemoteSource(this._dio);
  final Dio _dio;

  Future<Map<String, dynamic>> fetchStorefrontRaw(
      String shard, String puuid) async {
    final pdBase = RiotEndpoints.pd(shard);
    // Primary: storefront v3 (current endpoint confirmed from client telemetry)
    try {
      final response = await _dio.post<dynamic>(
        '$pdBase/store/v3/storefront/$puuid',
        data: {},
      );
      return _validateStorefront(response.data, 'storefront v3');
    } on DioException catch (e) {
      // Fallback to v2 ONLY when v3 is gone (404) or method not allowed (405).
      // Swallowing auth/rate-limit/network errors here would mask the root
      // cause and burn a second request against the same broken session.
      final status = e.response?.statusCode;
      if (status != 404 && status != 405) rethrow;
      final response = await _dio.post<dynamic>(
        '$pdBase/store/v2/storefront/$puuid',
        data: {},
      );
      return _validateStorefront(response.data, 'storefront v2');
    }
  }

  Future<Wallet> fetchWallet(String shard, String puuid) async {
    final url = '${RiotEndpoints.pd(shard)}/store/v1/wallet/$puuid';
    final response = await _dio.get<dynamic>(url);
    final data = ApiResponseDecoder.decodeMap(response.data, source: url);
    ApiResponseDecoder.requireShape(data, source: url, maps: ['Balances']);
    return Wallet.fromJson(data);
  }

  Map<String, dynamic> _validateStorefront(dynamic body, String source) {
    final data = ApiResponseDecoder.decodeMap(body, source: source);
    ApiResponseDecoder.requireShape(
      data,
      source: source,
      maps: ['SkinsPanelLayout'],
    );
    final panel = Map<String, dynamic>.from(data['SkinsPanelLayout'] as Map);
    ApiResponseDecoder.requireShape(
      panel,
      source: '$source SkinsPanelLayout',
      lists: ['SingleItemOffers'],
    );
    return data;
  }
}
