import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../models/post.dart';

/// Fullscreen image viewer with pinch and double-tap zoom.
///
/// Multi-image galleries page horizontally and dismiss with a vertical drag.
/// A single image follows free-direction drags and dismisses based on vertical
/// distance.
class ImageViewer extends StatefulWidget {
  const ImageViewer({required this.images, this.initialIndex = 0, super.key})
    : assert(images.length > 0, 'viewer needs at least one image');

  final List<EmbedImage> images;
  final int initialIndex;

  /// Pushes the viewer as a fullscreen dialog route.
  static void open(
    BuildContext context,
    List<EmbedImage> images, {
    int initialIndex = 0,
  }) {
    if (images.isEmpty) {
      return;
    }
    // A stale index (the exact bug the detail carousel guards against)
    // degrades weirdly rather than crashing: an out-of-extent PageView and
    // an indicator like "5/3". Clamp instead of trusting the caller.
    final index = initialIndex.clamp(0, images.length - 1);
    Navigator.of(context, rootNavigator: true).push<void>(
      PageRouteBuilder<void>(
        fullscreenDialog: true,
        // Not a MaterialPageRoute: Android's M3 zoom transition scale-fades
        // the incoming route, which on a black page holding one image reads
        // as a ghost of the image growing into place. A quick plain fade
        // fits a lightbox.
        transitionDuration: const Duration(milliseconds: 150),
        reverseTransitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (context, animation, secondaryAnimation) =>
            ImageViewer(images: images, initialIndex: index),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer>
    with SingleTickerProviderStateMixin {
  late final PageController? _pageController = widget.images.length > 1
      ? PageController(initialPage: widget.initialIndex)
      : null;
  final TransformationController _transform = TransformationController();
  late final AnimationController _zoomAnimation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  )..addListener(_onZoomAnimation);
  late Matrix4Tween _zoomTween;
  late int _index = widget.initialIndex;
  bool _zoomed = false;

  // Swipe-to-dismiss state, mirroring FullscreenVideoPlayer's gesture.
  Offset _dragOffset = Offset.zero;
  bool _isDragging = false;
  final Set<int> _activePointers = {};
  bool _gestureHadMultiplePointers = false;
  bool _contactSequenceCanceled = false;
  Offset? _doubleTapPosition;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _zoomAnimation.dispose();
    _transform
      ..removeListener(_onTransformChanged)
      ..dispose();
    _pageController?.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) {
      setState(() => _zoomed = zoomed);
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    // A new touch takes ownership at the current interpolated transform.
    _zoomAnimation.stop();
    if (_activePointers.isEmpty) {
      _gestureHadMultiplePointers = false;
      _contactSequenceCanceled = false;
    }
    _activePointers.add(event.pointer);
    if (_activePointers.length > 1) {
      _gestureHadMultiplePointers = true;
      if (_isDragging) {
        _snapBack();
      }
    }
  }

  void _onPointerEnded(PointerEvent event) {
    _activePointers.remove(event.pointer);
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _contactSequenceCanceled = true;
    _activePointers.remove(event.pointer);
  }

  void _onInteractionStart(ScaleStartDetails details) {
    if (details.pointerCount > 1) {
      _gestureHadMultiplePointers = true;
      _snapBack();
    }
  }

  void _onInteractionUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount > 1) {
      _gestureHadMultiplePointers = true;
      if (_isDragging) {
        _snapBack();
      }
      return;
    }
    if (_gestureHadMultiplePointers || _zoomed) {
      return;
    }

    setState(() {
      _isDragging = true;
      _dragOffset += widget.images.length == 1
          ? details.focalPointDelta
          : Offset(0, details.focalPointDelta.dy);
    });
  }

  void _onInteractionEnd(ScaleEndDetails details) {
    if (_contactSequenceCanceled) {
      _snapBack();
      return;
    }
    final hadMultiplePointers =
        _gestureHadMultiplePointers || details.pointerCount > 1;
    // Dragged far enough in either direction: let the image go.
    if (!hadMultiplePointers && !_zoomed && _dragOffset.dy.abs() > 100) {
      Navigator.of(context).pop();
      return;
    }
    _snapBack();
  }

