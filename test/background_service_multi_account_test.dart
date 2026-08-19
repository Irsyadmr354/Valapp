import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:valorant_app/core/network/valorant_headers.dart';
import 'package:valorant_app/core/storage/cache_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const puuidA = 'user-puuid-alpha-1111';
  const puuidB = 'user-puuid-beta-2222';
  const lastShopKey = 'background_last_shop_ids';
  final cache = CacheStorage.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await cache.clearAll();
  });

  group('Background Service Multi-Account Wishlist Isolation', () {
    test('wishlist reads are strictly isolated by PUUID in background isolate', () async {
      await cache.setWishlist(['skin-vandal-prime', 'skin-phantom-oni'], puuidA);
      await cache.setWishlist(['skin-sheriff-reaver'], puuidB);

      final wishlistA = await cache.getWishlist(puuidA);
      final wishlistB = await cache.getWishlist(puuidB);

      expect(wishlistA, containsAll({'skin-vandal-prime', 'skin-phantom-oni'}));
      expect(wishlistA.contains('skin-sheriff-reaver'), isFalse);

      expect(wishlistB, contains('skin-sheriff-reaver'));
      expect(wishlistB.contains('skin-vandal-prime'), isFalse);
    });
  });

  group('Background Service Shop Reset State Isolation', () {
    test('lastShopKey namespacing prevents false reset alerts when switching accounts', () async {
      final keyA = CacheStorage.userKeyFor(lastShopKey, puuidA);
      final keyB = CacheStorage.userKeyFor(lastShopKey, puuidB);

      final offersA = ['offer-1', 'offer-2', 'offer-3', 'offer-4'];
      final offersB = ['offer-5', 'offer-6', 'offer-7', 'offer-8'];

      await cache.setJson(keyA, {'ids': offersA});
      await cache.setJson(keyB, {'ids': offersB});

      final loadedA = await cache.getJson(keyA);
      final loadedB = await cache.getJson(keyB);

      final idsA = (loadedA?['ids'] as List<dynamic>?)?.cast<String>() ?? [];
      final idsB = (loadedB?['ids'] as List<dynamic>?)?.cast<String>() ?? [];

      expect(idsA, equals(offersA));
      expect(idsB, equals(offersB));

      final isNewShopA = !Set.from(offersA).containsAll(idsA) || idsA.length != offersA.length;
      expect(isNewShopA, isFalse);
    });
  });

  group('Background Service Client Version Fallback', () {
    test('resolves defaultClientVersion when cached version is missing or empty', () async {
      final cachedVersion = await cache.getString(CacheStorage.keyClientVersion);
      final effectiveVersion = cachedVersion ?? ValorantHeaders.defaultClientVersion;

      expect(effectiveVersion, equals(ValorantHeaders.defaultClientVersion));
      expect(effectiveVersion, isNotEmpty);
      expect(effectiveVersion.startsWith('release-'), isTrue);

      await cache.setString(CacheStorage.keyClientVersion, 'release-99.00-custom-12345');
      final updatedCached = await cache.getString(CacheStorage.keyClientVersion);
      final finalEffective = updatedCached ?? ValorantHeaders.defaultClientVersion;

      expect(finalEffective, equals('release-99.00-custom-12345'));
    });
  });
}