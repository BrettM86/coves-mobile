import 'package:flutter/foundation.dart';

/// One page of a cursor-paginated collection.
///
/// [cursor] is the cursor to pass to the *next* fetch. A null or empty
/// cursor means the collection has been fully read.
class CursorPage<T> {
  const CursorPage({required this.items, this.cursor});

  final List<T> items;
  final String? cursor;
}

/// The first-page error when the signed-in session kept changing while the
/// first page loaded, so no request finished under the session it started
/// in.
class SessionChangedDuringLoadException implements Exception {
  const SessionChangedDuringLoadException();

  @override
  String toString() =>
      'The account changed while the page was loading. Pull to refresh.';
}

/// Shared cursor pagination state machine.
///
/// Owns the items/cursor/loading/error state every paginated surface needs,
/// with the guards that used to be re-implemented (inconsistently) per
/// screen:
///
/// - **refresh supersedes**: a [refresh] always starts a fetch and takes
///   over, whatever is in flight. Dropping it (the old single-flight rule)
///   left the previous sort's — or previous profile's — content on screen
///   under the new label whenever the user switched during the first load.
/// - **loadMore is single flight**: a second [loadMore] while one is in
///   flight, or while the first page is loading, is ignored.
/// - **generation counter**: pages from a superseded request are discarded
///   whole when they land — no state, no error, no hydration.
/// - **separate error channels**: a pagination failure lands on
///   [loadMoreError] and never on [error], which drives full-screen error
///   states. [refresh] clears both.
/// - **a footer error stops the trigger**: [loadMore] is a no-op while
///   [loadMoreError] is set, so the scroll trigger cannot re-fire a failing
///   page ten times a second. The footer's Retry goes through
///   [retryLoadMore].
/// - **flags always clear**: loading flags are cleared on the failure path
///   as well as the success path, before any user-supplied callback runs,
///   so a throw can never wedge the feed.
/// - **new list instances**: appends never mutate the previously exposed
///   list, so widgets that captured it still see what they rendered.
///
/// `fetchPage` receives the cursor to fetch (null for the first page).
/// `onPageLoaded` is an optional hydration hook (vote / subscription
/// seeding); it receives only the new items and runs *after* the append is
/// visible on the controller. Its failures never corrupt a page that loaded
/// fine, but they are reported through `onUnexpectedError`.
/// `errorMapper` converts a thrown object into the user-facing message for
/// both error channels; without one the error's own text is used.
/// `idOf` is the item's stable server id. When supplied, items whose id is
/// already loaded are dropped instead of appended: overlapping pages from
/// server-side cursor drift would otherwise crash the list, which keys its
/// rows by that same id.
/// `onFirstPageAccepted` receives the page object `fetchPage` returned for
/// the first page, once that page is accepted and before listeners hear of
/// it; a superseded first page never reaches it. Its failures are reported
/// through `onUnexpectedError` and never undo the accepted page.
/// `onUnexpectedError` receives every error the controller swallows —
/// fetch failures, hydration failures, and failures of superseded requests
/// — so they reach crash reporting instead of only the debug console.
/// `sessionKeyOf` returns the current signed-in session's key. When
/// supplied, a page is accepted only if the session that requested it is
/// still current when it lands (and, for a load-more, is the session that
/// loaded the first page). [sessionStamp] is the session the loaded items
/// belong to. The controller never reloads on its own when the session
/// changes; the loaded items keep their old stamp until the next first-page
/// load. Two paths lead to that load:
///
/// - a first page whose session changed while it was in flight is requested
///   again under the current session, up to [maximumFirstPageAttempts]
///   requests in all, ending in [error] if the session never settles;
/// - a [loadMore] once the session differs from [sessionStamp] loads the
///   first page under the current session instead of appending, so a feed
///   the user scrolls to the end keeps paginating after a sign-in, sign-out
///   or account switch. A load-more page whose session changed in flight is
///   dropped, and the next [loadMore] takes this path. While [error] is set
///   this path sends nothing, whatever caused the error, so a reload that
///   keeps failing is not re-fired by the scroll trigger; only [retry] or
///   [refresh] (Retry or pull-to-refresh) clears it and reloads.
class CursorPaginationController<T> extends ChangeNotifier {
  CursorPaginationController({
    required this._fetchPage,
    this._onPageLoaded,
    this._errorMapper,
    this._idOf,
    this._onUnexpectedError,
    this._sessionKeyOf,
    this._onFirstPageAccepted,
    this.followCursorPastEmptyPages = false,
  });

