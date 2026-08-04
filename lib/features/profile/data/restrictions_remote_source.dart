import 'package:dio/dio.dart';
import '../../../core/network/api_response_decoder.dart';
import '../domain/models/account_health.dart';

class RestrictionsRemoteSource {
  const RestrictionsRemoteSource(this._dio);
  final Dio _dio;

  Future<AccountHealth> fetchAccountHealth(String shard, String puuid) async {
    final cleanShard = shard.toLowerCase();

    bool hasErrors = false;

    // Fetch penalties, avoid list, and activeFutureInterventions concurrently
    final responses = await Future.wait([
      _dio
          .get<dynamic>(
            'https://pd.$cleanShard.a.pvp.net/restrictions/v3/penalties',
          )
          .then((r) => ApiResponseDecoder.decodeMap(r.data,
              source: 'restrictions/v3/penalties'))
          .catchError((_) {
        hasErrors = true;
        return <String, dynamic>{};
      }),
      _dio
          .get<dynamic>(
            'https://pd.$cleanShard.a.pvp.net/restrictions/v1/avoidList',
          )
          .then((r) => ApiResponseDecoder.decodeMap(r.data,
              source: 'restrictions/v1/avoidList'))
          .catchError((_) {
        hasErrors = true;
        return <String, dynamic>{};
      }),
      _dio
          .get<dynamic>(
            'https://pd.$cleanShard.a.pvp.net/restrictions/v1/activeFutureInterventions',
          )
          .then((r) => ApiResponseDecoder.decodeMap(r.data,
              source: 'restrictions/v1/activeFutureInterventions'))
          .catchError((_) {
        hasErrors = true;
        return <String, dynamic>{};
      }),
    ]);

    return AccountHealth.fromJson(
      penaltiesJson: responses[0],
      avoidListJson: responses[1],
      interventionsJson: responses[2],
      hasFetchErrors: hasErrors,
    );
  }
}
