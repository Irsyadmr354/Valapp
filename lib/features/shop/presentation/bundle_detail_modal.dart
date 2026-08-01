import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
import '../../../shared/utils/app_colors.dart';
import '../../../shared/utils/tier_colors.dart';
import '../../../shared/widgets/countdown_timer.dart';
import '../domain/models/skin_offer.dart';
import '../domain/models/storefront.dart';
import 'skin_detail_modal.dart';

/// Modal displaying full contents of the Featured Bundle (all skin items, prices, timers, and inspectable preview).
class BundleDetailModal extends ConsumerWidget {
  const BundleDetailModal({
    super.key,
    required this.bundle,
    this.bannerImageUrl,
  });

  final FeaturedBundle bundle;
  final String? bannerImageUrl;

  static Future<void> show(
    BuildContext context, {
    required FeaturedBundle bundle,
    String? bannerImageUrl,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BundleDetailModal(
        bundle: bundle,
        bannerImageUrl: bannerImageUrl,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assets = ref.watch(valorantAssetsProvider);
    final discountInt = (bundle.totalDiscountPercent > 1
            ? bundle.totalDiscountPercent
            : bundle.totalDiscountPercent * 100)
        .round();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.fromBorderSide(
          BorderSide(color: AppColors.red, width: 1.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),

          // Header with Bundle Name & Price
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bundle.displayName ?? 'Featured Bundle',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (discountInt > 0) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF4655),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '-$discountInt% OFF',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            bundle.totalDiscountedCost > 0
                                ? '${bundle.totalDiscountedCost} VP'
                                : (bundle.totalBaseCost > 0
                                    ? '${bundle.totalBaseCost} VP'
                                    : 'FEATURED BUNDLE'),
                            style: const TextStyle(
                              color: AppColors.red,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Full-width countdown timer bar
          if (bundle.durationRemainingSeconds > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.red.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.red.withAlpha(80), width: 0.8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.timer_outlined, color: AppColors.red, size: 16),
                    const SizedBox(width: 8),
                    const Text('OFFER ENDS IN ',
                        style: TextStyle(
                            color: AppColors.red,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8)),
                    CountdownTimer(
                      remainingSeconds: bundle.durationRemainingSeconds,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 8),

          // Bundle Content List
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: assets.getSkinLevelsMap(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.red),
                  );
                }

                final skinMap = snapshot.data ?? {};

                return ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    // Promo Image Banner Artwork
                    if (bannerImageUrl != null && bannerImageUrl!.isNotEmpty) ...[
                      Container(
                        height: 160,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: const Color(0xFF141F2D),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          child: CachedNetworkImage(
                            imageUrl: bannerImageUrl!,
                            fit: BoxFit.cover,
                            alignment: Alignment.center,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Section Title
                    Row(
                      children: [
                        Container(width: 3, height: 14, color: AppColors.red),
                        const SizedBox(width: 8),
                        Text(
                          'BUNDLE ITEMS (${bundle.itemIds.length})',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Grid of Skins inside the Bundle
                    ...bundle.itemIds.map((itemId) {
                      final meta = skinMap[itemId] as Map<String, dynamic>? ??
                          skinMap[itemId.toLowerCase()] as Map<String, dynamic>?;

                      final skinName = meta?['displayName'] as String? ??
                          meta?['skinName'] as String? ??
                          'Bundle Item';
                      final displayIcon = meta?['displayIcon'] as String?;
                      final tierUuid = meta?['contentTierUuid'] as String?;
                      final tierColor = TierColors.forName(tierUuid);

                      final itemPrice = bundle.itemPrices[itemId] ?? 0;
                      final offer = SkinOffer(
                        offerId: itemId,
                        skinLevelUuid: itemId,
                        price: itemPrice,
                        displayName: skinName,
                        displayIcon: displayIcon,
                        contentTierUuid: tierUuid,
                      );

                      return GestureDetector(
                        onTap: () => SkinDetailModal.show(context, offer),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.bgCard2,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: tierColor.withAlpha(80), width: 1),
                          ),
                          child: Row(
                            children: [
                              // Skin Icon Preview Thumbnail
                              Container(
                                width: 56,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: AppColors.bg,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: displayIcon != null && displayIcon.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: displayIcon,
                                        fit: BoxFit.contain,
                                      )
                                    : const Icon(Icons.image,
                                        color: Colors.white24),
                              ),
                              const SizedBox(width: 14),

                              // Name & Tier Info
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      skinName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: tierColor.withAlpha(30),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            TierColors.tierLabel(tierUuid).toUpperCase(),
                                            style: TextStyle(
                                              color: tierColor,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              // INSPECT label + chevron
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('INSPECT',
                                          style: TextStyle(
                                              color: AppColors.red,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 0.5)),
                                      Icon(Icons.chevron_right,
                                          color: AppColors.red, size: 16),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 30),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
