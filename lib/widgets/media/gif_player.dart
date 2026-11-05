import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../models/post.dart';
import 'gif_codec.dart';
import 'play_chip.dart';

/// The key of the in-place animated frame a [GifPlayer] shows.
const Key kGifFrameKey = Key('gif-frame');

/// GIF frames shorter than this are shown for [_defaultFrameDuration], as
/// browsers do: many GIFs store a 0 delay meaning "as fast as possible".
const Duration _minimumFrameDuration = Duration(milliseconds: 20);
const Duration _defaultFrameDuration = Duration(milliseconds: 100);

/// A GIF that plays in place only when asked to.
///
/// Before a tap it shows [still] (the hydrated thumb) with a centred
/// `Play GIF` control and loads nothing. Playing loads the codec for
/// [EmbedImage.fullsize] through [GifCodecScope] and animates it; a small
/// `Pause GIF` control in the bottom-right corner freezes it on the current
/// frame. A load or decode failure returns to [still].
///
/// A local image (the optimistic copy of a fresh post) has no thumb, so its
/// still is the codec's first frame, decoded on build and never advanced
/// until played.
///
/// Playback stops, back to the still, when the player is disposed, when it
/// stops being [active] (a gallery page swiped away from, which can stay
/// built while a sliver of it is still on screen), and when it is given a
/// different image. It pauses, frozen on the current frame, while hidden:
/// under a disabled [TickerMode] (a covered route, an inactive tab) or with
/// the app in the background; it stays paused when shown again.
///
/// A GIF with a finite [ui.Codec.repetitionCount] stops on its last frame
/// after its last repetition; playing again starts from the first frame.
///
/// Only the controls take taps; a tap anywhere else falls through to the
/// enclosing surface.
class GifPlayer extends StatefulWidget {
  const GifPlayer({
    required this.image,
    required this.still,
    this.fit = BoxFit.cover,
    this.playChipStyle = PlayChipStyle.feed,
    this.active = true,
    this.labelsImage = true,
    super.key,
  });

  final EmbedImage image;

  /// What shows while no frame is decoded.
  final Widget still;

  final BoxFit fit;
  final PlayChipStyle playChipStyle;

  /// Whether this is the item the user is looking at. Turning false stops
  /// playback.
  final bool active;

  /// Whether the player labels its picture with the image's alt text. False
  /// when the enclosing surface already carries that label.
  final bool labelsImage;

  @override
  State<GifPlayer> createState() => _GifPlayerState();
}

class _GifPlayerState extends State<GifPlayer> with WidgetsBindingObserver {
  /// Bumped whenever playback is torn down, so a load or decode started
  /// before then is dropped when it completes.
  int _session = 0;

  ui.Codec? _codec;
  bool _loadingCodec = false;
  bool _decoding = false;

  /// Whether the user asked for playback (and has not paused it).
  bool _playing = false;

  /// The frame on screen, and how much of its duration is left to show.
  ui.Image? _frame;
  Duration _frameRemaining = Duration.zero;

  /// The decoded frame after [_frame], waiting for its turn.
  ui.FrameInfo? _nextFrame;

  /// Counts down [_frameRemaining] while playing.
  Timer? _frameTimer;

  /// The frame timestamp [_frameTimer] started counting from, so a pause
  /// can keep what is left of the current frame.
  Duration? _frameTimingStartedAt;

  /// Bumped by every start and pause of [_frameTimer], so a frame callback
  /// measuring an earlier one is dropped.
  int _timingToken = 0;

  /// The index in the codec of [_frame], or -1 when nothing is shown.
  int _frameIndex = -1;

  /// How many times the last frame has finished showing since playback
  /// last started from the first frame.
  int _completedPasses = 0;

  /// How long [_frame] shows for in full.
  Duration _frameDuration = Duration.zero;

  bool get _isLocal => widget.image.localFile != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A covered route disables TickerMode; an inactive IndexedStack tab only
    // reports itself through Visibility.
    final hidden =
        !TickerMode.valuesOf(context).enabled || !Visibility.of(context);
    if (hidden && _playing) {
      _pause();
    }
    _loadLocalStill();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        if (_playing) {
          // No frames are drawn in the background, so a frame callback would
          // only measure the pause once the app is back.
          _pause(measureNow: true);
        }
      case AppLifecycleState.resumed:
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  void didUpdateWidget(GifPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image.fullsize != widget.image.fullsize ||
        oldWidget.image.localFile != widget.image.localFile ||
        (oldWidget.active && !widget.active)) {
      _tearDown();
      _loadLocalStill();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tearDown();
    super.dispose();
  }

