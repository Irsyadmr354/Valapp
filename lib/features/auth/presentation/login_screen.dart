import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/providers.dart';
import '../../../shared/utils/app_colors.dart';
import '../data/credentials_local_source.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  List<SavedAccountProfile> _savedAccounts = [];
  bool _isLoadingAccounts = true;
  bool _isSwitching = false;

  @override
  void initState() {
    super.initState();
    _loadSavedAccounts();
  }

  Future<void> _loadSavedAccounts() async {
    try {
      final source = ref.read(credentialsLocalSourceProvider);
      final accounts = await source.getSavedAccounts();
      if (mounted) {
        setState(() {
          _savedAccounts = accounts;
          _isLoadingAccounts = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingAccounts = false);
      }
    }
  }

  Future<void> _handleSwitchAccount(SavedAccountProfile account) async {
    if (_isSwitching) return;
    setState(() => _isSwitching = true);
    try {
      await ref.read(sessionActionsProvider).switchAccount(account);
      // If successful, app.dart's auth listener handles navigation to /shop automatically
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal beralih akun: $e'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSwitching = false);
      }
    }
  }

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

          // Main Layout
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  const _ValAppLogo(),
                  const SizedBox(height: 12),
                  const Text(
                    'VALORANT ACCOUNT ACCESS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Saved Accounts or Main OAuth Login
                  Expanded(
                    child: _isLoadingAccounts
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.red,
                              strokeWidth: 2.5,
                            ),
                          )
                        : _savedAccounts.isNotEmpty
                            ? _buildSavedAccountsView()
                            : _buildDefaultLoginView(),
                  ),

                  const SizedBox(height: 16),
                  const _SecurityRow(),
                  const SizedBox(height: 10),
                  const _DisclaimerText(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultLoginView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Securely sign in through Riot Games OAuth to view your storefront, rank, and match history.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 12,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 32),

        // Primary Sleek Riot Sign-In Button
        GestureDetector(
          onTap: () => context.push('/login/webview'),
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              gradient: AppColors.redGradient,
              borderRadius: BorderRadius.circular(12),
              boxShadow: AppColors.redGlow(alpha: 0.45, blur: 24),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shield_outlined, color: Colors.white, size: 22),
                SizedBox(width: 12),
                Text(
                  'SIGN IN WITH RIOT GAMES',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Feature Pills Row
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _FeatureBadge(
              icon: Icons.key_rounded,
              label: 'iCloud Keychain',
            ),
            SizedBox(width: 8),
            _FeatureBadge(
              icon: Icons.fingerprint_rounded,
              label: 'FaceID Auto-Fill',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSavedAccountsView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 3,
              height: 12,
              color: AppColors.red,
            ),
            const SizedBox(width: 8),
            Text(
              'SAVED ACCOUNTS (${_savedAccounts.length})',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.separated(
            itemCount: _savedAccounts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final account = _savedAccounts[index];
              return _SavedAccountTile(
                account: account,
                isSwitching: _isSwitching,
                onTap: () => _handleSwitchAccount(account),
              );
            },
          ),
        ),
        const SizedBox(height: 12),

        // Sign in with new account button
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed:
                _isSwitching ? null : () => context.push('/login/webview'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: AppColors.red, width: 1.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.add_rounded, size: 20, color: AppColors.red),
            label: const Text(
              'ADD / LOGIN ANOTHER ACCOUNT',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SavedAccountTile extends StatelessWidget {
  const _SavedAccountTile({
    required this.account,
    required this.isSwitching,
    required this.onTap,
  });

  final SavedAccountProfile account;
  final bool isSwitching;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isSwitching ? null : onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.bgCard2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            // Avatar / Card Image
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF1E2328),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              clipBehavior: Clip.antiAlias,
              child: account.avatarUrl != null && account.avatarUrl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: account.avatarUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const Icon(
                        Icons.person_rounded,
                        color: Colors.white38,
                        size: 24,
                      ),
                    )
                  : const Icon(
                      Icons.person_rounded,
                      color: Colors.white38,
                      size: 24,
                    ),
            ),
            const SizedBox(width: 12),

            // Account details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.red.withAlpha(30),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          account.region.toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.red,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'PUUID: ${account.puuid.length > 8 ? account.puuid.substring(0, 8) : account.puuid}...',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Switch action icon
            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white38,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureBadge extends StatelessWidget {
  const _FeatureBadge({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.bgCard2,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.red, size: 13),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w700,
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
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: 8,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(width: 24, height: 1.5, color: AppColors.red),
            const SizedBox(width: 8),
            const Text(
              'ACCOUNT MONITORING',
              style: TextStyle(
                color: AppColors.red,
                fontSize: 10,
                letterSpacing: 3,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Container(width: 24, height: 1.5, color: AppColors.red),
          ],
        ),
      ],
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
              'SECURE RIOT RSO LOGIN — Credentials stored securely on-device only',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
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
      style: TextStyle(color: AppColors.textMuted, fontSize: 10, height: 1.4),
      textAlign: TextAlign.center,
    );
  }
}
