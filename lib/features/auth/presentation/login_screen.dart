import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../core/di/providers.dart';
import '../../../shared/utils/app_colors.dart';
import '../data/oauth_flow.dart';

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
  bool _isSubmittingJS = false;
  String? _errorMessage;

  late WebViewController _webViewController;
  late OAuthAttempt _attempt;

  @override
  void initState() {
    super.initState();
    _attempt = OAuthAttempt.create();
    _initOffscreenWebView();
  }

  void _initOffscreenWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0F1923))
      ..setUserAgent(
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) '
        'Version/17.0 Mobile/15E148 Safari/604.1',
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            _checkForToken(url);
          },
          onPageFinished: (url) {
            _checkForToken(url);
            if (_isSubmittingJS) {
              _injectCredentialsAndSubmit();
            }
          },
          onNavigationRequest: (request) {
            if (_checkForToken(request.url)) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (error) {
            final url = error.url ?? '';
            final uri = Uri.tryParse(url);
            if (uri != null && OAuthFlow.isRedirectUri(uri)) return;
            if (_isSubmittingJS && mounted) {
              setState(() {
                _isLoading = false;
                _isSubmittingJS = false;
                _errorMessage = 'Network error: ${error.description}';
              });
            }
          },
        ),
      );

    _webViewController.loadRequest(_attempt.authorizeUri);
  }

  bool _checkForToken(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null && OAuthFlow.isRedirectUri(uri)) {
      if (_isLoading || _isSubmittingJS) {
        _handleTokenRedirect(url);
        return true;
      }
    }
    return false;
  }

  Future<void> _handleNativeSubmit() async {
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
      _isSubmittingJS = true;
      _errorMessage = null;
    });

    final currentUrl = await _webViewController.currentUrl();
    if (currentUrl != null && currentUrl.contains('auth.riotgames.com')) {
      _injectCredentialsAndSubmit();
    } else {
      _attempt = OAuthAttempt.create();
      _webViewController.loadRequest(_attempt.authorizeUri);
    }
  }

  Future<void> _injectCredentialsAndSubmit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    final usernameEscaped =
        username.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
    final passwordEscaped =
        password.replaceAll('\\', '\\\\').replaceAll("'", "\\'");

    final js = '''
    (function() {
      function setReactInputValue(input, val) {
        if (!input) return false;
        var lastValue = input.value;
        input.value = val;
        var event = new Event('input', { bubbles: true });
        var tracker = input._valueTracker;
        if (tracker) {
          tracker.setValue(lastValue);
        }
        input.dispatchEvent(event);
        input.dispatchEvent(new Event('change', { bubbles: true }));
        input.dispatchEvent(new Event('blur', { bubbles: true }));
        return true;
      }

      function trySubmit() {
        var userInput = document.querySelector("input[name='username']") || document.querySelector("input[type='text']");
        var passInput = document.querySelector("input[name='password']") || document.querySelector("input[type='password']");

        if (userInput && passInput) {
          setReactInputValue(userInput, "$usernameEscaped");
          setReactInputValue(passInput, "$passwordEscaped");

          var rem = document.querySelector("input[name='remember'], input[type='checkbox']");
          if (rem && ${_rememberMe ? 'true' : 'false'}) {
            if (!rem.checked) {
              rem.click();
            }
          }

          setTimeout(function() {
            var btn = document.querySelector("button[type='submit']") || document.querySelector("button[data-testid='btn-signin']") || document.querySelector(".mobile-button") || document.querySelector("button");
            if (btn) {
              btn.click();
            }
          }, 350);
        }
      }

      trySubmit();
    })();
    ''';

    try {
      await _webViewController.runJavaScript(js);

      // Safety timer: If login doesn't redirect within 6 seconds, fall back cleanly to WebView
      Future.delayed(const Duration(seconds: 6), () async {
        if (!mounted || !_isLoading) return;
        final currentUrl = await _webViewController.currentUrl();
        if (currentUrl != null &&
            !OAuthFlow.isRedirectUri(Uri.parse(currentUrl))) {
          setState(() {
            _isLoading = false;
            _isSubmittingJS = false;
          });
          // Push WebView so user can see 2FA or Captcha prompt directly
          if (mounted) {
            context.push('/login/webview');
          }
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isSubmittingJS = false;
          _errorMessage = 'Failed to submit login: $e';
        });
      }
    }
  }

  Future<void> _handleTokenRedirect(String redirectUrl) async {
    if (!mounted) return;

    try {
      final tokens = OAuthFlow.parseTokenRedirect(
        redirectUrl,
        expectedState: _attempt.state,
        expectedNonce: _attempt.nonce,
      );
      final accessToken = tokens['access_token']!;
      final idToken = tokens['id_token']!;
      final expiresIn = int.parse(tokens['expires_in']!);

      final repo = await ref.read(authRepositoryProvider.future);
      if (!mounted) return;
      final creds = await repo.completeLoginFromWebView(
        accessToken: accessToken,
        idToken: idToken,
        expiresIn: expiresIn,
      );

      try {
        final source = await ref.read(accountRemoteSourceProvider.future);
        final loadoutSource =
            await ref.read(loadoutRemoteSourceProvider.future);
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
          displayName:
              (realName != null && realName.isNotEmpty) ? realName : null,
          playerCardId: cardId,
          avatarUrl: avatarUrl,
        );
      } catch (_) {}

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
          _isSubmittingJS = false;
          _errorMessage = 'Failed to complete login: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          // Offscreen Invisible WebView Instance for JS Injection & Bot Check Bypass
          Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: Opacity(
                opacity: 0.005,
                child: WebViewWidget(controller: _webViewController),
              ),
            ),
          ),

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

          // Native Form UI
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
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
                      onSubmitted: (_) => _handleNativeSubmit(),
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

                    // Primary Red Login Button
                    GestureDetector(
                      onTap: _isLoading ? null : _handleNativeSubmit,
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

                    // Divider OR
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
