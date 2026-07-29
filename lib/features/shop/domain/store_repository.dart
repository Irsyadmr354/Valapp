import 'package:flutter/foundation.dart';
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
      debugPrint('── REPO BUNDLE ENRICH ──');
      debugPrint('  bundleUuid: ${enrichedBundle.bundleUuid}');
      debugPrint('  bundleMap has key? ${bundleMap.containsKey(enrichedBundle.bundleUuid)}');
      debugPrint('  bundleMap has key (lc)? ${bundleMap.containsKey(enrichedBundle.bundleUuid.toLowerCase())}');
      final bundleMeta =
          bundleMap[enrichedBundle.bundleUuid] as Map<String, dynamic>? ??
          bundleMap[enrichedBundle.bundleUuid.toLowerCase()] as Map<String, dynamic>?;
      if (bundleMeta != null) {
        debugPrint('  bundleMeta displayName: ${bundleMeta['displayName']}');
        debugPrint('  bundleMeta displayIcon: ${bundleMeta['displayIcon']}');
        debugPrint('  bundleMeta displayIcon2: ${bundleMeta['displayIcon2']}');
        debugPrint('  bundleMeta verticalPromo: ${bundleMeta['verticalPromoImage']}');
        enrichedBundle = enrichedBundle.copyWith(
          displayName: bundleMeta['displayName'] as String?,
          displayIcon: bundleMeta['displayIcon'] as String?,
          verticalPromoImage:
              bundleMeta['verticalPromoImage'] as String? ?? bundleMeta['displayIcon2'] as String?,
        );
      } else {
        debugPrint('  ⚠️ bundleMeta is NULL — UUID not found in valorant-api.com bundles!');
        // Print first 5 keys for comparison
        final keys = bundleMap.keys.take(5).toList();
        debugPrint('  First 5 bundleMap keys: $keys');
      }
      debugPrint('── END REPO BUNDLE ENRICH ──');
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