  void _loadLocalStill() {
    if (_isLocal && _codec == null && !_loadingCodec) {
      _loadCodec();
    }
  }

  void _tearDown() {
    _session++;
    _frameTimer?.cancel();
    _frameTimer = null;
    _frameTimingStartedAt = null;
    _codec?.dispose();
    _codec = null;
    _frame?.dispose();
    _frame = null;
    _nextFrame?.image.dispose();
    _nextFrame = null;
    _frameRemaining = Duration.zero;
    _frameIndex = -1;
    _completedPasses = 0;
    _loadingCodec = false;
    _decoding = false;
    _playing = false;
  }

  Future<void> _loadCodec() async {
    final session = _session;
    final loader = GifCodecScope.of(context);
    _loadingCodec = true;
    final ui.Codec codec;
    try {
      codec = await loader(widget.image.fullsize);
    } on Object catch (error) {
      _fail(session, error);
      return;
    }
    if (session != _session || !mounted) {
      codec.dispose();
      return;
    }
    _loadingCodec = false;
    _codec = codec;
    _decodeNext();
  }

  /// Decodes the frame after [_frame], or the first one when nothing is
  /// shown yet. While stopped only the first frame is decoded.
  void _decodeNext() {
    final codec = _codec;
    if (codec == null || _decoding || _nextFrame != null) {
      return;
    }
    if (_frame != null && (!_playing || codec.frameCount < 2)) {
      return;
    }
    final session = _session;
    _decoding = true;
    codec.getNextFrame().then((info) {
      if (session != _session || !mounted) {
        info.image.dispose();
        return;
      }
      _decoding = false;
      if (_frame == null) {
        _show(info);
        return;
      }
      _nextFrame = info;
      if (_isFrameDue) {
        _advance();
      }
    }, onError: (Object error) => _fail(session, error));
  }

  /// Whether playback is waiting on [_nextFrame] to replace [_frame].
  bool get _isFrameDue =>
      _playing &&
      _frame != null &&
      _frameTimer == null &&
      _frameRemaining == Duration.zero;

  void _advance() {
    final next = _nextFrame;
    if (next == null) {
      return;
    }
    _nextFrame = null;
    _show(next);
  }

  void _show(ui.FrameInfo info) {
    _frame?.dispose();
    _frame = info.image;
    final frameCount = _codec?.frameCount ?? 1;
    _frameIndex = (_frameIndex + 1) % (frameCount < 1 ? 1 : frameCount);
    _frameDuration = info.duration < _minimumFrameDuration
        ? _defaultFrameDuration
        : info.duration;
    _frameRemaining = _frameDuration;
    setState(() {});
    if (_playing) {
      _startFrameTimer();
      _decodeNext();
    }
  }

  void _startFrameTimer() {
    final token = ++_timingToken;
    _frameTimer = Timer(_frameRemaining, _onFrameDue);
    _frameTimingStartedAt = null;
    // Timed from the frame that first draws it: frames are only drawn when
    // scheduled, so the last frame's timestamp is a stale clock, but the
    // frame this setState schedules is not.
    _onNextFrame(token, (timeStamp) => _frameTimingStartedAt = timeStamp);
  }

