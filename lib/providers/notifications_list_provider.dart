import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../models/notification.dart';
import '../services/api_exceptions.dart';
import '../services/coves_api_service.dart';
import '../utils/cursor_pagination_controller.dart';
import '../utils/notification_timestamp.dart';
import 'auth_provider.dart';
import 'unread_notification_count_provider.dart';

class NotificationsListProvider extends ChangeNotifier {
  NotificationsListProvider({
    required CovesApiService apiService,
    required AuthProvider authProvider,
    required Object? Function() sessionKeyOf,
    required UnreadNotificationCountProvider unreadNotificationCountProvider,
    void Function(Object error, StackTrace stackTrace)? reportError,
  }) {
    _apiService = apiService;
    _authProvider = authProvider;
    _sessionKeyOf = sessionKeyOf;
    _unreadNotificationCountProvider = unreadNotificationCountProvider;
    _reportError = reportError ?? _captureSeenError;
    _currentDid = _signedInDid;
    controller = CursorPaginationController<NotificationView>(
      fetchPage: (cursor) async {
        final page = await apiService.listNotifications(cursor: cursor);
        if (cursor == null) {
          return _PageOne(
            items: page.notifications,
            cursor: page.cursor,
            seenAt: page.seenAt,
            latestSortAt: page.latestSortAt,
          );
        }
        return CursorPage(
          items: _withEffectiveReadState(page.notifications),
          cursor: page.cursor,
        );
      },
      idOf: (notification) => notification.identity,
      sessionKeyOf: sessionKeyOf,
      onFirstPageAccepted: _onPageOneAccepted,
      followCursorPastEmptyPages: true,
      errorMapper: (_) => 'Could not load notifications. Please try again.',
      onUnexpectedError: _reportUnexpected,
    )..addListener(_onControllerChanged);
    _authProvider.addListener(_onAuthChanged);
  }

  late final CovesApiService _apiService;
  late final AuthProvider _authProvider;
  late final Object? Function() _sessionKeyOf;
  late final UnreadNotificationCountProvider _unreadNotificationCountProvider;
  late final void Function(Object error, StackTrace stackTrace) _reportError;
  late final CursorPaginationController<NotificationView> controller;
  String? _currentDid;

  /// Page one as loaded under `sessionStamp`, the session key it was
  /// accepted under; null until a page one lands for the current session.
  /// `latestSortAt` is the newest `sortAt` of every row page one received,
  /// rendered or not; null when it received none.
  ({String? latestSortAt, Object sessionStamp, bool marked})? _pageOne;

  /// `latestSortAt` of the page one the controller just accepted, held until
  /// [_onControllerChanged] records [_pageOne] for the same session.
  ({String? latestSortAt, Object sessionStamp})? _acceptedPageOne;
  bool _pageOneWasLoading = false;

  /// Page one's `seenAt` (null when the server sent none) from the page one
  /// the controller last accepted, with the session key it was accepted
  /// under; null before one is accepted for the current session. Later
  /// pages compute their read state against it. Marking page one seen never
  /// moves it.
  ({String? seenAt, Object sessionStamp})? _laterPageBoundary;
  int _sessionGeneration = 0;
  bool _firstPageRequested = false;
  bool _recoveryUsed = false;
  bool _retryPageOne = false;
  int _stateGeneration = 0;

  String? get _signedInDid =>
      _authProvider.isAuthenticated ? _authProvider.did : null;

  /// True while signed in but before [requestFirstPage] has started a load.
  bool get isAwaitingFirstPage => _currentDid != null && !_firstPageRequested;

  void requestFirstPage() {
    if (_currentDid == null || _firstPageRequested) {
      return;
    }
    _firstPageRequested = true;
    unawaited(controller.refresh());
  }

  Future<void> markPageOneSeen() async {
    final pageOne = _pageOne;
    final did = _currentDid;
    if (did == null ||
        did != _signedInDid ||
        pageOne == null ||
        pageOne.marked ||
        controller.sessionStamp != pageOne.sessionStamp ||
        _sessionKeyOf() != pageOne.sessionStamp) {
      return;
    }

    final latest = pageOne.latestSortAt;
    if (latest == null) {
      return;
    }

    _pageOne = (
      latestSortAt: latest,
      sessionStamp: pageOne.sessionStamp,
      marked: true,
    );
    final sessionGeneration = _sessionGeneration;
    try {
      await _apiService.updateNotificationsSeen(seenAt: latest);
      if (_sessionGeneration == sessionGeneration &&
          _currentDid == did &&
          _signedInDid == did) {
        unawaited(_unreadNotificationCountProvider.refresh());
      }
    } on Object catch (error, stackTrace) {
      if (error is ApiException && error.errorCode == 'AccountNotIndexed') {
        return;
      }
      try {
        _reportError(error, stackTrace);
      } on Object {
        // Marking seen must not fail because crash reporting failed.
      }
    }
  }

  void _onPageOneAccepted(CursorPage<NotificationView> page) {
    final sessionStamp = controller.sessionStamp;
    _laterPageBoundary = page is _PageOne && sessionStamp != null
        ? (seenAt: page.seenAt, sessionStamp: sessionStamp)
        : null;
    _acceptedPageOne = page is _PageOne && sessionStamp != null
        ? (latestSortAt: page.latestSortAt, sessionStamp: sessionStamp)
        : null;
  }

