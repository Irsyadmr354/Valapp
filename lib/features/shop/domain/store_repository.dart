import '../data/store_local_cache.dart';
import '../data/store_remote_source.dart';
import '../domain/models/storefront.dart';
import '../domain/models/wallet.dart';
import '../../../shared/utils/valorant_assets.dart';

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
    final raw = await _remote.fetchStorefrontRaw(shard, puuid);

    await _cache.saveStorefront(raw);

    final storefront = Storefront.fromJson(raw);
    return _enrichStorefront(storefront);
  }

  /// Returns cached storefront (if available) with enriched metadata.
  Future<Storefront?> loadCachedStorefront() async {
    final raw = await _cache.loadStorefrontRaw();
    if (raw == null) return null;
    final storefront = Storefront.fromJson(raw);
    return _enrichStorefront(storefront);
  }

  /// Enriches daily skin offers, Featured Bundle, and Night Market with metadata from valorant-api.
  Future<Storefront> _enrichStorefront(Storefront storefront) async {
    final skinMap = await _assets.getSkinLevelsMap();
    final bundleMap = await _assets.getBundlesMap();

    // Enrich daily offers
    final enrichedOffers = storefront.dailyOffers.map((offer) {
      final meta = skinMap[offer.skinLevelUuid] as Map<String, dynamic>?;
      return offer.copyWith(
        displayName: meta?['skinName'] as String?,
        displayIcon: meta?['displayIcon'] as String?,
        contentTierUuid: meta?['contentTierUuid'] as String?,
      );
    }).toList();

    // Enrich Featured Bundle
    FeaturedBundle? enrichedBundle = storefront.featuredBundle;
    if (enrichedBundle != null) {
      final bundleMeta =
          bundleMap[enrichedBundle.bundleUuid] as Map<String, dynamic>? ??
          bundleMap[enrichedBundle.bundleUuid.toLowerCase()] as Map<String, dynamic>?;

      String? bundleName = bundleMeta?['displayName'] as String?;
      String? bundleIcon = bundleMeta?['displayIcon'] as String?;
      String? promoImage = bundleMeta?['verticalPromoImage'] as String? ??
          bundleMeta?['displayIcon2'] as String?;

      // Fallback: if promo/icon is missing from valorant-api bundles, fetch icon from first item skin in bundle
      if ((promoImage == null || promoImage.isEmpty) &&
          (bundleIcon == null || bundleIcon.isEmpty) &&
          enrichedBundle.itemIds.isNotEmpty) {
        for (final itemId in enrichedBundle.itemIds) {
          final skinMeta = skinMap[itemId] as Map<String, dynamic>? ??
              skinMap[itemId.toLowerCase()] as Map<String, dynamic>?;
          if (skinMeta != null) {
            bundleName ??= skinMeta['skinName'] as String?;
            bundleIcon ??= skinMeta['displayIcon'] as String?;
            if (bundleIcon != null && bundleIcon.isNotEmpty) break;
          }
        }
      }

      enrichedBundle = enrichedBundle.copyWith(
        displayName: bundleName,
        displayIcon: bundleIcon,
        verticalPromoImage: promoImage,
      );
    }

    // Enrich Night Market
    final enrichedNightMarket = storefront.nightMarket.map((nm) {
      final meta = skinMap[nm.skinLevelUuid] as Map<String, dynamic>?;
      return nm.copyWith(
        skinName: meta?['skinName'] as String?,
        skinIcon: meta?['displayIcon'] as String?,
        contentTierUuid: meta?['contentTierUuid'] as String?,
      );
    }).toList();

    return Storefront(
      dailyOffers: enrichedOffers,
      dailyOffersRemainingSeconds: storefront.dailyOffersRemainingSeconds,
      featuredBundle: enrichedBundle,
      nightMarket: enrichedNightMarket,
      accessoryStore: storefront.accessoryStore,
      fetchedAt: storefront.fetchedAt,
    );
  }


  Future<Wallet> fetchWallet(String shard, String puuid) async {
    final wallet = await _remote.fetchWallet(shard, puuid);
    await _cache.saveWallet(wallet);
    return wallet;
  }

  Future<Wallet?> loadCachedWallet() => _cache.loadWallet();

  Future<DateTime?> lastShopFetch() => _cache.lastShopFetch();
}
