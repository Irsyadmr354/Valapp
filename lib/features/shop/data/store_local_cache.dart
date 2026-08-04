import '../../../core/storage/cache_storage.dart';
import '../domain/models/wallet.dart';

/// Caches storefront and wallet data locally.
class StoreLocalCache {
  final CacheStorage _cache;
  const StoreLocalCache(this._cache);

  // ── Storefront ─────────────────────────────────────────────────────────────

  Future<void> saveStorefront(Map<String, dynamic> raw) async {
    await _cache.setJson(CacheStorage.keyDailyShop, raw);
    await _cache.setTimestamp(CacheStorage.keyDailyShopFetchedAt);
  }

  Future<Map<String, dynamic>?> loadStorefrontRaw() async {
    final raw = await _cache.getJson(CacheStorage.keyDailyShop);
    if (raw == null) return null;

    // Check if the cached storefront has already passed its reset time.
    // If so, return null so the caller is forced to fetch fresh data from
    // the network rather than showing an expired shop.
    final fetchedAtStr = raw['_fetchedAt'] as String?;
    final remainingSec =
        ((raw['SkinsPanelLayout'] as Map?)?
                ['SingleItemOffersRemainingDurationInSeconds'] as num?)
            ?.toInt() ??
        0;
    if (fetchedAtStr != null && remainingSec > 0) {
      final fetchedAt = DateTime.tryParse(fetchedAtStr);
      if (fetchedAt != null) {
        final elapsed = DateTime.now().difference(fetchedAt).inSeconds;
        if (elapsed >= remainingSec) {
          // Cache is from a previous shop rotation — discard it.
          return null;
        }
      }
    }

    return raw;
  }

  Future<DateTime?> lastShopFetch() async {
    final ts = await _cache.getString(CacheStorage.keyDailyShopFetchedAt);
    if (ts == null) return null;
    return DateTime.tryParse(ts);
  }

  // ── Wallet ─────────────────────────────────────────────────────────────────

  Future<void> saveWallet(Wallet wallet) =>
      _cache.setJson('cached_wallet', wallet.toJson());

  Future<Wallet?> loadWallet() async {
    final data = await _cache.getJson('cached_wallet');
    if (data == null) return null;
    return Wallet(
      valorantPoints: (data['vp'] as num?)?.toInt() ?? 0,
      radianitePoints: (data['rp'] as num?)?.toInt() ?? 0,
      kingdomCredits: (data['kc'] as num?)?.toInt() ?? 0,
      freeAgentCurrency: (data['fa'] as num?)?.toInt() ?? 0,
    );
  }
}
