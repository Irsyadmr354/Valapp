import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../constants/valorant_constants.dart';
import '../utils/app_colors.dart';

/// Official Riot CDN URLs for Valorant In-Game Currencies.
class ValorantCurrencyUrls {
  ValorantCurrencyUrls._();

  static const vp = ValorantCurrencies.vpCdnUrl;
  static const kc = ValorantCurrencies.kcCdnUrl;
  static const rp = ValorantCurrencies.rpCdnUrl;
}

/// Official Riot CDN URLs for Content Tiers (Skin Editions - Gambar 1).
class ValorantContentTierUrls {
  ValorantContentTierUrls._();

  static const select = ValorantContentTiers.selectCdnUrl;
  static const deluxe = ValorantContentTiers.deluxeCdnUrl;
  static const premium = ValorantContentTiers.premiumCdnUrl;
  static const ultra = ValorantContentTiers.ultraCdnUrl;
  static const exclusive = ValorantContentTiers.exclusiveCdnUrl;

  static String? forUuid(String? uuid) => ValorantContentTiers.cdnUrlForUuid(uuid);
}

// ── Gambar 2: Valorant Points (VP) Icon ─────────────────────────────────────

/// Official Valorant Points (VP) Icon (Gambar 2).
/// Displays the official Riot PNG asset with a pixel-perfect CustomPainter vector fallback.
class VpIcon extends StatelessWidget {
  const VpIcon({super.key, this.size = 14, this.color = const Color(0xFF00F0FF)});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CachedNetworkImage(
        imageUrl: ValorantCurrencyUrls.vp,
        width: size,
        height: size,
        fit: BoxFit.contain,
        placeholder: (_, __) => CustomPaint(painter: VpIconPainter(color: color)),
        errorWidget: (_, __, ___) =>
            CustomPaint(painter: VpIconPainter(color: color)),
      ),
    );
  }
}

/// CustomPainter matching Gambar 2: Circular ring surrounding the official Valorant V emblem.
class VpIconPainter extends CustomPainter {
  const VpIconPainter({this.color = const Color(0xFF00F0FF)});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    final radius = w / 2 - 1.0;

    // 1. Outer circle ring
    final circlePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, w * 0.10);
    canvas.drawCircle(center, radius, circlePaint);

    // 2. Valorant V emblem inside
    // Left long slash
    final leftSlash = Path()
      ..moveTo(w * 0.27, h * 0.33)
      ..lineTo(w * 0.50, h * 0.68)
      ..lineTo(w * 0.40, h * 0.68)
      ..lineTo(w * 0.27, h * 0.50)
      ..close();

    // Right top slash / triangle
    final rightSlash = Path()
      ..moveTo(w * 0.53, h * 0.56)
      ..lineTo(w * 0.70, h * 0.33)
      ..lineTo(w * 0.70, h * 0.56)
      ..close();

    final emblemPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawPath(leftSlash, emblemPaint);
    canvas.drawPath(rightSlash, emblemPaint);
  }

  @override
  bool shouldRepaint(covariant VpIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

// ── Gambar 3: Kingdom Credits (KC) Icon ─────────────────────────────────────

/// Official Kingdom Credits (KC) Icon (Gambar 3).
/// Displays the official Riot PNG asset with a pixel-perfect CustomPainter vector fallback.
class KcIcon extends StatelessWidget {
  const KcIcon({super.key, this.size = 14, this.color = const Color(0xFF10B981)});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CachedNetworkImage(
        imageUrl: ValorantCurrencyUrls.kc,
        width: size,
        height: size,
        fit: BoxFit.contain,
        placeholder: (_, __) => CustomPaint(painter: KcIconPainter(color: color)),
        errorWidget: (_, __, ___) =>
            CustomPaint(painter: KcIconPainter(color: color)),
      ),
    );
  }
}

/// CustomPainter matching Gambar 3: Tilted rounded card container containing Kingdom emblem.
class KcIconPainter extends CustomPainter {
  const KcIconPainter({this.color = const Color(0xFF10B981)});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    canvas.save();
    // Rotate canvas by ~-32 degrees around center
    canvas.translate(w / 2, h / 2);
    canvas.rotate(-0.55);
    canvas.translate(-w / 2, -h / 2);

