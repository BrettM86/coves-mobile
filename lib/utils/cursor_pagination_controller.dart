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
/// `onUnexpectedError` receives every error the controller swallows —
/// fetch failures, hydration failures, and failures of superseded requests
/// — so they reach crash reporting instead of only the debug console.
class CursorPaginationController<T> extends ChangeNotifier {
  CursorPaginationController({
    required Future<CursorPage<T>> Function(String? cursor) fetchPage,
    Future<void> Function(List<T> newItems)? onPageLoaded,
    String Function(Object error)? errorMapper,
    String Function(T item)? idOf,
    void Function(Object error, StackTrace stack)? onUnexpectedError,
  }) : _fetchPage = fetchPage,
       _onPageLoaded = onPageLoaded,
       _errorMapper = errorMapper,
       _idOf = idOf,
       _onUnexpectedError = onUnexpectedError;

  final Future<CursorPage<T>> Function(String? cursor) _fetchPage;
  final Future<void> Function(List<T> newItems)? _onPageLoaded;
  final String Function(Object error)? _errorMapper;
  final String Function(T item)? _idOf;
  final void Function(Object error, StackTrace stack)? _onUnexpectedError;

  List<T> _items = List<T>.unmodifiable(const <Never>[]);
  String? _cursor;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;
  String? _loadMoreError;
  bool _disposed = false;

  /// Bumped by every [refresh] and [reset] so in-flight requests started
  /// under a previous generation can recognise themselves as stale.
  int _generation = 0;

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

  /// Pagination error — the footer error channel.
  String? get loadMoreError => _loadMoreError;

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
  Future<bool> refresh() async {
    final generation = ++_generation;
    _isLoading = true;
    // Any load-more in flight now belongs to a previous generation.
    _isLoadingMore = false;
    _error = null;
    _loadMoreError = null;
    _notify();

    try {
      final page = await _fetchPage(null);
      if (_isStale(generation)) {
        return false;
      }

      final fresh = _withoutDuplicates(page.items, const <Never>[]);
      _items = List<T>.unmodifiable(fresh);
      _cursor = page.cursor;
      _isLoading = false;
      _notify();

      await _hydrate(fresh);
      return true;
    } on Object catch (error, stack) {
      if (_isStale(generation)) {
        _report(error, stack);
        return false;
      }

      // Flags first: everything below can run user-supplied code, and a
      // throw there must not leave the feed stuck in a loading state.
      _isLoading = false;
      _error = _messageFor(error);
      _notify();
      _report(error, stack);

      if (kDebugMode) {
        debugPrint('❌ Pagination first page failed: $error');
      }
      return false;
    }
  }

  /// Append the next page.
  ///
  /// A no-op while any load is in flight, once the collection has ended, or
  /// while a [loadMoreError] is showing — the scroll trigger fires on every
  /// scroll tick, and without that last guard a failing page is retried
  /// continuously while the user sits at the bottom of the list.
  ///
  /// Never rethrows; failures land on [loadMoreError] and leave the loaded
  /// items, cursor and [hasMore] intact so a retry can resume.
  Future<void> loadMore() async {
    if (_isLoading || _isLoadingMore || _loadMoreError != null || !hasMore) {
      return;
    }

    final generation = _generation;
    _isLoadingMore = true;
    _notify();

    try {
      final page = await _fetchPage(_cursor);
      if (_isStale(generation)) {
        return;
      }

      final fresh = _withoutDuplicates(page.items, _items);
      _items = List<T>.unmodifiable(<T>[..._items, ...fresh]);
      // A page with no items ends the collection even when the server hands
      // back another cursor: following it again would poll the same empty
      // page forever.
      _cursor = page.items.isEmpty ? null : page.cursor;
      _isLoadingMore = false;
      _notify();

      await _hydrate(fresh);
    } on Object catch (error, stack) {
      if (_isStale(generation)) {
        _report(error, stack);
        return;
      }

      // Flags first — see refresh().
      _isLoadingMore = false;
      _loadMoreError = _messageFor(error);
      _notify();
      _report(error, stack);

      if (kDebugMode) {
        debugPrint('❌ Pagination next page failed: $error');
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
    _notify();
  }

  /// Drop everything back to the pre-first-load state and orphan any
  /// in-flight request.
  void reset() {
    _generation++;
    _items = List<T>.unmodifiable(const <Never>[]);
    _cursor = null;
    _isLoading = false;
    _isLoadingMore = false;
    _error = null;
    _loadMoreError = null;
    _notify();
  }

  /// Drop the items matching [test] (e.g. a comment the user deleted).
  ///
  /// Leaves the cursor alone: the server-side page boundaries do not move
  /// just because the client stopped showing a row.
  void removeWhere(bool Function(T item) test) {
    final remaining = _items.where((item) => !test(item)).toList();
    if (remaining.length == _items.length) {
      return;
    }
    _items = List<T>.unmodifiable(remaining);
    _notify();
  }

  /// A request is stale when the controller is gone or a newer generation
  /// has taken over. Stale results are dropped whole: no state, no error,
  /// no hydration hook.
  bool _isStale(int generation) => _disposed || generation != _generation;

  /// [incoming] minus anything whose id is already in [existing] or earlier
  /// in [incoming] itself. Identity-free (no `idOf`) collections are taken
  /// verbatim.
  List<T> _withoutDuplicates(List<T> incoming, List<T> existing) {
    final idOf = _idOf;
    if (idOf == null) {
      return incoming;
    }

    final seen = existing.map(idOf).toSet();
    final result = <T>[];
    for (final item in incoming) {
      if (seen.add(idOf(item))) {
        result.add(item);
      }
    }
    return result;
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
