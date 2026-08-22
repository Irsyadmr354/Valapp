import 'package:dio/dio.dart';
import '../../../core/network/api_response_decoder.dart';
import '../../../core/utils/app_logger.dart';
import '../../../shared/constants/valorant_constants.dart';
import '../domain/models/account_health.dart';

class RestrictionsRemoteSource {
  const RestrictionsRemoteSource(this._dio);
  final Dio _dio;

  Future<AccountHealth> fetchAccountHealth(String shard, String puuid) async {
    final pdBase = RiotEndpoints.pd(shard);
    bool hasErrors = false;

    // Fetch penalties, avoid list, and activeFutureInterventions concurrently
    final responses = await Future.wait([
      _fetchMap('$pdBase/restrictions/v3/penalties', () => hasErrors = true),
      _fetchMap('$pdBase/restrictions/v1/avoidList', () => hasErrors = true),
      _fetchMap('$pdBase/restrictions/v1/activeFutureInterventions',
          () => hasErrors = true),
    ]);

    return AccountHealth.fromJson(
      penaltiesJson: responses[0],
      avoidListJson: responses[1],
      interventionsJson: responses[2],
      hasFetchErrors: hasErrors,
    );
  }

  /// EH-07: decodes a single endpoint, logging (and preserving) its error
  /// identity instead of collapsing all failures into one boolean.
  Future<Map<String, dynamic>> _fetchMap(
    String url,
    void Function() onError,
  ) async {
    try {
      final r = await _dio.get<dynamic>(url);
      return ApiResponseDecoder.decodeMap(r.data, source: url);
    } catch (e) {
      AppLogger.warn('Restrictions endpoint failed: $url ($e)');
      onError();
      return <String, dynamic>{};
    }
  }
}
