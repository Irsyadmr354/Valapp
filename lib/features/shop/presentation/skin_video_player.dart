import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import '../../../shared/utils/app_colors.dart';

/// Fullscreen immersive video player for inspecting Valorant weapon skins,
/// upgrade VFX, chroma variants, and finishers on iOS (iPhone) and Android.
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
  bool _isPlaying = false;
  bool _isMuted = true;
  bool _hasError = false;
  bool _isAutoplayBlocked = false;
  bool _isLandscape = false;
  double _currentTime = 0.0;
  double _duration = 0.0;
  bool _isSeeking = false;
  double _seekValue = 0.0;

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
      ..addJavaScriptChannel(
        'FlutterBridge',
        onMessageReceived: _handleJsMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            _startHudTimer();
          },
          onWebResourceError: (error) {
            debugPrint(
                '[SkinVideoPlayer] WebResourceError: ${error.description}');
            if (mounted) {
              setState(() {
                _isLoading = false;
                _hasError = true;
              });
            }
          },
        ),
      );

    _loadVideo();
  }

  void _handleJsMessage(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      final event = data['event'] as String?;

      if (!mounted) return;

      if (event == 'playing') {
        setState(() {
          _isPlaying = true;
          _isLoading = false;
          _hasError = false;
          _isAutoplayBlocked = false;
        });
      } else if (event == 'pause') {
        setState(() {
          _isPlaying = false;
        });
      } else if (event == 'paused_blocked') {
        setState(() {
          _isPlaying = false;
          _isLoading = false;
          _isAutoplayBlocked = true;
        });
      } else if (event == 'canplay') {
        setState(() {
          _isLoading = false;
        });
      } else if (event == 'timeupdate') {
        final cur = (data['currentTime'] as num?)?.toDouble() ?? 0.0;
        final dur = (data['duration'] as num?)?.toDouble() ?? 0.0;
        setState(() {
          if (!_isSeeking) {
            _currentTime = cur;
          }
          if (dur > 0) {
            _duration = dur;
          }
        });
      } else if (event == 'ended') {
        setState(() {
          _isPlaying = false;
          _currentTime = _duration;
          _showHud = true;
        });
      } else if (event == 'error') {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    } catch (_) {}
  }

  void _loadVideo() {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _isAutoplayBlocked = false;
    });

    final videoUrl = widget.videoUrl;
    final html = '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
    html, body {
      width: 100%; height: 100%;
      background: #000000;
      overflow: hidden;
      display: flex;
      align-items: center;
      justify-content: center;
      user-select: none;
      -webkit-user-select: none;
    }
    video {
      width: 100%;
      height: 100%;
      max-width: 100vw;
      max-height: 100vh;
      object-fit: contain;
      background: #000000;
      outline: none;
    }
  </style>
</head>
<body>
  <video
    id="player"
    src="$videoUrl"
    preload="auto"
    autoplay
    muted
    playsinline
    webkit-playsinline
    x-webkit-airplay="allow"
  ></video>
  <script>
    var player = document.getElementById('player');

    function sendEvent(evt, extra) {
      if (window.FlutterBridge) {
        var payload = Object.assign({ event: evt }, extra || {});
        window.FlutterBridge.postMessage(JSON.stringify(payload));
      }
    }

    player.addEventListener('playing', function() { sendEvent('playing'); });
    player.addEventListener('pause', function() { sendEvent('pause'); });
    player.addEventListener('ended', function() { sendEvent('ended'); });
    player.addEventListener('waiting', function() { sendEvent('waiting'); });
    player.addEventListener('canplay', function() { sendEvent('canplay'); });
    player.addEventListener('timeupdate', function() {
      sendEvent('timeupdate', {
        currentTime: player.currentTime,
        duration: player.duration || 0
      });
    });
    player.addEventListener('error', function(e) {
      sendEvent('error', {
        message: player.error ? player.error.message : 'Video load error'
      });
    });

    function tryAutoPlay() {
      player.muted = true;
      var promise = player.play();
      if (promise !== undefined) {
        promise.then(function() {
          sendEvent('playing');
        }).catch(function() {
          sendEvent('paused_blocked');
        });
      }
    }

    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', tryAutoPlay);
    } else {
      tryAutoPlay();
    }

    window.playVideo = function() {
      player.play().then(function() {
        sendEvent('playing');
      }).catch(function() {
        player.muted = true;
        player.play().catch(function(){});
      });
    };

    window.pauseVideo = function() {
      player.pause();
    };

    window.togglePlay = function() {
      if (player.paused) {
        window.playVideo();
      } else {
        window.pauseVideo();
      }
    };

    window.setMuted = function(muted) {
      player.muted = muted;
    };

    window.seekTo = function(seconds) {
      player.currentTime = seconds;
    };
  </script>
