import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:valorant_app/core/storage/cache_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const puuidA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const puuidB = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

  final cache = CacheStorage.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await cache.setActiveSession(puuidA);
  });

  group('CacheStorage session isolation', () {
    test('userKeyFor namespaces keys deterministically per puuid', () {
      final keyA = CacheStorage.userKeyFor(CacheStorage.keyMmrCache, puuidA);
      final keyB = CacheStorage.userKeyFor(CacheStorage.keyMmrCache, puuidB);

      expect(keyA, isNot(keyB));
      expect(keyA, contains(puuidA));
      expect(keyB, contains(puuidB));
      expect(keyA, endsWith('/${CacheStorage.keyMmrCache}'));
    });

    test('userKeyFor uses the complete puuid and fails closed when empty', () {
      const sharedPrefixA = 'aaaaaaaa-user-a';
      const sharedPrefixB = 'aaaaaaaa-user-b';

      expect(
        CacheStorage.userKeyFor('key', sharedPrefixA),
        isNot(CacheStorage.userKeyFor('key', sharedPrefixB)),
      );
      expect(() => CacheStorage.userKeyFor('key', ''), throwsArgumentError);
    });

    test('isActiveSession reflects the current session', () async {
      expect(cache.isActiveSession(puuidA), isTrue);
      expect(cache.isActiveSession(puuidB), isFalse);

      await cache.setActiveSession(puuidB);
      expect(cache.isActiveSession(puuidB), isTrue);
      expect(cache.isActiveSession(puuidA), isFalse);
    });

    test('data written for one account is never read by another', () async {
      await cache.setJson(CacheStorage.userKeyFor('keyX', puuidA), {'v': 'A'});
      await cache.setJson(CacheStorage.userKeyFor('keyX', puuidB), {'v': 'B'});

      expect(await cache.getJson(CacheStorage.userKeyFor('keyX', puuidA)),
          {'v': 'A'});
      expect(await cache.getJson(CacheStorage.userKeyFor('keyX', puuidB)),
          {'v': 'B'});
    });

    test('clearUserCache clears the active session namespace', () async {
      await cache.setJson(
          CacheStorage.userKeyFor(CacheStorage.keyMmrCache, puuidA), {'v': 1});
      await cache.setJson(
          CacheStorage.userKeyFor(CacheStorage.keyMmrCache, puuidB), {'v': 2});

      await cache.clearUserCache();

      // Active session (A) namespace is wiped; other account (B) untouched.
      expect(
          await cache.getJson(
              CacheStorage.userKeyFor(CacheStorage.keyMmrCache, puuidA)),
          isNull);
      expect(
          await cache.getJson(
              CacheStorage.userKeyFor(CacheStorage.keyMmrCache, puuidB)),
          {'v': 2});
    });

    test('clearAll clears the in-memory active session immediately', () async {
      await cache.clearAll();

      expect(cache.activePuuid, isEmpty);
      expect(cache.isActiveSession(puuidA), isFalse);
    });

    test('transaction from an earlier account activation is rejected',
        () async {
      final stale = cache.beginUserTransaction(puuidA);
      await cache.setActiveSession(puuidB);
      await cache.setActiveSession(puuidA);

      final committed = await cache.runUserTransaction(stale, () async {
        await cache.setJson(
            CacheStorage.userKeyFor('generation', puuidA), {'stale': true});
      });

      expect(committed, isFalse);
      expect(await cache.getJson(CacheStorage.userKeyFor('generation', puuidA)),
          isNull);
    });

    test('session transition clears previous account before writes resume',
        () async {
      await cache.setJson(
          CacheStorage.userKeyFor(CacheStorage.keyMmrCache, puuidA),
          {'account': 'A'});
      final stale = cache.beginUserTransaction(puuidA);

      await cache.setActiveSession(puuidB, clearPrevious: true);

      expect(
          await cache.getJson(
              CacheStorage.userKeyFor(CacheStorage.keyMmrCache, puuidA)),
          isNull);
      expect(await cache.runUserTransaction(stale, () async {}), isFalse);
      expect(cache.activePuuid, puuidB);
    });

    test('wishlist notification claim deduplicates per shop and account',
        () async {
      expect(
        await cache.claimWishlistNotification(
          puuid: puuidA,
          shopIdentity: 'offer-a,offer-b',
          skinId: 'offer-a',
        ),
        isTrue,
      );
      expect(
        await cache.claimWishlistNotification(
          puuid: puuidA,
          shopIdentity: 'offer-a,offer-b',
          skinId: 'offer-a',
        ),
        isFalse,
      );
      expect(
        await cache.claimWishlistNotification(
          puuid: puuidB,
          shopIdentity: 'offer-a,offer-b',
          skinId: 'offer-a',
        ),
        isTrue,
      );
      expect(
        await cache.claimWishlistNotification(
          puuid: puuidA,
          shopIdentity: 'offer-c,offer-d',
          skinId: 'offer-a',
        ),
        isTrue,
      );
    });
  });

  group('CacheStorage corrupt JSON eviction', () {
    test('removes malformed JSON objects after a failed read', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('broken-map', '{not-json');

      expect(await cache.getJson('broken-map'), isNull);
      expect(await cache.getString('broken-map'), isNull);
    });

    test('removes JSON with the wrong container shape', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('map-as-list', '[]');
      await prefs.setString('list-as-map', '{}');

      expect(await cache.getJson('map-as-list'), isNull);
      expect(await cache.getJsonList('list-as-map'), isNull);
      expect(await cache.getString('map-as-list'), isNull);
      expect(await cache.getString('list-as-map'), isNull);
    });
  });
}
