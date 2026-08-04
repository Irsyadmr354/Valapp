import 'package:dio/dio.dart';
import '../../../core/network/api_response_decoder.dart';
import '../domain/models/wallet.dart';

class StoreRemoteSource {
  const StoreRemoteSource(this._dio);
  final Dio _dio;

  Future<Map<String, dynamic>> fetchStorefrontRaw(
      String shard, String puuid) async {
    // Storefront v3 is the primary endpoint used by official Riot client (POST with {})
    try {
      final response = await _dio.post<dynamic>(
        'https://pd.$shard.a.pvp.net/store/v3/storefront/$puuid',
        data: {},
      );
      return _validateStorefront(response.data, 'storefront v3');
    } on DioException catch (e) {
      if (e.response?.statusCode == 404 || e.response?.statusCode == 405) {
        final response = await _dio.post<dynamic>(
          'https://pd.$shard.a.pvp.net/store/v2/storefront/$puuid',
          data: {},
        );
        return _validateStorefront(response.data, 'storefront v2');
      }
      rethrow;
    }
  }

  Future<Map<String, int>> fetchPrices(String shard) async {
    final url = 'https://pd.$shard.a.pvp.net/store/v1/offers/';
    final response = await _dio.get<dynamic>(url);
    final data = ApiResponseDecoder.decodeMap(response.data, source: url);
    ApiResponseDecoder.requireShape(data, source: url, lists: ['Offers']);
    final offers = data['Offers'] as List<dynamic>;

    final map = <String, int>{};
    for (final offer in offers) {
      if (offer is Map) {
        final id = offer['OfferID'] as String?;
        final rawCosts = offer['Cost'];
        final costs =
            rawCosts is Map ? Map<String, dynamic>.from(rawCosts) : null;
        if (id != null && costs != null) {
          final vp = (costs[ValorantCurrency.vpUuid] as num?)?.toInt();
          if (vp != null) map[id] = vp;
        }
      }
    }
    return map;
  }

  Future<Wallet> fetchWallet(String shard, String puuid) async {
    final url = 'https://pd.$shard.a.pvp.net/store/v1/wallet/$puuid';
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