</body>
</html>
''';

    _controller.loadHtmlString(html, baseUrl: 'https://media.valorant-api.com');
  }

  void _startHudTimer() {
    _hudTimer?.cancel();
    _hudTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying) {
        setState(() => _showHud = false);
      }
    });
  }

  void _toggleHud() {
    setState(() => _showHud = !_showHud);
    if (_showHud) _startHudTimer();
  }

  void _togglePlay() {
    _startHudTimer();
    if (_isPlaying) {
      _controller.runJavaScript('window.pauseVideo();');
    } else {
      _controller.runJavaScript('window.playVideo();');
    }
  }

  void _toggleMute() {
    _startHudTimer();
    final newMuted = !_isMuted;
    setState(() => _isMuted = newMuted);
    _controller.runJavaScript('window.setMuted($newMuted);');
  }

  void _toggleOrientation() {
    _startHudTimer();
    final newLandscape = !_isLandscape;
    setState(() => _isLandscape = newLandscape);

    if (newLandscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
  }

  String _formatTime(double seconds) {
    if (seconds.isNaN || seconds.isInfinite || seconds <= 0) return '0:00';
    final totalSec = seconds.toInt();
    final mins = totalSec ~/ 60;
    final secs = totalSec % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
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
    // Restore default orientation on exit
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
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

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Fullscreen Video WebView Layer
          Positioned.fill(
            child: WebViewWidget(controller: _controller),
          ),

          // Tap gesture overlay for toggling HUD and play/pause
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _toggleHud,
              child: const SizedBox.expand(),
            ),
          ),

          // Big Central "Tap to Start Video" on iPhone if autoplay was blocked
          if (_isAutoplayBlocked && !_isPlaying && !_isLoading && !_hasError)
            Center(
              child: GestureDetector(
                onTap: _togglePlay,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.red,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.red.withAlpha(120),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 28),
                      SizedBox(width: 8),
                      Text(
                        'START VIDEO',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Center Big Play/Pause Toggle Indicator when HUD is active (and not blocked)
          if (_showHud && !_isLoading && !_hasError && !_isAutoplayBlocked)
            Center(
              child: GestureDetector(
                onTap: _togglePlay,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(160),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withAlpha(60),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ),
            ),

          // Clean Single Loading Spinner
          if (_isLoading)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        color: AppColors.red,
                        strokeWidth: 2.5,
                      ),
                      SizedBox(height: 14),
                      Text(
                        'Loading Weapon Video...',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Error Recovery Screen
          if (_hasError)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: AppColors.red, size: 48),
                      const SizedBox(height: 12),
                      const Text(
                        'Failed to load weapon video',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _loadVideo,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.red,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('RETRY'),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Top Header Safe Area HUD (Back button, Title, Screen Rotate)
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
                    mediaQuery.padding.top + 8,
                    16,
                    16,
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
                      // Back Button
                      GestureDetector(
                        onTap: _close,
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(160),
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
                      const SizedBox(width: 12),

                      // Weapon Title and Badge
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _cleanTitle(widget.title).toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
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

                      // Screen Orientation Toggle Button (Portrait / Landscape)
                      GestureDetector(
                        onTap: _toggleOrientation,
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: _isLandscape
                                ? AppColors.red.withAlpha(200)
                                : Colors.black.withAlpha(160),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _isLandscape
                                  ? AppColors.red
                                  : Colors.white.withAlpha(50),
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

          // Bottom Controls HUD (Play/Pause, Slider, Timers, Mute/Unmute)
          Positioned(
            bottom: 0,
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
                    14,
                    16,
                    mediaQuery.padding.bottom + 12,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withAlpha(220),
                        Colors.black.withAlpha(140),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Video Progress Scrubber Bar
                      Row(
                        children: [
                          Text(
                            _formatTime(_isSeeking ? _seekValue : _currentTime),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 12,
                                ),
                                activeTrackColor: AppColors.red,
                                inactiveTrackColor: Colors.white24,
                                thumbColor: Colors.white,
                              ),
                              child: Slider(
                                value: (_isSeeking ? _seekValue : _currentTime)
                                    .clamp(
                                        0.0, _duration > 0 ? _duration : 1.0),
                                min: 0.0,
                                max: _duration > 0 ? _duration : 1.0,
                                onChangeStart: (val) {
                                  setState(() {
                                    _isSeeking = true;
                                    _seekValue = val;
                                  });
                                },
                                onChanged: (val) {
                                  setState(() {
                                    _seekValue = val;
                                  });
                                },
                                onChangeEnd: (val) {
                                  setState(() {
                                    _isSeeking = false;
                                    _currentTime = val;
                                  });
                                  _controller
                                      .runJavaScript('window.seekTo($val);');
                                  _startHudTimer();
                                },
                              ),
                            ),
                          ),
                          Text(
                            _formatTime(_duration),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Action bar: Play/Pause, Replay, Mute/Unmute
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Play / Pause Icon Button
                          GestureDetector(
                            onTap: _togglePlay,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(20),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.white.withAlpha(30),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _isPlaying ? 'PAUSE' : 'PLAY',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Mute / Unmute Button
                          GestureDetector(
                            onTap: _toggleMute,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: _isMuted
                                    ? Colors.white.withAlpha(20)
                                    : AppColors.red.withAlpha(60),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _isMuted
                                      ? Colors.white.withAlpha(30)
                                      : AppColors.red,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _isMuted
                                        ? Icons.volume_off_rounded
                                        : Icons.volume_up_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _isMuted ? 'UNMUTE' : 'MUTE',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
