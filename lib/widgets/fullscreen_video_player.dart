import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../constants/app_colors.dart';
import 'minimal_video_controls.dart';

/// Fullscreen video player with swipe-to-dismiss gesture
///
/// Displays the video player in fullscreen with a black background.
/// Supports vertical swipe-down gesture to dismiss (like Instagram/TikTok).
class FullscreenVideoPlayer extends StatefulWidget {
  const FullscreenVideoPlayer({required this.videoUrl, super.key});

  final String videoUrl;

  @override
  State<FullscreenVideoPlayer> createState() => _FullscreenVideoPlayerState();
}

class _FullscreenVideoPlayerState extends State<FullscreenVideoPlayer>
    with WidgetsBindingObserver {
  double _dragOffsetX = 0;
  double _dragOffsetY = 0;
  bool _isDragging = false;
  VideoPlayerController? _videoController;
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializePlayer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _videoController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pause video when app goes to background
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _videoController?.pause();
    }
  }

  Future<void> _initializePlayer() async {
    try {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
      );

      await _videoController!.initialize();
      await _videoController!.play();

      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('Error initializing video: $e');
      }
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _isDragging = true;
      // Track both horizontal and vertical movement
      _dragOffsetX += details.delta.dx;
      _dragOffsetY += details.delta.dy;
    });
  }

  void _onPanEnd(DragEndDetails details) {
    // If dragged more than 100 pixels vertically, dismiss
    if (_dragOffsetY.abs() > 100) {
      Navigator.of(context).pop();
    } else {
      // Otherwise, animate back to original position
      setState(() {
        _dragOffsetX = 0.0;
        _dragOffsetY = 0.0;
        _isDragging = false;
      });
    }
  }

  void _togglePlayPause() {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return;
    }

    setState(() {
      if (_videoController!.value.isPlaying) {
        _videoController!.pause();
      } else {
        _videoController!.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Calculate opacity based on drag offset (fade out as user drags)
    final opacity = (1.0 - (_dragOffsetY.abs() / 300)).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: opacity),
      body: GestureDetector(
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        onTap: _togglePlayPause,
        child: Stack(
          children: [
            // Video player - fills entire screen and moves with drag
            AnimatedContainer(
              duration:
                  _isDragging
                      ? Duration.zero
                      : const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              transform: Matrix4.translationValues(
                _dragOffsetX,
                _dragOffsetY,
                0,
              ),
              child: SizedBox.expand(
                child:
                    _isInitializing || _videoController == null
                        ? const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.loadingIndicator,
                          ),
                        )
                        : Center(
                          child: AspectRatio(
                            aspectRatio: _videoController!.value.aspectRatio,
                            child: VideoPlayer(_videoController!),
                          ),
                        ),
              ),
            ),
            // Minimal controls at bottom (scrubber only)
            if (_videoController != null &&
                _videoController!.value.isInitialized)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: MinimalVideoControls(controller: _videoController!),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
