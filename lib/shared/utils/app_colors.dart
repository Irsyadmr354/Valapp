import 'package:flutter/material.dart';

/// Single source of truth for the Valorant-red accent system.
///
/// Rules:
/// - [red] is the ONE primary accent: buttons, active nav, section bars,
///   progress fills, borders, glow.
/// - [redDark] is used only for box-shadows / deep glows.
/// - [vpCyan] / [rpAmber] / [kcGreen] are semantic-only (currency colors).
/// - [win] / [loss] are semantic-only (match result colors).
/// - Purple is fully removed from the accent palette.
class AppColors {
  AppColors._();

  // ── Primary accent ─────────────────────────────────────────────────────────
  static const Color red = Color(0xFFFF4655); // Valorant signature red
  static const Color redDark = Color(0xFFC13040); // deep red for shadows
  static const Color redSubtle = Color(0xFF3A1118); // very dark red for fills

  // ── App Backgrounds ────────────────────────────────────────────────────────
  static const Color bg = Color(0xFF060810); // deepest background
  static const Color bgCard = Color(0xFF0D1117); // card surface
  static const Color bgCard2 = Color(0xFF111823); // secondary card / list item
  static const Color bgPanel = Color(0xFF0A0F18); // panel / app bar bg

  // ── Text ───────────────────────────────────────────────────────────────────
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFFAFB8C4);
  static const Color textMuted = Color(0xFF5C6B7A);

  // ── Currency (semantic only, NOT used as UI accent) ────────────────────────
  static const Color vpCyan = Color(0xFF00C8D4); // VP — muted teal
  static const Color rpAmber = Color(0xFFFF9900); // RP — amber
  static const Color kcGreen = Color(0xFF10B981); // KC — green

  // ── Match result (semantic) ────────────────────────────────────────────────
  static const Color win = Color(0xFF10B981); // green for Victory
  static const Color loss = Color(0xFFFF4655); // red  for Defeat (= red accent)
  static const Color draw = Color(0xFF5C6B7A); // grey for Draw

  // ── Borders ────────────────────────────────────────────────────────────────
  static const Color border = Color(0xFF1A2332);
  static const Color borderAccent =
      Color(0xFF3A1A1E); // subtle red-tinted border

  // ── Neutral grey / alt surfaces ────────────────────────────────────────────
  static const Color mutedGrey = Color(0xFF6B7280); // inactive / disabled grey
  static const Color borderAlt = Color(0xFF1F2937); // lighter alt border
  static const Color bgDeep = Color(0xFF070A10); // deep scrim / backdrop

  // ── Gradients ──────────────────────────────────────────────────────────────
  static const LinearGradient redGradient = LinearGradient(
    colors: [red, redDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [bgCard2, bgCard],
  );

  // ── Helper: red glow box shadow ────────────────────────────────────────────
  static List<BoxShadow> redGlow({double alpha = 0.25, double blur = 16}) => [
        BoxShadow(
          color: red.withAlpha((alpha * 255).round()),
          blurRadius: blur,
          spreadRadius: blur * 0.1,
        ),
      ];
}
