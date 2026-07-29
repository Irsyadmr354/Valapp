import 'package:dio/dio.dart';
import '../domain/models/account_xp.dart';

class AccountRemoteSource {
  const AccountRemoteSource(this._dio);
  final Dio _dio;

  Future<AccountXp> fetchAccountXp(String shard, String puuid) async {
    final response = await _dio.get<Map<String, dynamic>>(
      'https://pd.$shard.a.pvp.net/account-xp/v1/players/$puuid',
    );
    return AccountXp.fromJson(response.data ?? {});
  }

  /// Resolves display name for a PUUID.
  Future<String?> fetchDisplayName(String shard, String puuid) async {
    final response = await _dio.put<List<dynamic>>(
      'https://pd.$shard.a.pvp.net/name-service/v2/players',
      data: [puuid],
    );
    final list = response.data ?? [];
    if (list.isEmpty) return null;
    return list.first['DisplayName'] as String?;
  }

  /// Returns owned item UUIDs for a given item type.
  Future<List<String>> fetchOwnedItems(
      String shard, String puuid, String itemTypeId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      'https://pd.$shard.a.pvp.net/store/v1/entitlements/$puuid/$itemTypeId',
    );
    final entitlements =
        (response.data?['Entitlements'] as List<dynamic>?) ?? [];
    return entitlements
        .map((e) => e['ItemID'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
  }
}
