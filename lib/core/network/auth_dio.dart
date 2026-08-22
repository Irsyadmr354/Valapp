import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import 'valorant_headers.dart';

/// Creates a [Dio] instance dedicated to `auth.riotgames.com` requests.
/// - Attaches the required Riot User-Agent header on every request.
/// - Manages cookies via the shared in-memory [CookieJar].
/// - Does NOT follow redirects automatically so we can read the `location`
///   header for token extraction during cookie reauth.
Dio createAuthDio(CookieJar cookieJar) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'User-Agent': ValorantHeaders.riotClientUserAgent,
        'Content-Type': 'application/json',
      },
      // Do NOT follow redirects — we need to read location headers ourselves.
      followRedirects: false,
      validateStatus: (status) => status != null && status < 400,
    ),
  );

  dio.interceptors.add(CookieManager(cookieJar));

  return dio;
}
