import 'package:flutter/services.dart';

/// Reads session cookies straight from the NATIVE WebView cookie stores.
///
/// Why this exists (audit H4): Riot marks its critical session cookie `ssid`
/// as HttpOnly, so `document.cookie` inside the WebView can never see it.
/// Platform stores CAN be read natively:
/// - Android: `android.webkit.CookieManager.getCookie()` (shared with
///   webview_flutter_android instances),
/// - iOS: `WKWebsiteDataStore.default().httpCookieStore` (the default store
///   shared by all WKWebView instances).
///
/// Returns the raw `name=value; name=value` header, or null when the platform
/// implementation is unavailable (desktop, plugin missing) or errored —
/// callers fall back to the JS capture which only sees non-HttpOnly cookies.
class NativeCookieReader {
  NativeCookieReader._();

  static const MethodChannel _channel =
      MethodChannel('valapp/native_cookies');

  /// Riot auth host whose cookies we snapshot per account.
  static const riotAuthUrl = 'https://auth.riotgames.com';

  static Future<String?> readRiotSessionCookies() async {
    try {
      final raw = await _channel.invokeMethod<String>(
        'getCookies',
        {'url': riotAuthUrl},
      );
      if (raw == null || raw.trim().isEmpty || raw == 'null') return null;
      return raw;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
