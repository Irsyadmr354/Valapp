import 'package:flutter/material.dart';

/// Maps Valorant content tier names and UUIDs to their representative colors.
/// Colors sourced from valorant-api.com/v1/contenttiers `highlightColor` field.
class TierColors {
  TierColors._();

  static const Map<String, Color> byName = {
    'Select': Color(0xFF5A9FE2), // light blue
    'Deluxe': Color(0xFF009587), // teal/green
    'Premium': Color(0xFFD1548D), // pink/magenta
    'Ultra': Color(0xFFFAD663), // gold/yellow
    'Exclusive': Color(0xFFF5955B), // orange/amber
    'Melee': Color(0xFF6C4B2A),
  };

  /// Known content tier UUIDs from valorant-api.com.
  static const Map<String, Color> byUuid = {
    '12683d76-48d7-84a3-4e09-6985794f0445': Color(0xFF5A9FE2), // Select
    '0cebb8be-46d7-c12a-d306-e9907bfc5a25': Color(0xFF009587), // Deluxe
    '60bca009-4182-7998-dee7-b8a2558dc369': Color(0xFFD1548D), // Premium
    '411e4a55-4e59-7757-41f0-86a53f101bb5': Color(0xFFFAD663), // Ultra
    'e046854e-406c-37f4-6607-19a9ba8426fc': Color(0xFFF5955B), // Exclusive
  };

  /// Display names keyed by content tier UUID (valorant-api.com/v1/contenttiers).
  static const Map<String, String> tierDisplayNames = {
    '12683d76-48d7-84a3-4e09-6985794f0445': 'Select Edition',
    '0cebb8be-46d7-c12a-d306-e9907bfc5a25': 'Deluxe Edition',
    '60bca009-4182-7998-dee7-b8a2558dc369': 'Premium Edition',
    '411e4a55-4e59-7757-41f0-86a53f101bb5': 'Ultra Edition',
    'e046854e-406c-37f4-6607-19a9ba8426fc': 'Exclusive Edition',
  };

  /// Resolves display label from content tier UUID.
  static String tierLabel(String? tierUuid) {
    if (tierUuid == null || tierUuid.isEmpty) return 'Skin Offer';
    return tierDisplayNames[tierUuid.toLowerCase()] ?? 'Skin Offer';
  }

  /// Resolves label using UUID prefix matching (works with full or partial UUIDs).
  /// Falls back to [tierLabel] for exact-UUID lookups.
  /// Returns 'Standard Edition' when the UUID is absent.
  static String tierLabelForUuid(String? tierUuid) {
    if (tierUuid == null || tierUuid.isEmpty) return 'Standard Edition';
    final uuid = tierUuid.toLowerCase();
    if (uuid.contains('12683d76')) return 'Select Edition';
    if (uuid.contains('0cebb8be')) return 'Deluxe Edition';
    if (uuid.contains('60bca009')) return 'Premium Edition';
    if (uuid.contains('411e4a55')) return 'Ultra Edition';
    if (uuid.contains('e046854e')) return 'Exclusive Edition';
    return tierLabel(tierUuid);
  }

  /// Resolves color using UUID prefix matching.
  /// Returns the game-accurate palette color for each tier — Premium uses
  /// [Color(0xFFD1548D)] (pink/magenta) matching the official Valorant palette.
  /// Note: [wishlist_catalog_screen] intentionally overrides Premium to
  /// [AppColors.red] for brand consistency; use [forName] directly if you
  /// need that variant.
  static Color tierColorForUuid(String? tierUuid) {
    if (tierUuid == null || tierUuid.isEmpty) return const Color(0xFF5A9FE2);
    final uuid = tierUuid.toLowerCase();
    if (uuid.contains('12683d76')) return const Color(0xFF5A9FE2); // Select
    if (uuid.contains('0cebb8be')) return const Color(0xFF009587); // Deluxe
    if (uuid.contains('60bca009')) return const Color(0xFFD1548D); // Premium
    if (uuid.contains('411e4a55')) return const Color(0xFFFAD663); // Ultra
    if (uuid.contains('e046854e')) return const Color(0xFFF5955B); // Exclusive
    return forName(tierUuid);
  }

  /// Resolves representative color for competitive rank tiers (0-27).
  static Color forCompetitiveTier(int tier) {
    if (tier >= 27) return const Color(0xFFFFF7C0); // Radiant
    if (tier >= 24) return const Color(0xFFBB384E); // Immortal
    if (tier >= 21) return const Color(0xFF45B07B); // Ascendant
    if (tier >= 18) return const Color(0xFFB064DD); // Diamond
    if (tier >= 15) return const Color(0xFF3FB3BE); // Platinum
    if (tier >= 12) return const Color(0xFFE2B742); // Gold
    if (tier >= 9) return const Color(0xFFB0B9C6); // Silver
    if (tier >= 6) return const Color(0xFFA67C52); // Bronze
    if (tier >= 3) return const Color(0xFF6A7079); // Iron
    return const Color(0xFF202732); // Unranked
  }

  /// Resolves color from either UUID or name.
  static Color forName(String? identifier) {
    if (identifier == null) return Colors.grey;

    // Try UUID first (case-insensitive)
    final byUuidMatch = byUuid[identifier.toLowerCase()];
    if (byUuidMatch != null) return byUuidMatch;

    // Try name match
    for (final entry in byName.entries) {
      if (identifier.toLowerCase().contains(entry.key.toLowerCase())) {
        return entry.value;
      }
    }
    return Colors.grey;
  }
}
