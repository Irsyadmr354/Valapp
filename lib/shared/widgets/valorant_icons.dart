import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

/// Authentic Valorant Points (VP) Icon Painter.
/// Draws the signature Valorant V-shaped rhombus diamond symbol with dual-facet shading.
class VpIconPainter extends CustomPainter {
  const VpIconPainter({this.color = const Color(0xFF00F0FF)});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Left facet path
    final leftPath = Path()
      ..moveTo(w * 0.5, 0)
      ..lineTo(w * 0.1, h * 0.45)
      ..lineTo(w * 0.42, h)
      ..lineTo(w * 0.42, h * 0.52)
      ..close();

    // Right facet path
    final rightPath = Path()
      ..moveTo(w * 0.5, 0)
      ..lineTo(w * 0.9, h * 0.45)
      ..lineTo(w * 0.58, h)
      ..lineTo(w * 0.58, h * 0.52)
      ..close();

    // Center V slice gap / accent path
    final centerV = Path()
      ..moveTo(w * 0.5, h * 0.22)
      ..lineTo(w * 0.3, h * 0.48)
      ..lineTo(w * 0.42, h * 0.88)
      ..lineTo(w * 0.5, h * 0.72)
      ..lineTo(w * 0.58, h * 0.88)
      ..lineTo(w * 0.7, h * 0.48)
      ..close();

    final mainPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final darkFacetPaint = Paint()
      ..color = Color.alphaBlend(Colors.black.withAlpha(80), color)
      ..style = PaintingStyle.fill;

    final brightAccentPaint = Paint()
      ..color = Colors.white.withAlpha(220)
      ..style = PaintingStyle.fill;

    canvas.drawPath(leftPath, mainPaint);
    canvas.drawPath(rightPath, darkFacetPaint);
    canvas.drawPath(centerV, brightAccentPaint);
  }

  @override
  bool shouldRepaint(covariant VpIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Widget wrapper for VP Icon
class VpIcon extends StatelessWidget {
  const VpIcon({super.key, this.size = 14, this.color = const Color(0xFF00F0FF)});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 1.15,
      child: CustomPaint(
        painter: VpIconPainter(color: color),
      ),
    );
  }
}

/// Authentic Radianite Points (RP) Icon Painter.
/// Draws the 3D layered crystal diamond structure of Radianite Points.
class RpIconPainter extends CustomPainter {
  const RpIconPainter({this.color = const Color(0xFFFF9900)});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Outer crystal diamond
    final topRhombus = Path()
      ..moveTo(w * 0.5, 0)
      ..lineTo(w * 0.95, h * 0.35)
      ..lineTo(w * 0.5, h * 0.7)
      ..lineTo(w * 0.05, h * 0.35)
      ..close();

    // Bottom crystal shadow facet
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

    final innerCore = Path()
      ..moveTo(w * 0.5, h * 0.15)
      ..lineTo(w * 0.78, h * 0.35)
      ..lineTo(w * 0.5, h * 0.55)
      ..lineTo(w * 0.22, h * 0.35)
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

    final highlightPaint = Paint()
      ..color = Colors.white.withAlpha(200)
      ..style = PaintingStyle.fill;

    canvas.drawPath(topRhombus, topPaint);
    canvas.drawPath(bottomFacet, leftShadowPaint);
    canvas.drawPath(rightFacet, rightShadowPaint);
    canvas.drawPath(innerCore, highlightPaint);
  }

  @override
  bool shouldRepaint(covariant RpIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Widget wrapper for RP Icon
class RpIcon extends StatelessWidget {
  const RpIcon({super.key, this.size = 14, this.color = const Color(0xFFFF9900)});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: RpIconPainter(color: color),
      ),
    );
  }
}

/// Authentic Kingdom Credits (KC) Icon Painter.
/// Draws the chamfered hexagon shield badge with inner KC emblem.
class KcIconPainter extends CustomPainter {
  const KcIconPainter({this.color = const Color(0xFF10B981)});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Hexagon shield outline
    final shieldPath = Path()
      ..moveTo(w * 0.3, 0)
      ..lineTo(w * 0.7, 0)
      ..lineTo(w, h * 0.3)
      ..lineTo(w, h * 0.7)
      ..lineTo(w * 0.5, h)
      ..lineTo(0, h * 0.7)
      ..lineTo(0, h * 0.3)
      ..close();

    final innerK = Path()
      ..moveTo(w * 0.35, h * 0.25)
      ..lineTo(w * 0.45, h * 0.25)
      ..lineTo(w * 0.45, h * 0.75)
      ..lineTo(w * 0.35, h * 0.75)
      ..close();

    final innerVLeft = Path()
      ..moveTo(w * 0.45, h * 0.5)
      ..lineTo(w * 0.7, h * 0.25)
      ..lineTo(w * 0.7, h * 0.38)
      ..lineTo(w * 0.56, h * 0.5)
      ..lineTo(w * 0.7, h * 0.62)
      ..lineTo(w * 0.7, h * 0.75)
      ..close();

    final bgPaint = Paint()
      ..color = Color.alphaBlend(Colors.black.withAlpha(120), color)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.1;

    final glyphPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawPath(shieldPath, bgPaint);
    canvas.drawPath(shieldPath, borderPaint);
    canvas.drawPath(innerK, glyphPaint);
    canvas.drawPath(innerVLeft, glyphPaint);
  }

  @override
  bool shouldRepaint(covariant KcIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Widget wrapper for KC Icon
class KcIcon extends StatelessWidget {
  const KcIcon({super.key, this.size = 14, this.color = const Color(0xFF10B981)});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: KcIconPainter(color: color),
      ),
    );
  }
}

/// Premium Tactical Currency Chip with Glowing Edges & Custom Icon
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
        icon = RpIcon(size: compact ? 12 : 14, color: color);
        break;
      case 'KC':
        color = AppColors.kcGreen;
        icon = KcIcon(size: compact ? 12 : 14, color: color);
        break;
      case 'VP':
      default:
        color = AppColors.vpCyan;
        icon = VpIcon(size: compact ? 11 : 13, color: color);
        break;
    }

    final formatted = amount >= 10000
        ? '${(amount / 1000).toStringAsFixed(0)}k'
        : amount.toString();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF070B12).withAlpha(220),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(110), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: color.withAlpha(35),
            blurRadius: 8,
            spreadRadius: 0.5,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAlignment.center,
        children: [
          icon,
          SizedBox(width: compact ? 4 : 6),
          Text(
            formatted,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
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

    // Chamfered path (45-degree top-left & bottom-right cut)
    final path = Path()
      ..moveTo(chamfer, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h - chamfer)
      ..lineTo(w - chamfer, h)
      ..lineTo(0, h)
      ..lineTo(0, chamfer)
      ..close();

    // Background fill
    canvas.drawPath(
      path,
      Paint()
        ..color = backgroundColor
        ..style = PaintingStyle.fill,
    );

    // Border line
    canvas.drawPath(
      path,
      Paint()
        ..color = accentColor.withAlpha(90)
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth,
    );

    // Corner crosshair brackets (+)
    if (showBrackets) {
      final bracketPaint = Paint()
        ..color = accentColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      // Top-Left bracket
      canvas.drawLine(const Offset(0, 0), const Offset(6, 0), bracketPaint);
      canvas.drawLine(const Offset(0, 0), const Offset(0, 6), bracketPaint);

      // Bottom-Right bracket
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
