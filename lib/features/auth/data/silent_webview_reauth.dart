import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import '../../../core/navigation/navigator_key.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/exceptions/auth_exception.dart';
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

  /// In-flight reauth future — shared so concurrent callers await one attempt.
  Future<String>? _inFlight;

  /// Performs background silent token refresh using native WebView session cookies.
  /// Returns the redirect URI containing the fresh `access_token`.
  ///
  /// Concurrent callers do NOT share each other's redirect URL: every caller
  /// owns a distinct [OAuthAttempt] (state/nonce), so returning another
  /// caller's URL would fail its state validation. Instead, a new call waits
  /// for any in-flight refresh to finish and then runs its OWN attempt.
  Future<String> refreshTokens(OAuthAttempt attempt, {String? puuid}) async {
    while (true) {
      final existing = _inFlight;
      if (existing == null) break;
      try {
        await existing;
      } catch (_) {
        // Predecessor failed — its slot is free; proceed with our own attempt.
      }
    }
    final operation = _doRefreshTokens(attempt, puuid: puuid);
    _inFlight = operation;
    try {
      return await operation;
    } finally {
      if (identical(_inFlight, operation)) _inFlight = null;
    }
  }

  Future<String> _doRefreshTokens(OAuthAttempt attempt, {String? puuid}) async {
    final completer = Completer<String>();
    OverlayEntry? overlayEntry;

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
      final controller = WebViewController.fromPlatformCreationParams(params)
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
              final uri = Uri.tryParse(url);
              // Ignore errors for the redirect URI — it's not a real page
              if (uri != null && OAuthFlow.isRedirectUri(uri)) return;

              // Ignore non-main-frame errors (subresources, analytics, fonts, trackers)
              if (err.isForMainFrame == false) {
                return;
              }

              // Ignore aborted / cancelled requests (caused by redirects or page transitions)
              // -999 on iOS is NSURLErrorCancelled, -1 on Android is ERR_ABORTED
              if (err.errorCode == -999 ||
                  err.errorCode == -1 ||
                  err.description.toLowerCase().contains('cancel') ||
                  err.description.toLowerCase().contains('abort')) {
                return;
              }

              if (!completer.isCompleted) {
                final safeHost = uri?.host ?? 'unknown-host';
                debugPrint(
                    '[SilentReauth] WebView resource error on $safeHost: ${err.description} (code: ${err.errorCode})');
                completer.completeError(
                  TransientReauthException('WebView error: ${err.description}'),
                );
              }
            },
          ),
        );

      _controller = controller;

      // Restore saved Riot session cookies strictly for the target account into WebViewCookieManager
      if (puuid != null && puuid.isNotEmpty) {
        try {
          final rawCookies = await SecureStorage.instance.read(
            SecureStorage.keyRiotCookiesFor(puuid),
          );
          if (rawCookies != null && rawCookies.isNotEmpty) {
            final cookieManager = WebViewCookieManager();
            final pairs = rawCookies.split(';');
            for (final pair in pairs) {
              final parts = pair.split('=');
              if (parts.length >= 2) {
                final name = parts[0].trim();
                final value = parts.sublist(1).join('=').trim();
                if (name.isNotEmpty && value.isNotEmpty) {
                  await cookieManager.setCookie(
                    WebViewCookie(
                      name: name,
                      value: value,
                      domain: 'auth.riotgames.com',
                      path: '/',
                    ),
                  );
                  await cookieManager.setCookie(
                    WebViewCookie(
                      name: name,
                      value: value,
                      domain: '.riotgames.com',
                      path: '/',
                    ),
                  );
                }
              }
            }
            debugPrint(
                '[SilentReauth] Restored Riot session cookies into WKWebView');
          }
        } catch (e) {
          debugPrint('[SilentReauth] Non-fatal cookie restoration warning: $e');
        }
      }

      // Attach WebViewWidget into rootNavigatorKey overlay so iOS WebKit engine treats it as a live layer
      final navContext = rootNavigatorKey.currentContext;
      if (navContext != null && navContext.mounted) {
        overlayEntry = OverlayEntry(
          builder: (_) => Positioned(
            left: 0,
            top: 0,
            width: 1,
            height: 1,
            child: IgnorePointer(
              ignoring: true,
              child: Opacity(
                opacity: 0.01,
                child: WebViewWidget(controller: controller),
              ),
            ),
          ),
        );
        Overlay.of(navContext).insert(overlayEntry);
      }

      controller.loadRequest(attempt.authorizeUri);

      debugPrint('[SilentReauth] Started silent WebView reauth...');

      return await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          debugPrint('[SilentReauth] Timed out after 15 seconds');
          throw const TransientReauthException(
              'Silent WebView reauth timed out');
        },
      );
    } finally {
      overlayEntry?.remove();
      overlayEntry = null;
      try {
        _controller?.loadRequest(Uri.parse('about:blank'));
      } catch (_) {}
      _controller = null; // Release reference after completion
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
