import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:valorant_app/core/network/interceptors/valorant_interceptor.dart';
import 'package:valorant_app/core/storage/secure_storage.dart';
import 'package:valorant_app/features/auth/data/credentials_local_source.dart';
import 'package:valorant_app/features/auth/domain/models/credentials.dart';
import 'package:valorant_app/shared/utils/version_service.dart';

String _jwt(Map<String, dynamic> payload) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}.sig';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final storage = SecureStorage.instance;
  final local = CredentialsLocalSource(storage);

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  Future<Credentials> seedValidCredentials() async {
    final token = _jwt({
      'sub': '11112222333344445555666677778888',
      'exp': DateTime.now().add(const Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000,
    });
    final creds = Credentials(
      accessToken: token,
      idToken: token,
      entitlementToken: 'valid-entitlement',
      puuid: '11112222333344445555666677778888',
      region: 'ap',
      shard: 'ap',
      expiresAt: DateTime.now().add(const Duration(hours: 2)),
      entitlementExpiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
    await local.save(creds);
    return creds;
  }

  group('ValorantInterceptor HTTP 400 Heuristic Tests', () {
    test('400 with VALIDATION_ISSUE does NOT trigger reauth loop', () async {
      await seedValidCredentials();

      var reauthInvoked = false;
      var entitlementRefreshInvoked = false;

      final interceptor = ValorantInterceptor(
        secureStorage: storage,
        versionService: VersionService.instance,
        onRefreshEntitlement: () async {
          entitlementRefreshInvoked = true;
        },
        onReauth: () async {
          reauthInvoked = true;
        },
        onAuthFailed: () async {},
      );

      final dio = Dio()..interceptors.add(interceptor);
      dio.httpClientAdapter = _MockHttpAdapter((options) {
        return ResponseBody.fromString(
          jsonEncode({'errorCode': 'VALIDATION_ISSUE', 'message': 'Invalid query parameters'}),
          400,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      try {
        await dio.get<dynamic>('https://pd.ap.a.pvp.net/name-service/v2/players');
      } catch (_) {}

      expect(reauthInvoked, isFalse, reason: 'Validation error must not cause 15s reauth hang');
      expect(entitlementRefreshInvoked, isFalse);
    });

    test('400 with INVALID_ARGUMENT does NOT trigger reauth loop', () async {
      await seedValidCredentials();

      var reauthInvoked = false;

      final interceptor = ValorantInterceptor(
        secureStorage: storage,
        versionService: VersionService.instance,
        onRefreshEntitlement: () async {},
        onReauth: () async {
          reauthInvoked = true;
        },
        onAuthFailed: () async {},
      );

      final dio = Dio()..interceptors.add(interceptor);
      dio.httpClientAdapter = _MockHttpAdapter((options) {
        return ResponseBody.fromString(
          jsonEncode({'errorCode': 'INVALID_ARGUMENT', 'message': 'Bad argument'}),
          400,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      try {
        await dio.get<dynamic>('https://pd.ap.a.pvp.net/match-details/v1/matches/invalid-uuid');
      } catch (_) {}

      expect(reauthInvoked, isFalse);
    });

    test('400 with BAD_CLAIMS on game endpoint triggers fast entitlement refresh', () async {
      await seedValidCredentials();

      var entitlementRefreshInvoked = false;

      final interceptor = ValorantInterceptor(
        secureStorage: storage,
        versionService: VersionService.instance,
        onRefreshEntitlement: () async {
          entitlementRefreshInvoked = true;
        },
        onReauth: () async {},
        onAuthFailed: () async {},
      );

      final dio = Dio()..interceptors.add(interceptor);
      dio.httpClientAdapter = _MockHttpAdapter((options) {
        return ResponseBody.fromString(
          jsonEncode({'errorCode': 'BAD_CLAIMS', 'message': 'Token claims expired'}),
          400,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      try {
        await dio.post<dynamic>('https://pd.ap.a.pvp.net/store/v3/storefront/11112222333344445555666677778888');
      } catch (_) {}

      expect(entitlementRefreshInvoked, isTrue, reason: 'BAD_CLAIMS 400 must trigger fast entitlement renewal');
    });

    test('401 Unauthorized triggers reauth', () async {
      await seedValidCredentials();

      var reauthInvoked = false;

      final interceptor = ValorantInterceptor(
        secureStorage: storage,
        versionService: VersionService.instance,
        onRefreshEntitlement: () async {},
        onReauth: () async {
          reauthInvoked = true;
        },
        onAuthFailed: () async {},
      );

      final dio = Dio()..interceptors.add(interceptor);
      dio.httpClientAdapter = _MockHttpAdapter((options) {
        return ResponseBody.fromString(
          jsonEncode({'error': 'unauthorized'}),
          401,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      try {
        await dio.get<dynamic>('https://pd.ap.a.pvp.net/store/v1/wallet/11112222333344445555666677778888');
      } catch (_) {}

      expect(reauthInvoked, isTrue);
    });
  });
}

class _MockHttpAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions options) handler;
  _MockHttpAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}