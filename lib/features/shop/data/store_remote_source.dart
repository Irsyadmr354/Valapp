import 'dart:convert';
import 'package:dio/dio.dart';
import '../domain/models/wallet.dart';

class StoreRemoteSource {
  const StoreRemoteSource(this._dio);
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

  Future<Map<String, dynamic>> fetchStorefrontRaw(
      String shard, String puuid) async {
    // Storefront v3 is the primary endpoint used by official Riot client (POST with {})
    try {
      final response = await _dio.post<dynamic>(
        'https://pd.$shard.a.pvp.net/store/v3/storefront/$puuid',
        data: {},
      );
      return _toMap(response.data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404 ||
          e.response?.statusCode == 405 ||
          e.response?.statusCode == 400) {
        // Fall back to v2 if v3 fails
        final response = await _dio.post<dynamic>(
          'https://pd.$shard.a.pvp.net/store/v2/storefront/$puuid',
          data: {},
        );
        return _toMap(response.data);
      }
      rethrow;
    }
  }

  Future<Map<String, int>> fetchPrices(String shard) async {
    final response = await _dio.get<dynamic>(
      'https://pd.$shard.a.pvp.net/store/v1/offers/',
    );
    final data = _toMap(response.data);
    final offers = (data['Offers'] as List<dynamic>?) ?? [];

    final map = <String, int>{};
    for (final offer in offers) {
      if (offer is Map) {
        final id = offer['OfferID'] as String?;
        final costs = offer['Cost'] as Map<String, dynamic>?;
        if (id != null && costs != null) {
          final vp = (costs[ValorantCurrency.vpUuid] as num?)?.toInt();
          if (vp != null) map[id] = vp;
        }
      }
    }
    return map;
  }

  Future<Wallet> fetchWallet(String shard, String puuid) async {
    final response = await _dio.get<dynamic>(
      'https://pd.$shard.a.pvp.net/store/v1/wallet/$puuid',
    );
    return Wallet.fromJson(_toMap(response.data));
  }
}

