import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/providers.dart';
import '../../../shared/utils/app_colors.dart';
import '../data/oauth_flow.dart';
import '../domain/models/rso_auth_result.dart';
import 'multifactor_dialog.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _rememberMe = true;
  bool _isLoading = false;
  String? _errorMessage;

  late OAuthAttempt _currentAttempt;

  @override
  void initState() {
    super.initState();
    _currentAttempt = OAuthAttempt.create();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleNativeLogin() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter both Username and Password.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repo = await ref.read(authRepositoryProvider.future);
      _currentAttempt = OAuthAttempt.create();

      final result = await repo.loginNative(
        username: username,
        password: password,
        rememberMe: _rememberMe,
        attempt: _currentAttempt,
      );

      if (!mounted) return;

      if (result is RsoAuthSuccess) {
        await _finalizeLogin(result.redirectUrl);
      } else if (result is RsoAuthMultifactor) {
        setState(() => _isLoading = false);
        _show2faDialog(result);
      } else if (result is RsoAuthError) {
        setState(() {
          _isLoading = false;
          _errorMessage = result.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Login failed: ${e.toString().replaceAll('AuthException: ', '')}';
        });
      }
    }
  }

  void _show2faDialog(RsoAuthMultifactor challenge) async {
    final verified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => MultifactorDialog(
        challenge: challenge,
        onVerify: (code, rememberDevice) async {
          final repo = await ref.read(authRepositoryProvider.future);
          final res = await repo.submit2faCode(
            code: code,
            rememberDevice: rememberDevice,
          );

          if (res is RsoAuthSuccess) {
            await _finalizeLogin(res.redirectUrl);
          } else if (res is RsoAuthError) {
            throw Exception(res.message);
          } else {
            throw Exception('Unexpected verification response.');
          }
        },
      ),
    );

    if (verified != true && mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _finalizeLogin(String redirectUrl) async {
    try {
      final repo = await ref.read(authRepositoryProvider.future);
      final creds = await repo.completeLoginFromRedirectUrl(
        redirectUrl,
        _currentAttempt,
      );

      // Attempt to resolve real Riot ID display name and Player Card Avatar
      try {
        final source = await ref.read(accountRemoteSourceProvider.future);
        final loadoutSource = await ref.read(loadoutRemoteSourceProvider.future);
        final assets = ref.read(valorantAssetsProvider);
        final localSource = ref.read(credentialsLocalSourceProvider);

        final realName = await source.fetchDisplayName(
          creds.shard,
          creds.puuid,
          accessToken: creds.accessToken,
        );
        String? avatarUrl;
        String? cardId;

        try {
          final rawLoadout =
              await loadoutSource.fetchLoadoutRaw(creds.shard, creds.puuid);
          final loadoutRoot = rawLoadout.containsKey('Loadout')
              ? (rawLoadout['Loadout'] as Map<String, dynamic>? ?? {})
              : rawLoadout;
          final identity = loadoutRoot['Identity'] as Map<String, dynamic>? ??
              rawLoadout['Identity'] as Map<String, dynamic>? ??
              {};
          cardId = identity['PlayerCardID'] as String? ??
              loadoutRoot['PlayerCardID'] as String? ??
              rawLoadout['PlayerCardID'] as String?;
          if (cardId != null && cardId.isNotEmpty) {
            final cardsMap = await assets.getPlayerCardsMap();
            final cardInfo = (cardsMap[cardId] ??
                cardsMap[cardId.toLowerCase()]) as Map<String, dynamic>?;
            avatarUrl = cardInfo?['smallArt'] as String? ??
                cardInfo?['displayIcon'] as String?;
          }
        } catch (_) {}

        await localSource.save(
          creds,
          displayName: (realName != null && realName.isNotEmpty) ? realName : null,
          playerCardId: cardId,
          avatarUrl: avatarUrl,
        );
      } catch (_) {}

      // Invalidate credentials & session providers so router and UI pick up the new session
      ref.read(sessionActionsProvider).invalidateSession();

      if (mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        } else {
          context.go('/shop');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to save session: $e';
        });
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
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Logo
                    const _ValAppLogo(),
                    const SizedBox(height: 32),

                    // Error banner
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.red.withAlpha(38),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppColors.red.withAlpha(128)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                color: AppColors.red, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Username Field
                    const Text(
                      'USERNAME',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _usernameController,
                      enabled: !_isLoading,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        hintText: 'Riot Account Username',
                        hintStyle: const TextStyle(color: AppColors.textMuted),
                        prefixIcon: const Icon(Icons.person_outline_rounded,
                            color: AppColors.red, size: 20),
                        filled: true,
                        fillColor: AppColors.bgCard,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                              color: AppColors.red, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Password Field
                    const Text(
                      'PASSWORD',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _passwordController,
                      enabled: !_isLoading,
                      obscureText: _obscurePassword,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _handleNativeLogin(),
                      decoration: InputDecoration(
                        hintText: 'Riot Account Password',
                        hintStyle: const TextStyle(color: AppColors.textMuted),
                        prefixIcon: const Icon(Icons.lock_outline_rounded,
                            color: AppColors.red, size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: AppColors.textSecondary,
                            size: 20,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                        filled: true,
                        fillColor: AppColors.bgCard,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                              color: AppColors.red, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Stay Signed In Checkbox
                    GestureDetector(
                      onTap: _isLoading
                          ? null
                          : () {
                              setState(() {
                                _rememberMe = !_rememberMe;
                              });
                            },
                      child: Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: _rememberMe,
                              onChanged: _isLoading
                                  ? null
                                  : (val) {
                                      setState(() {
                                        _rememberMe = val ?? true;
                                      });
                                    },
                              activeColor: AppColors.red,
                              checkColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              side: const BorderSide(color: AppColors.border),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Stay signed in',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Login Button
                    GestureDetector(
                      onTap: _isLoading ? null : _handleNativeLogin,
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: AppColors.redGradient,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: AppColors.redGlow(alpha: 0.4, blur: 20),
                        ),
                        child: Center(
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'LOG IN',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 2,
                                  ),
                                ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Divider or
                    Row(
                      children: [
                        Expanded(
                          child: Container(height: 1, color: AppColors.border),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'OR',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Container(height: 1, color: AppColors.border),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Fallback Web Login button
                    OutlinedButton(
                      onPressed: _isLoading
                          ? null
                          : () => context.push('/login/webview'),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.open_in_browser_rounded,
                              color: AppColors.textSecondary, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'LOGIN WITH RIOT WEBVIEW',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),
                    const _SecurityRow(),
                    const SizedBox(height: 12),
                    const _DisclaimerText(),
                  ],
                ),
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
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.redSubtle,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.red, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: AppColors.red.withAlpha(80),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Center(
            child: CustomPaint(
              size: const Size(32, 32),
              painter: _VLogoPainter(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'VALAPP',
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: 8,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(width: 24, height: 1.5, color: AppColors.red),
            const SizedBox(width: 8),
            const Text(
              'SHOP MONITOR',
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

class _VLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.red
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * 0.38, 0)
      ..lineTo(size.width * 0.5, size.height * 0.55)
      ..lineTo(size.width * 0.62, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width * 0.5, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
              'SECURE RIOT RSO LOGIN — Credentials are not stored by this app',
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
