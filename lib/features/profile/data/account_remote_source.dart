import 'dart:convert';
import 'package:dio/dio.dart';
import '../domain/models/account_xp.dart';

class AccountRemoteSource {
  const AccountRemoteSource(this._dio);
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

  Future<AccountXp> fetchAccountXp(String shard, String puuid) async {
    final response = await _dio.get<dynamic>(
      'https://pd.$shard.a.pvp.net/account-xp/v1/players/$puuid',
    );
    return AccountXp.fromJson(_toMap(response.data));
  }

  /// Resolves display name via name-service.
  Future<String?> fetchDisplayName(String shard, String puuid) async {
    final names = await fetchDisplayNames(shard, [puuid]);
    return names[puuid];
  }

  /// Batch resolves display names via name-service for a list of PUUIDs.
  Future<Map<String, String>> fetchDisplayNames(
      String shard, List<String> puuids) async {
    if (puuids.isEmpty) return {};
    try {
      final response = await _dio.put<dynamic>(
        'https://pd.$shard.a.pvp.net/name-service/v2/players',
        data: puuids,
      );

      dynamic data = response.data;
      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (_) {}
      }

      List<dynamic> list = [];
      if (data is List) {
        list = data;
      } else if (data is Map) {
        list = data.values.toList();
      }

      final result = <String, String>{};
      for (final entry in list) {
        if (entry is Map) {
          final subject = entry['Subject']?.toString() ?? entry['puuid']?.toString() ?? '';
          final gameName = entry['GameName']?.toString() ?? entry['gameName']?.toString() ?? '';
          final tagLine = entry['TagLine']?.toString() ?? entry['tagLine']?.toString() ?? '';
          final displayName = entry['DisplayName']?.toString() ?? '';

          String finalName = '';
          if (gameName.isNotEmpty) {
            finalName = tagLine.isNotEmpty ? '$gameName#$tagLine' : gameName;
          } else if (displayName.isNotEmpty) {
            finalName = displayName;
          }

          if (subject.isNotEmpty && finalName.isNotEmpty) {
            result[subject] = finalName;
          }
        }
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  /// Returns owned item UUIDs for a given item type.
  Future<List<String>> fetchOwnedItems(
      String shard, String puuid, String itemTypeId) async {
    final response = await _dio.get<dynamic>(
      'https://pd.$shard.a.pvp.net/store/v1/entitlements/$puuid/$itemTypeId',
    );
    final data = _toMap(response.data);
    final entitlements = (data['Entitlements'] as List<dynamic>?) ?? [];
    return entitlements
        .whereType<Map>()
        .map((e) => e['ItemID']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
  }
}

