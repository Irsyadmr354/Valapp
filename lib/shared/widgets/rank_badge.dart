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
    final iconSize = large ? 72.0 : 44.0;
    final nameSize = large ? 20.0 : 13.0;
    final rrSize = large ? 14.0 : 11.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Rank icon
        SizedBox(
          width: iconSize,
          height: iconSize,
          child: iconUrl != null
              ? CachedNetworkImage(
                  imageUrl: iconUrl!,
                  fit: BoxFit.contain,
                  placeholder: (_, __) =>
                      const CircularProgressIndicator(strokeWidth: 2),
                  errorWidget: (_, __, ___) =>
                      const Icon(Icons.shield, color: Colors.white38),
                )
              : const Icon(Icons.shield, color: Colors.white38),
        ),
        const SizedBox(height: 6),

        // Tier name
        Text(
          tierName,
          style: TextStyle(
            color: Colors.white,
            fontSize: nameSize,
            fontWeight: FontWeight.w700,
          ),
        ),

        // RR — hidden for immortal+ where RR isn't shown
        if (rankedRating > 0)
          Text(
            '$rankedRating RR',
            style: TextStyle(
              color: Colors.white54,
              fontSize: rrSize,
            ),
          ),
      ],
    );
  }
}
