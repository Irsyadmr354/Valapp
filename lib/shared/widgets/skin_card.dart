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

                  // Top-right: Action pill button to inspect details (Chromas & Levels)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(160),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withAlpha(38),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(90),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'INSPECT',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_rounded,
                            color: Color(0xFFFF4655),
                            size: 12,
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: const BoxDecoration(
                color: Colors.black, // Solid black background
                border: Border(
                  top: BorderSide(color: Color(0x22FFFFFF), width: 0.8),
                ),
              ),
              child: Row(
                children: [
                  // Skin Tier Icon (only the icon) to the left of skin name
                  SkinTierIcon(
                    tierUuid: offer.contentTierUuid,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
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
                  // VP Price chip placed in footer (where bookmark used to be)
                  if (offer.price > 0) ...[
                    const SizedBox(width: 8),
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
