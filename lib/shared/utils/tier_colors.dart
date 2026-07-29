import 'package:flutter/material.dart';

/// Maps Valorant content tier names to their representative colors.
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

  static Color forName(String? name) {
    if (name == null) return Colors.grey;
    for (final entry in byName.entries) {
      if (name.toLowerCase().contains(entry.key.toLowerCase())) {
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