  final Future<CursorPage<T>> Function(String? cursor) _fetchPage;
  final Future<void> Function(List<T> newItems)? _onPageLoaded;
  final String Function(Object error)? _errorMapper;
  final String Function(T item)? _idOf;
  final void Function(Object error, StackTrace stack)? _onUnexpectedError;
  final Object? Function()? _sessionKeyOf;
  final void Function(CursorPage<T> page)? _onFirstPageAccepted;

  /// Whether [loadMore] keeps paging after a page with no items.
  ///
  /// Off by default: a page with no items ends the collection even when the
  /// server hands back another cursor, because following it again could poll
  /// the same empty page forever. When on, the cursor from an empty page is
  /// followed only when it differs from the cursor that page was requested
  /// with; a repeated cursor still ends the collection.
  final bool followCursorPastEmptyPages;
  Object? _sessionStamp;

  List<T> _items = List<T>.unmodifiable(const <Never>[]);
  final Set<String> _removedIds = {};
  String? _cursor;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;
  Object? _errorCause;
  String? _loadMoreError;
  Object? _loadMoreErrorCause;
  bool _disposed = false;

  /// Requests one [refresh] makes for the first page while the session keeps
  /// changing under it, before it gives up with an error.
  static const int maximumFirstPageAttempts = 3;

  /// Bumped by every [refresh] and [reset] so in-flight requests started
  /// under a previous generation can recognise themselves as stale.
  int _generation = 0;

  // Row replacements made since the in-flight first-page request was sent.
  // Each is a confirmed server readback, newer than that request's page, so
  // they are re-applied on top of it when it lands; a page requested after
  // a replacement already carries it.
  final List<(String, T Function(T item))> _replacementsDuringLoad = [];

  /// The session key the loaded first page was requested and accepted
  /// under; null before one is accepted or without `sessionKeyOf`.
  Object? get sessionStamp => _sessionStamp;

  /// The loaded items (unmodifiable; a new instance on every change).
  List<T> get items => _items;

  /// Cursor for the next page, or null/empty at the end of the collection.
  String? get cursor => _cursor;

  /// Whether the server handed back a cursor to follow. False before the
  /// first page has loaded — there is nothing to page through yet.
  bool get hasMore => _cursor != null && _cursor!.isNotEmpty;

  /// First-page load in flight.
  bool get isLoading => _isLoading;

  /// Pagination load in flight.
  bool get isLoadingMore => _isLoadingMore;

  /// First-page error — the full-screen error channel.
  ///
  /// Also set when a pull-to-refresh fails with items already on screen.
  /// Screens gate their full-screen error on an empty list and surface this
  /// in the list footer otherwise (`PaginatedSliverList.refreshError`).
  String? get error => _error;

  /// The thrown object behind [error], for callers that branch on its type
  /// (e.g. a server error code); null whenever [error] is null.
  Object? get errorCause => _errorCause;

  /// Pagination error — the footer error channel.
  String? get loadMoreError => _loadMoreError;

  /// The thrown object behind [loadMoreError], or null when it is cleared.
  Object? get loadMoreErrorCause => _loadMoreErrorCause;

  /// Load (or reload) the first page.
  ///
  /// Also the entry point for the initial load: there is no separate
  /// `load()`, since a first load *is* a refresh with a null cursor.
  ///
  /// Supersedes anything in flight — including another refresh — because
  /// the caller's fetcher closes over screen state (sort, profile DID) that
  /// may have changed since the in-flight call started.
  ///
  /// Never rethrows; failures land on [error]. Returns true when *this*
  /// call's page reached the controller, false when it failed or was
  /// superseded, so awaiters do not stamp "refreshed at" for a fetch that
  /// never landed.
  Future<bool> refresh() => _replaceFirstPage(failureOnLoadMore: false);

  /// Replace the list from page one after a pagination failure. A failed
  /// replacement keeps the old rows and exposes Retry on the footer.
  Future<bool> replaceFirstPageForLoadMore() =>
      _replaceFirstPage(failureOnLoadMore: true);

