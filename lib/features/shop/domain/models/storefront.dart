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
  final int discountedPrice;
  final double discountPercent;
  final String? skinName;
  final String? skinIcon;

  const NightMarketOffer({
    required this.offerId,
    required this.discountedPrice,
    required this.discountPercent,
    this.skinName,
    this.skinIcon,
  });

  factory NightMarketOffer.fromJson(Map<String, dynamic> json) {
    final offer = json['Offer'] as Map<String, dynamic>? ?? {};
    return NightMarketOffer(
      offerId: offer['OfferID'] as String? ?? '',
      discountedPrice:
          (json['DiscountCosts']?['85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741']
                  as num?)
              ?.toInt() ??
              0,
      discountPercent:
          (json['DiscountPercent'] as num?)?.toDouble() ?? 0.0,
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

  factory Storefront.fromJson(Map<String, dynamic> json,
      Map<String, int> priceMap) {
    final skinPanel =
        json['SkinsPanelLayout'] as Map<String, dynamic>? ?? {};
    final singleItemOfferIds =
        (skinPanel['SingleItemOffers'] as List<dynamic>?)
                ?.cast<String>() ??
            [];
    final remainingSec =
        (skinPanel['SingleItemOffersRemainingDurationInSeconds'] as num?)
                ?.toInt() ??
            0;

    final dailyOffers = singleItemOfferIds.map((id) {
      return SkinOffer(
        offerId: id,
        skinLevelUuid: id,
        price: priceMap[id] ?? 0,
      );
    }).toList();

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
