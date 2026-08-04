import 'package:cookie_jar/cookie_jar.dart';

/// Riot cookies are bearer credentials, so they must not be persisted as
/// plaintext files. Native WebView storage remains the primary reauth source;
/// this in-memory jar only supports the current process fallback.
Future<CookieJar> createCookieJar() async => CookieJar(ignoreExpires: false);