  Future<bool> _replaceFirstPage({required bool failureOnLoadMore}) async {
    final generation = ++_generation;
    _removedIds.clear();
    _isLoading = true;
    // Any load-more in flight now belongs to a previous generation.
    _isLoadingMore = false;
    _error = null;
    _errorCause = null;
    _loadMoreError = null;
    _loadMoreErrorCause = null;
    _notify();

    for (var attempt = 1; ; attempt++) {
      final sessionKey = _currentSessionKey();
      _replacementsDuringLoad.clear();
      try {
        final page = await _fetchPage(null);
        if (_isStale(generation)) {
          return false;
        }
        if (_sessionChangedSince(sessionKey)) {
          // The page belongs to the previous session; ask again under the
          // current one, staying in the loading state.
          if (attempt < maximumFirstPageAttempts) {
            continue;
          }
          _failFirstPageForUnsettledSession(
            failureOnLoadMore: failureOnLoadMore,
          );
          return false;
        }

        final fresh = _withReplacementsDuringLoad(
          _withoutDuplicates(page.items, const <Never>[]),
        );
        _items = List<T>.unmodifiable(fresh);
        _cursor = page.cursor;
        _sessionStamp = sessionKey;
        _isLoading = false;
        _announceFirstPage(page);
        _notify();

        await _hydrate(fresh);
        return true;
      } on Object catch (error, stack) {
        if (_isStale(generation)) {
          _report(error, stack);
          return false;
        }
        if (_sessionChangedSince(sessionKey)) {
          _report(error, stack);
          if (attempt < maximumFirstPageAttempts) {
            continue;
          }
          _failFirstPageForUnsettledSession(
            failureOnLoadMore: failureOnLoadMore,
          );
          return false;
        }

        // Flags first: everything below can run user-supplied code, and a
        // throw there must not leave the feed stuck in a loading state.
        _isLoading = false;
        if (failureOnLoadMore) {
          _loadMoreError = _messageFor(error);
          _loadMoreErrorCause = error;
        } else {
          _error = _messageFor(error);
          _errorCause = error;
        }
        _notify();
        _report(error, stack);

        if (kDebugMode) {
          debugPrint('❌ Pagination first page failed: ${error.runtimeType}');
        }
        return false;
      }
    }
  }

  /// End a [refresh] whose session changed under every attempt in a visible
  /// first-page error, never in an empty list that reads as "no items".
  void _failFirstPageForUnsettledSession({required bool failureOnLoadMore}) {
    const error = SessionChangedDuringLoadException();
    _isLoading = false;
    if (failureOnLoadMore) {
      _loadMoreError = _messageFor(error);
      _loadMoreErrorCause = error;
    } else {
      _error = _messageFor(error);
      _errorCause = error;
    }
    _notify();
  }

  /// Append the next page.
  ///
  /// A no-op while any load is in flight, once the collection has ended, or
  /// while a [loadMoreError] is showing — the scroll trigger fires on every
  /// scroll tick, and without that last guard a failing page is retried
  /// continuously while the user sits at the bottom of the list.
  ///
  /// With `sessionKeyOf`, once the session differs from [sessionStamp] the
  /// next page would belong to another session than the loaded ones, so
  /// this loads the first page under the current session instead ([refresh]).
  /// While [error] is set it sends nothing at all: the scroll trigger would
  /// otherwise re-fire a failing reload continuously. Only [retry] or
  /// [refresh] (Retry or pull-to-refresh) clears [error] and reloads.
  ///
  /// Never rethrows; failures land on [loadMoreError] and leave the loaded
  /// items, cursor and [hasMore] intact so a retry can resume.
  Future<void> loadMore() async {
    if (_isLoading || _isLoadingMore || _loadMoreError != null || !hasMore) {
      return;
    }

    final sessionKey = _currentSessionKey();
    if (_sessionKeyOf != null && sessionKey != _sessionStamp) {
      if (_error != null) {
        return;
      }
      await refresh();
      return;
    }

    final generation = _generation;
    _isLoadingMore = true;
    _notify();

    final requestedCursor = _cursor;
    try {
      final page = await _fetchPage(requestedCursor);
      if (_isStale(generation)) {
        return;
      }
      if (_sessionChangedSince(sessionKey)) {
        _isLoadingMore = false;
        _notify();
        return;
      }

      final fresh = _withoutDuplicates(page.items, _items);
      _items = List<T>.unmodifiable(<T>[..._items, ...fresh]);
      _cursor =
          page.items.isEmpty &&
              (!followCursorPastEmptyPages || page.cursor == requestedCursor)
          ? null
          : page.cursor;
      _isLoadingMore = false;
      _notify();

      await _hydrate(fresh);
    } on Object catch (error, stack) {
      if (_isStale(generation)) {
        _report(error, stack);
        return;
      }
      if (_sessionChangedSince(sessionKey)) {
        _isLoadingMore = false;
        _notify();
        _report(error, stack);
        return;
      }

      // Flags first — see refresh().
      _isLoadingMore = false;
      _loadMoreError = _messageFor(error);
      _loadMoreErrorCause = error;
      _notify();
      _report(error, stack);

      if (kDebugMode) {
        debugPrint('❌ Pagination next page failed: ${error.runtimeType}');
      }
    }
  }

