import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../constants/app_theme.dart';
import '../models/post.dart';
import '../services/media_saver.dart';
import '../utils/app_route_observer.dart';
import 'icons/lucide_icon_painter.dart';
import 'icons/lucide_paths.dart';

/// Fullscreen image viewer with pinch and double-tap zoom.
///
/// Multi-image galleries page horizontally and dismiss with a vertical drag.
/// A single image follows free-direction drags and dismisses based on vertical
/// distance. A single tap toggles the controls and the status bar; zooming in
/// hides them. With a screen reader on, the controls always stay shown.
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
    with TickerProviderStateMixin, RouteAware {
  // A zoomed image can pan under the navigation bar, so the bar goes clear.
  // On API 35+ edge-to-edge the color is ignored and only turning contrast
  // enforcement off removes the scrim.
  static final SystemUiOverlayStyle _zoomedNavigationBarStyle = AppTheme
      .navigationBarStyle
      .copyWith(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      );

  // Behind the control buttons and the page indicator pill, so they stay
  // visible over light images.
  static final Color _controlBackdropColor = Colors.black.withValues(
    alpha: 0.6,
  );

  static final ButtonStyle _controlButtonStyle = IconButton.styleFrom(
    backgroundColor: _controlBackdropColor,
    disabledBackgroundColor: _controlBackdropColor,
  );

  late final PageController? _pageController = widget.images.length > 1
      ? PageController(initialPage: widget.initialIndex)
      : null;
  final TransformationController _transform = TransformationController();
  late final AnimationController _zoomAnimation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  )..addListener(_onZoomAnimation);
  late Matrix4Tween _zoomTween;

  // Bluesky's lightbox FAST_SPRING: heavily damped, so the controls move
  // fast and then ease out while the status bar is still sliding.
  static final SpringDescription _controlsSpring = SpringDescription(
    mass: defaultTargetPlatform == TargetPlatform.iOS ? 1.25 : 0.75,
    stiffness: 900,
    damping: 150,
  );

  // How far the controls travel toward their edge as they hide.
  static const double _controlsHiddenOffset = 30;

  // 1 shown, 0 hidden; drives both opacity and the slide.
  late final AnimationController _controlsAnimation = AnimationController(
    vsync: this,
    value: 1,
  );
  late int _index = widget.initialIndex;
  bool _zoomed = false;
  bool _controlsVisible = true;
  bool _accessibleNavigation = false;

  // Whether the viewer has hidden the status bar, so it only talks to the
  // platform when the hidden state changes and restores only what it hid.
  bool _statusBarHidden = false;

  // Set while the viewer is closing or covered by another route: the system
  // bars belong to the app again, and the viewer sends nothing until a
  // covering route pops back to it.
  bool _systemUiReleased = false;

  ModalRoute<void>? _route;
  Size? _screenSize;

  // Hiding the status bar zeroes the top padding. The image keeps the inset
  // it had while the controls were shown, and only follows the reported
  // padding again once that changes after the controls come back.
  EdgeInsets _padding = EdgeInsets.zero;
  EdgeInsets? _heldInset;
  EdgeInsets? _paddingWhenShown;

  // Swipe-to-dismiss state, mirroring FullscreenVideoPlayer's gesture.
  Offset _dragOffset = Offset.zero;
  bool _isDragging = false;
  final Set<int> _activePointers = {};
  bool _gestureHadMultiplePointers = false;
  bool _contactSequenceCanceled = false;
  Offset? _doubleTapPosition;

  // Set synchronously on tap so a second tap in the same frame, before the
  // button rebuilds, still sees the save in flight.
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransformChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _route) {
      _route?.animation?.removeStatusListener(_onRouteAnimationStatus);
      appRouteObserver.unsubscribe(this);
      _route = route is ModalRoute<void> ? route : null;
      _route?.animation?.addStatusListener(_onRouteAnimationStatus);
      if (_route case final route?) {
        appRouteObserver.subscribe(this, route);
      }
    }
    _padding = MediaQuery.paddingOf(context);
    // A new screen size (a rotation, a resized window) makes the held inset
    // meaningless; the new real padding applies.
    final screenSize = MediaQuery.sizeOf(context);
    if (_screenSize != null && screenSize != _screenSize) {
      _heldInset = null;
      _paddingWhenShown = null;
    }
    _screenSize = screenSize;
    _accessibleNavigation = MediaQuery.accessibleNavigationOf(context);
    if (_accessibleNavigation) {
      _controlsVisible = true;
    }
    if (_heldInset != null &&
        !_controlsHidden &&
        _paddingWhenShown != null &&
        _padding != _paddingWhenShown) {
      _heldInset = null;
      _paddingWhenShown = null;
    }
    _syncControlsHidden();
  }

  @override
  void dispose() {
    _releaseSystemUi();
    _route?.animation?.removeStatusListener(_onRouteAnimationStatus);
    appRouteObserver.unsubscribe(this);
    _zoomAnimation.dispose();
    _controlsAnimation.dispose();
    _transform
      ..removeListener(_onTransformChanged)
      ..dispose();
    _pageController?.dispose();
    super.dispose();
  }

  // The pop animation reverses on the first frame of the pop; restoring the
  // bars there, rather than in dispose after the fade, keeps the page below
  // from appearing without its status bar.
  void _onRouteAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.reverse) {
      _releaseSystemUi();
    }
  }

  @override
  void didPushNext() => _releaseSystemUi();

  @override
  void didPopNext() {
    if (!_systemUiReleased) {
      return;
    }
    _systemUiReleased = false;
    if (_zoomed) {
      SystemChrome.setSystemUIOverlayStyle(_zoomedNavigationBarStyle);
    }
    _syncControlsHidden();
  }

  /// Hands the system bars back to the app: the closing pop, a covering
  /// route and dispose all release through here, once.
  void _releaseSystemUi() {
    if (_systemUiReleased) {
      return;
    }
    _systemUiReleased = true;
    if (_zoomed) {
      SystemChrome.setSystemUIOverlayStyle(AppTheme.navigationBarStyle);
    }
    if (_statusBarHidden) {
      _statusBarHidden = false;
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
  }

  /// The one place the controls count as hidden; opacity, hit testing, focus
  /// and the status bar all follow it.
  bool get _controlsHidden => !_controlsVisible && !_accessibleNavigation;

  EdgeInsets get _imageInset => _heldInset ?? _padding;

  void _syncControlsHidden() {
    final hidden = _controlsHidden;
    _animateControls(shown: !hidden);
    if (_systemUiReleased || hidden == _statusBarHidden) {
      return;
    }
    _statusBarHidden = hidden;
    if (hidden) {
      _heldInset ??= _padding;
      _paddingWhenShown = null;
      // Manual mode with only the bottom overlay hides the status bar and
      // keeps the navigation bar without moving the layout.
      unawaited(
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: [SystemUiOverlay.bottom],
        ),
      );
    } else {
      if (_heldInset != null) {
        _paddingWhenShown = _padding;
      }
      // Edge-to-edge, not manual with both overlays: it is the app's mode.
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
  }

  void _animateControls({required bool shown}) {
    final target = shown ? 1.0 : 0.0;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controlsAnimation.value = target;
      return;
    }
    if (_controlsAnimation.value == target && !_controlsAnimation.isAnimating) {
      return;
    }
    _controlsAnimation.animateWith(
      SpringSimulation(
        _controlsSpring,
        _controlsAnimation.value,
        target,
        _controlsAnimation.velocity,
        snapToEnd: true,
      ),
    );
  }

  void _onTransformChanged() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed == _zoomed) {
      return;
    }
    if (!_systemUiReleased) {
      SystemChrome.setSystemUIOverlayStyle(
        zoomed ? _zoomedNavigationBarStyle : AppTheme.navigationBarStyle,
      );
    }
    setState(() {
      _zoomed = zoomed;
      // Zooming in clears the picture; zooming out leaves the controls to
      // the next tap.
      if (zoomed) {
        _controlsVisible = false;
      }
    });
    _syncControlsHidden();
  }

  void _onTap() {
    if (_accessibleNavigation) {
      return;
    }
    setState(() => _controlsVisible = !_controlsVisible);
    _syncControlsHidden();
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

  void _onSavePressed() {
    if (_saving) {
      return;
    }
    // Looked up before any busy state so a missing provider throws from the
    // tap itself instead of leaving a stuck spinner. The messenger is captured
    // before the await: the viewer may be closed by the time the save
    // finishes.
    final saver = context.read<MediaSaver>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    unawaited(_saveImage(saver, messenger));
  }

  Future<void> _saveImage(
    MediaSaver saver,
    ScaffoldMessengerState messenger,
  ) async {
    String message;
    try {
      await saver.saveImage(widget.images[_index].fullsize);
      message = 'Saved to Photos';
    } on MediaSaveException catch (error) {
      message = switch (error.failure) {
        MediaSaveFailure.accessDenied =>
          'Allow photo access in Settings to save images',
        MediaSaveFailure.downloadFailed =>
          "Couldn't download image. Check your connection and try again.",
        MediaSaveFailure.saveFailed => "Couldn't save image",
      };
    } on Object {
      message = "Couldn't save image";
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
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
        onTap: _onTap,
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
          // The inset sits inside the zoom surface, unclipped, so the image
          // fits between the system bars at rest yet pans under them zoomed.
          child: Padding(
            padding: _imageInset,
            child: Center(
              key: const Key('image-viewer-image-slot'),
              child: rendered,
            ),
          ),
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
          Positioned.fill(
            child: ExcludeFocus(
              excluding: _controlsHidden,
              child: IgnorePointer(
                ignoring: _controlsHidden,
                child: FadeTransition(
                  opacity: _controlsAnimation,
                  child: _buildControls(context, multi),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context, bool multi) {
    // The controls sit in the image's held inset, so the status bar going
    // away doesn't move them on top of their slide.
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(padding: _imageInset),
      child: Stack(
        children: [
          if (multi)
            _slideToEdge(
              direction: 1,
              child: SafeArea(
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
                        color: _controlBackdropColor,
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
            ),
          _slideToEdge(
            direction: -1,
            child: SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  // Same 24px footprint as the glyph so the button doesn't
                  // shift while saving.
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 24,
                          child: Padding(
                            padding: EdgeInsets.all(3),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        )
                      : const LucideGlyph(
                          LucidePaths.download,
                          color: AppColors.textPrimary,
                        ),
                  tooltip: 'Save image',
                  style: _controlButtonStyle,
                  onPressed: _saving ? null : _onSavePressed,
                ),
              ),
            ),
          ),
          _slideToEdge(
            direction: -1,
            child: SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textPrimary),
                  tooltip: 'Close',
                  style: _controlButtonStyle,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Moves [child] up to [_controlsHiddenOffset] toward the bottom edge
  /// ([direction] 1) or the top edge (-1) as the controls hide.
  Widget _slideToEdge({required double direction, required Widget child}) {
    return AnimatedBuilder(
      animation: _controlsAnimation,
      builder: (context, child) => Transform.translate(
        offset: Offset(
          0,
          direction * _controlsHiddenOffset * (1 - _controlsAnimation.value),
        ),
        child: child,
      ),
      child: child,
    );
  }
}
