import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

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
    body, html { width: 100%; height: 100%; background: #000; overflow: hidden; position: relative; }
    video { width: 100%; height: 100%; object-fit: contain; position: absolute; top: 0; left: 0; }
    #overlay {
      position: absolute; top: 0; left: 0; width: 100%; height: 100%;
      display: flex; flex-direction: column; align-items: center; justify-content: center;
      background: rgba(0,0,0,0.55); z-index: 10;
      transition: opacity 0.3s ease;
    }
    #overlay.hidden { opacity: 0; pointer-events: none; }
    .spinner {
      width: 36px; height: 36px;
      border: 3px solid rgba(255,255,255,0.15);
      border-top-color: #FF4655;
      border-radius: 50%;
      animation: spin 0.7s linear infinite;
    }
    @keyframes spin { to { transform: rotate(360deg); } }
    #overlay p {
      margin-top: 10px; color: rgba(255,255,255,0.6);
      font: 12px -apple-system, BlinkMacSystemFont, sans-serif;
    }
    #tap-hint {
      position: absolute; bottom: 8px; left: 0; width: 100%; text-align: center;
      color: rgba(255,255,255,0.35); font: 10px -apple-system, sans-serif; z-index: 11;
    }
  </style>
</head>
<body>
  <div id="overlay">
    <div class="spinner"></div>
    <p>Buffering video...</p>
  </div>
  <video id="vid" preload="auto" autoplay loop muted playsinline webkit-playsinline></video>
  <div id="tap-hint">Tap video to unmute</div>
  <script>
    var v = document.getElementById('vid');
    var ov = document.getElementById('overlay');

    v.src = "$videoUrl";

    v.addEventListener('playing', function() { ov.classList.add('hidden'); });
    v.addEventListener('waiting', function() { ov.classList.remove('hidden'); });
    v.addEventListener('stalled', function() { ov.classList.remove('hidden'); });
    v.addEventListener('canplay', function() {
      v.play().catch(function(){});
    });

    // Retry play every 1.5s until video is truly playing
    var retryId = setInterval(function() {
      if (!v.paused && v.currentTime > 0) {
        clearInterval(retryId);
        return;
      }
      v.play().catch(function(){});
    }, 1500);

    // Stop retrying after 30s to avoid infinite loop
    setTimeout(function() { clearInterval(retryId); }, 30000);

    // Initial play attempt
    v.play().catch(function(){});

    // Tap to toggle mute
    document.body.addEventListener('click', function() {
      v.muted = !v.muted;
      v.play().catch(function(){});
    });
  </script>
</body>
</html>
''';

    _controller.loadHtmlString(html);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0E1622),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: widget.tierColor, width: 1.5),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Dialog Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54, size: 20),
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