    // Tilted rounded card border
    final cardRect = Rect.fromLTWH(w * 0.08, h * 0.18, w * 0.84, h * 0.64);
    final cardRRect = RRect.fromRectAndRadius(cardRect, Radius.circular(w * 0.15));

    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, w * 0.11);
    canvas.drawRRect(cardRRect, borderPaint);

    // Stylized Kingdom K emblem inside
    final topDiamond1 = Path()
      ..moveTo(w * 0.32, h * 0.44)
      ..lineTo(w * 0.42, h * 0.32)
      ..lineTo(w * 0.50, h * 0.44)
      ..lineTo(w * 0.40, h * 0.56)
      ..close();

    final topDiamond2 = Path()
      ..moveTo(w * 0.45, h * 0.32)
      ..lineTo(w * 0.56, h * 0.20)
      ..lineTo(w * 0.65, h * 0.32)
      ..lineTo(w * 0.54, h * 0.44)
      ..close();

    final bottomStem = Path()
      ..moveTo(w * 0.40, h * 0.56)
      ..lineTo(w * 0.54, h * 0.44)
      ..lineTo(w * 0.72, h * 0.66)
      ..lineTo(w * 0.52, h * 0.66)
      ..close();

    final kPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawPath(topDiamond1, kPaint);
    canvas.drawPath(topDiamond2, kPaint);
    canvas.drawPath(bottomStem, kPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant KcIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

// ── Radianite Points (RP) Icon ──────────────────────────────────────────────

/// Official Radianite Points (RP) Icon.
class RpIcon extends StatelessWidget {
  const RpIcon({super.key, this.size = 14, this.color = const Color(0xFFFF9900)});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CachedNetworkImage(
        imageUrl: ValorantCurrencyUrls.rp,
        width: size,
        height: size,
        fit: BoxFit.contain,
        placeholder: (_, __) => CustomPaint(painter: RpIconPainter(color: color)),
        errorWidget: (_, __, ___) =>
            CustomPaint(painter: RpIconPainter(color: color)),
      ),
    );
  }
}

class RpIconPainter extends CustomPainter {
  const RpIconPainter({this.color = const Color(0xFFFF9900)});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final topRhombus = Path()
      ..moveTo(w * 0.5, 0)
      ..lineTo(w * 0.95, h * 0.35)
      ..lineTo(w * 0.5, h * 0.7)
      ..lineTo(w * 0.05, h * 0.35)
      ..close();

    final bottomFacet = Path()
      ..moveTo(w * 0.05, h * 0.35)
      ..lineTo(w * 0.5, h * 0.7)
      ..lineTo(w * 0.5, h)
      ..lineTo(w * 0.2, h * 0.75)
      ..close();

    final rightFacet = Path()
      ..moveTo(w * 0.95, h * 0.35)
      ..lineTo(w * 0.5, h * 0.7)
      ..lineTo(w * 0.5, h)
      ..lineTo(w * 0.8, h * 0.75)
      ..close();

    final topPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final leftShadowPaint = Paint()
      ..color = Color.alphaBlend(Colors.black.withAlpha(100), color)
      ..style = PaintingStyle.fill;

    final rightShadowPaint = Paint()
      ..color = Color.alphaBlend(Colors.black.withAlpha(60), color)
      ..style = PaintingStyle.fill;

    canvas.drawPath(topRhombus, topPaint);
    canvas.drawPath(bottomFacet, leftShadowPaint);
    canvas.drawPath(rightFacet, rightShadowPaint);
  }

  @override
  bool shouldRepaint(covariant RpIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

// ── Gambar 1: Content Tier Icons (Select, Deluxe, Premium, Ultra, Exclusive) ────

/// Official Skin Tier Icon Widget (Gambar 1).
/// Displays the official Riot CDN PNG icon for the skin edition with a CustomPainter fallback matching Gambar 1!
class SkinTierIcon extends StatelessWidget {
  const SkinTierIcon({
    super.key,
    required this.tierUuid,
    this.size = 16,
  });

  final String? tierUuid;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = ValorantContentTierUrls.forUuid(tierUuid);

    if (url != null) {
      return SizedBox(
        width: size,
        height: size,
        child: CachedNetworkImage(
          imageUrl: url,
          width: size,
          height: size,
          fit: BoxFit.contain,
          placeholder: (_, __) => _buildFallbackVector(tierUuid, size),
          errorWidget: (_, __, ___) => _buildFallbackVector(tierUuid, size),
        ),
      );
    }

    return _buildFallbackVector(tierUuid, size);
  }

  Widget _buildFallbackVector(String? uuid, double size) {
    final lower = (uuid ?? '').toLowerCase();

    if (lower.contains('12683d76')) {
      // Select Edition (Blue circle ring)
      return SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _SelectTierPainter(),
        ),
      );
    }
    if (lower.contains('0cebb8be')) {
      // Deluxe Edition (Teal tilted diamond)
      return SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _DeluxeTierPainter(),
        ),
      );
    }
    if (lower.contains('60bca009')) {
      // Premium Edition (Purple inverted triangle)
      return SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _PremiumTierPainter(),
        ),
      );
    }
    if (lower.contains('411e4a55')) {
      // Ultra Edition (Gold 3D diamond)
      return SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _UltraTierPainter(),
        ),
      );
    }
    if (lower.contains('e046854e')) {
      // Exclusive Edition (Orange pentagon)
      return SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _ExclusiveTierPainter(),
        ),
      );
    }

    // Default fallback circle
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF5A9FE2).withAlpha(50),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF5A9FE2), width: 1.2),
      ),
    );
  }
}

