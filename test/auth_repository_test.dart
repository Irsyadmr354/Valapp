import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:valorant_app/core/storage/secure_storage.dart';
import 'package:valorant_app/features/auth/data/auth_remote_source.dart';
import 'package:valorant_app/features/auth/data/credentials_local_source.dart';
import 'package:valorant_app/features/auth/domain/auth_repository.dart';
import 'package:valorant_app/features/auth/domain/models/credentials.dart';
import 'package:dio/dio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final secure = SecureStorage.instance;
  final local = CredentialsLocalSource(secure);

  final testCreds = Credentials(
    accessToken: _mockJwt({'sub': 'test-puuid-123'}),
    idToken: _mockJwt({'sub': 'test-puuid-123'}),
    entitlementToken: 'mock-entitlement',
    puuid: 'test-puuid-123',
    region: 'ap',
    shard: 'ap',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    entitlementExpiresAt: DateTime.now().add(const Duration(hours: 1)),
  );

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('AuthRepository', () {
    test('saveSessionCookies sanitizes and persists Riot session cookies',
        () async {
      final repo = AuthRepository(
        remoteSource: AuthRemoteSource(Dio(), Dio()),
        localSource: local,
      );

      const rawCookies =
          'ssid=abc12345; clid=def67890; other_tracking=ignored; csid=xyz999';

      await repo.saveSessionCookies('test-puuid-123', rawCookies);

      final saved =
          await secure.read(SecureStorage.keyRiotCookiesFor('test-puuid-123'));
      expect(saved, isNotNull);
      expect(saved, contains('ssid=abc12345'));
      expect(saved, contains('clid=def67890'));
      expect(saved, contains('csid=xyz999'));
      expect(saved, isNot(contains('other_tracking=ignored')));
    });

    test('ensureValidSession returns active creds when not expired', () async {
      await local.save(testCreds);
      final repo = AuthRepository(
        remoteSource: AuthRemoteSource(Dio(), Dio()),
        localSource: local,
      );

      final valid = await repo.ensureValidSession();
      expect(valid, isNotNull);
      expect(valid!.puuid, 'test-puuid-123');
    });

    test('logout clears credentials from storage', () async {
      await local.save(testCreds);
      final repo = AuthRepository(
        remoteSource: AuthRemoteSource(Dio(), Dio()),
        localSource: local,
      );

      await repo.logout();
      final loaded = await local.load();
      expect(loaded, isNull);
    });
  });
}

String _mockJwt(Map<String, dynamic> claims) {
  final header =
      base64Url.encode(utf8.encode(jsonEncode({'alg': 'none', 'typ': 'JWT'})));
  final payload = base64Url.encode(utf8.encode(jsonEncode(claims)));
  return '$header.$payload.signature';
}