  /// Retry the first page after a failure.
  Future<bool> retry() => refresh();

  /// The footer's Retry: clears the pagination error that [loadMore] treats
  /// as a stop sign, then fetches the page again.
  Future<void> retryLoadMore() async {
    clearLoadMoreError();
    await loadMore();
  }

  /// Dismiss the footer error without touching anything else.
  void clearLoadMoreError() {
    if (_loadMoreError == null) {
      return;
    }
    _loadMoreError = null;
    _loadMoreErrorCause = null;
    _notify();
  }

  /// Drop everything back to the pre-first-load state and orphan any
  /// in-flight request.
  void reset() {
    _generation++;
    _removedIds.clear();
    _items = List<T>.unmodifiable(const <Never>[]);
    _cursor = null;
    _sessionStamp = null;
    _isLoading = false;
    _isLoadingMore = false;
    _error = null;
    _errorCause = null;
    _loadMoreError = null;
    _loadMoreErrorCause = null;
    _notify();
  }

  /// Drop the items matching [test] (e.g. a comment the user deleted).
  ///
  /// Leaves the cursor alone: the server-side page boundaries do not move
  /// just because the client stopped showing a row.
  void removeWhere(bool Function(T item) test) {
    final remaining = <T>[];
    for (final item in _items) {
      if (test(item)) {
        final idOf = _idOf;
        if (idOf != null) {
          _removedIds.add(idOf(item));
        }
      } else {
        remaining.add(item);
      }
    }
    if (remaining.length == _items.length) {
      return;
    }
    _items = List<T>.unmodifiable(remaining);
    _notify();
  }

  /// Drop the item with [id], and keep it out of any page that lands later,
  /// including one already in flight, even when no loaded item has [id] yet.
  ///
  /// Requires `idOf`. Leaves the cursor alone, like [removeWhere].
  void removeById(String id) {
    final idOf = _idOf;
    assert(idOf != null, 'removeById requires idOf');
    if (idOf == null) {
      return;
    }
    _removedIds.add(id);
    final remaining = _items.where((item) => idOf(item) != id).toList();
    if (remaining.length == _items.length) {
      return;
    }
    _items = List<T>.unmodifiable(remaining);
    _notify();
  }

  /// Replace a loaded row after a newer confirmed server readback.
  /// A first page already in flight lands with [replacement] re-applied to
  /// that row, so its older copy cannot overwrite the readback.
  /// Requires `idOf` and keeps the row's identity and position.
  void replaceItemById(String id, T Function(T item) replacement) {
    final idOf = _idOf;
    assert(idOf != null, 'replaceItemById requires idOf');
    if (idOf == null || !_items.any((item) => idOf(item) == id)) {
      return;
    }
    if (_isLoading) {
      _replacementsDuringLoad.add((id, replacement));
    }
    replaceItems([
      for (final item in _items)
        if (idOf(item) == id) replacement(item) else item,
    ]);
  }

