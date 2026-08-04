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
  bool _hasError = false;

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
    } on Object catch (_) {
      // Deliberately catches Errors as well as Exceptions: the video_player
      // platform channel throws UnimplementedError when no implementation is
      // registered, and an `on Exception` clause lets that escape — leaving
      // the user watching a spinner that never resolves.
      //
      // The thrown object is not logged: it can carry the video URL, which
      // may be a signed blob endpoint with credentials in the query string.
      if (kDebugMode) {
        debugPrint('FullscreenVideoPlayer: video initialization failed');
      }
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _hasError = true;
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

  /// The centre of the screen: the failure notice, the loading spinner, or
  /// the video itself.
  Widget _buildStage() {
    if (_hasError) {
      return _buildErrorState();
    }

    if (_isInitializing || _videoController == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.loadingIndicator),
      );
    }

    return Center(
      child: AspectRatio(
        aspectRatio: _videoController!.value.aspectRatio,
        child: VideoPlayer(_videoController!),
      ),
    );
  }

  /// Shown when the video could not be initialized.
  ///
  /// The player is a full-screen route, so without a visible way out a
  /// failure would otherwise trap the user on a black screen — swipe-to-
  /// dismiss still works, but nothing on screen advertises it.
  Widget _buildErrorState() {
    return Center(
      key: const Key('fullscreen-video-error'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.videocam_off_outlined,
              color: AppColors.textSecondary,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              "This video couldn't be played.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textPrimary.withValues(alpha: 0.9),
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 8),
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(
                Icons.close,
                color: AppColors.textPrimary,
                semanticLabel: 'Close',
              ),
            ),
          ],
        ),
      ),
    );
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
              child: SizedBox.expand(child: _buildStage()),
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
