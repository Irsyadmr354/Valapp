import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import '../../../shared/utils/app_colors.dart';

/// Modal dialog for playing level upgrade VFX & finisher videos natively via WebView HTML5 Video.
class SkinVideoDialog extends StatefulWidget {
  const SkinVideoDialog({
    super.key,
    required this.videoUrl,
    required this.title,
    required this.tierColor,
  });

  final String videoUrl;
  final String title;
  final Color tierColor;

  static Future<void> show(
    BuildContext context, {
    required String videoUrl,
    required String title,
    required Color tierColor,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => SkinVideoDialog(
        videoUrl: videoUrl,
        title: title,
        tierColor: tierColor,
      ),
    );
  }

  @override
  State<SkinVideoDialog> createState() => _SkinVideoDialogState();
}

class _SkinVideoDialogState extends State<SkinVideoDialog> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();

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
          },
        ),
      );

    final videoUrl = widget.videoUrl;
    final html = '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body, html { width: 100%; height: 100%; background: #000; overflow: hidden; position: relative; user-select: none; }
    video { width: 100%; height: 100%; object-fit: contain; position: absolute; top: 0; left: 0; }
    #overlay {
      position: absolute; top: 0; left: 0; width: 100%; height: 100%;
      display: flex; flex-direction: column; align-items: center; justify-content: center;
      background: rgba(0,0,0,0.65); z-index: 10;
      transition: opacity 0.25s ease;
    }
    #overlay.hidden { opacity: 0; pointer-events: none; }
    .spinner {
      width: 36px; height: 36px;
      border: 3px solid rgba(255,255,255,0.2);
      border-top-color: #FF4655;
      border-radius: 50%;
      animation: spin 0.7s linear infinite;
    }
    @keyframes spin { to { transform: rotate(360deg); } }
    #overlay p {
      margin-top: 12px; color: rgba(255,255,255,0.7);
      font: 12px -apple-system, BlinkMacSystemFont, sans-serif;
      letter-spacing: 0.5px;
    }
    #play-btn {
      display: none;
      margin-top: 10px;
      padding: 8px 16px;
      background: #FF4655;
      color: #fff;
      border-radius: 20px;
      font: bold 12px -apple-system, sans-serif;
      cursor: pointer;
    }
    #audio-badge {
      position: absolute; top: 10px; left: 10px;
      padding: 4px 8px; background: rgba(0,0,0,0.7);
      color: #fff; border-radius: 12px; font: bold 11px -apple-system, sans-serif;
      border: 1px solid rgba(255,255,255,0.2); z-index: 11;
      pointer-events: none; transition: background 0.2s;
    }
    #tap-hint {
      position: absolute; bottom: 8px; left: 0; width: 100%; text-align: center;
      color: rgba(255,255,255,0.5); font: 10px -apple-system, sans-serif; z-index: 11;
      pointer-events: none;
    }
  </style>
</head>
<body>
  <div id="audio-badge">🔇 MUTED (TAP TO UNMUTE)</div>
  <div id="overlay">
    <div class="spinner" id="spin"></div>
    <p id="status-txt">Loading video...</p>
    <div id="play-btn" onclick="forcePlay()">▶ TAP TO PLAY</div>
  </div>
  <video id="vid" crossorigin="anonymous" preload="auto" autoplay loop muted playsinline webkit-playsinline></video>
  <div id="tap-hint">Tap anywhere on video to toggle sound</div>
  <script>
    var v = document.getElementById('vid');
    var ov = document.getElementById('overlay');
    var spin = document.getElementById('spin');
    var statusTxt = document.getElementById('status-txt');
    var playBtn = document.getElementById('play-btn');
    var audioBadge = document.getElementById('audio-badge');

    v.src = "$videoUrl";

    function hideOverlay() {
      ov.classList.add('hidden');
    }

    function showOverlay(txt) {
      ov.classList.remove('hidden');
      if (txt) statusTxt.innerText = txt;
    }

    function updateAudioBadge() {
      if (v.muted) {
        audioBadge.innerText = "🔇 MUTED (TAP TO UNMUTE)";
        audioBadge.style.borderColor = "rgba(255,255,255,0.2)";
      } else {
        audioBadge.innerText = "🔊 SOUND ON";
        audioBadge.style.borderColor = "#00F0FF";
      }
    }

    function forcePlay() {
      v.muted = false;
      updateAudioBadge();
      v.play().then(function() {
        hideOverlay();
      }).catch(function(err) {
        v.muted = true;
        updateAudioBadge();
        v.play().then(hideOverlay).catch(function(){});
      });
    }

    // Hide buffering overlay as soon as video advances frames
    v.addEventListener('timeupdate', function() {
      if (v.currentTime > 0) hideOverlay();
    });

    v.addEventListener('playing', function() {
      hideOverlay();
      updateAudioBadge();
    });

    v.addEventListener('canplay', function() {
      v.play().then(hideOverlay).catch(function(){});
    });

    v.addEventListener('waiting', function() {
      if (v.currentTime === 0) showOverlay("Buffering video...");
    });

    // Fallback: If not playing within 3s, show manual play button
    setTimeout(function() {
      if (v.paused || v.currentTime === 0) {
        spin.style.display = 'none';
        statusTxt.innerText = "Video ready";
        playBtn.style.display = 'inline-block';
        v.play().then(hideOverlay).catch(function(){});
      }
    }, 3000);

    // Initial play attempt
    v.play().then(hideOverlay).catch(function(){});

    // Tap video body to toggle mute / play
    document.body.addEventListener('click', function(e) {
      if (e.target.id === 'play-btn') return;
      if (v.paused) {
        v.play().then(hideOverlay).catch(function(){});
      } else {
        v.muted = !v.muted;
        updateAudioBadge();
      }
    });
  </script>
</body>
</html>
''';

    _controller.loadHtmlString(html, baseUrl: 'https://valorant-api.com');
  }

  /// Shortens a title like "Sentinels of Light Sheriff Level 4 - Video Preview"
  /// to "Sentinels of Light Sheriff · Lv.4" for the dialog header.
  String _shortTitle(String raw) {
    // Strip everything from " - " onwards
    var s = raw.contains(' - ') ? raw.substring(0, raw.indexOf(' - ')) : raw;
    // Compress "Level N" → "· Lv.N"
    s = s.replaceAllMapped(
      RegExp(r'Level\s+(\d+)', caseSensitive: false),
      (m) => '· Lv.${m[1]}',
    );
    return s.trim();
  }

  @override
  void dispose() {
    // Explicitly pause video and clear source to stop background audio playback on dialog close
    try {
      _controller.runJavaScript(
          "var v = document.getElementById('vid'); if (v) { v.pause(); v.src = ''; }");
      _controller.loadHtmlString('<html><body></body></html>');
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.red, width: 1.5),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Dialog Header — title trimmed to skin name + level only
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                const Icon(Icons.play_circle_outline_rounded,
                    color: AppColors.red, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _shortTitle(widget.title),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon:
                      const Icon(Icons.close, color: Colors.white54, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Video Container
          Container(
            height: 240,
            color: Colors.black,
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_isLoading)
                  const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: Color(0xFFFF4655)),
                        SizedBox(height: 12),
                        Text(
                          'Loading video player...',
                          style: TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // Dialog Footer
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'CLOSE',
                    style: TextStyle(
                      color: Color(0xFFFF4655),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
