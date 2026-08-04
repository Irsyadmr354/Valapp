import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'oauth_flow.dart';

/// Performs silent background token refresh using the native WebView engine's
/// shared cookie store. On iOS, all WKWebView instances share cookies via
/// the default WKWebsiteDataStore — so the `ssid` session cookie from the
/// initial login is automatically available here.
class SilentWebviewReauth {
  SilentWebviewReauth._();
  static final instance = SilentWebviewReauth._();

  /// Strong reference to prevent the WebViewController from being
  /// garbage-collected before the navigation completes.
  // ignore: unused_field
  WebViewController? _controller;

  /// Whether a reauth is currently in progress (prevents concurrent calls).
  bool _isRunning = false;

  /// Performs background silent token refresh using native WebView session cookies.
  /// Returns the redirect URI containing the fresh `access_token`.
  Future<String> refreshTokens(OAuthAttempt attempt) async {
    // Prevent concurrent reauth attempts
    if (_isRunning) {
      throw Exception('Silent reauth already in progress');
    }
    _isRunning = true;

    final completer = Completer<String>();

    try {
      // Create platform-specific params — on iOS, WebKitWebViewControllerCreationParams
      // ensures the WKWebView uses the default WKWebsiteDataStore (shared cookies).
      late final PlatformWebViewControllerCreationParams params;
      if (WebViewPlatform.instance is WebKitWebViewPlatform) {
        params = WebKitWebViewControllerCreationParams(
          allowsInlineMediaPlayback: true,
        );
      } else {
        params = const PlatformWebViewControllerCreationParams();
      }

      // Store reference in instance field to prevent GC
      _controller = WebViewController.fromPlatformCreationParams(params)
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
              // Ignore errors for the redirect URI — it's not a real page
              final uri = Uri.tryParse(url);
              if (uri != null && OAuthFlow.isRedirectUri(uri)) return;
              // Only fail on main frame errors, not sub-resource (CSS/JS) errors
              if (err.isForMainFrame == true && !completer.isCompleted) {
                debugPrint(
                    '[SilentReauth] WebView main frame error: ${err.description} (url: $url)');
                completer.completeError(
                  Exception('WebView error: ${err.description}'),
                );
              }
            },
          ),
        )
        ..loadRequest(attempt.authorizeUri);

      debugPrint('[SilentReauth] Started silent WebView reauth...');

      return await completer.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          debugPrint('[SilentReauth] Timed out after 20 seconds');
          throw Exception('Silent WebView reauth timed out');
        },
      );
    } finally {
      _controller = null; // Release reference after completion
      _isRunning = false;
    }
  }

  bool _checkUrl(String url, Completer<String> completer) {
    final uri = Uri.tryParse(url);
    if (uri != null && OAuthFlow.isRedirectUri(uri)) {
      debugPrint('[SilentReauth] SUCCESS — got redirect with access_token');
      if (!completer.isCompleted) {
        completer.complete(url);
      }
      return true;
    }
    return false;
  }
}
