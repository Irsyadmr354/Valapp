import 'package:dio/dio.dart';
import '../domain/models/wallet.dart';

class StoreRemoteSource {
  const StoreRemoteSource(this._dio);
  final Dio _dio;

  Future<Map<String, dynamic>> fetchStorefrontRaw(
      String shard, String puuid) async {
    // Try v2 first, fall back to v3 if 404
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'https://pd.$shard.a.pvp.net/store/v2/storefront/$puuid',
      );
      return response.data ?? {};
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        // Some regions use v3
        final response = await _dio.get<Map<String, dynamic>>(
          'https://pd.$shard.a.pvp.net/store/v3/storefront/$puuid',
        );
        return response.data ?? {};
      }
      rethrow;
    }
  }

  Future<Map<String, int>> fetchPrices(String shard) async {
    final response = await _dio.get<Map<String, dynamic>>(
      'https://pd.$shard.a.pvp.net/store/v1/offers/',
    );
    final offers =
        (response.data?['Offers'] as List<dynamic>?) ?? [];

    final map = <String, int>{};
    for (final offer in offers) {
      final id = offer['OfferID'] as String?;
      final costs = offer['Cost'] as Map<String, dynamic>?;
      if (id != null && costs != null) {
        // VP currency ID
        final vp = (costs['85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741'] as num?)
            ?.toInt();
        if (vp != null) map[id] = vp;
      }
    }
    return map;
  }

  Future<Wallet> fetchWallet(String shard, String puuid) async {
    final response = await _dio.get<Map<String, dynamic>>(
      'https://pd.$shard.a.pvp.net/store/v1/wallet/$puuid',
    );
    return Wallet.fromJson(response.data ?? {});
  }
}
