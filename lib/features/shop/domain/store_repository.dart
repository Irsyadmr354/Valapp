import '../data/store_local_cache.dart';
import '../data/store_remote_source.dart';
import '../domain/models/storefront.dart';
import '../domain/models/wallet.dart';
import '../../../shared/utils/valorant_assets.dart';
import '../../../core/storage/cache_storage.dart';

class StoreRepository {
  const StoreRepository({
    required StoreRemoteSource remoteSource,
    required StoreLocalCache localCache,
    required ValorantAssets assets,
  })  : _remote = remoteSource,
        _cache = localCache,
        _assets = assets;

  final StoreRemoteSource _remote;
  final StoreLocalCache _cache;
  final ValorantAssets _assets;

  /// Fetches fresh storefront data, enriches skin metadata, and caches it.
  Future<Storefront> fetchStorefront(String shard, String puuid) async {
    final transaction = CacheStorage.instance.beginUserTransaction(puuid);
    if (transaction == null) {
      throw StateError('Storefront request started outside the active session');
    }
    final raw = await _remote.fetchStorefrontRaw(shard, puuid);

    // Stamp the fetch time into the raw map before caching so that
    // fromJson can use the real fetch time (not parse time) for the
    // remainingSeconds calculation when loading from cache.
    raw['_fetchedAt'] = DateTime.now().toIso8601String();
    final storefront = Storefront.fromJson(raw);
    await _cache.saveStorefront(raw, puuid: puuid, transaction: transaction);

    return _enrichStorefront(storefront);
  }

  /// Returns cached storefront (if available) with enriched metadata.
  Future<Storefront?> loadCachedStorefront(String puuid,
      {bool allowExpired = true}) async {
    final raw = await _cache.loadStorefrontRaw(
        puuid: puuid, allowExpired: allowExpired);
    if (raw == null) return null;
    final storefront = Storefront.fromJson(raw);
    return _enrichStorefront(storefront);
  }

