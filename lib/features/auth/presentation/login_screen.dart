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
  bool _isPageReady = false;

  @override
  void initState() {
    super.initState();
    _attempt = OAuthAttempt.create();
    _initPreloadedWebView();
  }

  void _initPreloadedWebView() {
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
            _isPageReady = true;
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

    // Preload Riot Login page immediately when screen opens
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

    if (_isPageReady) {
      _injectCredentialsAndSubmit();
    } else {
      // If page isn't ready yet, load request and submit on finish
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

    final jsInject = '''
    (function() {
      function findInput(root, keywords) {
        try {
          var inputs = root.querySelectorAll('input');
          for (var i = 0; i < inputs.length; i++) {
            var inp = inputs[i];
            var type = (inp.type || '').toLowerCase();
            var name = (inp.name || '').toLowerCase();
            var id = (inp.id || '').toLowerCase();
            var placeholder = (inp.placeholder || '').toLowerCase();
            var autocomplete = (inp.getAttribute('autocomplete') || '').toLowerCase();
            var testid = (inp.getAttribute('data-testid') || '').toLowerCase();

            for (var k = 0; k < keywords.length; k++) {
              var kw = keywords[k];
              if (name.includes(kw) || id.includes(kw) || placeholder.includes(kw) || autocomplete.includes(kw) || testid.includes(kw)) {
                return inp;
              }
            }
          }

          var all = root.querySelectorAll('*');
          for (var j = 0; j < all.length; j++) {
            if (all[j].shadowRoot) {
              var found = findInput(all[j].shadowRoot, keywords);
              if (found) return found;
            }
          }
        } catch(e) {}
        return null;
      }

      function findButton(root) {
        try {
          var btns = root.querySelectorAll('button, input[type="submit"], a.mobile-button, [role="button"]');
          for (var i = 0; i < btns.length; i++) {
            var b = btns[i];
            var type = (b.getAttribute('type') || '').toLowerCase();
            var testid = (b.getAttribute('data-testid') || '').toLowerCase();
            var cls = (b.className || '').toString().toLowerCase();
            var text = (b.innerText || b.textContent || '').toLowerCase();

            if (type === 'submit' || testid.includes('signin') || testid.includes('submit') || testid.includes('login') || cls.includes('mobile-button') || cls.includes('btn-signin') || text.includes('sign in') || text.includes('masuk') || text.includes('log in')) {
              return b;
            }
          }

          var all = root.querySelectorAll('*');
          for (var j = 0; j < all.length; j++) {
            if (all[j].shadowRoot) {
              var found = findButton(all[j].shadowRoot);
              if (found) return found;
            }
          }
        } catch(e) {}
        return null;
      }

      var userInput = findInput(document, ['username', 'account_name', 'account', 'user', 'login', 'email']) || document.querySelector("input[type='text']");
      var passInput = findInput(document, ['password', 'pass']) || document.querySelector("input[type='password']");
      var btn = findButton(document) || document.querySelector("button");

      if (userInput && passInput && btn) {
        function setReact18Value(element, val) {
          if (!element) return;
          try {
            element.focus();
            element.dispatchEvent(new Event('focus', { bubbles: true }));
          } catch(e) {}

          var valueSetter;
          try {
            var proto = Object.getPrototypeOf(element);
            valueSetter = Object.getOwnPropertyDescriptor(proto, 'value').set;
          } catch(e) {}

          if (valueSetter) {
            valueSetter.call(element, val);
          } else {
            element.value = val;
          }
          var tracker = element._valueTracker;
          if (tracker) {
            tracker.setValue(val);
          }
          element.dispatchEvent(new Event('input', { bubbles: true }));
          element.dispatchEvent(new Event('change', { bubbles: true }));
          element.dispatchEvent(new Event('blur', { bubbles: true }));
        }

        setReact18Value(userInput, "$usernameEscaped");
        setReact18Value(passInput, "$passwordEscaped");

        var rem = document.querySelector("input[name='remember'], input[type='checkbox']");
        if (rem && ${_rememberMe ? 'true' : 'false'}) {
          if (!rem.checked) {
            rem.click();
          }
        }

        setTimeout(function() {
          btn.disabled = false;
          btn.removeAttribute('disabled');
          try {
            btn.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true }));
            btn.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, cancelable: true }));
            btn.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
          } catch(e) {}
          if (btn.click) btn.click();
        }, 250);

        return "SUCCESS";
      }
      return "WAITING";
    })();
    ''';

    const checkDomJs = '''
    (function() {
      var errEl = document.querySelector("div[data-testid='error-message']") || 
                  document.querySelector(".error-message") || 
                  document.querySelector(".field__error") || 
                  document.querySelector(".form-error") ||
                  document.querySelector("[data-testid='input-error']");
      if (errEl && errEl.innerText && errEl.innerText.trim().length > 0) {
        return "ERROR:" + errEl.innerText.trim();
      }
      var mfaEl = document.querySelector("input[name='multifactorCode']") || 
                  document.querySelector("input[name='code']") || 
                  document.querySelector("div[data-testid='mfa-container']") ||
                  document.querySelector(".mfa-container");
      if (mfaEl) {
        return "MFA";
      }
      return "OK";
    })();
    ''';

    try {
      // Dart-driven evaluation loop (avoids iOS WebKit background setInterval throttling)
      var injected = false;
      for (var i = 0; i < 20; i++) {
        if (!mounted || !_isLoading) return;
        try {
          final res = await _webViewController
              .runJavaScriptReturningResult(jsInject);
          if (res.toString().contains('SUCCESS')) {
            injected = true;
            break;
          }
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 300));
      }

      if (!injected && mounted) {
        setState(() {
          _isLoading = false;
          _isSubmittingJS = false;
          _errorMessage =
              'Could not connect to Riot Login form. Please tap "LOGIN WITH RIOT WEBVIEW" below.';
        });
        return;
      }

      // Check Riot DOM for errors or MFA after 3, 6, and 9 seconds
      for (final _ in [1, 2, 3]) {
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted || !_isLoading) return;

        final currentUrl = await _webViewController.currentUrl();
        if (currentUrl != null &&
            OAuthFlow.isRedirectUri(Uri.parse(currentUrl))) {
          return; // Redirect handled by navigation delegate
        }

        try {
          final result = await _webViewController
              .runJavaScriptReturningResult(checkDomJs);
          final resStr = result.toString().replaceAll('"', '');

          if (resStr.startsWith('ERROR:')) {
            final errorText = resStr.substring(6);
            setState(() {
              _isLoading = false;
              _isSubmittingJS = false;
              _errorMessage = errorText;
            });
            return;
          } else if (resStr == 'MFA') {
            setState(() {
              _isLoading = false;
              _isSubmittingJS = false;
              _errorMessage =
                  '2FA Code required for this account. Redirecting to Riot Webview...';
            });
            await Future.delayed(const Duration(milliseconds: 800));
            if (mounted) context.push('/login/webview');
            return;
          }
        } catch (_) {}
      }

      // Fallback check after 8 seconds total
      if (mounted && _isLoading) {
        final currentUrl = await _webViewController.currentUrl();
        if (currentUrl != null &&
            !OAuthFlow.isRedirectUri(Uri.parse(currentUrl))) {
          setState(() {
            _isLoading = false;
            _isSubmittingJS = false;
            _errorMessage =
                'Authentication taking longer than expected. Please check your credentials or tap "LOGIN WITH RIOT WEBVIEW" below.';
          });
        }
      }
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

      final accountSource = await ref.read(accountRemoteSourceProvider.future);
      final loadoutSource = await ref.read(loadoutRemoteSourceProvider.future);
      final assets = ref.read(valorantAssetsProvider);

      await repo.resolveAndSaveMetadata(
        creds,
        accountSource: accountSource,
        loadoutSource: loadoutSource,
        assets: assets,
      );

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
          // Preloaded Active WebView Instance placed behind dark background (unthrottled on iOS)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: Opacity(
                opacity: 0.05,
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
