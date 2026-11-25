import 'dart:async';

import 'package:flutter/widgets.dart';

/// How many viewport heights before the end of a list the next page is
/// requested. A fixed 200px trigger fired only once the user was already at
/// the loading footer, so a normal fling through a 15-post page stalled on
/// a spinner every time; starting ~1.5 screens early lets the request land
/// while the user is still reading.
const double kPaginationPrefetchViewports = 1.5;

/// Whether [position] is close enough to its end to request the next page:
/// within [threshold] pixels when given, otherwise within
/// [kPaginationPrefetchViewports] viewport heights.
bool isNearScrollEnd(ScrollPosition position, {double? threshold}) {
  final trigger =
      threshold ?? position.viewportDimension * kPaginationPrefetchViewports;
  return position.pixels >= position.maxScrollExtent - trigger;
}

/// Fires [onLoadMore] when a scroll view gets near its bottom (see
/// [isNearScrollEnd]), at most once per [throttle] window.
///
/// The listener borrows an externally owned [controller]: it attaches and
/// detaches, and never disposes it. Callers own the lifecycle —
/// [attach] after the controller has a client (typically in `initState`)
/// and [dispose] from the widget's `dispose`.
///
/// `clock` exists so the throttle can be driven deterministically in tests;
/// production code leaves it at [DateTime.now].
class PaginationScrollListener {
  PaginationScrollListener({
    required this.controller,
    required this.onLoadMore,
    this.threshold,
    this.throttle = const Duration(milliseconds: 100),
    this._clock = DateTime.now,
  });

  /// The scroll controller to observe. Not owned; never disposed here.
  final ScrollController controller;

  /// Called when the viewport nears the bottom.
  final VoidCallback onLoadMore;

  /// How close to the bottom (in pixels) counts as "near". Null means
  /// [kPaginationPrefetchViewports] viewport heights.
  final double? threshold;

  /// Minimum gap between two callbacks. Scroll notifications arrive per
  /// frame; without this a single flick fires a burst of load requests.
  final Duration throttle;

  final DateTime Function() _clock;

  bool _attached = false;
  DateTime? _lastFiredAt;

  /// The one check scheduled for the end of the throttle window after a
  /// check landed inside it.
  Timer? _followUp;

  /// Whether the listener is currently observing the controller.
  bool get isAttached => _attached;

  /// Start observing. Idempotent — a second call does not double-fire.
  void attach() {
    if (_attached) {
      return;
    }
    controller.addListener(_onScroll);
    _attached = true;
  }

  /// Stop observing. Idempotent, and safe to call after the borrowed
  /// controller has been disposed ([ChangeNotifier.removeListener] is
  /// documented as callable on a disposed notifier).
  void detach() {
    if (!_attached) {
      return;
    }
    controller.removeListener(_onScroll);
    _attached = false;
    _cancelFollowUp();
  }

  /// Detaches. The borrowed [controller] is left alone.
  void dispose() => detach();

  /// Fire [onLoadMore] now if the viewport is already at (or near) the
  /// bottom, subject to the same throttle as a scroll trigger.
  ///
  /// A scroll listener only runs on scroll events, so a first page shorter
  /// than the viewport leaves nothing to scroll and pagination stalls
  /// forever. Screens call this after a page lands (post-frame, while
  /// `hasMore` and nothing is in flight) to keep filling the viewport.
  /// A detached listener stays silent — detaching means the owner has
  /// stopped paginating.
  ///
  /// A check inside the throttle window is not dropped: one follow-up check
  /// runs when the window ends, since a page landing that soon after the
  /// last trigger would otherwise leave the list stalled with more to load.
  void checkNow() => _maybeFire(scheduleFollowUp: true);

  void _onScroll() => _maybeFire();

  void _maybeFire({bool scheduleFollowUp = false, bool throttled = true}) {
    if (!_attached || !controller.hasClients) {
      _cancelFollowUp();
      return;
    }

    final position = controller.position;
    if (!isNearScrollEnd(position, threshold: threshold)) {
      _cancelFollowUp();
      return;
    }

    final now = _clock();
    final last = _lastFiredAt;
    if (throttled && last != null) {
      final elapsed = now.difference(last);
      if (elapsed < throttle) {
        if (scheduleFollowUp && _followUp == null) {
          // The follow-up skips the throttle: it is already timed to the end
          // of the window, and the clock may not have moved with the timer.
          _followUp = Timer(throttle - elapsed, () {
            _followUp = null;
            _maybeFire(throttled: false);
          });
        }
        return;
      }
    }

    _cancelFollowUp();
    _lastFiredAt = now;
    onLoadMore();
  }

  void _cancelFollowUp() {
    _followUp?.cancel();
    _followUp = null;
  }
}
