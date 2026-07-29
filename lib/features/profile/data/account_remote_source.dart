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

  /// Resolves display name via name-service.
  /// Riot's name-service returns a List, not a Map — handle both.
  Future<String?> fetchDisplayName(String shard, String puuid) async {
    try {
      final response = await _dio.put<dynamic>(
        'https://pd.$shard.a.pvp.net/name-service/v2/players',
        data: [puuid],
      );

      final data = response.data;
      List<dynamic> list = [];

      if (data is List) {
        list = data;
      } else if (data is Map) {
        // Some regions return a Map keyed by puuid
        list = data.values.toList();
      }

      if (list.isEmpty) return null;

      final entry = list.first;
      if (entry is Map) {
        final gameName = entry['GameName']?.toString() ?? '';
        final tagLine = entry['TagLine']?.toString() ?? '';
        if (gameName.isNotEmpty) {
          return tagLine.isNotEmpty ? '$gameName#$tagLine' : gameName;
        }
        return entry['DisplayName']?.toString();
      }
      return null;
    } catch (_) {
      return null;
    }
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
        .map((e) => e['ItemID']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
  }
}
