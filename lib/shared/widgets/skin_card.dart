import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../features/shop/domain/models/skin_offer.dart';
import '../utils/tier_colors.dart';

/// Card displaying a single skin with its name, tier color, price, and wishlist toggle.
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
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isHighlighted
              ? const Color(0xFFFF4655)
              : tierColor.withAlpha(160),
          width: isHighlighted ? 2 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: (isHighlighted ? const Color(0xFFFF4655) : tierColor)
                .withAlpha(25),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            tierColor.withAlpha(45),
            const Color(0xFF0F1722),
            const Color(0xFF0B101A),
          ],
          stops: const [0.0, 0.4, 1.0],
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Stack(
          children: [
            // Top Accent Bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 3,
                color: tierColor,
              ),
            ),

            // Card Body
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                // Skin Image
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
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

                // Info Footer
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF080D14).withAlpha(220),
                    border: const Border(
                      top: BorderSide(color: Color(0xFF1B2738), width: 0.8),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Skin Name
                      Text(
                        offer.displayName ?? 'Unknown Skin',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),

                      // Price + Wishlist Row
                      Row(
                        children: [
                          // VP Badge Chip
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00F0FF).withAlpha(25),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFF00F0FF).withAlpha(90),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const _VpIcon(),
                                const SizedBox(width: 4),
                                Text(
                                  offer.price.toString(),
                                  style: const TextStyle(
                                    color: Color(0xFF00F0FF),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),

                          // Wishlist button
                          if (onWishlistToggle != null)
                            GestureDetector(
                              onTap: onWishlistToggle,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: offer.isInWishlist
                                      ? const Color(0xFFFF4655).withAlpha(40)
                                      : Colors.transparent,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  offer.isInWishlist
                                      ? Icons.bookmark
                                      : Icons.bookmark_border,
                                  color: offer.isInWishlist
                                      ? const Color(0xFFFF4655)
                                      : Colors.white38,
                                  size: 18,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VpIcon extends StatelessWidget {
  const _VpIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: const BoxDecoration(
        color: Color(0xFF00F0FF),
        shape: BoxShape.circle,
      ),
      child: const Center(
        child: Text(
          'V',
          style: TextStyle(
              color: Color(0xFF080D14),
              fontSize: 8,
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
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141F2D),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}

class _PlaceholderIcon extends StatelessWidget {
  const _PlaceholderIcon();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(Icons.image_not_supported_outlined,
          color: Colors.white24, size: 36),
    );
  }
}

