import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Modal dialog for playing level upgrade VFX & finisher videos cleanly without blocking UI.
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
  VideoPlayerController? _controller;
  bool _hasError = false;
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      final uri = Uri.parse(widget.videoUrl);
      final controller = VideoPlayerController.networkUrl(uri);
      _controller = controller;
      await controller.initialize();
      controller.setLooping(true);
      controller.setVolume(1.0);
      controller.play();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _hasError = true);
    }
  }

  @override
  void dispose() {
    _controller?.pause();
    _controller?.dispose();
    super.dispose();
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
            height: 220,
            color: Colors.black,
            child: _buildVideoContent(),
          ),

          // Dialog Footer Controls
          if (_controller != null && _controller!.value.isInitialized)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      _controller!.value.isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                      color: const Color(0xFFFF4655),
                      size: 28,
                    ),
                    onPressed: () {
                      setState(() {
                        if (_controller!.value.isPlaying) {
                          _controller!.pause();
                        } else {
                          _controller!.play();
                        }
                      });
                    },
                  ),
                  IconButton(
                    icon: Icon(
                      _isMuted ? Icons.volume_off : Icons.volume_up,
                      color: Colors.white70,
                      size: 22,
                    ),
                    onPressed: () {
                      setState(() {
                        _isMuted = !_isMuted;
                        _controller!.setVolume(_isMuted ? 0.0 : 1.0);
                      });
                    },
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'CLOSE',
                      style: TextStyle(
                        color: Colors.white54,
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

  Widget _buildVideoContent() {
    if (_hasError) {
      return const Center(
        child: Text(
          'Video preview unavailable',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
      );
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFFFF4655)),
            SizedBox(height: 12),
            Text(
              'Loading Video Stream...',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
      );
    }

    return AspectRatio(
      aspectRatio: controller.value.aspectRatio > 0
          ? controller.value.aspectRatio
          : 16 / 9,
      child: VideoPlayer(controller),
    );
  }
}
