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
    var unifiedMap = await _assets
        .getAllStoreItemsMap()
        .catchError((_) => <String, dynamic>{});
    if (unifiedMap.isEmpty) {
      unifiedMap = await _assets
          .getAllStoreItemsMap(forceRefresh: true)
          .catchError((_) => <String, dynamic>{});
    }

    var bundleMap = await _assets
        .getBundlesMap()
        .catchError((_) => <String, dynamic>{});

    final skinMap = unifiedMap;

    // Check if any active featured bundle or any of its items are missing from metadata cache.
    final hasUnknownBundle = storefront.featuredBundles.any((b) =>
        b.bundleUuid.isNotEmpty &&
        !bundleMap.containsKey(b.bundleUuid) &&
        !bundleMap.containsKey(b.bundleUuid.toLowerCase()) &&
        !bundleMap.containsKey(b.bundleUuid.replaceAll('-', '').toLowerCase()));

    final hasUnknownItems = storefront.featuredBundles.any((b) =>
        b.itemIds.isNotEmpty &&
        b.itemIds.any((id) =>
            !unifiedMap.containsKey(id) &&
            !unifiedMap.containsKey(id.toLowerCase()) &&
            !unifiedMap.containsKey(id.replaceAll('-', '').toLowerCase())));

    if (hasUnknownBundle || hasUnknownItems) {
      bundleMap = await _assets
          .getBundlesMap(forceRefresh: true)
          .catchError((_) => bundleMap);
      unifiedMap = await _assets
          .getAllStoreItemsMap(forceRefresh: true)
          .catchError((_) => unifiedMap);
    }

    // Enrich daily offers
    final enrichedOffers = storefront.dailyOffers.map((offer) {
      final meta = skinMap[offer.skinLevelUuid] as Map<String, dynamic>? ??
          skinMap[offer.skinLevelUuid.toLowerCase()] as Map<String, dynamic>? ??
          skinMap[offer.skinLevelUuid.replaceAll('-', '').toLowerCase()]
              as Map<String, dynamic>?;
      return offer.copyWith(
        displayName: (meta?['skinName'] as String?) ??
            (meta?['displayName'] as String?),
        displayIcon: meta?['displayIcon'] as String?,
        contentTierUuid: meta?['contentTierUuid'] as String?,
      );
    }).toList();

    // Enrich all Featured Bundles
    final enrichedBundles = storefront.featuredBundles.map((bundle) {
      final bundleMeta =
          (bundleMap[bundle.bundleUuid] as Map<String, dynamic>?) ??
              (bundleMap[bundle.bundleUuid.toLowerCase()]
                  as Map<String, dynamic>?) ??
              (bundleMap[bundle.bundleUuid.replaceAll('-', '').toLowerCase()]
                  as Map<String, dynamic>?);

      String? bundleName = bundleMeta?['displayName'] as String?;
      String? bundleIcon = bundleMeta?['displayIcon'] as String?;
      String? promoImage = bundleMeta?['verticalPromoImage'] as String? ??
          bundleMeta?['displayIcon2'] as String? ??
          bundleMeta?['displayIcon'] as String?;

      // Deep inspection of bundle items if bundle metadata or banner artwork is missing
      if (bundle.itemIds.isNotEmpty) {
        String? bestCardWideArt;
        String? bestCardLargeArt;
        String? bestWeaponWallpaper;
        String? bestItemIcon;
        String? detectedCollectionName;
        final detectedSkinNames = <String>[];

        for (final itemId in bundle.itemIds) {
          final itemMeta = (unifiedMap[itemId] as Map<String, dynamic>?) ??
              (unifiedMap[itemId.toLowerCase()] as Map<String, dynamic>?) ??
              (unifiedMap[itemId.replaceAll('-', '').toLowerCase()]
                  as Map<String, dynamic>?);

          if (itemMeta != null) {
            final displayName = (itemMeta['displayName'] as String?) ??
                (itemMeta['skinName'] as String?) ??
                '';
            final itemType = itemMeta['itemType'] as String? ?? '';
            final wideArt = itemMeta['wideArt'] as String?;
            final largeArt = itemMeta['largeArt'] as String?;
            final wallpaper = itemMeta['wallpaper'] as String?;
            final icon = itemMeta['displayIcon'] as String?;

            if (wideArt != null && wideArt.isNotEmpty) {
              bestCardWideArt ??= wideArt;
            }
            if (largeArt != null && largeArt.isNotEmpty) {
              bestCardLargeArt ??= largeArt;
            }
            if (wallpaper != null && wallpaper.isNotEmpty) {
              bestWeaponWallpaper ??= wallpaper;
            }
            if (icon != null && icon.isNotEmpty) {
              bestItemIcon ??= icon;
            }

            // Extract clean collection name from PlayerCard, Spray, Buddy, or Title
            if (itemType == 'PlayerCard' ||
                itemType == 'Spray' ||
                itemType == 'Buddy') {
              final cleaned = displayName
                  .replaceAll(
                      RegExp(r'\s+(Card|Player Card|Spray|Buddy|Gun Buddy)$',
                          caseSensitive: false),
                      '')
                  .trim();
              if (cleaned.isNotEmpty && detectedCollectionName == null) {
                detectedCollectionName = cleaned;
              }
            } else if (itemType != 'Title') {
              final skinName =
                  (itemMeta['skinName'] as String?) ?? displayName;
              if (skinName.isNotEmpty) {
                detectedSkinNames.add(skinName);
              }
            }
          }
        }

        // If bundle name wasn't found directly by UUID, deduce from detected items
        if (bundleName == null ||
            bundleName.isEmpty ||
            bundleName == 'Featured Bundle') {
          // If we detected a collection name from card/spray/buddy, search bundleMap for it
          if (detectedCollectionName != null &&
              detectedCollectionName.isNotEmpty) {
            final lowerDetected = detectedCollectionName.toLowerCase();
            final normDetected = lowerDetected
                .replaceAll('//', '')
                .replaceAll(':', '')
                .replaceAll(' ', '');

            for (final entry in bundleMap.values) {
              if (entry is Map) {
                final entryName = (entry['displayName'] as String?) ?? '';
                final lowerEntryName = entryName.toLowerCase();
                final normEntryName = lowerEntryName
                    .replaceAll('//', '')
                    .replaceAll(':', '')
                    .replaceAll(' ', '');

                if (lowerEntryName == lowerDetected ||
                    lowerEntryName.startsWith(lowerDetected) ||
                    lowerDetected.startsWith(lowerEntryName) ||
                    lowerEntryName == '$lowerDetected bundle' ||
                    lowerEntryName == '$lowerDetected collection' ||
                    normEntryName == normDetected ||
                    normEntryName.startsWith(normDetected) ||
                    normDetected.startsWith(normEntryName)) {
                  bundleName = entryName;
                  promoImage ??= (entry['verticalPromoImage'] as String?) ??
                      (entry['displayIcon2'] as String?) ??
                      (entry['displayIcon'] as String?);
                  bundleIcon ??=
                      (entry['displayIcon'] as String?) ?? promoImage;
                  break;
                }
              }
            }
            bundleName ??= detectedCollectionName.endsWith('Bundle') ||
                    detectedCollectionName.endsWith('Collection')
                ? detectedCollectionName
                : '$detectedCollectionName Bundle';
          } else if (detectedSkinNames.isNotEmpty) {
            // Deduce from weapon skin names (e.g. all start with same word)
            final firstSkin = detectedSkinNames.first;
            final words = firstSkin.split(' ');
            final prefix = words.first;
            final allSharePrefix = prefix.length > 2 &&
                detectedSkinNames.every((s) => s.startsWith(prefix));
            if (allSharePrefix) {
              final collectionGuess = '$prefix Bundle';
              final lowerPrefix = prefix.toLowerCase();
              for (final entry in bundleMap.values) {
                if (entry is Map) {
                  final entryName = (entry['displayName'] as String?) ?? '';
                  if (entryName.toLowerCase().startsWith(lowerPrefix)) {
                    bundleName = entryName;
                    promoImage ??= (entry['verticalPromoImage'] as String?) ??
                        (entry['displayIcon2'] as String?) ??
                        (entry['displayIcon'] as String?);
                    bundleIcon ??=
                        (entry['displayIcon'] as String?) ?? promoImage;
                    break;
                  }
                }
              }
              bundleName ??= collectionGuess;
            } else {
              bundleName = 'Featured Bundle';
            }
          }
        }

        // Set banner artwork fallback from items
        promoImage ??= bestCardWideArt ??
            bestCardLargeArt ??
            bestWeaponWallpaper ??
            bestItemIcon;
        bundleIcon ??= bestItemIcon ?? promoImage;
      }

      bundleName ??= 'Featured Bundle';

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
