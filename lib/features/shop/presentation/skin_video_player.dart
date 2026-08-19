import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

/// Fullscreen immersive WebView video player for inspecting Valorant weapon skins,
/// upgrade VFX, chroma variants, and finishers in high detail.
class SkinVideoScreen extends StatefulWidget {
  const SkinVideoScreen({
    super.key,
    required this.videoUrl,
    required this.title,
    required this.tierColor,
  });

  final String videoUrl;
  final String title;
  final Color tierColor;

  /// Opens the video player in a dedicated fullscreen view.
  static Future<void> show(
    BuildContext context, {
    required String videoUrl,
    required String title,
    required Color tierColor,
  }) {
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: true,
        pageBuilder: (_, animation, secondaryAnimation) => SkinVideoScreen(
          videoUrl: videoUrl,
          title: title,
          tierColor: tierColor,
        ),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
      ),
    );
  }

  @override
  State<SkinVideoScreen> createState() => _SkinVideoScreenState();
}

/// Backwards compatibility alias for existing call-sites.
class SkinVideoDialog {
  static Future<void> show(
    BuildContext context, {
    required String videoUrl,
    required String title,
    required Color tierColor,
  }) {
    return SkinVideoScreen.show(
      context,
      videoUrl: videoUrl,
      title: title,
      tierColor: tierColor,
    );
  }
}

class _SkinVideoScreenState extends State<SkinVideoScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _showHud = true;
  Timer? _hudTimer;

  @override
  void initState() {
    super.initState();

    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    _controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
            _startHudTimer();
          },
        ),
      );

    _loadVideo();
  }

  void _loadVideo() {
    final videoUrl = widget.videoUrl;
    final html = '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body {
      width: 100%; height: 100%;
      background: #000;
      overflow: hidden;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    video {
      width: 100%;
      height: 100%;
      object-fit: contain;
      background: #000;
    }
    #loader {
      position: absolute;
      top: 50%; left: 50%;
      transform: translate(-50%, -50%);
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 12px;
      z-index: 10;
      pointer-events: none;
      transition: opacity 0.3s ease;
    }
    #loader.hidden { opacity: 0; visibility: hidden; }
    .spinner {
      width: 42px; height: 42px;
      border: 3px solid rgba(255,255,255,0.15);
      border-top-color: #FF4655;
      border-radius: 50%;
      animation: spin 0.8s linear infinite;
    }
    @keyframes spin { to { transform: rotate(360deg); } }
    .loader-text {
      color: rgba(255,255,255,0.7);
      font: 600 12px -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      letter-spacing: 0.5px;
    }
  </style>
</head>
<body>
  <div id="loader">
    <div class="spinner"></div>
    <div class="loader-text">Loading Weapon Preview...</div>
  </div>
  <video
    id="player"
    src="$videoUrl"
    controls
    autoplay
    muted
    playsinline
    webkit-playsinline
    controlsList="nodownload"
  ></video>
  <script>
    var player = document.getElementById('player');
    var loader = document.getElementById('loader');

    function hideLoader() {
      if (loader) loader.classList.add('hidden');
    }

    player.addEventListener('playing', hideLoader);
    player.addEventListener('canplay', function() {
      hideLoader();
      player.play().catch(function(){});
    });
    player.addEventListener('timeupdate', function() {
      if (player.currentTime > 0) hideLoader();
    });

    // iOS autoplay: start muted, then unmute after first play
    player.play().then(function() {
      hideLoader();
      // Unmute after a tiny delay so iOS allows it
      setTimeout(function() { player.muted = false; }, 300);
    }).catch(function() {
      // If even muted autoplay fails, the native controls play button is there
      hideLoader();
    });
  </script>
</body>
</html>
''';

    _controller.loadHtmlString(html, baseUrl: 'https://valorant-api.com');
  }

  void _startHudTimer() {
    _hudTimer?.cancel();
    _hudTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showHud = false);
    });
  }

  void _toggleHud() {
    setState(() => _showHud = !_showHud);
    if (_showHud) _startHudTimer();
  }

  String _cleanTitle(String raw) {
    var s = raw.contains(' - ') ? raw.substring(0, raw.indexOf(' - ')) : raw;
    s = s.replaceAllMapped(
      RegExp(r'Level\s+(\d+)', caseSensitive: false),
      (m) => '· Lv.${m[1]}',
    );
    return s.trim();
  }

  void _close() {
    try {
      _controller.runJavaScript(
        "var p = document.getElementById('player'); if (p) { p.pause(); p.src = ''; }",
      );
    } catch (_) {}
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _hudTimer?.cancel();
    try {
      _controller.runJavaScript(
        "var p = document.getElementById('player'); if (p) { p.pause(); p.src = ''; }",
      );
      _controller.loadHtmlString('<html><body></body></html>');
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Fullscreen WebView ─────────────────────────────────────────
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleHud,
              child: WebViewWidget(controller: _controller),
            ),
          ),

          // ── Loading Indicator ──────────────────────────────────────────
          if (_isLoading)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    color: Color(0xFFFF4655),
                    strokeWidth: 3,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Opening Preview...',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

          // ── Back / Close Button — ALWAYS visible ───────────────────────
          Positioned(
            top: mq.padding.top + 8,
            left: 16,
            child: GestureDetector(
              onTap: _close,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(180),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withAlpha(50),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
          ),

          // ── Top HUD (title) — auto-hides ──────────────────────────────
          Positioned(
            top: mq.padding.top + 8,
            left: 68,
            right: 16,
            child: IgnorePointer(
              ignoring: !_showHud,
              child: AnimatedOpacity(
                opacity: _showHud ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _cleanTitle(widget.title).toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: widget.tierColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Weapon Preview',
                          style: TextStyle(
                            color: Colors.white.withAlpha(140),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
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
