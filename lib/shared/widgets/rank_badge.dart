import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Displays a competitive rank badge (icon + tier name + RR).
class RankBadge extends StatelessWidget {
  const RankBadge({
    super.key,
    required this.tierName,
    required this.rankedRating,
    this.iconUrl,
    this.large = false,
  });

  final String tierName;
  final int rankedRating;
  final String? iconUrl;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final iconSize = large ? 96.0 : 44.0;
    final nameSize = large ? 22.0 : 13.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Rank icon
        SizedBox(
          width: iconSize,
          height: iconSize,
          child: iconUrl != null && iconUrl!.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: iconUrl!,
                  fit: BoxFit.contain,
                  placeholder: (_, __) => const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFFFF4655)),
                    ),
                  ),
                  errorWidget: (_, __, ___) =>
                      const Icon(Icons.shield, color: Colors.white38, size: 48),
                )
              : const Icon(Icons.shield, color: Colors.white38, size: 48),
        ),
        const SizedBox(height: 10),

        // Tier name
        Text(
          tierName.toUpperCase(),
          style: TextStyle(
            color: Colors.white,
            fontSize: nameSize,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