  /// Runs [callback] with the next frame's timestamp, unless playback was
  /// started, paused or torn down again before it.
  void _onNextFrame(int token, void Function(Duration timeStamp) callback) {
    final session = _session;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      if (session == _session && token == _timingToken) {
        callback(SchedulerBinding.instance.currentSystemFrameTimeStamp);
      }
    });
  }

  void _onFrameDue() {
    _frameTimer = null;
    _frameTimingStartedAt = null;
    _frameRemaining = Duration.zero;
    final codec = _codec;
    if (codec != null && codec.frameCount < 2) {
      // A still: one play shows it for its duration, whatever the loop
      // count says.
      setState(() => _playing = false);
      return;
    }
    if (codec != null && _frameIndex == codec.frameCount - 1) {
      _completedPasses++;
      final repetitions = codec.repetitionCount;
      if (repetitions >= 0 && _completedPasses > repetitions) {
        // Done: stay on the last frame. The codec wraps on its own, so the
        // frame decoded next is the first, and playing again shows it.
        _completedPasses = 0;
        setState(() => _playing = false);
        return;
      }
    }
    _advance();
  }

  void _play() {
    setState(() => _playing = true);
    if (_codec == null) {
      if (!_loadingCodec) {
        _loadCodec();
      }
      return;
    }
    if (_frame == null) {
      _decodeNext();
      return;
    }
    if (_frameRemaining == Duration.zero && _codec!.frameCount < 2) {
      // A still replays by showing its one frame again.
      _frameRemaining = _frameDuration;
    }
    if (_frameRemaining > Duration.zero) {
      _startFrameTimer();
    } else {
      _advance();
    }
    _decodeNext();
  }

  /// Freezes playback on the current frame. [measureNow] measures what is
  /// left of the frame against the last drawn frame instead of the next one,
  /// for when no next frame will be drawn soon.
  void _pause({bool measureNow = false}) {
    final timer = _frameTimer;
    if (timer != null) {
      timer.cancel();
      _frameTimer = null;
      final startedAt = _frameTimingStartedAt;
      void keepRemaining(Duration now) {
        final elapsed = startedAt == null || now < startedAt
            ? Duration.zero
            : now - startedAt;
        // Never zero: zero means the frame is due and waiting to advance.
        _frameRemaining = elapsed >= _frameRemaining
            ? const Duration(microseconds: 1)
            : _frameRemaining - elapsed;
      }

      final token = ++_timingToken;
      if (measureNow) {
        keepRemaining(SchedulerBinding.instance.currentSystemFrameTimeStamp);
      } else {
        // What is left of the frame is measured at the frame the pause
        // draws, for the same reason the start is.
        _onNextFrame(token, keepRemaining);
      }
      _frameTimingStartedAt = null;
    }
    // A load still in flight carries on and shows its first frame, paused.
    setState(() => _playing = false);
  }

  void _fail(int session, Object error) {
    if (session != _session || !mounted) {
      return;
    }
    if (kDebugMode) {
      debugPrint('GIF playback failed (${error.runtimeType})');
    }
    setState(_tearDown);
  }

  @override
  Widget build(BuildContext context) {
    final frame = _frame;
    final alt = widget.image.alt;

    var content = frame != null
        ? RawImage(key: kGifFrameKey, image: frame, fit: widget.fit)
        : widget.still;
    if (widget.labelsImage && alt != null && alt.isNotEmpty) {
      content = Semantics(image: true, label: alt, child: content);
    }

    final style = widget.playChipStyle;
    final control = switch ((_playing, frame)) {
      (false, _) => Positioned.fill(
        child: Center(
          child: _GifControl(
            label: 'Play GIF',
            onTap: _play,
            chip: PlayChip(style: style),
          ),
        ),
      ),
      // Asked to play, still loading.
      (true, null) => Positioned.fill(
        child: Center(
          child: _GifControl(
            label: 'Pause GIF',
            onTap: _pause,
            chip: PlayChip(style: style, loading: true),
          ),
        ),
      ),
      // Small and in the corner so it never covers the animation.
      (true, _) => Positioned(
        right: 8,
        bottom: 8,
        child: _GifControl(
          label: 'Pause GIF',
          onTap: _pause,
          chip: PlayChip(
            style: style,
            glyph: PlayChipGlyph.pause,
            compact: true,
          ),
        ),
      ),
    };

    return Stack(fit: StackFit.passthrough, children: [content, control]);
  }
}

/// A play or pause control: its own button node, and a tap target that
/// wins over the surface's own gestures the moment the finger lifts, even
/// when the surface also listens for a double tap (the viewer's zoom), which
/// would otherwise hold every tap back for the double-tap timeout.
class _GifControl extends StatelessWidget {
  const _GifControl({
    required this.label,
    required this.onTap,
    required this.chip,
  });

  final String label;
  final VoidCallback onTap;
  final Widget chip;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: label,
      // The custom recognizer adds no semantics action of its own.
      onTap: onTap,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          _ImmediateTapRecognizer:
              GestureRecognizerFactoryWithHandlers<_ImmediateTapRecognizer>(
                _ImmediateTapRecognizer.new,
                (recognizer) => recognizer.onTap = onTap,
              ),
        },
        child: chip,
      ),
    );
  }
}

/// A tap that claims the gesture arena on pointer up instead of waiting for
/// the arena to be swept, so an enclosing double-tap recognizer holding the
/// arena does not delay it. A drag past the slop still rejects it first.
class _ImmediateTapRecognizer extends TapGestureRecognizer {
  @override
  void handlePrimaryPointer(PointerEvent event) {
    if (event is PointerUpEvent) {
      resolve(GestureDisposition.accepted);
    }
    super.handlePrimaryPointer(event);
  }
}
