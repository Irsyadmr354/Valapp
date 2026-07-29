/// A single skin item in the daily shop or bundle.
class SkinOffer {
  final String offerId;
  final String skinLevelUuid;
  final int price; // in VP
  final String? displayName;
  final String? displayIcon;
  final String? contentTierUuid;
  final bool isInWishlist;

  const SkinOffer({
    required this.offerId,
    required this.skinLevelUuid,
    required this.price,
    this.displayName,
    this.displayIcon,
    this.contentTierUuid,
    this.isInWishlist = false,
  });

  SkinOffer copyWith({
    String? displayName,
    String? displayIcon,
    String? contentTierUuid,
    bool? isInWishlist,
  }) {
    return SkinOffer(
      offerId: offerId,
      skinLevelUuid: skinLevelUuid,
      price: price,
      displayName: displayName ?? this.displayName,
      displayIcon: displayIcon ?? this.displayIcon,
      contentTierUuid: contentTierUuid ?? this.contentTierUuid,
      isInWishlist: isInWishlist ?? this.isInWishlist,
    );
  }
}
