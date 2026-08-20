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

    // Flat tier-tinted background with deep dark base
    final bgColor = Color.alphaBlend(
      tierColor.withAlpha(32),
      const Color(0xFF0A0F17),
    );

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isHighlighted
              ? const Color(0xFFFF4655)
              : Colors.white.withAlpha(22),
          width: isHighlighted ? 1.8 : 1.0,
        ),
        boxShadow: isHighlighted
            ? [
                BoxShadow(
                  color: const Color(0xFFFF4655).withAlpha(60),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withAlpha(90),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Image area ─────────────────────────────────────────────────
            Expanded(
              child: Stack(
                children: [
                  // Subtle tactical corner indicator
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: tierColor.withAlpha(180),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),

                  // Skin image
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
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

                  // Top-right: Action pill button to inspect details (Chromas & Levels)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B1017).withAlpha(220),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.white.withAlpha(30),
                          width: 1,
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'INSPECT',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                            ),
                          ),
                          SizedBox(width: 3),
                          Icon(
                            Icons.arrow_forward_rounded,
                            color: Color(0xFFFF4655),
                            size: 11,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Footer (Black Background): Tier Icon + Name + VP Price ────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: const BoxDecoration(
                color: Color(0xFF06090E), // Solid deep tactical background
                border: Border(
                  top: BorderSide(color: Color(0x1FFFFFFF), width: 0.8),
                ),
              ),
              child: Row(
                children: [
                  // Skin Tier Icon (only the icon) to the left of skin name
                  SkinTierIcon(
                    tierUuid: offer.contentTierUuid,
                    size: 17,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      offer.displayName ?? 'Unknown Skin',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // VP Price chip placed in footer
                  if (offer.price > 0) ...[
                    const SizedBox(width: 6),
                    _VpChip(price: offer.price),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const VpIcon(size: 16, color: Colors.white),
        const SizedBox(width: 5),
        Text(
          price.toString(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
      ],
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
