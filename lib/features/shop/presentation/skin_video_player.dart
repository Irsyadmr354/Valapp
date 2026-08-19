import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

/// Fullscreen immersive WebView video player for inspecting Valorant weapon skins,
/// upgrade VFX, chroma variants, and finishers in high detail with pinch-to-zoom,
/// rotation, and native playback controls.
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
  bool _isLandscape = false;
  bool _isCoverMode = false;
  Timer? _hudTimer;

  @override
  void initState() {
    super.initState();

    // Enable both portrait and landscape orientation while watching the video
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
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
  <meta name="viewport" content="width=device-width, initial-scale=1.0, minimum-scale=1.0, maximum-scale=5.0, user-scalable=yes">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body {
      width: 100%;
      height: 100%;
      background: #000000;
      overflow: hidden;
      display: flex;
      align-items: center;
      justify-content: center;
      touch-action: manipulation;
    }
    #stage {
      width: 100%;
      height: 100%;
      position: relative;
      display: flex;
      align-items: center;
      justify-content: center;
      background: #000000;
    }
    video {
      width: 100%;
      height: 100%;
      max-width: 100%;
      max-height: 100%;
      object-fit: contain;
      background: #000;
      outline: none;
      transition: object-fit 0.25s ease;
    }
    video.cover-mode {
      object-fit: cover;
    }
    #loader {
      position: absolute;
      top: 50%;
      left: 50%;
      transform: translate(-50%, -50%);
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 12px;
      z-index: 10;
      pointer-events: none;
      transition: opacity 0.3s ease;
    }
    #loader.hidden {
      opacity: 0;
      visibility: hidden;
    }
    .spinner {
      width: 42px;
      height: 42px;
      border: 3px solid rgba(255, 255, 255, 0.15);
      border-top-color: #FF4655;
      border-radius: 50%;
      animation: spin 0.8s linear infinite;
    }
    @keyframes spin { to { transform: rotate(360deg); } }
    .loader-text {
      color: rgba(255, 255, 255, 0.7);
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      font-size: 12px;
      font-weight: 600;
      letter-spacing: 0.5px;
    }
  </style>
</head>
<body>
  <div id="stage">
    <div id="loader">
      <div class="spinner"></div>
      <div class="loader-text">Loading Weapon Preview...</div>
    </div>
    <video
      id="player"
      src="$videoUrl"
      controls
      autoplay
      playsinline
      webkit-playsinline
      controlsList="nodownload"
    ></video>
  </div>
  <script>
    const player = document.getElementById('player');
    const loader = document.getElementById('loader');

    function hideLoader() {
      if (loader) loader.classList.add('hidden');
    }

    player.addEventListener('playing', hideLoader);
    player.addEventListener('canplay', hideLoader);
    player.addEventListener('timeupdate', () => {
      if (player.currentTime > 0) hideLoader();
    });

    player.play().catch(() => {
      player.muted = true;
      player.play().finally(hideLoader);
    });

    function setCoverMode(isCover) {
      if (isCover) {
        player.classList.add('cover-mode');
      } else {
        player.classList.remove('cover-mode');
      }
    }
  </script>
</body>
</html>
''';

    _controller.loadHtmlString(html, baseUrl: 'https://valorant-api.com');
  }

  void _startHudTimer() {
    _hudTimer?.cancel();
    _hudTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showHud = false);
    });
  }

  void _toggleHud() {
    setState(() => _showHud = !_showHud);
    if (_showHud) {
      _startHudTimer();
    } else {
      _hudTimer?.cancel();
    }
  }

  void _toggleOrientation() {
    setState(() {
      _isLandscape = !_isLandscape;
      if (_isLandscape) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeRight,
          DeviceOrientation.landscapeLeft,
        ]);
      } else {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      }
    });
    _startHudTimer();
  }

  void _toggleCoverMode() {
    setState(() {
      _isCoverMode = !_isCoverMode;
      _controller.runJavaScript('setCoverMode($_isCoverMode);');
    });
    _startHudTimer();
  }

  String _cleanTitle(String raw) {
    var s = raw.contains(' - ') ? raw.substring(0, raw.indexOf(' - ')) : raw;
    s = s.replaceAllMapped(
      RegExp(r'Level\s+(\d+)', caseSensitive: false),
      (m) => '· Lv.${m[1]}',
    );
    return s.trim();
  }

  @override
  void dispose() {
    _hudTimer?.cancel();
    // Restore default portrait orientation when leaving player
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

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
    final mediaQuery = MediaQuery.of(context);
    final isActuallyLandscape =
        mediaQuery.orientation == Orientation.landscape;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _toggleHud,
        child: Stack(
          children: [
            // ── Fullscreen Webview Video Viewport ────────────────────────────
            Positioned.fill(
              child: WebViewWidget(controller: _controller),
            ),

            // ── Loading Indicator ───────────────────────────────────────────
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
                      'Opening Fullscreen Preview...',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),

            // ── Floating Sleek Top Overlay HUD ──────────────────────────────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: _showHud ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: IgnorePointer(
                  ignoring: !_showHud,
                  child: Container(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      mediaQuery.padding.top + (isActuallyLandscape ? 6 : 10),
                      16,
                      14,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withAlpha(220),
                          Colors.black.withAlpha(120),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
                        // Back / Close Button
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: Colors.black.withAlpha(150),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withAlpha(40),
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
                        const SizedBox(width: 12),

                        // Title & Tier Pill
                        Expanded(
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
                                    'Pinch to Zoom & Inspect Gun',
                                    style: TextStyle(
                                      color: Colors.white.withAlpha(160),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Fit / Zoom Mode Toggle Button
                        GestureDetector(
                          onTap: _toggleCoverMode,
                          child: Container(
                            width: 38,
                            height: 38,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: _isCoverMode
                                  ? const Color(0xFFFF4655).withAlpha(180)
                                  : Colors.black.withAlpha(150),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _isCoverMode
                                    ? const Color(0xFFFF4655)
                                    : Colors.white.withAlpha(40),
                                width: 1,
                              ),
                            ),
                            child: Icon(
                              _isCoverMode
                                  ? Icons.fit_screen_rounded
                                  : Icons.aspect_ratio_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),

                        // 1-Tap Screen Rotate (Portrait / Landscape) Button
                        GestureDetector(
                          onTap: _toggleOrientation,
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: isActuallyLandscape
                                  ? const Color(0xFFFF4655).withAlpha(180)
                                  : Colors.black.withAlpha(150),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isActuallyLandscape
                                    ? const Color(0xFFFF4655)
                                    : Colors.white.withAlpha(40),
                                width: 1,
                              ),
                            ),
                            child: const Icon(
                              Icons.screen_rotation_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
