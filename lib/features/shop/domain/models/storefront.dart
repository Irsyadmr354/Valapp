import 'package:flutter/foundation.dart';
import 'skin_offer.dart';
import 'wallet.dart';

class BundleItem {
  final String itemId;
  final int basePrice;
  final int discountedPrice;
  final int discountPercent;

  const BundleItem({
    required this.itemId,
    required this.basePrice,
    required this.discountedPrice,
    required this.discountPercent,
  });
}

/// Featured bundle in the store.
class FeaturedBundle {
  final String bundleUuid;
  final int durationRemainingSeconds;
  final List<String> itemIds;
  final List<BundleItem> items;
  final Map<String, int> itemPrices;
  final int totalBaseCost;
  final int totalDiscountedCost;
  final double totalDiscountPercent;
  final String? displayName;
  final String? displayIcon;
  final String? verticalPromoImage;

  const FeaturedBundle({
    required this.bundleUuid,
    required this.durationRemainingSeconds,
    required this.itemIds,
    this.items = const [],
    this.itemPrices = const {},
    required this.totalBaseCost,
    required this.totalDiscountedCost,
    required this.totalDiscountPercent,
    this.displayName,
    this.displayIcon,
    this.verticalPromoImage,
  });

  FeaturedBundle copyWith({
    String? displayName,
    String? displayIcon,
    String? verticalPromoImage,
  }) {
    return FeaturedBundle(
      bundleUuid: bundleUuid,
      durationRemainingSeconds: durationRemainingSeconds,
      itemIds: itemIds,
      items: items,
      itemPrices: itemPrices,
      totalBaseCost: totalBaseCost,
      totalDiscountedCost: totalDiscountedCost,
      totalDiscountPercent: totalDiscountPercent,
      displayName: displayName ?? this.displayName,
      displayIcon: displayIcon ?? this.displayIcon,
      verticalPromoImage: verticalPromoImage ?? this.verticalPromoImage,
    );
  }