  /// [rows] from a page after page one, with `isRead` computed against page
  /// one's `seenAt`: read when `sortAt <= seenAt`, and all read when page one
  /// had no `seenAt`. A row whose timestamp cannot be compared keeps the
  /// server's value.
  List<NotificationView> _withEffectiveReadState(List<NotificationView> rows) {
    final boundary = _laterPageBoundary;
    if (boundary == null || boundary.sessionStamp != controller.sessionStamp) {
      // No page one was accepted for these items; keep the server values.
      return rows;
    }
    final seenAt = boundary.seenAt;
    return [for (final row in rows) _withReadState(row, seenAt)];
  }

  static NotificationView _withReadState(NotificationView row, String? seenAt) {
    bool isRead;
    if (seenAt == null) {
      isRead = true;
    } else {
      try {
        isRead = compareNotificationTimestamps(row.sortAt, seenAt) <= 0;
      } on FormatException {
        return row;
      }
    }
    return isRead == row.isRead ? row : row.withReadState(isRead: isRead);
  }

  void _onControllerChanged() {
    final sessionStamp = controller.sessionStamp;
    if (controller.isLoading) {
      _pageOneWasLoading = true;
      _pageOne = null;
    } else if (sessionStamp == null) {
      _pageOneWasLoading = false;
      _pageOne = null;
      _laterPageBoundary = null;
      _acceptedPageOne = null;
    } else if (_pageOneWasLoading) {
      _pageOneWasLoading = false;
      final accepted = _acceptedPageOne;
      _acceptedPageOne = null;
      if (accepted != null &&
          accepted.sessionStamp == sessionStamp &&
          controller.error == null &&
          controller.loadMoreError == null &&
          _currentDid != null &&
          _currentDid == _signedInDid &&
          sessionStamp == _sessionKeyOf()) {
        _pageOne = (
          latestSortAt: accepted.latestSortAt,
          sessionStamp: sessionStamp,
          marked: false,
        );
      }
    }
    notifyListeners();
  }

  static void _captureSeenError(Object error, StackTrace stackTrace) {
    unawaited(Sentry.captureException(error, stackTrace: stackTrace));
  }

  Future<void> loadMore() => _loadLaterPage(retry: false);

  Future<void> retryLoadMore() => _loadLaterPage(retry: true);

  Future<bool> refresh() {
    if (_currentDid == null) {
      return Future<bool>.value(false);
    }
    _stateGeneration++;
    _recoveryUsed = false;
    _retryPageOne = false;
    _firstPageRequested = true;
    return controller.refresh();
  }

  Future<void> _loadLaterPage({required bool retry}) async {
    final did = _currentDid;
    if (did == null || controller.isLoading || controller.isLoadingMore) {
      return;
    }
    // Recovery re-arms only on a user gesture, never on automatic paging.
    if (retry) {
      _recoveryUsed = false;
    }
    if (retry && _retryPageOne) {
      final generation = _stateGeneration;
      final replaced = await controller.replaceFirstPageForLoadMore();
      if (_stateGeneration == generation && _currentDid == did && replaced) {
        _retryPageOne = false;
      }
      return;
    }
    if (!controller.hasMore || (!retry && controller.loadMoreError != null)) {
      return;
    }

    final generation = _stateGeneration;
    final sessionStamp = controller.sessionStamp;
    if (retry) {
      await controller.retryLoadMore();
    } else {
      await controller.loadMore();
    }
    // A reset, explicit refresh, or session change supersedes this request.
    if (_stateGeneration != generation ||
        _currentDid != did ||
        _signedInDid != did ||
        controller.sessionStamp != sessionStamp) {
      return;
    }

    final cause = controller.loadMoreErrorCause;
    if (cause is! ApiException ||
        cause.statusCode != 400 ||
        cause.errorCode != 'InvalidCursor') {
      return;
    }
    if (_recoveryUsed) {
      // Resending the rejected cursor cannot succeed; Retry reloads page one.
      _retryPageOne = true;
      return;
    }
    _recoveryUsed = true;
    final replaced = await controller.replaceFirstPageForLoadMore();
    if (_stateGeneration == generation && _currentDid == did && !replaced) {
      _retryPageOne = controller.loadMoreError != null;
    }
  }

  void _onAuthChanged() {
    final did = _signedInDid;
    if (did == _currentDid) {
      return;
    }
    _currentDid = did;
    _sessionGeneration++;
    _pageOne = null;
    _laterPageBoundary = null;
    _acceptedPageOne = null;
    _pageOneWasLoading = false;
    _stateGeneration++;
    _recoveryUsed = false;
    _retryPageOne = false;
    controller.reset();
    if (did == null) {
      _firstPageRequested = false;
    } else if (_firstPageRequested) {
      unawaited(controller.refresh());
    }
  }

  void _reportUnexpected(Object error, StackTrace stackTrace) {
    if (error is ApiException) {
      return;
    }
    unawaited(Sentry.captureException(error, stackTrace: stackTrace));
  }

  @override
  void dispose() {
    _authProvider.removeListener(_onAuthChanged);
    controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    super.dispose();
  }
}

/// Page one as fetched, carrying the `seenAt` later pages are computed
/// against once the controller accepts it.
class _PageOne extends CursorPage<NotificationView> {
  const _PageOne({
    required super.items,
    super.cursor,
    required this.seenAt,
    required this.latestSortAt,
  });

  final String? seenAt;
  final String? latestSortAt;
}
