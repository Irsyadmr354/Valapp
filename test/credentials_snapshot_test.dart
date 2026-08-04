import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:valorant_app/core/storage/secure_storage.dart';
import 'package:valorant_app/features/auth/data/credentials_local_source.dart';
import 'package:valorant_app/features/auth/domain/models/credentials.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final local = CredentialsLocalSource(SecureStorage.instance);

  final creds = Credentials(
    accessToken: _jwt({'sub': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'}),
    idToken: _jwt({'sub': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'}),
    entitlementToken: 'ent-1',
    puuid: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    region: 'ap',
    shard: 'ap',
    expiresAt: _d('2026-08-05T12:00:00.000Z'),
    entitlementExpiresAt: _d('2026-08-05T13:00:00.000Z'),
  );

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('CredentialsLocalSource atomic snapshot', () {
    test('save writes a single atomically-readable snapshot blob', () async {
      await local.save(creds);

      final snapshot =
          await SecureStorage.instance.read(SecureStorage.keyActiveSession);
      expect(snapshot, isNotNull);
      // Snapshot is a single JSON document containing all fields.
      expect(snapshot, contains(creds.accessToken));
      expect(snapshot, contains('ent-1'));
      expect(snapshot, contains(creds.puuid));
      expect(snapshot, contains(creds.region));
    });

    test('load prefers the snapshot over the mirror keys', () async {
      await local.save(creds);

      // Simulate the mirror keys drifting (e.g. torn write after the
      // snapshot was written) — load() must still return the snapshot.
      await SecureStorage.instance
          .write(SecureStorage.keyAccessToken, 'stale-access');

      final loaded = await local.load();
      expect(loaded, isNotNull);
      expect(loaded!.accessToken, creds.accessToken);
      expect(loaded.puuid, creds.puuid);
    });

    test('load falls back to mirror keys when no snapshot exists', () async {
      // Pre-snapshot install: only individual keys present.
      await SecureStorage.instance
          .write(SecureStorage.keyAccessToken, creds.accessToken);
      await SecureStorage.instance
          .write(SecureStorage.keyIdToken, creds.idToken);
      await SecureStorage.instance
          .write(SecureStorage.keyEntitlementToken, 'legacy-ent');
      await SecureStorage.instance.write(SecureStorage.keyPuuid, creds.puuid);
      await SecureStorage.instance.write(SecureStorage.keyRegion, 'ap');
      await SecureStorage.instance.write(SecureStorage.keyShard, 'ap');
      await SecureStorage.instance
          .write(SecureStorage.keyExpiresAt, creds.expiresAt.toIso8601String());
      await SecureStorage.instance.write(
        SecureStorage.keyEntitlementExpiresAt,
        creds.entitlementExpiresAt.toIso8601String(),
      );

      final loaded = await local.load();
      expect(loaded, isNotNull);
      expect(loaded!.accessToken, creds.accessToken);
    });

    test('load returns null when neither snapshot nor keys exist', () async {
      expect(await local.load(), isNull);
    });

    test('load rejects malformed or incomplete snapshots', () async {
      await SecureStorage.instance.write(
        SecureStorage.keyActiveSession,
        '{"accessToken":"token","region":"unknown"}',
      );

      expect(await local.load(), isNull);
    });

    test('saved accounts skip malformed profiles', () async {
      await local.save(creds, displayName: 'Valid Player');
      final storage = SecureStorage.instance;
      final raw = await storage.read('valapp_saved_accounts_v1');
      final profiles = jsonDecode(raw!) as List<dynamic>;
      profiles.add({'puuid': '', 'displayName': '', 'region': 'unknown'});
      await storage.write('valapp_saved_accounts_v1', jsonEncode(profiles));

      final loaded = await local.getSavedAccounts();
      expect(loaded, hasLength(1));
      expect(loaded.single.displayName, 'Valid Player');
    });

    test('clearActiveSessionOnly removes the snapshot too', () async {
      await local.save(creds);
      await local.clearActiveSessionOnly();

      expect(await SecureStorage.instance.read(SecureStorage.keyActiveSession),
          isNull);
      expect(await local.load(), isNull);
    });

    test('saveIfCurrent cannot overwrite an account switch', () async {
      await local.save(creds);
      final switched = creds.copyWith(
        accessToken: _jwt({'sub': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'}),
        idToken: _jwt({'sub': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'}),
        puuid: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      );
      await local.save(switched);

      final refreshedA = creds.copyWith(
        accessToken: _jwt({'sub': creds.puuid, 'refresh': true}),
      );
      expect(await local.saveIfCurrent(creds, refreshedA), isFalse);
      expect((await local.load())?.puuid, switched.puuid);
      expect((await local.load())?.accessToken, switched.accessToken);
    });
  });
}

DateTime _d(String iso) => DateTime.parse(iso);

String _jwt(Map<String, dynamic> payload) {
  String part(Object value) =>
      base64UrlEncode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part(payload)}.signature';
}