// ── CustomPainters for Gambar 1 Fallbacks ───────────────────────────────────

class _SelectTierPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1.0;
    final paint = Paint()
      ..color = const Color(0xFF5A9FE2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.22;
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DeluxeTierPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.5, 0)
      ..lineTo(w, h * 0.5)
      ..lineTo(w * 0.5, h)
      ..lineTo(0, h * 0.5)
      ..close();
    final paint = Paint()
      ..color = const Color(0xFF009587)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.20;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PremiumTierPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w * 0.5, h)
      ..close();
    final paint = Paint()
      ..color = const Color(0xFFD1548D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.20;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _UltraTierPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.5, 0)
      ..lineTo(w, h * 0.5)
      ..lineTo(w * 0.5, h)
      ..lineTo(0, h * 0.5)
      ..close();
    final paint = Paint()
      ..color = const Color(0xFFFAD663)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.22;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ExclusiveTierPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.5, 0)
      ..lineTo(w, h * 0.38)
      ..lineTo(w * 0.81, h)
      ..lineTo(w * 0.19, h)
      ..lineTo(0, h * 0.38)
      ..close();
    final paint = Paint()
      ..color = const Color(0xFFF5955B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.20;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Shared Widgets ──────────────────────────────────────────────────────────

/// Premium Tactical Currency Chip with Glowing Edges & Official Riot Icon
class ValorantCurrencyChip extends StatelessWidget {
  const ValorantCurrencyChip({
    super.key,
    required this.amount,
    required this.type, // 'VP', 'RP', 'KC'
    this.compact = false,
  });

  final int amount;
  final String type;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final Widget icon;

    switch (type.toUpperCase()) {
      case 'RP':
        color = AppColors.rpAmber;
        icon = RpIcon(size: compact ? 16 : 18, color: color);
        break;
      case 'KC':
        color = AppColors.kcGreen;
        icon = KcIcon(size: compact ? 16 : 18, color: color);
        break;
      case 'VP':
      default:
        color = AppColors.vpCyan;
        icon = VpIcon(size: compact ? 16 : 18, color: color);
        break;
    }

    final formatted = amount >= 10000
        ? '${(amount / 1000).toStringAsFixed(0)}k'
        : amount.toString();

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        icon,
        SizedBox(width: compact ? 5 : 6),
        Text(
          formatted,
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 14 : 15,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Tactical HUD Chamfered Container with Corner Brackets & Border Accent
class ValorantHudBox extends StatelessWidget {
  const ValorantHudBox({
    super.key,
    required this.child,
    this.accentColor = AppColors.red,
    this.padding = const EdgeInsets.all(12),
    this.showCornerBrackets = true,
    this.borderWidth = 1.0,
    this.backgroundColor = AppColors.bgCard,
  });

  final Widget child;
  final Color accentColor;
  final EdgeInsetsGeometry padding;
  final bool showCornerBrackets;
  final double borderWidth;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ChamferedHudPainter(
        accentColor: accentColor,
        borderWidth: borderWidth,
        showBrackets: showCornerBrackets,
        backgroundColor: backgroundColor,
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}

class _ChamferedHudPainter extends CustomPainter {
  const _ChamferedHudPainter({
    required this.accentColor,
    required this.borderWidth,
    required this.showBrackets,
    required this.backgroundColor,
  });

  final Color accentColor;
  final double borderWidth;
  final bool showBrackets;
  final Color backgroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const chamfer = 10.0;

    final path = Path()
      ..moveTo(chamfer, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h - chamfer)
      ..lineTo(w - chamfer, h)
      ..lineTo(0, h)
      ..lineTo(0, chamfer)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = backgroundColor
        ..style = PaintingStyle.fill,
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = accentColor.withAlpha(90)
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth,
    );

    if (showBrackets) {
      final bracketPaint = Paint()
        ..color = accentColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      canvas.drawLine(const Offset(0, 0), const Offset(6, 0), bracketPaint);
      canvas.drawLine(const Offset(0, 0), const Offset(0, 6), bracketPaint);

      canvas.drawLine(Offset(w, h), Offset(w - 6, h), bracketPaint);
      canvas.drawLine(Offset(w, h), Offset(w, h - 6), bracketPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ChamferedHudPainter oldDelegate) =>
      oldDelegate.accentColor != accentColor ||
      oldDelegate.borderWidth != borderWidth ||
      oldDelegate.backgroundColor != backgroundColor;
}
