import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../models/bluesky_profile_import.dart';
import '../providers/viewer_authority_provider.dart';
import '../services/api_exceptions.dart';
import '../utils/bluesky_import_motion.dart';
import '../utils/error_messages.dart';
import 'bluesky_import/import_card_style.dart';
import 'bluesky_import/import_cards.dart';
import 'bluesky_import/seat_burst.dart';

/// Shows the Bluesky profile import choices and resolves to the imported
/// fields, an empty list when there was nothing to import, or null when the
/// dialog was declined or closed.
///
/// [handle] is the signed-in account's handle, shown under the display name;
/// the Bluesky account shares it, as both are the same atproto identity.
///
/// Declining (No thanks, the close button, a barrier tap or system back)
/// calls [onDecline]. A change of signed-in session closes the dialog without
/// declining.
Future<List<BlueskyProfileField>?> showBlueskyProfileImportDialog(
  BuildContext context, {
  required List<BlueskyImportChoice> choices,
  required Future<List<BlueskyProfileField>> Function(
    List<BlueskyProfileField> fields,
  )
  onImport,
  Future<void> Function()? onDecline,
  String? handle,
}) async {
  final outcome = await showDialog<_ImportDialogOutcome>(
    context: context,
    builder: (_) => _BlueskyProfileImportDialog(
      choices: choices,
      onImport: onImport,
      handle: handle,
    ),
  );
  if (outcome == null) {
    await onDecline?.call();
    return null;
  }
  return outcome.imported;
}

/// The snackbar text for a finished import: [imported] is what the dialog
/// resolved to.
String blueskyImportResultMessage(List<BlueskyProfileField> imported) =>
    imported.isEmpty ? 'Nothing to import' : 'Imported your Bluesky profile.';

/// How the dialog closed other than by declining. [imported] is null when a
/// session change closed it.
class _ImportDialogOutcome {
  const _ImportDialogOutcome(this.imported);

  final List<BlueskyProfileField>? imported;
}

const _hint = 'Drag onto your Coves profile, or tap Import profile';
const _description =
    'Drag your Bluesky card onto your Coves profile to copy it over. Tap a '
    'field to leave it out.';

/// A press becomes a drag once it has moved this far.
const _dragThreshold = 6.0;

const _springBackDuration = Duration(milliseconds: 300);
const _springBackCurve = Cubic(0.34, 1.56, 0.64, 1);
const _moveDuration = Duration(milliseconds: 560);
const _reducedMoveDuration = Duration(milliseconds: 150);
const _moveCurve = Cubic(0.2, 0.8, 0.2, 1);
const _inkTransition = Duration(milliseconds: 120);
const _seatPause = Duration(milliseconds: 2700);
const _reducedSeatPause = Duration(milliseconds: 600);

/// When each Coves slot starts popping in during the move, in milliseconds,
/// and how long each pop-in takes.
const _bannerPopIn = 180;
const _avatarPopIn = 240;
const _namePopIn = 300;
const _bioPopIn = 360;
const _popInLength = 200;

const _hintFontSize = 12.0;
const _hintLineHeight = 1.25;

enum _Phase {
  /// At rest, waiting for a drag, a tap or Import profile.
  idle,

  /// The card follows the pointer.
  dragging,

  /// The card springs back to its slot.
  returning,

  /// The card moves into the Coves slot.
  moving,

  /// The card has landed; the import runs and the seat pause holds.
  seated,
}

/// Where the floating copy of the Bluesky card is, in global coordinates,
/// its colour blend amount and its opacity.
@immutable
class _FloatingFrame {
  const _FloatingFrame(this.rect, this.blend, this.opacity);

  final Rect rect;
  final double blend;
  final double opacity;
}

class _BlueskyProfileImportDialog extends StatefulWidget {
  const _BlueskyProfileImportDialog({
    required this.choices,
    required this.onImport,
    required this.handle,
  });

  final List<BlueskyImportChoice> choices;
  final String? handle;
  final Future<List<BlueskyProfileField>> Function(
    List<BlueskyProfileField> fields,
  )
  onImport;

  @override
  State<_BlueskyProfileImportDialog> createState() =>
      _BlueskyProfileImportDialogState();
}

