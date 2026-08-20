import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:valorant_app/core/storage/cache_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const puuidA = 'aaaaaaaa-1111-1111-1111-aaaaaaaaaaaa';
  const puuidB = 'bbbbbbbb-2222-2222-2222-bbbbbbbbbbbb';

  final cache = CacheStorage.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await cache.clearAll();
    await cache.setActiveSession(puuidA);
  });

  group('CacheStorage Wishlist Isolation & Migration', () {
    test('isolates wishlist per account puuid', () async {
      await cache.addToWishlist('skin-1', puuidA);
      await cache.addToWishlist('skin-2', puuidA);

      await cache.addToWishlist('skin-3', puuidB);

      final wishlistA = await cache.getWishlist(puuidA);
      final wishlistB = await cache.getWishlist(puuidB);

      expect(wishlistA, ['skin-1', 'skin-2']);
      expect(wishlistB, ['skin-3']);
    });

    test('removes from wishlist strictly for target account', () async {
      await cache.addToWishlist('skin-common', puuidA);
      await cache.addToWishlist('skin-common', puuidB);

      await cache.removeFromWishlist('skin-common', puuidA);

      expect(await cache.getWishlist(puuidA), isEmpty);
      expect(await cache.getWishlist(puuidB), ['skin-common']);
    });

    test('migrates legacy un-namespaced wishlist to active user on first read',
        () async {
      await cache.clearAll();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
          CacheStorage.keyWishlist, ['legacy-skin-1', 'legacy-skin-2']);
      await cache.setActiveSession(puuidA);

      // Read for puuidA when its namespaced key is empty
      final listA = await cache.getWishlist(puuidA);
      expect(listA, ['legacy-skin-1', 'legacy-skin-2']);

      final namespacedKey = CacheStorage.wishlistKeyFor(puuidA);
      expect(prefs.getStringList(namespacedKey),
          ['legacy-skin-1', 'legacy-skin-2']);
    });
  });
}