  factory FeaturedBundle.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['Items'] as List<dynamic>?) ??
        (json['ItemOffers'] as List<dynamic>?) ??
        [];
    final itemIds = <String>[];
    final bundleItems = <BundleItem>[];
    final itemPrices = <String, int>{};

    for (final e in rawItems) {
      if (e is Map) {
        final itemObj = e['Item'] as Map?;
        final offerObj = e['Offer'] as Map?;
        final rewards = offerObj?['Rewards'] as List<dynamic>?;
        final rewardId =
            (rewards != null && rewards.isNotEmpty && rewards.first is Map)
                ? rewards.first['ItemID']?.toString()
                : null;
        final id = itemObj?['ItemID']?.toString() ??
            e['ItemID']?.toString() ??
            rewardId ??
            offerObj?['OfferID']?.toString() ??
            '';

        final costMap = (offerObj?['Cost'] as Map?) ?? (e['Cost'] as Map?);
        final baseCost = (e['BasePrice'] as num?)?.toInt() ??
            (costMap?[ValorantCurrency.vpUuid] as num?)?.toInt() ??
            0;
        final discCost = (e['DiscountedPrice'] as num?)?.toInt() ??
            (e['DiscountCosts']?[ValorantCurrency.vpUuid] as num?)?.toInt() ??
            baseCost;
        final discPct = (e['DiscountPercent'] as num?)?.toInt() ?? 0;

        if (id.isNotEmpty) {
          itemIds.add(id);
          itemPrices[id] = discCost > 0 ? discCost : baseCost;
          bundleItems.add(BundleItem(
            itemId: id,
            basePrice: baseCost,
            discountedPrice: discCost,
            discountPercent: discPct,
          ));
        }
      }
    }

    final dataAssetId = json['DataAssetID']?.toString().trim() ?? '';
    final offerId = json['ID']?.toString().trim() ?? '';
    final bundleUuid = dataAssetId.isNotEmpty ? dataAssetId : offerId;

    return FeaturedBundle(
      bundleUuid: bundleUuid,
      durationRemainingSeconds:
          (json['DurationRemainingInSeconds'] as num?)?.toInt() ??
              (json['BundleRemainingDurationInSeconds'] as num?)?.toInt() ??
              0,
      itemIds: itemIds,
      items: bundleItems,
      itemPrices: itemPrices,
      totalBaseCost:
          (json['TotalBaseCost']?[ValorantCurrency.vpUuid] as num?)?.toInt() ??
              0,
      totalDiscountedCost:
          (json['TotalDiscountedCost']?[ValorantCurrency.vpUuid] as num?)
                  ?.toInt() ??
              0,
      totalDiscountPercent:
          (json['TotalDiscountPercent'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Night market bundle item.
class NightMarketOffer {
  final String offerId;
  final String skinLevelUuid;
  final int basePrice;
  final int discountedPrice;
  final int discountPercent; // e.g. 22 for 22%
  final String? skinName;
  final String? skinIcon;
  final String? contentTierUuid;

  const NightMarketOffer({
    required this.offerId,
    required this.skinLevelUuid,
    required this.basePrice,
    required this.discountedPrice,
    required this.discountPercent,
    this.skinName,
    this.skinIcon,
    this.contentTierUuid,
  });

  NightMarketOffer copyWith({
    String? skinName,
    String? skinIcon,
    String? contentTierUuid,
  }) {
    return NightMarketOffer(
      offerId: offerId,
      skinLevelUuid: skinLevelUuid,
      basePrice: basePrice,
      discountedPrice: discountedPrice,
      discountPercent: discountPercent,
      skinName: skinName ?? this.skinName,
      skinIcon: skinIcon ?? this.skinIcon,
      contentTierUuid: contentTierUuid ?? this.contentTierUuid,
    );
  }

  SkinOffer toSkinOffer() {
    return SkinOffer(
      offerId: offerId,
      skinLevelUuid: skinLevelUuid,
      price: discountedPrice,
      displayName: skinName,
      displayIcon: skinIcon,
      contentTierUuid: contentTierUuid,
    );
  }

  factory NightMarketOffer.fromJson(Map<String, dynamic> json) {
    final offer = json['Offer'] as Map<String, dynamic>? ?? {};
    final rewards = (offer['Rewards'] as List<dynamic>?) ?? [];
    String skinLevelUuid = '';
    if (rewards.isNotEmpty && rewards.first is Map) {
      skinLevelUuid = rewards.first['ItemID']?.toString() ?? '';
    }

    final rawCost = offer['Cost'] as Map<String, dynamic>? ?? {};
    final basePrice = (rawCost[ValorantCurrency.vpUuid] as num?)?.toInt() ?? 0;

    final discCost = json['DiscountCosts'] as Map<String, dynamic>? ?? {};
    final discountedPrice =
        (discCost[ValorantCurrency.vpUuid] as num?)?.toInt() ?? 0;

    final rawDiscount = (json['DiscountPercent'] as num?)?.toDouble() ?? 0.0;
    final discountPercent =
        rawDiscount > 1 ? rawDiscount.round() : (rawDiscount * 100).round();

    return NightMarketOffer(
      offerId:
          offer['OfferID'] as String? ?? json['BonusOfferID'] as String? ?? '',
      skinLevelUuid: skinLevelUuid,
      basePrice: basePrice,
      discountedPrice: discountedPrice,
      discountPercent: discountPercent,
    );
  }
}

/// Accessory store — daily rotating accessories (sprays, cards, etc.)
class AccessoryStore {
  final int durationRemainingSeconds;
  final List<String> offerIds;

  const AccessoryStore({
    required this.durationRemainingSeconds,
    required this.offerIds,
  });

  factory AccessoryStore.fromJson(Map<String, dynamic> json) {
    final offers = (json['AccessoryStoreOffers'] as List<dynamic>?) ?? [];
    return AccessoryStore(
      durationRemainingSeconds:
          (json['AccessoryStoreRemainingDurationInSeconds'] as num?)?.toInt() ??
              0,
      offerIds: offers
          .whereType<Map>()
          .map((e) => (e['Offer'] as Map?)?['OfferID'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toList(),
    );
  }
}

/// Complete storefront snapshot.
class Storefront {
  final List<SkinOffer> dailyOffers;
  final int dailyOffersRemainingSeconds;
  final List<FeaturedBundle> featuredBundles;
  final List<NightMarketOffer> nightMarket;
  final AccessoryStore? accessoryStore;
  final DateTime fetchedAt;
  final bool isFromOfflineCache;

  const Storefront({
    required this.dailyOffers,
    required this.dailyOffersRemainingSeconds,
    this.featuredBundles = const [],
    FeaturedBundle? featuredBundle,
    required this.nightMarket,
    this.accessoryStore,
    required this.fetchedAt,
    this.isFromOfflineCache = false,
  }) : _legacyBundle = featuredBundle;

  final FeaturedBundle? _legacyBundle;

  /// Primary featured bundle (or first bundle among active featured bundles)
  FeaturedBundle? get featuredBundle =>
      _legacyBundle ?? featuredBundles.firstOrNull;

  Storefront copyWith({
    List<SkinOffer>? dailyOffers,
    int? dailyOffersRemainingSeconds,
    FeaturedBundle? featuredBundle,
    List<FeaturedBundle>? featuredBundles,
    List<NightMarketOffer>? nightMarket,
    AccessoryStore? accessoryStore,
    DateTime? fetchedAt,
    bool? isFromOfflineCache,
  }) {
    return Storefront(
      dailyOffers: dailyOffers ?? this.dailyOffers,
      dailyOffersRemainingSeconds:
          dailyOffersRemainingSeconds ?? this.dailyOffersRemainingSeconds,
      featuredBundles: featuredBundles ??
          (featuredBundle != null ? [featuredBundle] : this.featuredBundles),
      nightMarket: nightMarket ?? this.nightMarket,
      accessoryStore: accessoryStore ?? this.accessoryStore,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      isFromOfflineCache: isFromOfflineCache ?? this.isFromOfflineCache,
    );
  }

  bool get hasNightMarket => nightMarket.isNotEmpty;

  DateTime get dailyOffersDeadline =>
      fetchedAt.add(Duration(seconds: dailyOffersRemainingSeconds));

  String get dailyOffersIdentity {
    final ids = dailyOffers.map((offer) => offer.skinLevelUuid).toList()
      ..sort();
    return ids.join(',');
  }

  /// Returns true if this storefront data is past its reset time and stale.
  /// Used by the cache layer to decide whether to return cached data or force
  /// a fresh fetch even when offline.
  bool get isExpired {
    final elapsed = DateTime.now().difference(fetchedAt).inSeconds;
    final remaining = dailyOffersRemainingSeconds - elapsed;
    return remaining <= 0;
  }

  /// Dynamically computes remaining seconds for the daily shop countdown,
  /// accounting for elapsed time since the data was fetched.
  ///
  /// Returns 0 (not negative) if the shop has already passed its reset time —
  /// this immediately triggers the CountdownTimer.onExpired callback which
  /// calls _refresh() and re-fetches the new shop from the network.
  int get currentDailyOffersRemainingSeconds {
    final elapsed = DateTime.now().difference(fetchedAt).inSeconds;
    final remaining = dailyOffersRemainingSeconds - elapsed;
    // Clamp to 0 so CountdownTimer fires onExpired rather than showing
    // a nonsensical negative or astronomically large number.
    if (remaining >= 0 && remaining <= 86400) return remaining;
    // remaining < 0: shop already reset — return 0 to fire onExpired now.
    if (remaining < 0) return 0;
    // remaining > 86400: something is wrong with the server value — fall back
    // to next midnight UTC (Riot resets at 00:00 UTC = 07:00 WIB).
    final nowUtc = DateTime.now().toUtc();
    final nextResetUtc =
        DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day + 1, 0, 0, 0);
    return nextResetUtc.difference(nowUtc).inSeconds.clamp(0, 86400);
  }

  factory Storefront.fromJson(Map<String, dynamic> json) {
    final skinPanel = json['SkinsPanelLayout'] as Map<String, dynamic>? ?? {};
    final singleItemOfferIds = (skinPanel['SingleItemOffers'] as List<dynamic>?)
            ?.whereType<String>()
            .toList() ??
        [];
    final singleItemStoreOffers =
        (skinPanel['SingleItemStoreOffers'] as List<dynamic>?) ?? [];
    final remainingSec =
        (skinPanel['SingleItemOffersRemainingDurationInSeconds'] as num?)
                ?.toInt() ??
            0;

    // Build daily offers — match prices by OfferID, not array index.
    final offerPrices = <String, int>{};
    for (final item in singleItemStoreOffers) {
      if (item is! Map) continue;
      final storeOffer = Map<String, dynamic>.from(item);
      final offerId = storeOffer['OfferID'] as String?;
      if (offerId == null || offerId.isEmpty) continue;
      final cost = storeOffer['Cost'] as Map<String, dynamic>? ?? {};
      final price = (cost[ValorantCurrency.vpUuid] as num?)?.toInt() ?? 0;
      offerPrices[offerId] = price;
    }

    if (singleItemOfferIds.length != singleItemStoreOffers.length) {
      debugPrint(
        '[Storefront] WARNING: offer/price list length mismatch '
        '(${singleItemOfferIds.length} offers vs '
        '${singleItemStoreOffers.length} store offers)',
      );
    }

    final dailyOffers = <SkinOffer>[];
    for (final id in singleItemOfferIds) {
      final price = offerPrices[id] ?? 0;
      if (price == 0 && offerPrices.isNotEmpty) {
        debugPrint(
          '[Storefront] WARNING: no price found for offer ID $id',
        );
      }
      dailyOffers.add(SkinOffer(
        offerId: id,
        skinLevelUuid: id,
        price: price,
      ));
    }

    // Featured bundles (handles multiple bundles, single bundle, or direct bundle map)
    final featuredBundles = <FeaturedBundle>[];
    final fbJson = json['FeaturedBundle'] as Map<String, dynamic>?;
    if (fbJson != null) {
      final bundlesList = fbJson['Bundles'] as List<dynamic>?;
      if (bundlesList != null && bundlesList.isNotEmpty) {
        for (final b in bundlesList.whereType<Map>()) {
          try {
            featuredBundles
                .add(FeaturedBundle.fromJson(Map<String, dynamic>.from(b)));
          } catch (_) {}
        }
      } else if (fbJson['Bundle'] != null && fbJson['Bundle'] is Map) {
        try {
          featuredBundles.add(FeaturedBundle.fromJson(
              fbJson['Bundle'] as Map<String, dynamic>));
        } catch (_) {}
      } else if (fbJson['Items'] != null ||
          fbJson['ItemOffers'] != null ||
          fbJson['DataAssetID'] != null ||
          fbJson['ID'] != null) {
        try {
          featuredBundles.add(FeaturedBundle.fromJson(fbJson));
        } catch (_) {}
      }
    }

    // Night market
    final bonusStore = json['BonusStore'] as Map<String, dynamic>?;
    final nightMarketOffers = (bonusStore?['BonusStoreOffers']
                as List<dynamic>?)
            ?.whereType<Map>()
            .map((e) => NightMarketOffer.fromJson(Map<String, dynamic>.from(e)))
            .toList() ??
        [];

    // Accessory store
    AccessoryStore? accessoryStore;
    if (json['AccessoryStore'] != null) {
      accessoryStore = AccessoryStore.fromJson(
          json['AccessoryStore'] as Map<String, dynamic>);
    }

    return Storefront(
      dailyOffers: dailyOffers,
      dailyOffersRemainingSeconds: remainingSec,
      featuredBundles: featuredBundles,
      nightMarket: nightMarketOffers,
      accessoryStore: accessoryStore,
      fetchedAt: DateTime.tryParse(json['_fetchedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
