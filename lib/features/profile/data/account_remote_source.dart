import 'package:dio/dio.dart';
import '../../../core/network/api_response_decoder.dart';

class AccountRemoteSource {
  const AccountRemoteSource(this._dio);
  final Dio _dio;

  Future<Map<String, dynamic>> fetchAccountXpRaw(
      String shard, String puuid) async {
    final cleanShard = shard.toLowerCase();
    final url = 'https://pd.$cleanShard.a.pvp.net/account-xp/v1/players/$puuid';
    final response = await _dio.get<dynamic>(url);
    final data = ApiResponseDecoder.decodeMap(response.data, source: url);
    return ApiResponseDecoder.requireShape(
      data,
      source: url,
      maps: ['Progress'],
      lists: ['History'],
      strings: ['Subject'],
    );
  }

  /// Resolves display name via name-service, with Riot userinfo fallback.
  Future<String?> fetchDisplayName(
    String shard,
    String puuid, {
    String? accessToken,
  }) async {
    final names = await fetchDisplayNames(shard, [puuid]);
    final fromNameService = names[puuid];
    if (fromNameService != null && fromNameService.isNotEmpty) {
      return fromNameService;
    }

    if (accessToken != null && accessToken.isNotEmpty) {
      return _fetchDisplayNameFromUserInfo(accessToken);
    }
    return null;
  }

  Future<String?> _fetchDisplayNameFromUserInfo(String accessToken) async {
    try {
      final response = await _dio.get<dynamic>(
        'https://auth.riotgames.com/userinfo',
        options: Options(
          headers: {'Authorization': 'Bearer $accessToken'},
        ),
      );
      final data = response.data;
      if (data is! Map) return null;
      final gameName = data['acct'] is Map
          ? (data['acct'] as Map)['game_name']?.toString() ??
              (data['acct'] as Map)['gameName']?.toString()
          : null;
      final tagLine = data['acct'] is Map
          ? (data['acct'] as Map)['tag_line']?.toString() ??
              (data['acct'] as Map)['tagLine']?.toString()
          : null;
      if (gameName == null || gameName.isEmpty) return null;
      return (tagLine != null && tagLine.isNotEmpty)
          ? '$gameName#$tagLine'
          : gameName;
    } catch (_) {
      return null;
    }
  }

  /// Batch resolves display names via name-service for a list of PUUIDs.
  Future<Map<String, String>> fetchDisplayNames(
      String shard, List<String> puuids) async {
    if (puuids.isEmpty) return {};
    final cleanShard = shard.toLowerCase();
    try {
      dynamic data;
      try {
        final response = await _dio.put<dynamic>(
          'https://pd.$cleanShard.a.pvp.net/name-service/v2/players',
          data: puuids,
        );
        data = response.data;
      } on DioException catch (_) {
        final response = await _dio.post<dynamic>(
          'https://pd.$cleanShard.a.pvp.net/name-service/v3/players',
          data: puuids,
        );
        data = response.data;
      }
      final list = ApiResponseDecoder.decodeList(
        data,
        source: 'name-service players',
      );

      final result = <String, String>{};
      for (final entry in list) {
        if (entry is Map) {
          final subject =
              entry['Subject']?.toString() ?? entry['puuid']?.toString() ?? '';
          final gameName = entry['GameName']?.toString() ??
              entry['gameName']?.toString() ??
              '';
          final tagLine = entry['TagLine']?.toString() ??
              entry['tagLine']?.toString() ??
              '';
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
}
