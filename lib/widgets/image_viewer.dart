import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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
import 'media/gif_player.dart';
import 'media/image_error.dart';
import 'media/media_page_dots.dart';
import 'media/play_chip.dart';

/// Fullscreen image viewer with pinch and double-tap zoom.
///
/// A gallery pages on a swipe within [_pagingAngle] of horizontal. Any
/// steeper drag, like any drag on a single image, follows the finger freely
/// and dismisses based on vertical distance. A single tap toggles the
/// controls and the status bar; zooming in hides them. With a screen reader
/// on, the controls always stay shown.
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

  // The gallery swipe in progress, driven from [_PagingDragRecognizer], and
  // the hold its touch put on a settling page.
  Drag? _pageDrag;
  ScrollHoldController? _pageHold;

  // Set synchronously on tap so a second tap in the same frame, before the
  // button rebuilds, still sees the save in flight.
  bool _saving = false;

  // Whether the current image's alt text panel is open.
  bool _altTextOpen = false;

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
    final accessibleNavigation = MediaQuery.accessibleNavigationOf(context);
    if (accessibleNavigation && !_accessibleNavigation) {
      _releasePageDrag();
    }
    _accessibleNavigation = accessibleNavigation;
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
    _releasePageDrag();
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

  /// Lets go of a gallery swipe whose recognizer is about to be removed:
  /// disposing a recognizer reports neither end nor cancel.
  void _releasePageDrag() {
    _pageHold?.cancel();
    _pageDrag?.cancel();
  }

  void _onTransformChanged() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed == _zoomed) {
      return;
    }
    if (zoomed) {
      _releasePageDrag();
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
      _dragOffset += details.focalPointDelta;
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
    final localFile = image.localFile;
    final cacheManager = ImageCacheScope.of(context);

    var rendered = image.isGif
        ? SizedBox.expand(
            // Its still is the thumb (a local GIF's first frame); fullsize
            // is only fetched to play it. It labels itself with the alt.
            child: GifPlayer(
              image: image,
              fit: BoxFit.contain,
              playChipStyle: PlayChipStyle.detail,
              active: widget.images.length == 1 || index == _index,
              still: localFile != null
                  ? const SizedBox.shrink()
                  : CachedNetworkImage(
                      cacheManager: cacheManager,
                      imageUrl: image.thumb,
                      fit: BoxFit.contain,
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      errorWidget: (context, url, error) => ImageLoadError(
                        url: url,
                        error: error,
                        cacheManager: cacheManager,
                        fallback: const Icon(
                          Icons.broken_image,
                          color: AppColors.textMuted,
                          size: 48,
                        ),
                      ),
                    ),
            ),
          )
        : localFile != null
        ? Image.file(
            localFile,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const Icon(
              Icons.broken_image,
              color: AppColors.textMuted,
              size: 48,
            ),
          )
        : CachedNetworkImage(
            cacheManager: cacheManager,
            imageUrl: image.fullsize,
            fit: BoxFit.contain,
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            // Show the thumb while the fullsize downloads. It is almost
            // always already in the cache from the feed or the post body, so
            // the viewer opens on the picture instead of on a black screen.
            placeholder: (context, url) => CachedNetworkImage(
              cacheManager: cacheManager,
              imageUrl: image.thumb,
              fit: BoxFit.contain,
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
              errorWidget: (context, url, error) => const SizedBox.shrink(),
            ),
            errorWidget: (context, url, error) => ImageLoadError(
              url: url,
              error: error,
              cacheManager: cacheManager,
              fallback: const Icon(
                Icons.broken_image,
                color: AppColors.textMuted,
                size: 48,
              ),
            ),
          );

    if (!image.isGif && alt != null && alt.isNotEmpty) {
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
        ? RawGestureDetector(
            // A zoomed page owns horizontal drags; no paging recognizer then,
            // so a pan at the picture's edge doesn't yank to the next image.
            // With a screen reader on, the PageView pages itself so its
            // scroll actions stay available.
            gestures: _zoomed || _accessibleNavigation
                ? const {}
                : _pagingGestures(),
            child: PageView.builder(
              controller: _pageController,
              // Otherwise paging is driven by the recognizer above, which
              // leaves steeper drags to the dismiss gesture; the physics only
              // snap to a page.
              physics: _zoomed
                  ? const NeverScrollableScrollPhysics()
                  : _accessibleNavigation
                  ? const PageScrollPhysics()
                  : const _DrivenPageScrollPhysics(),
              itemCount: widget.images.length,
              onPageChanged: (index) {
                setState(() {
                  _index = index;
                  _altTextOpen = false;
                });
                _transform.value = Matrix4.identity();
              },
              itemBuilder: _buildPage,
            ),
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

  Map<Type, GestureRecognizerFactory> _pagingGestures() {
    // Set up as Scrollable sets up its own drag recognizer, so flings and
    // devices behave as a stock PageView's do on each platform.
    final behavior = ScrollConfiguration.of(context);
    final physics = const _DrivenPageScrollPhysics().applyTo(
      behavior.getScrollPhysics(context),
    );
    return {
      _PagingDragRecognizer:
          GestureRecognizerFactoryWithHandlers<_PagingDragRecognizer>(
            () => _PagingDragRecognizer(
              debugOwner: this,
              supportedDevices: behavior.dragDevices,
            ),
            (recognizer) {
              recognizer
                ..minFlingDistance = physics.minFlingDistance
                ..minFlingVelocity = physics.minFlingVelocity
                ..maxFlingVelocity = physics.maxFlingVelocity
                ..velocityTrackerBuilder = behavior.velocityTrackerBuilder(
                  context,
                )
                ..multitouchDragStrategy = behavior.getMultitouchDragStrategy(
                  context,
                )
                ..supportedDevices = behavior.dragDevices
                // The device's touch slop, which the dismiss drag doubles for
                // its own: without it paging waits for the default 18px and
                // the dismiss drag claims every swipe first on a real phone.
                ..gestureSettings = MediaQuery.maybeGestureSettingsOf(context)
                ..onDown = (details) {
                  // Like Scrollable: a touch stops a page still settling.
                  _pageHold = _pageController!.position.hold(
                    () => _pageHold = null,
                  );
                }
                ..onStart = (details) {
                  _pageDrag = _pageController!.position.drag(
                    details,
                    () => _pageDrag = null,
                  );
                }
                ..onUpdate = (details) {
                  _pageDrag?.update(details);
                }
                ..onEnd = (details) {
                  _pageDrag?.end(details);
                }
                ..onCancel = () {
                  _pageHold?.cancel();
                  _pageDrag?.cancel();
                };
            },
          ),
    };
  }

  Widget _buildControls(BuildContext context, bool multi) {
    final alt = widget.images[_index].alt;
    // The controls sit in the image's held inset, so the status bar going
    // away doesn't move them on top of their slide.
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(padding: _imageInset),
      child: Stack(
        children: [
          if (alt != null && alt.isNotEmpty)
            _slideToEdge(
              direction: 1,
              child: SafeArea(
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    // Clear of the page dots, which sit centred at the same
                    // height.
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: _buildAltText(context, alt),
                  ),
                ),
              ),
            ),
          if (multi)
            _slideToEdge(
              direction: 1,
              child: SafeArea(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    // The dots draw their own pill, so no backdrop here.
                    child: KeyedSubtree(
                      key: const Key('image-viewer-page-indicator'),
                      child: MediaPageDots(
                        count: widget.images.length,
                        index: _index,
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

  /// The ALT badge, with the full alt text in a scrollable panel above it
  /// while open.
  Widget _buildAltText(BuildContext context, String alt) {
    void toggle() => setState(() => _altTextOpen = !_altTextOpen);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_altTextOpen)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ConstrainedBox(
              key: const Key('image-viewer-alt-text'),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.4,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    alt,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ),
          ),
        Semantics(
          key: const Key('image-viewer-alt-badge'),
          container: true,
          button: true,
          expanded: _altTextOpen,
          label: 'Show alt text',
          onTap: toggle,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: toggle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'ALT',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ),
      ],
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

/// How far from horizontal, in radians, a gallery swipe may start and still
/// page (about 30°). Steeper drags go to the dismiss gesture.
const double _pagingAngle = 0.52;

/// A horizontal drag that only claims gestures starting within
/// [_pagingAngle] of horizontal, so diagonal drags reach the dismiss gesture.
class _PagingDragRecognizer extends HorizontalDragGestureRecognizer {
  _PagingDragRecognizer({super.debugOwner, super.supportedDevices});

  static final double _tanPagingAngle = math.tan(_pagingAngle);

  /// Each pointer's travel since it went down, kept only until the drag is
  /// accepted: once paging starts, the swipe may bend any way it likes.
  final Map<int, Offset> _travel = {};

  bool _isSteep(Offset travel) =>
      travel.dy.abs() > travel.dx.abs() * _tanPagingAngle;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _travel[event.pointer] = Offset.zero;
    super.addAllowedPointer(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) {
    if (!super.hasSufficientGlobalDistanceToAccept(
      pointerDeviceKind,
      deviceTouchSlop,
    )) {
      return false;
    }
    return !_isSteep(_travel.values.fold(Offset.zero, (sum, t) => sum + t));
  }

  @override
  void rejectGesture(int pointer) {
    // A finger lost to another gesture no longer counts toward the angle.
    _travel.remove(pointer);
    super.rejectGesture(pointer);
  }

  @override
  void acceptGesture(int pointer) {
    _travel.clear();
    super.acceptGesture(pointer);
  }

  @override
  void handleEvent(PointerEvent event) {
    final travelSoFar = _travel[event.pointer];
    if (event is PointerMoveEvent && travelSoFar != null) {
      final travel = travelSoFar + event.delta;
      _travel[event.pointer] = travel;
      // Too steep before paging could start: leave it to the dismiss drag.
      // Rejecting goes through the arena, whose rejectGesture gives the
      // pointer up with the base class's own bookkeeping.
      if (_isSteep(travel) &&
          travel.distance > computeHitSlop(event.kind, gestureSettings)) {
        _travel.remove(event.pointer);
        resolvePointer(event.pointer, GestureDisposition.rejected);
        return;
      }
    }
    super.handleEvent(event);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _travel.clear();
    super.didStopTrackingLastPointer(pointer);
  }
}

/// Page snapping without the PageView's own drag recognizer, which
/// [_PagingDragRecognizer] replaces.
class _DrivenPageScrollPhysics extends PageScrollPhysics {
  const _DrivenPageScrollPhysics({super.parent});

  @override
  _DrivenPageScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _DrivenPageScrollPhysics(parent: buildParent(ancestor));

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) => false;
}
