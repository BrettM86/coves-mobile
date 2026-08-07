import 'package:flutter/widgets.dart';

/// Fires [onLoadMore] when a scroll view gets within [threshold] pixels of
/// its bottom, at most once per [throttle] window.
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
    this.threshold = 200,
    this.throttle = const Duration(milliseconds: 100),
    DateTime Function() clock = DateTime.now,
  }) : _clock = clock;

  /// The scroll controller to observe. Not owned; never disposed here.
  final ScrollController controller;

  /// Called when the viewport nears the bottom.
  final VoidCallback onLoadMore;

  /// How close to the bottom (in pixels) counts as "near".
  final double threshold;

  /// Minimum gap between two callbacks. Scroll notifications arrive per
  /// frame; without this a single flick fires a burst of load requests.
  final Duration throttle;

  final DateTime Function() _clock;

  bool _attached = false;
  DateTime? _lastFiredAt;

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
  void checkNow() => _maybeFire();

  void _onScroll() => _maybeFire();

  void _maybeFire() {
    if (!_attached || !controller.hasClients) {
      return;
    }

    final position = controller.position;
    if (position.pixels < position.maxScrollExtent - threshold) {
      return;
    }

    final now = _clock();
    final last = _lastFiredAt;
    if (last != null && now.difference(last) < throttle) {
      return;
    }

    _lastFiredAt = now;
    onLoadMore();
  }
}
