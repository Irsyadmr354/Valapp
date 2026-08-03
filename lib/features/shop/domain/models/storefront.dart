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
    final rawItems = (json['Items'] as List<dynamic>?) ?? [];
    final itemIds = <String>[];
    final bundleItems = <BundleItem>[];
    final itemPrices = <String, int>{};

    for (final e in rawItems) {
      if (e is Map) {
        final itemObj = e['Item'] as Map?;
        final id = itemObj?['ItemID']?.toString() ?? e['ItemID']?.toString() ?? '';
        final baseCost = (e['BasePrice'] as num?)?.toInt() ??
            (e['Cost']?[ValorantCurrency.vpUuid] as num?)?.toInt() ??
            0;
        final discCost = (e['DiscountedPrice'] as num?)?.toInt() ?? baseCost;
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

    return FeaturedBundle(
      bundleUuid: json['DataAssetID'] as String? ?? json['ID'] as String? ?? '',
      durationRemainingSeconds:
          (json['DurationRemainingInSeconds'] as num?)?.toInt() ??
          (json['BundleRemainingDurationInSeconds'] as num?)?.toInt() ?? 0,
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
    final basePrice =
        (rawCost[ValorantCurrency.vpUuid] as num?)?.toInt() ?? 0;

    final discCost = json['DiscountCosts'] as Map<String, dynamic>? ?? {};
    final discountedPrice =
        (discCost[ValorantCurrency.vpUuid] as num?)?.toInt() ?? 0;

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

  /// Dynamically computes remaining seconds for daily shop reset,
  /// accounting for elapsed time since fetch and falling back to 00:00 UTC (07:00 AM WIB).
  int get currentDailyOffersRemainingSeconds {
    final elapsed = DateTime.now().difference(fetchedAt).inSeconds;
    final remaining = dailyOffersRemainingSeconds - elapsed;
    if (remaining > 0 && remaining <= 86400) {
      return remaining;
    }
    final nowUtc = DateTime.now().toUtc();
    final nextResetUtc = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day + 1, 0, 0, 0);
    return nextResetUtc.difference(nowUtc).inSeconds;
  }

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

    // Build daily offers — match prices by OfferID, not array index.
    final offerPrices = <String, int>{};
    for (final item in singleItemStoreOffers) {
      if (item is! Map) continue;
      final storeOffer = Map<String, dynamic>.from(item);
      final offerId = storeOffer['OfferID'] as String?;
      if (offerId == null || offerId.isEmpty) continue;
      final cost = storeOffer['Cost'] as Map<String, dynamic>? ?? {};
      final price =
          (cost[ValorantCurrency.vpUuid] as num?)?.toInt() ?? 0;
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

    // Featured bundle
    FeaturedBundle? bundle;
    final fbJson = json['FeaturedBundle'] as Map<String, dynamic>?;
    if (fbJson != null) {
      final bundlesList = fbJson['Bundles'] as List<dynamic>?;
      if (bundlesList != null && bundlesList.isNotEmpty) {
        bundle = FeaturedBundle.fromJson(
            bundlesList.first as Map<String, dynamic>);
      } else if (fbJson['Bundle'] != null && fbJson['Bundle'] is Map) {
        bundle = FeaturedBundle.fromJson(
            fbJson['Bundle'] as Map<String, dynamic>);
      }
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
      fetchedAt: DateTime.tryParse(json['_fetchedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
