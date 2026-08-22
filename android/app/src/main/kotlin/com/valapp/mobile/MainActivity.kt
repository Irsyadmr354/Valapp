package com.valapp.mobile

import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "valapp/native_cookies"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCookies" -> {
                    try {
                        val url = call.argument<String>("url").orEmpty()
                        // android.webkit.CookieManager shares its store with every
                        // WebView instance in the process, and getCookie() returns
                        // the full header INCLUDING HttpOnly cookies — exactly what
                        // JS document.cookie cannot see (audit H4).
                        val header: String? =
                            if (url.isEmpty()) null else CookieManager.getInstance().getCookie(url)
                        result.success(header)
                    } catch (e: Exception) {
                        result.error("cookie_error", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
