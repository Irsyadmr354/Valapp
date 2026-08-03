import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../core/di/providers.dart';
import '../../../core/storage/cache_storage.dart';
import '../../../core/exceptions/auth_exception.dart';
import '../data/auth_remote_source.dart';

/// Opens Riot's real login page in a WebView and intercepts the redirect
/// that contains the access_token. This avoids CAPTCHA entirely because
/// the user authenticates through the real browser engine.
class WebViewLoginScreen extends ConsumerStatefulWidget {
  const WebViewLoginScreen({super.key});

  @override
  ConsumerState<WebViewLoginScreen> createState() =>
      _WebViewLoginScreenState();
}

class _WebViewLoginScreenState extends ConsumerState<WebViewLoginScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _isProcessing = false;
  String? _errorMessage;

  static const _loginUrl =
      'https://auth.riotgames.com/authorize'
      '?client_id=play-valorant-web-prod'
      '&nonce=1'
      '&redirect_uri=https://playvalorant.com/opt_in'
      '&response_type=token%20id_token'
      '&scope=account%20openid';

  static const _redirectPrefix = 'https://playvalorant.com/opt_in';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0F1923))
      ..setUserAgent(
        // Use a real Chrome user agent so Cloudflare doesn't block
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) '
        'Version/17.0 Mobile/15E148 Safari/604.1',
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() => _isLoading = true);
            _checkForToken(url);
          },
          onPageFinished: (url) {
            setState(() => _isLoading = false);
            _checkForToken(url);
          },
          onNavigationRequest: (request) {
            _checkForToken(request.url);
            return NavigationDecision.navigate;
          },
          onWebResourceError: (error) {
            // Ignore errors for the redirect URI — it doesn't actually load
            final url = error.url ?? '';
            if (!url.startsWith(_redirectPrefix)) {
              setState(() {
                _isLoading = false;
                _errorMessage = 'Network error: ${error.description}';
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(_loginUrl));
  }

  void _checkForToken(String url) {
    // _isProcessing is checked synchronously (field read, not setState-read)
    // so concurrent callbacks from onPageStarted/onPageFinished/onNavigationRequest
    // all see the same value before any setState frame fires.
    if (_isProcessing) return;

    if (url.startsWith(_redirectPrefix) && url.contains('access_token')) {
      _isProcessing = true; // set field directly — no setState needed here
      _handleTokenRedirect(url);
    }
  }

  Future<void> _handleTokenRedirect(String redirectUrl) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final tokens = AuthRemoteSource.parseTokensFromUri(redirectUrl);
      final accessToken = tokens['access_token']!;
      final idToken = tokens['id_token']!;
      final expiresIn = int.parse(tokens['expires_in']!);

      final repo = await ref.read(authRepositoryProvider.future);
      final creds = await repo.completeLoginFromWebView(
        accessToken: accessToken,
        idToken: idToken,
        expiresIn: expiresIn,
      );

      // Wipe cached user data from old session
      await CacheStorage.instance.clearUserCache();

      // Attempt to resolve real Riot ID display name and Player Card Avatar for multi-account profile
      try {
        final source = await ref.read(accountRemoteSourceProvider.future);
        final loadoutSource = await ref.read(loadoutRemoteSourceProvider.future);
        final assets = ref.read(valorantAssetsProvider);
        final localSource = ref.read(credentialsLocalSourceProvider);

        final realName = await source.fetchDisplayName(creds.shard, creds.puuid);
        String? avatarUrl;
        String? cardId;

        try {
          final rawLoadout = await loadoutSource.fetchLoadoutRaw(creds.shard, creds.puuid);
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
            final cardInfo = (cardsMap[cardId] ?? cardsMap[cardId.toLowerCase()]) as Map<String, dynamic>?;
            avatarUrl = cardInfo?['smallArt'] as String? ?? cardInfo?['displayIcon'] as String?;
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
      ref.invalidate(currentCredentialsProvider);
      ref.invalidate(apiDioProvider);
      ref.invalidate(storeRemoteSourceProvider);
      ref.invalidate(storeRepositoryProvider);
      ref.invalidate(matchRemoteSourceProvider);
      ref.invalidate(mmrRemoteSourceProvider);
      ref.invalidate(contractsRemoteSourceProvider);
      ref.invalidate(accountRemoteSourceProvider);
      ref.invalidate(restrictionsRemoteSourceProvider);
      ref.invalidate(loadoutRemoteSourceProvider);

      if (mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        } else {
          context.go('/shop');
        }
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isProcessing = false;
          _errorMessage = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isProcessing = false;
          _errorMessage = 'Failed to complete login: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1923),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1923),
        title: const Text(
          'Login with Riot',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFFFF4655),
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          // WebView
          if (_errorMessage == null && !_isProcessing)
            WebViewWidget(controller: _controller),

          // Processing overlay
          if (_isProcessing)
            Container(
              color: const Color(0xFF0F1923),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Color(0xFFFF4655)),
                    SizedBox(height: 20),
                    Text(
                      'Logging in...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),

          // Error state
          if (_errorMessage != null)
            Container(
              color: const Color(0xFF0F1923),
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        color: Color(0xFFFF4655), size: 48),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () {
                        setState(() {
                          _errorMessage = null;
                          _isProcessing = false;
                        });
                        _controller.loadRequest(Uri.parse(_loginUrl));
                      },
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFF4655)),
                      child: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
