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

  Future<Map<String, dynamic>?> loadStorefrontRaw() =>
      _cache.getJson(CacheStorage.keyDailyShop);

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