  void _onDoubleTapDown(TapDownDetails details) {
    _doubleTapPosition = details.localPosition;
  }

  void _onDoubleTap() {
    if (_zoomed) {
      _animateZoom(Matrix4.identity());
      return;
    }

    final position = _doubleTapPosition;
    if (position == null) {
      return;
    }
    const scale = 2.5;
    final target = Matrix4.identity()
      ..translateByDouble(position.dx, position.dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-position.dx, -position.dy, 0, 1);
    _animateZoom(target);
  }

  void _animateZoom(Matrix4 target) {
    _zoomTween = Matrix4Tween(begin: _transform.value.clone(), end: target);
    _zoomAnimation.forward(from: 0);
  }

  void _onZoomAnimation() {
    _transform.value = _zoomTween.transform(
      Curves.easeOutCubic.transform(_zoomAnimation.value),
    );
  }

  /// Releases a drag back to center after a short interaction or a sequence
  /// marked canceled by the raw pointer listener.
  void _snapBack() {
    if (_dragOffset == Offset.zero && !_isDragging) {
      return;
    }
    setState(() {
      _dragOffset = Offset.zero;
      _isDragging = false;
    });
  }

  Widget _buildPage(BuildContext context, int index) {
    final image = widget.images[index];
    final alt = image.alt;

    Widget rendered = CachedNetworkImage(
      imageUrl: image.fullsize,
      fit: BoxFit.contain,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      // Show the thumb while the fullsize downloads. It is almost always
      // already in the cache from the feed or the post body, so the viewer
      // opens on the picture instead of on a black screen.
      placeholder: (context, url) => CachedNetworkImage(
        imageUrl: image.thumb,
        fit: BoxFit.contain,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        errorWidget: (context, url, error) => const SizedBox.shrink(),
      ),
      errorWidget: (context, url, error) =>
          const Icon(Icons.broken_image, color: AppColors.textMuted, size: 48),
    );

    if (alt != null && alt.isNotEmpty) {
      rendered = Semantics(image: true, label: alt, child: rendered);
    }

    return Listener(
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerEnded,
      onPointerCancel: _onPointerCancel,
      child: GestureDetector(
        onDoubleTapDown: _onDoubleTapDown,
        onDoubleTap: _onDoubleTap,
        child: InteractiveViewer(
          transformationController: _transform,
          // The default minScale of 0.8 allows an under-zoom (scale < 1) that
          // keeps _zoomed false, so paging stays live while the shared
          // transform is non-identity — the neighbor page would render
          // shrunken mid-swipe. A lightbox has no use for under-zoom anyway.
          minScale: 1,
          maxScale: 4,
          // While zoomed, a one-finger drag pans the picture; at rest it
          // falls through to the PageView so the gallery can swipe.
          panEnabled: _zoomed,
          onInteractionStart: _onInteractionStart,
          onInteractionUpdate: _onInteractionUpdate,
          onInteractionEnd: _onInteractionEnd,
          child: Center(child: rendered),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final multi = widget.images.length > 1;
    // Fade the backdrop as the image is dragged toward release.
    final opacity = (1.0 - (_dragOffset.dy.abs() / 300)).clamp(0.0, 1.0);
    final content = multi
        ? PageView.builder(
            controller: _pageController,
            // A zoomed page owns horizontal drags; freeze paging so a
            // pan at the picture's edge doesn't yank to the next image.
            physics: _zoomed
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            itemCount: widget.images.length,
            onPageChanged: (index) {
              setState(() => _index = index);
              _transform.value = Matrix4.identity();
            },
            itemBuilder: _buildPage,
          )
        : _buildPage(context, 0);

    return Scaffold(
      key: const Key('image-viewer'),
      backgroundColor: Colors.black.withValues(alpha: opacity),
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedContainer(
              duration: _isDragging
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              transform: Matrix4.translationValues(
                _dragOffset.dx,
                _dragOffset.dy,
                0,
              ),
              child: content,
            ),
          ),
          if (multi)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Container(
                    key: const Key('image-viewer-page-indicator'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_index + 1}/${widget.images.length}',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close, color: AppColors.textPrimary),
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
