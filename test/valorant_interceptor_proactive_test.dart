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

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test(
      'proactive reauth prefers fast onRefreshEntitlement when accessToken is valid',
      () async {
    final validToken = _jwt({
      'sub': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'exp':
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
              1000,
    });

    // Valid accessToken, expired entitlementToken
    final creds = Credentials(
      accessToken: validToken,
      idToken: validToken,
      entitlementToken: 'stale-entitlement-token',
      puuid: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      region: 'ap',
      shard: 'ap',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      entitlementExpiresAt:
          DateTime.now().subtract(const Duration(minutes: 10)),
    );
    await local.save(creds);

    var entitlementRefreshCalled = false;
    var fullReauthCalled = false;

    final interceptor = ValorantInterceptor(
      secureStorage: storage,
      versionService: VersionService.instance,
      onRefreshEntitlement: () async {
        entitlementRefreshCalled = true;
        // Update credentials with renewed entitlement
        final updated = creds.copyWith(
          entitlementToken: 'fresh-entitlement-token',
          entitlementExpiresAt: DateTime.now().add(const Duration(minutes: 55)),
        );
        await local.save(updated);
      },
      onReauth: () async {
        fullReauthCalled = true;
      },
      onAuthFailed: () async {},
    );

    final dio = Dio()..httpClientAdapter = _MockAdapter();
    dio.interceptors.add(interceptor);

    await dio.get<dynamic>(
        'https://pd.ap.a.pvp.net/store/v3/storefront/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');

    expect(entitlementRefreshCalled, isTrue,
        reason: 'Fast entitlement refresh should have been called');
    expect(fullReauthCalled, isFalse,
        reason:
            'Full reauth (WebView) should NOT be called when access token is valid');
  });

  test('proactive reauth invokes onReauth when accessToken is expired',
      () async {
    final expiredToken = _jwt({
      'sub': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'exp': DateTime.now()
              .subtract(const Duration(minutes: 10))
              .millisecondsSinceEpoch ~/
          1000,
    });
    final freshToken = _jwt({
      'sub': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'exp':
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
              1000,
    });

    // Expired accessToken
    final creds = Credentials(
      accessToken: expiredToken,
      idToken: expiredToken,
      entitlementToken: 'expired-entitlement-token',
      puuid: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      region: 'ap',
      shard: 'ap',
      expiresAt: DateTime.now().subtract(const Duration(minutes: 10)),
      entitlementExpiresAt:
          DateTime.now().subtract(const Duration(minutes: 10)),
    );
    await local.save(creds);

    var entitlementRefreshCalled = false;
    var fullReauthCalled = false;

    final interceptor = ValorantInterceptor(
      secureStorage: storage,
      versionService: VersionService.instance,
      onRefreshEntitlement: () async {
        entitlementRefreshCalled = true;
      },
      onReauth: () async {
        fullReauthCalled = true;
        final updated = creds.copyWith(
          accessToken: freshToken,
          idToken: freshToken,
          entitlementToken: 'fresh-entitlement-token',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          entitlementExpiresAt: DateTime.now().add(const Duration(minutes: 55)),
        );
        await local.save(updated);
      },
      onAuthFailed: () async {},
    );

    final dio = Dio()..httpClientAdapter = _MockAdapter();
    dio.interceptors.add(interceptor);

    await dio.get<dynamic>(
        'https://pd.ap.a.pvp.net/store/v3/storefront/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');

    expect(fullReauthCalled, isTrue,
        reason: 'Full reauth should be called when access token is expired');
    expect(entitlementRefreshCalled, isFalse,
        reason:
            'Entitlement-only refresh cannot proceed without valid access token');
  });
}

class _MockAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode({'status': 'ok'}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
