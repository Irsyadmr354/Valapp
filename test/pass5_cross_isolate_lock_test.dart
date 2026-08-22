import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:valorant_app/core/storage/cache_storage.dart';
import 'package:valorant_app/core/utils/cross_isolate_lock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('valapp_xilock_test');
    CrossIsolateLock.overrideBaseDir(() async => tmp);
  });

  tearDownAll(() async {
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
    // Reset override so other suites are unaffected.
    CrossIsolateLock.overrideBaseDir(() async => null);
  });

  group('CrossIsolateLock', () {
    test('serialises concurrent critical sections on the same key', () async {
      var inCritical = 0;
      var maxConcurrent = 0;
      final futures = List.generate(6, (i) {
        return CrossIsolateLock.run('counter', () async {
          inCritical++;
          maxConcurrent =
              inCritical > maxConcurrent ? inCritical : maxConcurrent;
          await Future<void>.delayed(const Duration(milliseconds: 15));
          inCritical--;
        });
      });
      await Future.wait(futures);
      expect(maxConcurrent, 1,
          reason: 'no two critical sections may overlap');
    });

    test('different keys do not block each other', () async {
      final sw = Stopwatch()..start();
      await Future.wait([
        CrossIsolateLock.run(
            'k1',
            () => Future<void>.delayed(const Duration(milliseconds: 60))),
        CrossIsolateLock.run(
            'k2',
            () => Future<void>.delayed(const Duration(milliseconds: 60))),
      ]);
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(110),
          reason: 'independent keys must run in parallel');
    });

    test('lock file is released after completion and after error',
        () async {
      await CrossIsolateLock.run<int>(
          'release-ok', () async => Future<int>.value(1));
      await expectLater(
        CrossIsolateLock.run<int>('release-err', () async => throw StateError('x')),
        throwsStateError,
      );

      final locksDir = Directory('${tmp.path}${Platform.pathSeparator}locks');
      final leftovers = <String>[];
      if (await locksDir.exists()) {
        await for (final e in locksDir.list()) {
          leftovers.add(e.path);
        }
      }
      expect(leftovers, isEmpty,
          reason: 'released locks must not leave files behind');
    });
  });

  group('Wishlist notification claim ledger (cross-isolate guarded)', () {
    final cache = CacheStorage.instance;
    const puuid = 'cccccccc-3333-3333-3333-cccccccccccc';

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await cache.clearAll();
      await cache.setActiveSession(puuid);
    });

    test('concurrent claims for one skin succeed exactly once', () async {
      const identity = 'id1,id2,id3,id4';
      final results = await Future.wait(List.generate(5, (_) {
        return cache.claimWishlistNotification(
          puuid: puuid,
          shopIdentity: identity,
          skinId: 'skin-x',
        );
      }));
      expect(results.where((r) => r), hasLength(1),
          reason: 'only the first concurrent claim wins');
    });

    test('rollback frees the slot so it can be claimed again', () async {
      const identity = 'id1,id2,id3,id4';
      expect(
        await cache.claimWishlistNotification(
            puuid: puuid, shopIdentity: identity, skinId: 'skin-y'),
        isTrue,
      );
      await cache.rollbackWishlistNotificationClaim(
          puuid: puuid, shopIdentity: identity, skinId: 'skin-y');
      expect(
        await cache.claimWishlistNotification(
            puuid: puuid, shopIdentity: identity, skinId: 'skin-y'),
        isTrue,
      );
    });
  });
}