  /// Swap in a rewritten list of the loaded items, for tree-shaped items
  /// whose rows change in place (e.g. merging a fetched reply subtree into
  /// its parent comment).
  ///
  /// Leaves the cursor, both errors, the loading flags and the generation
  /// alone: the server-side page boundaries have not moved, and a load-more
  /// already in flight still appends to the replacement when it lands.
  /// With `idOf`, the replacement must keep the same ids in the same order:
  /// the cursor still points past these rows, so adding, dropping or
  /// reordering them would desync the list from the server's pages.
  void replaceItems(List<T> items) {
    assert(
      _idOf == null ||
          listEquals(items.map(_idOf).toList(), _items.map(_idOf).toList()),
      'replaceItems must keep the same ids in the same order',
    );
    _items = List<T>.unmodifiable(items);
    _notify();
  }

  /// Dismiss the first-page error without touching anything else.
  void clearError() {
    if (_error == null) {
      return;
    }
    _error = null;
    _errorCause = null;
    _notify();
  }

  /// A request is stale when the controller is gone or a newer generation
  /// has taken over. Stale results are dropped whole: no state, no error,
  /// no hydration hook.
  bool _isStale(int generation) => _disposed || generation != _generation;

  Object? _currentSessionKey() => _sessionKeyOf?.call();

  /// Whether the session that started a request is no longer current.
  /// Its page or error is never applied: no items, no error, no hydration.
  bool _sessionChangedSince(Object? sessionKey) =>
      _sessionKeyOf != null && _currentSessionKey() != sessionKey;

  /// [incoming] minus anything whose id is already in [existing] or earlier
  /// in [incoming] itself. Identity-free (no `idOf`) collections are taken
  /// verbatim.
  List<T> _withoutDuplicates(List<T> incoming, List<T> existing) {
    final idOf = _idOf;
    if (idOf == null) {
      return incoming;
    }

    final seen = {...existing.map(idOf), ..._removedIds};
    final result = <T>[];
    for (final item in incoming) {
      if (seen.add(idOf(item))) {
        result.add(item);
      }
    }
    return result;
  }

  /// [page] with every replacement recorded while it was in flight applied,
  /// in the order they were made.
  List<T> _withReplacementsDuringLoad(List<T> page) {
    final idOf = _idOf;
    if (idOf == null || _replacementsDuringLoad.isEmpty) {
      return page;
    }
    var result = page;
    for (final (id, replacement) in _replacementsDuringLoad) {
      result = [
        for (final item in result)
          if (idOf(item) == id) replacement(item) else item,
      ];
    }
    _replacementsDuringLoad.clear();
    return result;
  }

  void _announceFirstPage(CursorPage<T> page) {
    final hook = _onFirstPageAccepted;
    if (hook == null) {
      return;
    }
    try {
      hook(page);
    } on Object catch (error, stack) {
      _report(error, stack);
    }
  }

  Future<void> _hydrate(List<T> newItems) async {
    final hook = _onPageLoaded;
    if (hook == null) {
      return;
    }
    try {
      await hook(List<T>.unmodifiable(newItems));
    } on Object catch (error, stack) {
      // Hydration is best-effort for the page (which already loaded), but
      // it is never silent: a failure here means viewer state — votes,
      // subscriptions — is missing from what the user sees.
      _report(error, stack);
      if (kDebugMode) {
        debugPrint('⚠️ Pagination hydration hook failed: $error');
      }
    }
  }

  /// Hand [error] to the crash reporter, if the owner wired one up.
  ///
  /// The reporter is untrusted: it runs on the failure path, where a throw
  /// would escape [refresh] / [loadMore] and wedge the loading flags.
  void _report(Object error, StackTrace stack) {
    final onUnexpectedError = _onUnexpectedError;
    if (onUnexpectedError == null) {
      return;
    }
    try {
      onUnexpectedError(error, stack);
    } on Object catch (reportFailure) {
      if (kDebugMode) {
        debugPrint('⚠️ Pagination error reporter threw: $reportFailure');
      }
    }
  }

  /// The user-facing message for [error].
  ///
  /// Both the mapper and [Object.toString] are treated as untrusted for the
  /// same reason as [_report].
  String _messageFor(Object error) {
    final mapper = _errorMapper;
    if (mapper != null) {
      try {
        return mapper(error);
      } on Object catch (mapperFailure) {
        if (kDebugMode) {
          debugPrint('⚠️ Pagination errorMapper threw: $mapperFailure');
        }
      }
    }
    try {
      return error.toString();
    } on Object {
      return 'Something went wrong. Please try again.';
    }
  }

  void _notify() {
    if (_disposed) {
      return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
