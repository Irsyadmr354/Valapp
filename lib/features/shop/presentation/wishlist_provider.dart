import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/storage/cache_storage.dart';

final wishlistProvider =
    StateNotifierProvider<WishlistNotifier, List<String>>((ref) {
  return WishlistNotifier();
});

class WishlistNotifier extends StateNotifier<List<String>> {
  WishlistNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    final list = await CacheStorage.instance.getWishlist();
    state = list;
  }

  Future<void> toggle(String skinId) async {
    if (state.contains(skinId)) {
      await CacheStorage.instance.removeFromWishlist(skinId);
      state = state.where((id) => id != skinId).toList();
    } else {
      await CacheStorage.instance.addToWishlist(skinId);
      state = [...state, skinId];
    }
  }

  bool isWishlisted(String skinId) => state.contains(skinId);
}
