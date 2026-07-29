import 'package:flutter/material.dart';

/// Maps Valorant content tier names and UUIDs to their representative colors.
class TierColors {
  TierColors._();

  static const Map<String, Color> byName = {
    'Select': Color(0xFF009587),
    'Deluxe': Color(0xFF0D76CB),
    'Premium': Color(0xFF9B4DC1),
    'Ultra': Color(0xFFEFB843),
    'Exclusive': Color(0xFFFF4655),
    'Melee': Color(0xFF6C4B2A),
  };

  /// Known content tier UUIDs from valorant-api.com.
  static const Map<String, Color> byUuid = {
    '12683d76-48d7-84a3-4e09-6985794f0445': Color(0xFF009587), // Select
    '0cebb8be-46d7-c12a-d306-e9907bfc5a25': Color(0xFF0D76CB), // Deluxe
    '60bca009-4182-7998-dee7-b8a2558dc369': Color(0xFF9B4DC1), // Premium
    '411e4a55-4e59-7757-41f0-86a53f101bb5': Color(0xFFEFB843), // Ultra
    'e046854e-406c-37f4-6571-7a8baeeb93ab': Color(0xFFFF4655), // Exclusive
  };

  /// Resolves color from either UUID or name.
  static Color forName(String? identifier) {
    if (identifier == null) return Colors.grey;

    // Try UUID first
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

  /// Parses a hex color string like `"FF9B4DC1FF"` returned by valorant-api.com.
  static Color? fromHex(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    try {
      final cleaned = hex.replaceAll('#', '');
      if (cleaned.length == 8) {
        // RRGGBBAA → AARRGGBB
        final r = cleaned.substring(0, 2);
        final g = cleaned.substring(2, 4);
        final b = cleaned.substring(4, 6);
        final a = cleaned.substring(6, 8);
        return Color(int.parse('$a$r$g$b', radix: 16));
      } else if (cleaned.length == 6) {
        return Color(int.parse('FF$cleaned', radix: 16));
      }
    } catch (_) {}
    return null;
  }
}
