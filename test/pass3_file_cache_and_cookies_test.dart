import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:valorant_app/core/storage/cache_storage.dart';
import 'package:valorant_app/features/auth/domain/auth_repository.dart';
import 'package:valorant_app/features/match/data/match_local_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthRepository.mergeSetCookieHeaders', () {
    test('extracts name=value pairs and drops attributes', () {
      final merged = AuthRepository.mergeSetCookieHeaders([
        'ssid=abc123; Path=/; HttpOnly; Secure; SameSite=None',
        'clid=xyz789; Domain=.riotgames.com; Max-Age=31536000',
        'not-a-cookie-segment',
      ]);
      expect(merged.split('; ').toSet(), {'ssid=abc123', 'clid=xyz789'});
    });

    test('deduplicates repeated cookies across headers', () {
      final merged = AuthRepository.mergeSetCookieHeaders([
        'ssid=same; Path=/',
        'tdid=t1; Path=/',
        'ssid=same; Secure',
      ]);
      expect(merged.split('; ').toSet(), {'ssid=same', 'tdid=t1'});
    });
  });

  group('MatchDetailLocalCache (file-backed)', () {
    late Directory tmp;
    late CacheStorage storage;
    late MatchDetailLocalCache cache;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tmp = await Directory.systemTemp.createTemp('valapp_matchcache_test');
      storage = CacheStorage.instance;
      await storage.clearAll();
      await storage.setActiveSession('account-a');
      cache = MatchDetailLocalCache(storage, baseDirResolver: () async => tmp);
    });

    tearDown(() async {
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    });

    File fileFor(String puuid, String matchId) => File(
        '${tmp.path}${Platform.pathSeparator}match_details${Platform.pathSeparator}$puuid${Platform.pathSeparator}$matchId.json');

    test('saves to per-account files and loads them back', () async {
      final tx = storage.beginUserTransaction('account-a')!;
      await cache.saveMatchDetail('m-1', {'owner': 'A'},
          puuid: 'account-a', transaction: tx);

      expect(fileFor('account-a', 'm-1').existsSync(), isTrue,
          reason: 'detail must be persisted as its own JSON file');
      expect(await cache.loadMatchDetailRaw('m-1', puuid: 'account-a'),
          {'owner': 'A'});
    });

    test('stale transactions never reach disk', () async {
      final stale = storage.beginUserTransaction('account-a')!;
      await storage.setActiveSession('account-b');
      await storage.setActiveSession('account-a');

      await cache.saveMatchDetail('m-stale', {'stale': true},
          puuid: 'account-a', transaction: stale);

      expect(fileFor('account-a', 'm-stale').existsSync(), isFalse);
      expect(
          await cache.loadMatchDetailRaw('m-stale', puuid: 'account-a'), isNull);
    });

    test('evicts oldest files beyond maxEntries', () async {
      final tx = storage.beginUserTransaction('account-a')!;
      for (var i = 0; i < 33; i++) {
        await cache.saveMatchDetail('m-$i', {'i': i},
            puuid: 'account-a', transaction: tx);
      }
      final dir = Directory(
          '${tmp.path}${Platform.pathSeparator}match_details${Platform.pathSeparator}account-a');
      var jsonCount = 0;
      await for (final e in dir.list()) {
        if (e is File && e.path.endsWith('.json')) jsonCount++;
      }
      expect(jsonCount, lessThanOrEqualTo(30));
      // Newest entry survives eviction.
      expect(await cache.loadMatchDetailRaw('m-32', puuid: 'account-a'),
          {'i': 32});
    });

    test('purgeAccount removes file tree for that account only', () async {
      final txA = storage.beginUserTransaction('account-a')!;
      await storage.setActiveSession('account-b');
      final txB = storage.beginUserTransaction('account-b')!;

      await cache.saveMatchDetail('shared-1', {'a': 1},
          puuid: 'account-a', transaction: txA);
      await cache.saveMatchDetail('shared-1', {'b': 2},
          puuid: 'account-b', transaction: txB);

      await cache.purgeAccount('account-a');

      expect(fileFor('account-a', 'shared-1').existsSync(), isFalse);
      expect(await cache.loadMatchDetailRaw('shared-1', puuid: 'account-a'),
          isNull);
      expect(await cache.loadMatchDetailRaw('shared-1', puuid: 'account-b'),
          {'b': 2});
    });
  });
}
