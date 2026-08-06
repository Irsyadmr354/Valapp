import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../features/shop/domain/models/skin_offer.dart';
import '../utils/tier_colors.dart';
import 'valorant_icons.dart';

/// Card displaying a single skin.
/// Background: flat solid tier color tint (no gradient, no shadow, not 3D).
/// VP price chip: overlaid bottom-right of the image area.
/// Footer: skin name + bookmark only.
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
    final tierLabel = TierColors.tierLabel(offer.contentTierUuid);

    // Flat tier-tinted background — enough color to show the tier without 3D.
    // We blend a very low-alpha tier color over the dark base so it reads flat.
    final bgColor = Color.alphaBlend(
      tierColor.withAlpha(38),
      const Color(0xFF0C1118),
    );

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isHighlighted
              ? const Color(0xFFFF4655)
              : Colors.white.withAlpha(18),
          width: isHighlighted ? 2 : 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Image area ─────────────────────────────────────────────────
            Expanded(
              child: Stack(
                children: [
                  // Skin image
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
                      child: offer.displayIcon != null
                          ? CachedNetworkImage(
                              imageUrl: offer.displayIcon!,
                              fit: BoxFit.contain,
                              placeholder: (_, __) => const _ShimmerBox(),
                              errorWidget: (_, __, ___) =>
                                  const _PlaceholderIcon(),
                            )
                          : const _PlaceholderIcon(),
                    ),
                  ),

                  // Top-right: edition tier chip
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: tierColor.withAlpha(40),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: tierColor.withAlpha(120), width: 0.6),
                      ),
                      child: Text(
                        tierLabel.replaceAll(' Edition', '').toUpperCase(),
                        style: TextStyle(
                          color: tierColor,
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),

                  // Bottom-right: VP price chip overlaid on image (no bg card)
                  if (offer.price > 0)
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: _VpChip(price: offer.price),
                    ),
                ],
              ),
            ),

            // ── Footer: name + bookmark ────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(60),
                border: const Border(
                  top: BorderSide(color: Color(0x22FFFFFF), width: 0.8),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      offer.displayName ?? 'Unknown Skin',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (onWishlistToggle != null) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: onWishlistToggle,
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
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── VP price chip ─────────────────────────────────────────────────────────────

class _VpChip extends StatelessWidget {
  const _VpChip({required this.price});
  final int price;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF070C14).withAlpha(220),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: const Color(0xFF00F0FF).withAlpha(120),
          width: 0.9,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00F0FF).withAlpha(35),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const VpIcon(size: 11, color: Color(0xFF00F0FF)),
          const SizedBox(width: 5),
          Text(
            price.toString(),
            style: const TextStyle(
              color: Color(0xFF00F0FF),
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ],
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
