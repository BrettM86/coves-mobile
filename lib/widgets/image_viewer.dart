import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../models/post.dart';

/// Fullscreen, zoomable viewer for native image embeds.
///
/// Shows [images] starting at [initialIndex]. A multi-image gallery is
/// swipeable with an i/N indicator; pinch zooms any page. Swiping the
/// image away vertically (or the close button) dismisses the viewer,
/// matching the fullscreen video player's gesture.
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
        pageBuilder:
            (context, animation, secondaryAnimation) =>
                ImageViewer(images: images, initialIndex: index),
        transitionsBuilder:
            (context, animation, secondaryAnimation, child) =>
                FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  late final PageController _pageController = PageController(
    initialPage: widget.initialIndex,
  );
  final TransformationController _transform = TransformationController();
  late int _index = widget.initialIndex;
  bool _zoomed = false;

  // Swipe-to-dismiss state, mirroring FullscreenVideoPlayer's gesture.
  double _dragOffsetY = 0;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transform
      ..removeListener(_onTransformChanged)
      ..dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) {
      setState(() => _zoomed = zoomed);
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _isDragging = true;
      _dragOffsetY += details.delta.dy;
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    // Dragged far enough in either direction: let the image go.
    if (_dragOffsetY.abs() > 100) {
      Navigator.of(context).pop();
      return;
    }
    _snapBack();
  }

  /// Releases a drag back to center. Also handles the cancel path (incoming
  /// call, OS edge-gesture takeover) — without it the image would stay
  /// stranded mid-dismiss over a dimmed backdrop.
  void _snapBack() {
    setState(() {
      _dragOffsetY = 0;
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
      placeholder:
          (context, url) => CachedNetworkImage(
            imageUrl: image.thumb,
            fit: BoxFit.contain,
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            errorWidget: (context, url, error) => const SizedBox.shrink(),
          ),
      errorWidget:
          (context, url, error) => const Icon(
            Icons.broken_image,
            color: AppColors.textMuted,
            size: 48,
          ),
    );

    if (alt != null && alt.isNotEmpty) {
      rendered = Semantics(image: true, label: alt, child: rendered);
    }

    return InteractiveViewer(
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
      child: Center(child: rendered),
    );
  }

  @override
  Widget build(BuildContext context) {
    final multi = widget.images.length > 1;
    // Fade the backdrop as the image is dragged toward release.
    final opacity = (1.0 - (_dragOffsetY.abs() / 300)).clamp(0.0, 1.0);

    return Scaffold(
      key: const Key('image-viewer'),
      backgroundColor: Colors.black.withValues(alpha: opacity),
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              // While zoomed the drag belongs to InteractiveViewer's pan;
              // detaching the handlers keeps the recognizers out of each
              // other's arena instead of racing for the same finger.
              onVerticalDragUpdate: _zoomed ? null : _onVerticalDragUpdate,
              onVerticalDragEnd: _zoomed ? null : _onVerticalDragEnd,
              onVerticalDragCancel: _zoomed ? null : _snapBack,
              child: AnimatedContainer(
                duration:
                    _isDragging
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                transform: Matrix4.translationValues(0, _dragOffsetY, 0),
                child: PageView.builder(
                  controller: _pageController,
                  // A zoomed page owns horizontal drags; freeze paging so a
                  // pan at the picture's edge doesn't yank to the next image.
                  physics:
                      _zoomed
                          ? const NeverScrollableScrollPhysics()
                          : const PageScrollPhysics(),
                  itemCount: widget.images.length,
                  onPageChanged: (index) {
                    setState(() => _index = index);
                    _transform.value = Matrix4.identity();
                  },
                  itemBuilder: _buildPage,
                ),
              ),
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