  /// Enriches daily skin offers, Featured Bundles, and Night Market with metadata from valorant-api.
  Future<Storefront> _enrichStorefront(Storefront storefront) async {
    var skinMap = await _assets
        .getSkinLevelsMap()
        .catchError((_) => <String, dynamic>{});
    var bundleMap = await _assets
        .getBundlesMap()
        .catchError((_) => <String, dynamic>{});

    // Check if any daily skin offer is missing from the cache.
    // If so, force-refresh skin metadata from valorant-api to handle newly released skins.
    final hasUnknownDailySkin = storefront.dailyOffers.any((offer) =>
        !skinMap.containsKey(offer.skinLevelUuid) &&
        !skinMap.containsKey(offer.skinLevelUuid.toLowerCase()));
    if (hasUnknownDailySkin) {
      skinMap = await _assets
          .getSkinLevelsMap(forceRefresh: true)
          .catchError((_) => skinMap);
    }

    // Check if any active featured bundle is missing from the bundle metadata cache.
    // If so, force-refresh bundle metadata from valorant-api to handle newly released bundles.
    final hasUnknownBundle = storefront.featuredBundles.any((b) =>
        b.bundleUuid.isNotEmpty &&
        !bundleMap.containsKey(b.bundleUuid) &&
        !bundleMap.containsKey(b.bundleUuid.toLowerCase()) &&
        !bundleMap.containsKey(b.bundleUuid.replaceAll('-', '').toLowerCase()));
    if (hasUnknownBundle) {
      bundleMap = await _assets
          .getBundlesMap(forceRefresh: true)
          .catchError((_) => bundleMap);
    }

    // Enrich daily offers
    final enrichedOffers = storefront.dailyOffers.map((offer) {
      final meta = skinMap[offer.skinLevelUuid] as Map<String, dynamic>? ??
          skinMap[offer.skinLevelUuid.toLowerCase()] as Map<String, dynamic>?;
      return offer.copyWith(
        displayName: meta?['skinName'] as String?,
        displayIcon: meta?['displayIcon'] as String?,
        contentTierUuid: meta?['contentTierUuid'] as String?,
      );
    }).toList();

    // Check if any bundle needs unified store items map (buddies, cards, sprays, etc.)
    Map<String, dynamic>? unifiedMap;
    final needsItemFallback = storefront.featuredBundles.any((b) {
      final meta = bundleMap[b.bundleUuid] ??
          bundleMap[b.bundleUuid.toLowerCase()] ??
          bundleMap[b.bundleUuid.replaceAll('-', '').toLowerCase()];
      return meta == null || (meta['verticalPromoImage'] == null && meta['displayIcon2'] == null && meta['displayIcon'] == null);
    });
    if (needsItemFallback) {
      unifiedMap = await _assets
          .getAllStoreItemsMap()
          .catchError((_) => <String, dynamic>{});
    }

    // Enrich all Featured Bundles
    final enrichedBundles = storefront.featuredBundles.map((bundle) {
      final bundleMeta = (bundleMap[bundle.bundleUuid] as Map<String, dynamic>?) ??
          (bundleMap[bundle.bundleUuid.toLowerCase()] as Map<String, dynamic>?) ??
          (bundleMap[bundle.bundleUuid.replaceAll('-', '').toLowerCase()] as Map<String, dynamic>?);

      String? bundleName = bundleMeta?['displayName'] as String?;
      String? bundleIcon = bundleMeta?['displayIcon'] as String?;
      String? promoImage = bundleMeta?['verticalPromoImage'] as String? ??
          bundleMeta?['displayIcon2'] as String?;

      // Fallback: if promo/icon or name is missing from valorant-api bundles, fetch from items in bundle
      if ((promoImage == null || promoImage.isEmpty || bundleName == null || bundleName.isEmpty) &&
          bundle.itemIds.isNotEmpty) {
        final itemLookup = unifiedMap ?? skinMap;
        for (final itemId in bundle.itemIds) {
          final itemMeta = itemLookup[itemId] as Map<String, dynamic>? ??
              itemLookup[itemId.toLowerCase()] as Map<String, dynamic>? ??
              itemLookup[itemId.replaceAll('-', '').toLowerCase()] as Map<String, dynamic>?;
          if (itemMeta != null) {
            bundleName ??= (itemMeta['skinName'] as String?) ??
                (itemMeta['displayName'] as String?);
            bundleIcon ??= itemMeta['displayIcon'] as String?;
            promoImage ??= (itemMeta['wallpaper'] as String?) ??
                (itemMeta['displayIcon'] as String?);
            if (bundleIcon != null && bundleIcon.isNotEmpty) break;
          }
        }
      }

      return bundle.copyWith(
        displayName: bundleName,
        displayIcon: bundleIcon,
        verticalPromoImage: promoImage,
      );
    }).toList();

    // Enrich Night Market
    final enrichedNightMarket = storefront.nightMarket.map((nm) {
      final meta = skinMap[nm.skinLevelUuid] as Map<String, dynamic>? ??
          skinMap[nm.skinLevelUuid.toLowerCase()] as Map<String, dynamic>?;
      return nm.copyWith(
        skinName: meta?['skinName'] as String?,
        skinIcon: meta?['displayIcon'] as String?,
        contentTierUuid: meta?['contentTierUuid'] as String?,
      );
    }).toList();

    return Storefront(
      dailyOffers: enrichedOffers,
      dailyOffersRemainingSeconds: storefront.dailyOffersRemainingSeconds,
      featuredBundles: enrichedBundles,
      nightMarket: enrichedNightMarket,
      accessoryStore: storefront.accessoryStore,
      fetchedAt: storefront.fetchedAt,
    );
  }

  Future<Wallet> fetchWallet(String shard, String puuid) async {
    final transaction = CacheStorage.instance.beginUserTransaction(puuid);
    if (transaction == null) {
      throw StateError('Wallet request started outside the active session');
    }
    final wallet = await _remote.fetchWallet(shard, puuid);
    await _cache.saveWallet(wallet, puuid: puuid, transaction: transaction);
    return wallet;
  }

  Future<Wallet?> loadCachedWallet(String puuid) =>
      _cache.loadWallet(puuid: puuid);

  Future<DateTime?> lastShopFetch(String puuid) =>
      _cache.lastShopFetch(puuid: puuid);
}
