import 'skin_offer.dart';

/// Featured bundle in the store.
class FeaturedBundle {
  final String bundleUuid;
  final int durationRemainingSeconds;
  final List<String> itemIds;
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
      totalBaseCost: totalBaseCost,
      totalDiscountedCost: totalDiscountedCost,
      totalDiscountPercent: totalDiscountPercent,
      displayName: displayName ?? this.displayName,
      displayIcon: displayIcon ?? this.displayIcon,
      verticalPromoImage: verticalPromoImage ?? this.verticalPromoImage,
    );
  }

  factory FeaturedBundle.fromJson(Map<String, dynamic> json) {
    final items = (json['Items'] as List<dynamic>?) ?? [];
    return FeaturedBundle(
      bundleUuid: json['DataAssetID'] as String? ?? '',
      durationRemainingSeconds:
          (json['DurationRemainingInSeconds'] as num?)?.toInt() ?? 0,
      itemIds: items
          .map((e) => e['Item']?['ItemID'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toList(),
      totalBaseCost:
          (json['TotalBaseCost']?['85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741']
                  as num?)
              ?.toInt() ??
              0,
      totalDiscountedCost: (json['TotalDiscountedCost']
                  ?['85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741'] as num?)
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

  factory NightMarketOffer.fromJson(Map<String, dynamic> json) {
    final offer = json['Offer'] as Map<String, dynamic>? ?? {};
    final rewards = (offer['Rewards'] as List<dynamic>?) ?? [];
    String skinLevelUuid = '';
    if (rewards.isNotEmpty && rewards.first is Map) {
      skinLevelUuid = rewards.first['ItemID']?.toString() ?? '';
    }

    final rawCost = offer['Cost'] as Map<String, dynamic>? ?? {};
    final basePrice =
        (rawCost['85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741'] as num?)?.toInt() ?? 0;

    final discCost = json['DiscountCosts'] as Map<String, dynamic>? ?? {};
    final discountedPrice =
        (discCost['85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741'] as num?)?.toInt() ?? 0;

    final rawDiscount = (json['DiscountPercent'] as num?)?.toDouble() ?? 0.0;
    final discountPercent = rawDiscount > 1
        ? rawDiscount.round()
        : (rawDiscount * 100).round();

    return NightMarketOffer(
      offerId: offer['OfferID'] as String? ?? json['BonusOfferID'] as String? ?? '',
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
          .map((e) => e['Offer']?['OfferID'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toList(),
    );
  }
}

/// Complete storefront snapshot.
class Storefront {
  final List<SkinOffer> dailyOffers;
  final int dailyOffersRemainingSeconds;
  final FeaturedBundle? featuredBundle;
  final List<NightMarketOffer> nightMarket;
  final AccessoryStore? accessoryStore;
  final DateTime fetchedAt;

  const Storefront({
    required this.dailyOffers,
    required this.dailyOffersRemainingSeconds,
    this.featuredBundle,
    required this.nightMarket,
    this.accessoryStore,
    required this.fetchedAt,
  });

  bool get hasNightMarket => nightMarket.isNotEmpty;

  factory Storefront.fromJson(Map<String, dynamic> json) {
    final skinPanel =
        json['SkinsPanelLayout'] as Map<String, dynamic>? ?? {};
    final singleItemOfferIds =
        (skinPanel['SingleItemOffers'] as List<dynamic>?)
                ?.cast<String>() ??
            [];
    final singleItemStoreOffers =
        (skinPanel['SingleItemStoreOffers'] as List<dynamic>?) ?? [];
    final remainingSec =
        (skinPanel['SingleItemOffersRemainingDurationInSeconds'] as num?)
                ?.toInt() ??
            0;

    // Build daily offers — price comes from SingleItemStoreOffers[i].Cost
    final dailyOffers = <SkinOffer>[];
    for (int i = 0; i < singleItemOfferIds.length; i++) {
      final id = singleItemOfferIds[i];
      int price = 0;

      // Match price from SingleItemStoreOffers (index matches 1:1)
      if (i < singleItemStoreOffers.length) {
        final storeOffer =
            singleItemStoreOffers[i] as Map<String, dynamic>? ?? {};
        final cost = storeOffer['Cost'] as Map<String, dynamic>? ?? {};
        // VP currency ID
        price =
            (cost['85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741'] as num?)?.toInt() ??
                0;
      }

      dailyOffers.add(SkinOffer(
        offerId: id,
        skinLevelUuid: id,
        price: price,
      ));
    }

    // Featured bundle
    FeaturedBundle? bundle;
    final bundlesData =
        json['FeaturedBundle']?['Bundles'] as List<dynamic>?;
    if (bundlesData != null && bundlesData.isNotEmpty) {
      bundle = FeaturedBundle.fromJson(
          bundlesData.first as Map<String, dynamic>);
    }

    // Night market
    final bonusStore = json['BonusStore'] as Map<String, dynamic>?;
    final nightMarketOffers = (bonusStore?['BonusStoreOffers'] as List<dynamic>?)
            ?.map((e) =>
                NightMarketOffer.fromJson(e as Map<String, dynamic>))
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
      featuredBundle: bundle,
      nightMarket: nightMarketOffers,
      accessoryStore: accessoryStore,
      fetchedAt: DateTime.now(),
    );
  }
}
