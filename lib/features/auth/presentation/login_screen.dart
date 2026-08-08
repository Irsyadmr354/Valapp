import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/utils/app_colors.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          // Diagonal slash pattern background
          const Positioned.fill(child: _SlashPatternBackground()),
          // Red radial glow top-center
          Positioned(
            top: -80,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 340,
                height: 340,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.red.withAlpha(55),
                      AppColors.red.withAlpha(0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(flex: 2),
                  // Logo
                  const _ValAppLogo(),
                  const SizedBox(height: 48),
                  // Tagline
                  const Text(
                    'Sign in with your official Riot Games account to access your\nshop, rank, match history and profile.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      height: 1.55,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  // Login button
                  _LoginButton(onTap: () => context.push('/login/webview')),
                  const Spacer(flex: 3),
                  // Security row
                  const _SecurityRow(),
                  const SizedBox(height: 12),
                  const _DisclaimerText(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Background & Logo ─────────────────────────────────────────────────────────

class _SlashPatternBackground extends StatelessWidget {
  const _SlashPatternBackground();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SlashPainter(),
    );
  }
}

class _SlashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.red.withAlpha(12)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    const spacing = 28.0;
    final diagonal =
        math.sqrt(size.width * size.width + size.height * size.height);
    final count = (diagonal / spacing).ceil() + 4;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-math.pi / 5);

    final start = -diagonal / 2 - spacing * 2;
    for (var i = 0; i < count; i++) {
      final x = start + i * spacing;
      canvas.drawLine(
        Offset(x, -diagonal),
        Offset(x, diagonal),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ValAppLogo extends StatelessWidget {
  const _ValAppLogo();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          'VALAPP',
          style: TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.w900,
            letterSpacing: 8,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(width: 28, height: 1.5, color: AppColors.red),
            const SizedBox(width: 10),
            const Text(
              'ACCOUNT MONITORING',
              style: TextStyle(
                color: AppColors.red,
                fontSize: 11,
                letterSpacing: 3,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 10),
            Container(width: 28, height: 1.5, color: AppColors.red),
          ],
        ),
      ],
    );
  }
}

class _LoginButton extends StatelessWidget {
  const _LoginButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          gradient: AppColors.redGradient,
          borderRadius: BorderRadius.circular(8),
          boxShadow: AppColors.redGlow(alpha: 0.4, blur: 20),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.open_in_browser_rounded, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Text(
              'LOGIN WITH RIOT',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecurityRow extends StatelessWidget {
  const _SecurityRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bgCard2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: const Row(
        children: [
          Icon(Icons.shield_outlined, color: AppColors.red, size: 16),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'SECURE RIOT OAUTH — Credentials are never stored by this app',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DisclaimerText extends StatelessWidget {
  const _DisclaimerText();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Unofficial Valorant companion app for personal use only.\nNot affiliated with or endorsed by Riot Games.',
      style: TextStyle(color: AppColors.textMuted, fontSize: 11, height: 1.4),
      textAlign: TextAlign.center,
    );
  }
}