class _BlueskyProfileImportDialogState
    extends State<_BlueskyProfileImportDialog>
    with TickerProviderStateMixin {
  late final List<bool> _checked = [
    for (final choice in widget.choices) choice.initiallyChecked,
  ];
  _Phase _phase = _Phase.idle;
  bool _isClosed = false;
  String? _errorText;
  late final ViewerAuthorityProvider _viewerAuthority;
  late final Object? _sessionKey;

  final GlobalKey _cardKey = GlobalKey();
  final GlobalKey _covesKey = GlobalKey();
  final FocusNode _cardFocus = FocusNode(debugLabel: 'Bluesky card');
  late final List<FocusNode> _fieldFocus = [
    for (final choice in widget.choices)
      FocusNode(debugLabel: 'Bluesky ${choice.view.field.name}'),
  ];

  /// The card or field toggle that had keyboard focus when the card left
  /// its slot; it gets focus back once the card returns.
  FocusNode? _focusToRestore;

  // The press on the card.
  int? _pointer;
  Offset _pressStart = Offset.zero;
  bool _isDragging = false;
  int? _pressedField;

  /// The field a pointer last went down on, before the card decides whether
  /// that pointer is the press it follows.
  ({int pointer, int field})? _fieldPointerDown;

  /// The card's and the Coves card's global rects, measured when a press
  /// becomes a drag or a move starts.
  Rect _homeRect = Rect.zero;
  Rect _covesRect = Rect.zero;

  OverlayState? _overlay;
  OverlayEntry? _floatingEntry;
  final ValueNotifier<_FloatingFrame> _floating = ValueNotifier(
    const _FloatingFrame(Rect.zero, 0, 1),
  );

  /// Whether a release now would drop the card into the Coves slot.
  final ValueNotifier<bool> _wouldDrop = ValueNotifier(false);

  late final AnimationController _return = AnimationController(
    vsync: this,
    duration: _springBackDuration,
  );
  _FloatingFrame _returnStart = const _FloatingFrame(Rect.zero, 0, 1);
  late final AnimationController _move = AnimationController(vsync: this);
  _FloatingFrame _flightStart = const _FloatingFrame(Rect.zero, 0, 1);

  CovesHeaderCopy? _header;
  List<BlueskyProfileField> _moveFields = const [];
  OverlayEntry? _burstEntry;
  Timer? _pauseTimer;
  bool _pauseDone = false;
  bool _importInFlight = false;
  List<BlueskyProfileField>? _imported;

  @override
  void initState() {
    super.initState();
    _viewerAuthority = context.read<ViewerAuthorityProvider>();
    _sessionKey = _viewerAuthority.sessionKey;
    _viewerAuthority.addListener(_onViewerAuthorityChanged);
    _return
      ..addListener(_onReturnTick)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _finishReturn();
        }
      });
    _move
      ..addListener(_onMoveTick)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _land();
        }
      });
  }

  @override
  void dispose() {
    _viewerAuthority.removeListener(_onViewerAuthorityChanged);
    _removeOverlays();
    _return.dispose();
    _move.dispose();
    _floating.dispose();
    _wouldDrop.dispose();
    _cardFocus.dispose();
    for (final node in _fieldFocus) {
      node.dispose();
    }
    super.dispose();
  }

  void _onViewerAuthorityChanged() {
    if (_viewerAuthority.sessionKey != _sessionKey) {
      _close(const _ImportDialogOutcome(null));
    }
  }

  void _close(_ImportDialogOutcome? outcome) {
    if (_isClosed || !mounted) {
      return;
    }
    _isClosed = true;
    _removeOverlays();
    Navigator.of(context).pop(outcome);
  }

  bool get _canEndSeatPause =>
      _phase == _Phase.seated && !_importInFlight && _imported != null;

  /// The close X, a barrier tap or system back: declines at rest, ends the
  /// seat pause early once the import is done, and does nothing while the
  /// card is moving or the import is in flight.
  void _requestClose() {
    switch (_phase) {
      case _Phase.idle:
      case _Phase.dragging:
      case _Phase.returning:
        _close(null);
      case _Phase.seated:
        if (_canEndSeatPause) {
          _close(_ImportDialogOutcome(_imported));
        }
      case _Phase.moving:
        break;
    }
  }

  void _removeOverlays() {
    _pauseTimer?.cancel();
    _pauseTimer = null;
    _removeFloating();
    _removeBurst();
  }

  bool get _animate => !MediaQuery.disableAnimationsOf(context);

  bool get _anySelected => _checked.contains(true);

  bool get _canImport => _phase == _Phase.idle && _anySelected;

  void _toggle(int index) {
    if (_phase != _Phase.idle) {
      return;
    }
    setState(() => _checked[index] = !_checked[index]);
  }

  Rect _globalRect(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      return Rect.zero;
    }
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _measure() {
    _homeRect = _globalRect(_cardKey);
    _covesRect = _globalRect(_covesKey);
  }

  // Floating copy of the card, above everything.

  void _showFloating(_FloatingFrame frame) {
    _floating.value = frame;
    if (_floatingEntry != null) {
      return;
    }
    final overlay = _overlay ??= Overlay.of(context, rootOverlay: true);
    final entry = OverlayEntry(builder: _buildFloating);
    _floatingEntry = entry;
    overlay.insert(entry);
  }

  void _removeFloating() {
    final entry = _floatingEntry;
    if (entry == null) {
      return;
    }
    _floatingEntry = null;
    entry
      ..remove()
      ..dispose();
  }

  Widget _buildFloating(BuildContext overlayContext) {
    final geometry = _geometryFor(MediaQuery.sizeOf(overlayContext));
    final coves = CovesTargetPalette.of(overlayContext);
    final animate = !MediaQuery.disableAnimationsOf(overlayContext);
    return ValueListenableBuilder<_FloatingFrame>(
      valueListenable: _floating,
      builder: (context, frame, _) {
        final overlayBox = _overlay?.context.findRenderObject();
        final topLeft = overlayBox is RenderBox
            ? overlayBox.globalToLocal(frame.rect.topLeft)
            : frame.rect.topLeft;
        return Positioned(
          left: topLeft.dx,
          top: topLeft.dy,
          width: frame.rect.width,
          height: frame.rect.height,
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: Opacity(
                opacity: frame.opacity.clamp(0.0, 1.0),
                child: Material(
                  type: MaterialType.transparency,
                  child: BlueskyCardFace(
                    geometry: geometry,
                    palette: ImportCardPalette.blend(coves, frame.blend),
                    choices: widget.choices,
                    checked: List.of(_checked),
                    handle: widget.handle,
                    inkDuration: animate ? _inkTransition : Duration.zero,
                    hidesExcludedFields: true,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // Seat burst.

  void _showBurst() {
    _removeBurst();
    final overlay = _overlay ??= Overlay.of(context, rootOverlay: true);
    final overlayBox = overlay.context.findRenderObject();
    final covesRect = _globalRect(_covesKey);
    final local = overlayBox is RenderBox
        ? overlayBox.globalToLocal(covesRect.topLeft) & covesRect.size
        : covesRect;
    final entry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: SeatBurst(cardRect: local, onDone: _removeBurst),
      ),
    );
    _burstEntry = entry;
    overlay.insert(entry);
  }

  void _removeBurst() {
    final entry = _burstEntry;
    if (entry == null) {
      return;
    }
    _burstEntry = null;
    entry
      ..remove()
      ..dispose();
  }

  // Pointer handling on the card: under 6px a press is a tap that toggles
  // the field under it; from 6px on it is a drag.

  void _onPointerDown(PointerDownEvent event) {
    final fieldDown = _fieldPointerDown;
    _fieldPointerDown = null;
    if (_phase != _Phase.idle || _pointer != null) {
      return;
    }
    _pointer = event.pointer;
    _pressStart = event.position;
    _isDragging = false;
    _pressedField = fieldDown?.pointer == event.pointer
        ? fieldDown?.field
        : null;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    if (!_isDragging) {
      if ((event.position - _pressStart).distance < _dragThreshold) {
        return;
      }
      _beginDrag();
    }
    if (_phase == _Phase.dragging) {
      _dragTo(event.position);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    final field = _pressedField;
    final wasDragging = _isDragging;
    _endPress();
    if (!wasDragging) {
      if (field != null) {
        _toggle(field);
      }
      return;
    }
    if (_phase != _Phase.dragging) {
      return;
    }
    // Progress at release comes from the release point, not the last move.
    final progress = _dragTo(event.position);
    if (shouldDrop(
      releaseOverTarget: _covesRect.contains(event.position),
      progress: progress,
      anySelected: _anySelected,
    )) {
      _startMove();
    } else {
      _springBack(_floating.value);
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    final wasDragging = _isDragging;
    _endPress();
    if (wasDragging && _phase == _Phase.dragging) {
      _springBack(_floating.value);
    }
  }

  void _endPress() {
    _pointer = null;
    _pressedField = null;
    _isDragging = false;
  }

  void _beginDrag() {
    _isDragging = true;
    _pressedField = null;
    _rememberFocus();
    _measure();
    setState(() => _phase = _Phase.dragging);
    _showFloating(_FloatingFrame(_homeRect, 0, 1));
  }

  /// Moves the floating card with the pointer at [position] and returns the
  /// drag progress.
  double _dragTo(Offset position) {
    final delta = position - _pressStart;
    final progress = dragProgress(
      start: _homeRect.center,
      target: _covesRect.center,
      delta: delta,
    );
    _floating.value = _FloatingFrame(
      _homeRect.shift(delta),
      _animate ? blendAmount(progress) : 0,
      1,
    );
    _wouldDrop.value = shouldDrop(
      releaseOverTarget: _covesRect.contains(position),
      progress: progress,
      anySelected: _anySelected,
    );
    return progress;
  }

  // Spring back.

  void _springBack(_FloatingFrame from) {
    _wouldDrop.value = false;
    _homeRect = _globalRect(_cardKey);
    setState(() => _phase = _Phase.returning);
    if (!_animate) {
      _finishReturn();
      return;
    }
    _returnStart = from;
    _showFloating(from);
    _return.forward(from: 0);
  }

  void _onReturnTick() {
    if (_phase != _Phase.returning) {
      return;
    }
    final t = _return.value;
    _floating.value = _FloatingFrame(
      Rect.lerp(_returnStart.rect, _homeRect, _springBackCurve.transform(t))!,
      lerpDouble(_returnStart.blend, 0, t)!,
      1,
    );
  }

  void _finishReturn() {
    if (!mounted || _phase != _Phase.returning) {
      return;
    }
    _removeFloating();
    setState(() => _phase = _Phase.idle);
    final restore = _focusToRestore;
    _focusToRestore = null;
    if (restore != null) {
      // The card and its fields take focus again once rebuilt at rest.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _phase == _Phase.idle) {
          restore.requestFocus();
        }
      });
    }
  }

  /// Notes which of the card and its field toggles has keyboard focus, as
  /// it is lost while the card is away from its slot.
  void _rememberFocus() {
    _focusToRestore = _cardFocus.hasPrimaryFocus
        ? _cardFocus
        : _fieldFocus.where((node) => node.hasPrimaryFocus).firstOrNull;
  }

  // Move, seat and close.

  void _startMove() {
    if (_phase != _Phase.idle && _phase != _Phase.dragging) {
      return;
    }
    if (!_anySelected) {
      if (_phase == _Phase.dragging) {
        _springBack(_floating.value);
      }
      return;
    }
    if (_phase == _Phase.idle) {
      _rememberFocus();
    }
    _measure();
    _wouldDrop.value = false;
    _moveFields = [
      for (var index = 0; index < widget.choices.length; index++)
        if (_checked[index]) widget.choices[index].view.field,
    ];
    String? valueOf(BlueskyProfileField field) {
      if (!_moveFields.contains(field)) {
        return null;
      }
      final view = widget.choices
          .firstWhere((choice) => choice.view.field == field)
          .view;
      return view.blueskyImageUrl ?? view.bluesky;
    }

    setState(() {
      _phase = _Phase.moving;
      _errorText = null;
      _header = CovesHeaderCopy(
        bannerUrl: valueOf(BlueskyProfileField.banner),
        avatarUrl: valueOf(BlueskyProfileField.avatar),
        displayName: valueOf(BlueskyProfileField.displayName),
        handle: widget.handle,
        bio: valueOf(BlueskyProfileField.description),
      );
    });
    if (_animate && _floatingEntry == null) {
      _showFloating(_FloatingFrame(_homeRect, 0, 1));
    }
    _flightStart = _floating.value;
    _move.duration = _animate ? _moveDuration : _reducedMoveDuration;
    _move.forward(from: 0);
  }

  void _onMoveTick() {
    if (_phase != _Phase.moving || _floatingEntry == null) {
      return;
    }
    final t = _move.value;
    if (!_animate) {
      // The crossfade: a dropped card fades out where it was released.
      _floating.value = _FloatingFrame(_flightStart.rect, 0, 1 - t);
      return;
    }
    final eased = _moveCurve.transform(t);
    _floating.value = _FloatingFrame(
      Rect.lerp(_flightStart.rect, _covesRect, eased)!,
      lerpDouble(_flightStart.blend, 1, eased)!,
      t < 0.6 ? 1 : 1 - (t - 0.6) / 0.4,
    );
  }

  CovesSlotFill get _slotFill {
    if (_phase == _Phase.seated) {
      return CovesSlotFill.full;
    }
    final t = _move.value;
    if (!_animate) {
      return CovesSlotFill(banner: t, avatar: t, name: t, bio: t);
    }
    final elapsed = t * _moveDuration.inMilliseconds;
    double popIn(int start) =>
        ((elapsed - start) / _popInLength).clamp(0.0, 1.0);
    return CovesSlotFill(
      banner: popIn(_bannerPopIn),
      avatar: popIn(_avatarPopIn),
      name: popIn(_namePopIn),
      bio: popIn(_bioPopIn),
    );
  }

  void _land() {
    if (!mounted || _isClosed || _phase != _Phase.moving) {
      return;
    }
    _removeFloating();
    setState(() {
      _phase = _Phase.seated;
      _importInFlight = true;
      _imported = null;
      _pauseDone = false;
    });
    if (_animate) {
      _showBurst();
    }
    _pauseTimer = Timer(_animate ? _seatPause : _reducedSeatPause, () {
      _pauseTimer = null;
      _pauseDone = true;
      _finishIfDone();
    });
    unawaited(_runImport(_moveFields));
  }

  Future<void> _runImport(List<BlueskyProfileField> fields) async {
    final List<BlueskyProfileField> imported;
    try {
      imported = await widget.onImport(fields);
    } on ApiException catch (error) {
      if (error.errorCode == 'NothingToImport') {
        _close(const _ImportDialogOutcome([]));
        return;
      }
      _rollBack(
        error.errorCode == 'Conflict'
            ? 'Your profile changed while importing. Try again.'
            : ErrorMessage.blueskyImport(error),
      );
      return;
    } on Object catch (error) {
      _rollBack(ErrorMessage.blueskyImport(error));
      return;
    }
    if (!mounted || _isClosed) {
      return;
    }
    setState(() {
      _importInFlight = false;
      _imported = imported;
    });
    _finishIfDone();
  }

  void _finishIfDone() {
    if (_pauseDone && _canEndSeatPause) {
      _close(_ImportDialogOutcome(_imported));
    }
  }

  /// The import failed: the header copy goes at once, the card returns to
  /// its slot and the error shows.
  void _rollBack(String message) {
    if (!mounted || _isClosed) {
      return;
    }
    _pauseTimer?.cancel();
    _pauseTimer = null;
    _removeBurst();
    _measure();
    setState(() {
      _importInFlight = false;
      _header = null;
      _errorText = message;
    });
    _springBack(_FloatingFrame(_covesRect, _animate ? 1 : 0, 1));
  }

  // Layout.

  static ImportCardGeometry _geometryFor(Size screen) =>
      screen.width >= importWideBreakpoint
      ? ImportCardGeometry.wide
      : ImportCardGeometry.phone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screen = MediaQuery.sizeOf(context);
    final wide = screen.width >= importWideBreakpoint;
    final geometry = _geometryFor(screen);
    final canClose =
        _phase == _Phase.idle ||
        _phase == _Phase.dragging ||
        _phase == _Phase.returning;
    final horizontalPadding = wide ? 24.0 : 16.0;

    return PopScope<_ImportDialogOutcome>(
      canPop: canClose,
      // Any pop (barrier, back or a button) closes the dialog, so a session
      // change during the closing animation must not pop again.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _isClosed = true;
          _removeOverlays();
        } else {
          _requestClose();
        }
      },
      child: Dialog(
        backgroundColor: AppColors.backgroundSecondary,
        insetPadding: wide
            ? const EdgeInsets.symmetric(horizontal: 32, vertical: 24)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.border),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: wide ? 1024 : 448),
          // The buttons stay below the content, so they are always on screen
          // even when a large text size makes the content scroll.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    wide ? 16 : 8,
                    horizontalPadding,
                    0,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Import your Bluesky profile',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: wide ? 20 : 18,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: canClose || _canEndSeatPause
                                ? _requestClose
                                : null,
                            icon: const Icon(Icons.close, size: 20),
                            color: AppColors.textSecondary,
                            style: IconButton.styleFrom(
                              minimumSize: const Size(32, 32),
                              padding: EdgeInsets.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _description,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: wide ? 14 : 12,
                          height: wide ? 1.4 : 1.33,
                        ),
                      ),
                      SizedBox(height: wide ? 20 : 10),
                      if (wide)
                        _buildWideStage(geometry)
                      else
                        _buildPhoneStage(geometry),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  wide ? 12 : 10,
                  horizontalPadding,
                  wide ? 20 : 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: _phase == _Phase.idle
                            ? () => _close(null)
                            : null,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          backgroundColor: AppColors.backgroundTertiary,
                          minimumSize: const Size.fromHeight(44),
                          shape: const StadiumBorder(
                            side: BorderSide(color: AppColors.border),
                          ),
                        ),
                        child: const Text('No thanks'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _canImport ? _startMove : null,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                          shape: const StadiumBorder(),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_importInFlight) ...[
                                const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              const Text(
                                'Import profile',
                                maxLines: 1,
                                softWrap: false,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneStage(ImportCardGeometry geometry) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBlueskySlot(geometry),
        const SizedBox(height: 6),
        _buildMessage(),
        const SizedBox(height: 6),
        _buildCovesSlot(geometry),
      ],
    );
  }

  Widget _buildWideStage(ImportCardGeometry geometry) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _buildBlueskySlot(geometry)),
            const SizedBox(
              width: 40,
              child: ExcludeSemantics(
                child: Text(
                  '→',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMeta, fontSize: 18),
                ),
              ),
            ),
            Expanded(child: _buildCovesSlot(geometry)),
          ],
        ),
        const SizedBox(height: 16),
        _buildMessage(),
      ],
    );
  }

  /// The hint, or an error in its place. The slot is two lines tall whatever
  /// it holds, so the cards don't move.
  Widget _buildMessage() {
    final errorText = _errorText;
    final slotHeight =
        2 *
        MediaQuery.textScalerOf(context).scale(_hintFontSize) *
        _hintLineHeight;
    return SizedBox(
      height: slotHeight,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: errorText == null ? 1 : 0,
            child: const Text(
              _hint,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textMeta,
                fontSize: _hintFontSize,
                height: _hintLineHeight,
              ),
            ),
          ),
          if (errorText != null)
            Semantics(
              liveRegion: true,
              child: Text(
                errorText,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.error,
                  fontSize: _hintFontSize,
                  height: _hintLineHeight,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBlueskySlot(ImportCardGeometry geometry) {
    final face = BlueskyCardFace(
      geometry: geometry,
      palette: ImportCardPalette.bluesky,
      choices: widget.choices,
      checked: _checked,
      handle: widget.handle,
      wrapField: _wrapField,
    );
    final Widget shown;
    if (_phase == _Phase.idle) {
      shown = face;
    } else if (_phase == _Phase.moving && !_animate && _floatingEntry == null) {
      // Reduced motion: the card crossfades out in place.
      shown = AnimatedBuilder(
        animation: _move,
        builder: (context, child) =>
            Opacity(opacity: 1 - _move.value, child: child),
        child: ExcludeSemantics(child: face),
      );
    } else {
      // The floating copy or the Coves card shows the card; its slot keeps
      // an invisible placeholder so the layout doesn't jump.
      shown = Visibility(
        visible: false,
        maintainState: true,
        maintainAnimation: true,
        maintainSize: true,
        child: face,
      );
    }
    return Semantics(
      container: true,
      label: 'Bluesky',
      hint: _hint,
      child: FocusableActionDetector(
        focusNode: _cardFocus,
        enabled: _phase == _Phase.idle,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (_canImport) {
                _startMove();
              }
              return null;
            },
          ),
        },
        // Takes every press that starts on the card, so a scrolling
        // ancestor never turns a drag into a scroll.
        child: RawGestureDetector(
          gestures: {
            EagerGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                  EagerGestureRecognizer.new,
                  (_) {},
                ),
          },
          child: Listener(
            key: const ValueKey('blueskyImportCard'),
            behavior: HitTestBehavior.opaque,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerCancel,
            child: KeyedSubtree(key: _cardKey, child: shown),
          ),
        ),
      ),
    );
  }

  /// A field toggle: named by its label alone, toggled by a tap (handled by
  /// the card's pointer logic), by assistive tech or by Space.
  Widget _wrapField(int index, Widget child) {
    final field = widget.choices[index].view.field;
    final included = _checked[index];
    final enabled = _phase == _Phase.idle;
    return Semantics(
      key: ValueKey('blueskyImportField-${field.name}'),
      container: true,
      checked: included,
      label: _fieldLabel(field),
      onTap: enabled ? () => _toggle(index) : null,
      excludeSemantics: true,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) =>
            _fieldPointerDown = (pointer: event.pointer, field: index),
        child: _FieldFocus(
          focusNode: _fieldFocus[index],
          enabled: enabled,
          onActivate: () => _toggle(index),
          child: child,
        ),
      ),
    );
  }

  Widget _buildCovesSlot(ImportCardGeometry geometry) {
    final coves = CovesTargetPalette.of(context);
    return Semantics(
      container: true,
      label: 'Your Coves profile',
      child: KeyedSubtree(
        key: _covesKey,
        child: AnimatedBuilder(
          animation: Listenable.merge([_move, _wouldDrop]),
          builder: (context, _) {
            final moving = _phase == _Phase.moving;
            final seated = _phase == _Phase.seated;
            final filled = (moving || seated) && _header != null;
            return Semantics(
              container: true,
              child: CovesCardFace(
                key: const ValueKey('covesImportTarget'),
                geometry: geometry,
                palette: coves,
                outlineColor:
                    filled || (_phase == _Phase.dragging && _wouldDrop.value)
                    ? coves.ink
                    : coves.outline,
                solidness: seated
                    ? 1
                    : moving
                    ? _move.value
                    : 0,
                showDropHere: !moving && !seated,
                header: filled ? _header : null,
                fill: _slotFill,
                scalesPopIn: _animate,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Makes a field keyboard focusable, outlined while focus is shown; Enter
/// or Space toggles it.
class _FieldFocus extends StatefulWidget {
  const _FieldFocus({
    required this.focusNode,
    required this.enabled,
    required this.onActivate,
    required this.child,
  });

  final FocusNode focusNode;
  final bool enabled;
  final VoidCallback onActivate;
  final Widget child;

  @override
  State<_FieldFocus> createState() => _FieldFocusState();
}

class _FieldFocusState extends State<_FieldFocus> {
  bool _showsHighlight = false;

  late final Map<Type, Action<Intent>> _actions = {
    ActivateIntent: CallbackAction<ActivateIntent>(
      onInvoke: (_) {
        widget.onActivate();
        return null;
      },
    ),
  };

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      enabled: widget.enabled,
      actions: _actions,
      onShowFocusHighlight: (showsHighlight) {
        if (mounted && showsHighlight != _showsHighlight) {
          setState(() => _showsHighlight = showsHighlight);
        }
      },
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: _showsHighlight
            ? BoxDecoration(
                border: Border.all(color: AppColors.blueskyCardMutedText),
                borderRadius: BorderRadius.circular(4),
              )
            : const BoxDecoration(),
        child: widget.child,
      ),
    );
  }
}

String _fieldLabel(BlueskyProfileField field) => switch (field) {
  BlueskyProfileField.displayName => 'Display name',
  BlueskyProfileField.description => 'Bio',
  BlueskyProfileField.avatar => 'Avatar',
  BlueskyProfileField.banner => 'Banner',
};
