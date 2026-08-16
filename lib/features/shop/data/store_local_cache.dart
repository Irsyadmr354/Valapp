import '../../../core/storage/cache_storage.dart';
import '../domain/models/wallet.dart';

/// Caches storefront and wallet data locally.
class StoreLocalCache {
  final CacheStorage _cache;
  const StoreLocalCache(this._cache);

  // ── Storefront ─────────────────────────────────────────────────────────────

  Future<void> saveStorefront(Map<String, dynamic> raw,
      {required String puuid, required CacheTransaction transaction}) async {
    await _cache.runUserTransaction(transaction, () async {
      await _cache.setJson(
          CacheStorage.userKeyFor(CacheStorage.keyDailyShop, puuid), raw);
      await _cache.setTimestamp(
          CacheStorage.userKeyFor(CacheStorage.keyDailyShopFetchedAt, puuid));
    });
  }

  Future<Map<String, dynamic>?> loadStorefrontRaw(
      {required String puuid}) async {
    final raw = await _cache
        .getJson(CacheStorage.userKeyFor(CacheStorage.keyDailyShop, puuid));
    if (raw == null) return null;

    // Check if the cached storefront has already passed its reset time.
    // If so, return null so the caller is forced to fetch fresh data from
    // the network rather than showing an expired shop.
    final fetchedAtStr = raw['_fetchedAt'] as String?;
    final remainingSec = ((raw['SkinsPanelLayout']
                as Map?)?['SingleItemOffersRemainingDurationInSeconds'] as num?)
            ?.toInt() ??
        0;
    if (fetchedAtStr == null || remainingSec <= 0) {
      await _evictStorefront(puuid);
      return null;
    }
    final fetchedAt = DateTime.tryParse(fetchedAtStr);
    if (fetchedAt == null) {
      await _evictStorefront(puuid);
      return null;
    }
    final elapsed = DateTime.now().difference(fetchedAt).inSeconds;
    if (elapsed >= remainingSec) {
      await _evictStorefront(puuid);
      return null;
    }

    return raw;
  }

  Future<DateTime?> lastShopFetch({required String puuid}) async {
    final ts = await _cache.getString(
        CacheStorage.userKeyFor(CacheStorage.keyDailyShopFetchedAt, puuid));
    if (ts == null) return null;
    return DateTime.tryParse(ts);
  }

  // ── Wallet ─────────────────────────────────────────────────────────────────

  Future<void> saveWallet(Wallet wallet,
      {required String puuid, required CacheTransaction transaction}) async {
    await _cache.runUserTransaction(transaction, () async {
      await _cache.setJson(
          CacheStorage.userKeyFor(CacheStorage.keyWalletCache, puuid),
          wallet.toJson());
    });
  }

  Future<Wallet?> loadWallet({required String puuid}) async {
    final data = await _cache
        .getJson(CacheStorage.userKeyFor(CacheStorage.keyWalletCache, puuid));
    if (data == null) return null;
    return Wallet(
      valorantPoints: (data['vp'] as num?)?.toInt() ?? 0,
      radianitePoints: (data['rp'] as num?)?.toInt() ?? 0,
      kingdomCredits: (data['kc'] as num?)?.toInt() ?? 0,
      freeAgentCurrency: (data['fa'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> clearStorefront({required String puuid}) async {
    await _cache
        .remove(CacheStorage.userKeyFor(CacheStorage.keyDailyShop, puuid));
    await _cache.remove(
        CacheStorage.userKeyFor(CacheStorage.keyDailyShopFetchedAt, puuid));
  }

  Future<void> _evictStorefront(String puuid) => clearStorefront(puuid: puuid);
}
