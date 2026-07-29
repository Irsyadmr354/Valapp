import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../features/shop/domain/models/skin_offer.dart';
import '../utils/tier_colors.dart';

/// Card displaying a single skin with its name, tier color, price, and
/// wishlist toggle.
class SkinCard extends StatelessWidget {
  const SkinCard({
    super.key,
    required this.offer,
    this.onWishlistToggle,
    this.isHighlighted = false,
  });

  final SkinOffer offer;
  final VoidCallback? onWishlistToggle;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    final tierColor = TierColors.forName(offer.contentTierUuid);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isHighlighted
              ? const Color(0xFFFF4655)
              : tierColor.withAlpha(120),
          width: isHighlighted ? 2 : 1,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tierColor.withAlpha(30),
            const Color(0xFF1A2634),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Skin image
          Expanded(
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(7)),
              child: offer.displayIcon != null
                  ? CachedNetworkImage(
                      imageUrl: offer.displayIcon!,
                      fit: BoxFit.contain,
                      placeholder: (_, __) => const _ShimmerBox(),
                      errorWidget: (_, __, ___) => const _PlaceholderIcon(),
                    )
                  : const _PlaceholderIcon(),
            ),
          ),

          // Info row
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Skin name
                Text(
                  offer.displayName ?? 'Unknown Skin',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),

                Row(
                  children: [
                    // VP icon + price
                    const _VpIcon(),
                    const SizedBox(width: 4),
                    Text(
                      offer.price.toString(),
                      style: TextStyle(
                        color: tierColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),

                    // Wishlist button
                    if (onWishlistToggle != null)
                      GestureDetector(
                        onTap: onWishlistToggle,
                        child: Icon(
                          offer.isInWishlist
                              ? Icons.bookmark
                              : Icons.bookmark_border,
                          color: offer.isInWishlist
                              ? const Color(0xFFFF4655)
                              : Colors.white38,
                          size: 20,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VpIcon extends StatelessWidget {
  const _VpIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: const BoxDecoration(
        color: Color(0xFF0BC4C4),
        shape: BoxShape.circle,
      ),
      child: const Center(
        child: Text(
          'VP',
          style: TextStyle(
              color: Colors.white,
              fontSize: 6,
              fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _ShimmerBox extends StatelessWidget {
  const _ShimmerBox();

  @override
  Widget build(BuildContext context) {
    return Container(color: const Color(0xFF1E2C3A));
  }
}

class _PlaceholderIcon extends StatelessWidget {
  const _PlaceholderIcon();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(Icons.image_not_supported_outlined,
          color: Colors.white24, size: 40),
    );
  }
}
