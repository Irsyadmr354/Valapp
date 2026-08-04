import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/storage/cache_storage.dart';
import '../../../core/utils/async_lock.dart';

final wishlistProvider =
    StateNotifierProvider<WishlistNotifier, List<String>>((ref) {
  return WishlistNotifier();
});

class WishlistNotifier extends StateNotifier<List<String>> {
  WishlistNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    await AsyncLock.run('wishlist_toggle', () async {
      final list = await CacheStorage.instance.getWishlist();
      if (mounted) state = list;
    });
  }

  /// Serialised via AsyncLock so rapid taps cannot interleave reads and
  /// produce a stale-state overwrite (e.g. double-tap toggling a skin twice
  /// would otherwise result in no net change due to both seeing the same
  /// initial state).
  Future<void> toggle(String skinId) async {
    await AsyncLock.run('wishlist_toggle', () async {
      // Re-read canonical state from disk to survive any race
      final current = await CacheStorage.instance.getWishlist();
      if (current.contains(skinId)) {
        await CacheStorage.instance.removeFromWishlist(skinId);
        if (mounted) state = current.where((id) => id != skinId).toList();
      } else {
        await CacheStorage.instance.addToWishlist(skinId);
        if (mounted) state = [...current, skinId];
      }
    });
  }
}
