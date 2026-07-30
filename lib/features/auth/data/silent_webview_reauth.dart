import 'dart:async';
import 'package:webview_flutter/webview_flutter.dart';

/// Performs silent background token refresh using the native WebView engine's
/// stored Riot session cookies (`ssid`). This guarantees permanent login session
/// renewal without user interaction.
class SilentWebviewReauth {
  SilentWebviewReauth._();
  static final instance = SilentWebviewReauth._();

  static const _authorizeUrl =
      'https://auth.riotgames.com/authorize'
      '?client_id=play-valorant-web-prod'
      '&nonce=1'
      '&redirect_uri=https://playvalorant.com/opt_in'
      '&response_type=token%20id_token'
      '&scope=account%20openid';

  static const _redirectPrefix = 'https://playvalorant.com/opt_in';

  /// Performs background silent token refresh using native WebView session cookies.
  Future<String> refreshTokens() async {
    final completer = Completer<String>();

    WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) '
        'Version/17.0 Mobile/15E148 Safari/604.1',
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            _checkUrl(url, completer);
          },
          onPageFinished: (url) {
            _checkUrl(url, completer);
          },
          onNavigationRequest: (req) {
            if (_checkUrl(req.url, completer)) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (err) {
            final url = err.url ?? '';
            if (!url.startsWith(_redirectPrefix) && !completer.isCompleted) {
              // Ignore minor asset loading errors
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(_authorizeUrl));

    return completer.future.timeout(
      const Duration(seconds: 12),
      onTimeout: () => throw Exception('Silent WebView reauth timed out'),
    );
  }

  bool _checkUrl(String url, Completer<String> completer) {
    if (url.startsWith(_redirectPrefix) && url.contains('access_token')) {
      if (!completer.isCompleted) {
        completer.complete(url);
      }
      return true;
    }
    return false;
  }
}
