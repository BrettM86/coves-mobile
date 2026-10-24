// RED-phase spec for the shared cursor pagination controller.
//
// This file is intentionally compile-red until
// lib/utils/cursor_pagination_controller.dart exists. It is self-contained:
// nothing else in the suite imports it, so the rest of the tests still
// compile while this one fails to resolve its import.
//
// The spec pins the behaviours that are currently inconsistent across
// community_feed_screen.dart, communities_see_all_screen.dart and
// user_profile_provider.dart:
//   - single-flight guards
//   - a refresh started while a loadMore is in flight discards the stale page
//     (community feed sort-change race)
//   - refresh clears BOTH error and loadMoreError (community feed stale
//     load-more error surviving a refresh / sort change)
//   - loadMore failures never touch the first-page `error` (profile's
//     shared-error-field bug)
//   - loading flags are always cleared, even when the fetch throws
//   - appends produce new list instances (no in-place addAll)

import 'dart:async';

import 'package:coves_flutter/utils/cursor_pagination_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fetch function whose pages are completed by hand, so every test can
/// interleave refresh/loadMore deterministically without timers.
class _ScriptedFetcher {
  final List<String?> requestedCursors = <String?>[];
  final List<Completer<CursorPage<String>>> completers =
      <Completer<CursorPage<String>>>[];

  int get requestCount => completers.length;

  Future<CursorPage<String>> call(String? cursor) {
    requestedCursors.add(cursor);
    final completer = Completer<CursorPage<String>>();
    completers.add(completer);
    return completer.future;
  }

  void complete(int index, CursorPage<String> page) {
    completers[index].complete(page);
  }

  void fail(int index, Object error) {
    completers[index].completeError(error);
  }
}

/// Stand-in for a transport failure (the tests only care that it is thrown).
class NetworkFailure implements Exception {
  @override
  String toString() => 'NetworkFailure: the network is gone';
}

CursorPage<String> page(List<String> items, {String? cursor}) {
  return CursorPage<String>(items: items, cursor: cursor);
}

void main() {
  late _ScriptedFetcher fetcher;

  setUp(() {
    fetcher = _ScriptedFetcher();
  });

  CursorPaginationController<String> build({
    Future<void> Function(List<String> newItems)? onPageLoaded,
    String Function(Object error)? errorMapper,
    String Function(String item)? idOf,
    void Function(Object error, StackTrace stack)? onUnexpectedError,
    Object? Function()? sessionKeyOf,
    bool followCursorPastEmptyPages = false,
  }) {
    return CursorPaginationController<String>(
      fetchPage: fetcher.call,
      onPageLoaded: onPageLoaded,
      errorMapper: errorMapper,
      idOf: idOf,
      onUnexpectedError: onUnexpectedError,
      sessionKeyOf: sessionKeyOf,
      followCursorPastEmptyPages: followCursorPastEmptyPages,
    );
  }

  /// Drives the first page to completion.
  Future<void> loadFirstPage(
    CursorPaginationController<String> controller, {
    List<String> items = const <String>['a', 'b'],
    String? cursor = 'cursor-1',
    int requestIndex = 0,
  }) async {
    final future = controller.refresh();
    fetcher.complete(requestIndex, page(items, cursor: cursor));
    await future;
  }

  group('first load', () {
    test('starts empty and idle', () {
      final controller = build();
      addTearDown(controller.dispose);

      expect(controller.items, isEmpty);
      expect(controller.cursor, isNull);
      expect(controller.isLoading, isFalse);
      expect(controller.isLoadingMore, isFalse);
      expect(controller.error, isNull);
      expect(controller.loadMoreError, isNull);
      // Nothing has been fetched yet, so there is no cursor to follow.
      expect(controller.hasMore, isFalse);
    });

    test('refresh fetches with a null cursor and exposes the page', () async {
      final controller = build();
      addTearDown(controller.dispose);

      await loadFirstPage(controller);

      expect(fetcher.requestedCursors, <String?>[null]);
      expect(controller.items, <String>['a', 'b']);
      expect(controller.cursor, 'cursor-1');
      expect(controller.hasMore, isTrue);
      expect(controller.isLoading, isFalse);
      expect(controller.error, isNull);
    });

    test('isLoading is true only while the first page is in flight', () async {
      final controller = build();
      addTearDown(controller.dispose);

      final future = controller.refresh();
      expect(controller.isLoading, isTrue);
      expect(controller.isLoadingMore, isFalse);

      fetcher.complete(0, page(<String>['a'], cursor: 'c1'));
      await future;

      expect(controller.isLoading, isFalse);
    });

    test('notifies listeners when the page arrives', () async {
      final controller = build();
      addTearDown(controller.dispose);

      var notifications = 0;
      controller.addListener(() => notifications++);

      await loadFirstPage(controller);

      expect(notifications, greaterThanOrEqualTo(2));
    });
  });

  group('append', () {
    test('loadMore sends the current cursor and appends the page', () async {
      final controller = build();
      addTearDown(controller.dispose);

      await loadFirstPage(controller);

      final future = controller.loadMore();
      expect(controller.isLoadingMore, isTrue);
      fetcher.complete(1, page(<String>['c'], cursor: 'cursor-2'));
      await future;

      expect(fetcher.requestedCursors, <String?>[null, 'cursor-1']);
      expect(controller.items, <String>['a', 'b', 'c']);
      expect(controller.cursor, 'cursor-2');
      expect(controller.isLoadingMore, isFalse);
    });

    test('append produces a new list instance and never mutates the old '
        'one', () async {
      final controller = build();
      addTearDown(controller.dispose);

      await loadFirstPage(controller);
      final before = controller.items;

      final future = controller.loadMore();
      fetcher.complete(1, page(<String>['c'], cursor: 'cursor-2'));
      await future;

      expect(identical(before, controller.items), isFalse);
      expect(before, <String>['a', 'b']);
    });

    test('refresh replaces the items instead of appending', () async {
      final controller = build();
      addTearDown(controller.dispose);

      await loadFirstPage(controller);

      final future = controller.refresh();
      fetcher.complete(1, page(<String>['z'], cursor: 'cursor-9'));
      await future;

      expect(controller.items, <String>['z']);
      expect(fetcher.requestedCursors, <String?>[null, null]);
    });
  });

  group('hasMore', () {
    test('a null cursor ends the feed', () async {
      final controller = build();
      addTearDown(controller.dispose);

      await loadFirstPage(controller, cursor: null);

      expect(controller.hasMore, isFalse);
    });

    test('an empty-string cursor ends the feed', () async {
      final controller = build();
      addTearDown(controller.dispose);

      await loadFirstPage(controller, cursor: '');

      expect(controller.hasMore, isFalse);
    });

    test('loadMore is a no-op once the feed has ended', () async {
      final controller = build();
      addTearDown(controller.dispose);

      await loadFirstPage(controller, cursor: null);

      await controller.loadMore();

      expect(fetcher.requestCount, 1);
      expect(controller.isLoadingMore, isFalse);
    });
  });

  group('single flight', () {
    // SPEC CHANGE (multi-model review, FIX 2): this used to pin "a second
    // refresh while one is in flight is ignored". Dropping it meant a sort
    // change (or profile switch) during the initial load rendered the OLD
    // query's content under the NEW label, because the generation counter
    // only covers a refresh landing on top of a loadMore. A refresh now
    // supersedes whatever is in flight, refresh included.
    test('a second refresh supersedes the one in flight', () async {
      final controller = build();
      addTearDown(controller.dispose);

      final first = controller.refresh();
      final second = controller.refresh();

      expect(fetcher.requestCount, 2);

      // The superseded request lands first and must be thrown away.
      fetcher.complete(0, page(<String>['stale'], cursor: 'stale-cursor'));
      expect(await first, isFalse);
      expect(controller.items, isEmpty);
      expect(controller.isLoading, isTrue);

      fetcher.complete(1, page(<String>['fresh'], cursor: 'c1'));
      expect(await second, isTrue);

      expect(controller.items, <String>['fresh']);
      expect(controller.cursor, 'c1');
      expect(controller.isLoading, isFalse);
    });

    test('a superseding refresh sees the new query context', () async {
      // The community-feed sort race and the profile-switch race: the
      // fetcher closes over screen state that changed between the two
      // calls, so only the second call's page may reach the controller.
      var sort = 'hot';
      final controller = CursorPaginationController<String>(
        fetchPage: (cursor) => fetcher.call(sort),
      );
      addTearDown(controller.dispose);

      final hotLoad = controller.refresh();
      sort = 'new';
      final newLoad = controller.refresh();

      expect(fetcher.requestedCursors, <String?>['hot', 'new']);

      fetcher.complete(1, page(<String>['new-1'], cursor: 'c-new'));
      expect(await newLoad, isTrue);

      fetcher.complete(0, page(<String>['hot-1'], cursor: 'c-hot'));
      expect(await hotLoad, isFalse);

      expect(controller.items, <String>['new-1']);
      expect(controller.cursor, 'c-new');
      expect(controller.isLoading, isFalse);
    });

    test('a superseded refresh failure never surfaces', () async {
      final controller = build();
      addTearDown(controller.dispose);

      final first = controller.refresh();
      final second = controller.refresh();

      fetcher.fail(0, Exception('superseded boom'));
      expect(await first, isFalse);

      fetcher.complete(1, page(<String>['a'], cursor: 'c1'));
      await second;

      expect(controller.error, isNull);
      expect(controller.items, <String>['a']);
    });

    test('a second loadMore while one is in flight is ignored', () async {
      final controller = build();
      addTearDown(controller.dispose);

      await loadFirstPage(controller);

      final first = controller.loadMore();
      final second = controller.loadMore();

      expect(fetcher.requestCount, 2);

      fetcher.complete(1, page(<String>['c'], cursor: 'cursor-2'));
      await Future.wait(<Future<void>>[first, second]);

      expect(controller.items, <String>['a', 'b', 'c']);
    });

    test('loadMore during a first-page load is ignored', () async {
      final controller = build();
      addTearDown(controller.dispose);

      final refreshFuture = controller.refresh();
      final loadMoreFuture = controller.loadMore();

      expect(fetcher.requestCount, 1);

      fetcher.complete(0, page(<String>['a'], cursor: 'c1'));
      await Future.wait(<Future<void>>[refreshFuture, loadMoreFuture]);

      expect(controller.items, <String>['a']);
    });
  });

  group('generation counter', () {
    test(
      'a refresh started during a loadMore discards the stale page',
      () async {
        // This is the community-feed sort-change race: the user changes sort
        // while a page of the previous sort is still in flight.
        final controller = build();
        addTearDown(controller.dispose);

        await loadFirstPage(controller);

        final staleLoadMore = controller.loadMore(); // request 1
        final refreshed = controller.refresh(); // request 2 — must be allowed

        expect(fetcher.requestCount, 3);

        fetcher.complete(2, page(<String>['x'], cursor: 'cursor-new'));
        await refreshed;

        expect(controller.items, <String>['x']);

        // The stale page lands last and must be thrown away.
        fetcher.complete(1, page(<String>['stale'], cursor: 'cursor-stale'));
        await staleLoadMore;

        expect(controller.items, <String>['x']);
        expect(controller.cursor, 'cursor-new');
        expect(controller.isLoadingMore, isFalse);
      },
    );

    test('a discarded stale page never reaches onPageLoaded', () async {
      final hydrated = <List<String>>[];
      final controller = build(
        onPageLoaded: (newItems) async => hydrated.add(newItems),
      );
      addTearDown(controller.dispose);

      await loadFirstPage(controller);

      final staleLoadMore = controller.loadMore();
      final refreshed = controller.refresh();

      fetcher.complete(2, page(<String>['x'], cursor: 'cursor-new'));
      await refreshed;
      fetcher.complete(1, page(<String>['stale'], cursor: 'cursor-stale'));
      await staleLoadMore;

      expect(hydrated, <List<String>>[
        <String>['a', 'b'],
        <String>['x'],
      ]);
    });

    test('a stale failure does not surface as an error', () async {
      final controller = build();
      addTearDown(controller.dispose);

      await loadFirstPage(controller);

      final staleLoadMore = controller.loadMore();
      final refreshed = controller.refresh();

      fetcher.complete(2, page(<String>['x'], cursor: 'cursor-new'));
      await refreshed;
      fetcher.fail(1, Exception('stale request failed'));
      await staleLoadMore;

      expect(controller.error, isNull);
      expect(controller.loadMoreError, isNull);
      expect(controller.isLoadingMore, isFalse);
    });
  });

  group('errors', () {
    test('a first-page failure sets error and clears isLoading', () async {
      final controller = build();
      addTearDown(controller.dispose);

      final future = controller.refresh();
      fetcher.fail(0, Exception('boom'));
      await future;

      expect(controller.error, isNotNull);
      expect(controller.error, contains('boom'));
      expect(controller.isLoading, isFalse);
      expect(controller.loadMoreError, isNull);
    });

    test('a loadMore failure sets loadMoreError only', () async {
      // Profile's shared-error-field bug: a pagination failure must never
      // populate the field that drives the full-screen error state.
      final controller = build();
      addTearDown(controller.dispose);

      await loadFirstPage(controller);

      final future = controller.loadMore();
      fetcher.fail(1, Exception('page 2 exploded'));
      await future;

      expect(controller.loadMoreError, isNotNull);
      expect(controller.error, isNull);
      expect(controller.isLoadingMore, isFalse);
      // Already-loaded items and the cursor survive so a retry can resume.
      expect(controller.items, <String>['a', 'b']);
      expect(controller.cursor, 'cursor-1');
      expect(controller.hasMore, isTrue);
    });

    test('refresh clears both error and loadMoreError', () async {
      // Community feed: a stale load-more error used to survive a refresh
      // and a sort change.
      final controller = build();
      addTearDown(controller.dispose);

      await loadFirstPage(controller);

      final failed = controller.loadMore();
      fetcher.fail(1, Exception('page 2 exploded'));
      await failed;
      expect(controller.loadMoreError, isNotNull);

      final refreshed = controller.refresh();
      // Cleared optimistically, before the new page even lands.
      expect(controller.loadMoreError, isNull);
      expect(controller.error, isNull);

      fetcher.complete(2, page(<String>['a'], cursor: 'cursor-1'));
      await refreshed;

      expect(controller.loadMoreError, isNull);
      expect(controller.error, isNull);
    });

    test('clearLoadMoreError clears only the load-more error', () async {
      final controller = build();
      addTearDown(controller.dispose);

      await loadFirstPage(controller);

      final failed = controller.loadMore();
      fetcher.fail(1, Exception('page 2 exploded'));
      await failed;

      controller.clearLoadMoreError();

      expect(controller.loadMoreError, isNull);
      expect(controller.items, <String>['a', 'b']);
    });

    test('retry re-runs the first page and clears the error', () async {
      final controller = build();
      addTearDown(controller.dispose);

      final failed = controller.refresh();
      fetcher.fail(0, Exception('boom'));
      await failed;
      expect(controller.error, isNotNull);

      final retried = controller.retry();
      fetcher.complete(1, page(<String>['a'], cursor: 'c1'));
      await retried;

      expect(controller.error, isNull);
      expect(controller.items, <String>['a']);
    });

    test('errorMapper maps both first-page and load-more failures', () async {
      final controller = build(errorMapper: (error) => 'mapped');
      addTearDown(controller.dispose);

      final failedFirst = controller.refresh();
      fetcher.fail(0, Exception('raw first page'));
      await failedFirst;
      expect(controller.error, 'mapped');

      final ok = controller.refresh();
      fetcher.complete(1, page(<String>['a'], cursor: 'c1'));
      await ok;

      final failedMore = controller.loadMore();
      fetcher.fail(2, Exception('raw page 2'));
      await failedMore;
      expect(controller.loadMoreError, 'mapped');
    });

    test('refresh and loadMore never rethrow', () async {
      final controller = build();
      addTearDown(controller.dispose);

      final first = controller.refresh();
      fetcher.fail(0, Exception('boom'));
      await expectLater(first, completes);
    });
  });

  group('onPageLoaded', () {
    test('receives only the new items of each page', () async {
      final hydrated = <List<String>>[];
      final controller = build(
        onPageLoaded: (newItems) async => hydrated.add(newItems),
      );
      addTearDown(controller.dispose);

      await loadFirstPage(controller);

      final more = controller.loadMore();
      fetcher.complete(1, page(<String>['c'], cursor: 'cursor-2'));
      await more;

      expect(hydrated, <List<String>>[
        <String>['a', 'b'],
        <String>['c'],
      ]);
    });

    test('runs after the new items are visible on the controller', () async {
      // Hydration hooks (vote/subscription seeding) read the controller's
      // state, so the append must already be committed when they run.
      late CursorPaginationController<String> controller;
      var itemsDuringHook = <String>[];

      controller = CursorPaginationController<String>(
        fetchPage: fetcher.call,
        onPageLoaded: (newItems) async {
          itemsDuringHook = List<String>.of(controller.items);
        },
      );
      addTearDown(controller.dispose);

      await loadFirstPage(controller);

      final more = controller.loadMore();
      fetcher.complete(1, page(<String>['c'], cursor: 'cursor-2'));
      await more;

      expect(itemsDuringHook, <String>['a', 'b', 'c']);
    });

    test('a throwing hook does not corrupt the loaded page', () async {
      final controller = build(
        onPageLoaded: (newItems) async => throw StateError('hydration'),
      );
      addTearDown(controller.dispose);

      final future = controller.refresh();
      fetcher.complete(0, page(<String>['a'], cursor: 'c1'));
      await future;

      expect(controller.items, <String>['a']);
      expect(controller.isLoading, isFalse);
    });
  });

  group('refresh result', () {
    test('reports whether this call put its own page on screen', () async {
      // Awaiters (the profile provider stamps a "last refreshed" timestamp)
      // need to know a fetch of *theirs* actually completed.
      final controller = build();
      addTearDown(controller.dispose);

      final ok = controller.refresh();
      fetcher.complete(0, page(<String>['a'], cursor: 'c1'));
      expect(await ok, isTrue);

      final failed = controller.refresh();
      fetcher.fail(1, Exception('boom'));
      expect(await failed, isFalse);
    });

    test('a refresh orphaned by reset reports false', () async {
      final controller = build();
      addTearDown(controller.dispose);

      final orphaned = controller.refresh();
      controller.reset();
      fetcher.complete(0, page(<String>['a'], cursor: 'c1'));

      expect(await orphaned, isFalse);
      expect(controller.items, isEmpty);
    });
  });

  group('failed refresh from a populated state', () {
    test('keeps the items and cursor already on screen', () async {
      // Pull-to-refresh with content on screen: a failure must not blank
      // the list, and the surviving cursor keeps pagination usable.
      final controller = build();
      addTearDown(controller.dispose);

      await loadFirstPage(controller);

      final failed = controller.refresh();
      fetcher.fail(1, NetworkFailure());
      expect(await failed, isFalse);

      expect(controller.items, <String>['a', 'b']);
      expect(controller.cursor, 'cursor-1');
      expect(controller.hasMore, isTrue);
      expect(controller.isLoading, isFalse);
      // The failure is reported on the first-page channel even though the
      // list is non-empty — screens surface it in the footer instead of a
      // full-screen error (PaginatedSliverList.refreshError).
      expect(controller.error, isNotNull);
      expect(controller.loadMoreError, isNull);
    });

    test('a later successful refresh clears the error', () async {
      final controller = build();
      addTearDown(controller.dispose);

      await loadFirstPage(controller);

      final failed = controller.refresh();
      fetcher.fail(1, NetworkFailure());
      await failed;

      final ok = controller.refresh();
      fetcher.complete(2, page(<String>['z'], cursor: 'cursor-9'));
      expect(await ok, isTrue);

      expect(controller.error, isNull);
      expect(controller.items, <String>['z']);
    });
  });

  group('load-more error gating', () {
    test('loadMore is a no-op while a footer error is showing', () async {
      // The scroll trigger keeps firing while the user sits at the bottom;
      // without this gate a failed page retries ~10x/second.
      final controller = build();
      addTearDown(controller.dispose);

      await loadFirstPage(controller);

      final failed = controller.loadMore();
      fetcher.fail(1, Exception('offline'));
      await failed;

      await controller.loadMore();
      await controller.loadMore();

      expect(fetcher.requestCount, 2);
      expect(controller.loadMoreError, isNotNull);
    });

    test('retryLoadMore clears the error and fetches the page', () async {
      final controller = build();
      addTearDown(controller.dispose);

      await loadFirstPage(controller);

      final failed = controller.loadMore();
      fetcher.fail(1, Exception('offline'));
      await failed;

      final retried = controller.retryLoadMore();
      expect(controller.loadMoreError, isNull);
      expect(fetcher.requestCount, 3);
      fetcher.complete(2, page(<String>['c'], cursor: 'cursor-2'));
      await retried;

      expect(controller.items, <String>['a', 'b', 'c']);
      expect(controller.loadMoreError, isNull);
    });

    test('refresh re-enables loadMore after a footer error', () async {
      final controller = build();
      addTearDown(controller.dispose);

      await loadFirstPage(controller);

      final failed = controller.loadMore();
      fetcher.fail(1, Exception('offline'));
      await failed;

      final refreshed = controller.refresh();
      fetcher.complete(2, page(<String>['a'], cursor: 'cursor-1'));
      await refreshed;

      final more = controller.loadMore();
      fetcher.complete(3, page(<String>['c'], cursor: 'cursor-2'));
      await more;

      expect(controller.items, <String>['a', 'c']);
    });

    test('loadMoreErrorCause holds the failure until the footer error is '
        'cleared by retry, dismissal, refresh, replacement or reset', () async {
      // Callers treat a null cause as success: a stale cause would make the
      // next successful page look like the old failure.
      final controller = build();
      addTearDown(controller.dispose);

      await loadFirstPage(controller);
      var request = 1;

      Future<Object> failLoadMore() async {
        final failure = Exception('page failure $request');
        final failed = controller.loadMore();
        fetcher.fail(request++, failure);
        await failed;
        expect(controller.loadMoreErrorCause, same(failure));
        return failure;
      }

      await failLoadMore();
      final retried = controller.retryLoadMore();
      fetcher.complete(request++, page(<String>['c'], cursor: 'cursor-2'));
      await retried;
      expect(controller.loadMoreErrorCause, isNull, reason: 'retryLoadMore');

      await failLoadMore();
      controller.clearLoadMoreError();
      expect(
        controller.loadMoreErrorCause,
        isNull,
        reason: 'clearLoadMoreError',
      );

      await failLoadMore();
      final refreshed = controller.refresh();
      fetcher.complete(request++, page(<String>['a'], cursor: 'cursor-1'));
      await refreshed;
      expect(controller.loadMoreErrorCause, isNull, reason: 'refresh');

      await failLoadMore();
      final replaced = controller.replaceFirstPageForLoadMore();
      fetcher.complete(request++, page(<String>['a'], cursor: 'cursor-1'));
      await replaced;
      expect(
        controller.loadMoreErrorCause,
        isNull,
        reason: 'replaceFirstPageForLoadMore',
      );

      await failLoadMore();
      controller.reset();
      expect(controller.loadMoreErrorCause, isNull, reason: 'reset');
    });
  });

  group('empty pages', () {
    test('opt-in follows an empty page cursor until the final page', () async {
      final controller = build(followCursorPastEmptyPages: true);
      addTearDown(controller.dispose);

      await loadFirstPage(controller, items: <String>['a'], cursor: 'c1');

      final emptyPage = controller.loadMore();
      expect(fetcher.requestedCursors, <String?>[null, 'c1']);
      fetcher.complete(1, page(const <String>[], cursor: 'c2'));
      await emptyPage;

      expect(controller.items, <String>['a']);
      expect(controller.cursor, 'c2');
      expect(controller.hasMore, isTrue);

      final lastPage = controller.loadMore();
      expect(fetcher.requestedCursors, <String?>[null, 'c1', 'c2']);
      fetcher.complete(2, page(<String>['b']));
      await lastPage;

      expect(controller.items, <String>['a', 'b']);
      expect(controller.hasMore, isFalse);
      await controller.loadMore();
      expect(fetcher.requestedCursors, <String?>[null, 'c1', 'c2']);
    });

    test(
      'opt-in ends the feed when an empty page repeats its cursor',
      () async {
        // Following a cursor that does not advance would poll the same empty
        // page once per frame from the fill check.
        final controller = build(followCursorPastEmptyPages: true);
        addTearDown(controller.dispose);

        await loadFirstPage(controller, items: <String>['a'], cursor: 'c1');

        final emptyPage = controller.loadMore();
        expect(fetcher.requestedCursors, <String?>[null, 'c1']);
        fetcher.complete(1, page(const <String>[], cursor: 'c1'));
        await emptyPage;

        expect(controller.items, <String>['a']);
        expect(controller.cursor, isNull);
        expect(controller.hasMore, isFalse);

        await controller.loadMore();
        expect(fetcher.requestedCursors, <String?>[null, 'c1']);
      },
    );

    test('an empty load-more page ends the feed even with a cursor', () async {
      // Otherwise the cursor is polled forever by the scroll trigger.
      final controller = build();
      addTearDown(controller.dispose);

      await loadFirstPage(controller);

      final more = controller.loadMore();
      fetcher.complete(1, page(const <String>[], cursor: 'cursor-2'));
      await more;

      expect(controller.items, <String>['a', 'b']);
      expect(controller.hasMore, isFalse);
      expect(controller.cursor, isNull);

      await controller.loadMore();
      expect(fetcher.requestCount, 2);
    });
  });

  group('duplicate ids', () {
    test('an item already on screen is not appended twice', () async {
      // Cursor drift on the server hands back an overlapping page; the
      // sliver keys rows by id, so a duplicate is a hard assertion crash.
      final controller = build(idOf: (item) => item);
      addTearDown(controller.dispose);

      await loadFirstPage(controller);

      final more = controller.loadMore();
      fetcher.complete(1, page(<String>['b', 'c'], cursor: 'cursor-2'));
      await more;

      expect(controller.items, <String>['a', 'b', 'c']);
      expect(controller.cursor, 'cursor-2');
    });

    test('duplicates inside a single page are dropped', () async {
      final controller = build(idOf: (item) => item);
      addTearDown(controller.dispose);

      await loadFirstPage(controller, items: <String>['a', 'a', 'b']);

      expect(controller.items, <String>['a', 'b']);
    });

    test('only the genuinely new items are hydrated', () async {
      final hydrated = <List<String>>[];
      final controller = build(
        idOf: (item) => item,
        onPageLoaded: (newItems) async => hydrated.add(newItems),
      );
      addTearDown(controller.dispose);

      await loadFirstPage(controller);

      final more = controller.loadMore();
      fetcher.complete(1, page(<String>['b', 'c'], cursor: 'cursor-2'));
      await more;

      expect(hydrated, <List<String>>[
        <String>['a', 'b'],
        <String>['c'],
      ]);
    });

    test('without idOf the page is appended verbatim', () async {
      final controller = build();
      addTearDown(controller.dispose);

      await loadFirstPage(controller);

      final more = controller.loadMore();
      fetcher.complete(1, page(<String>['b'], cursor: 'cursor-2'));
      await more;

      expect(controller.items, <String>['a', 'b', 'b']);
    });
  });

  group('removeWhere', () {
    test(
      'B4 removed id in a pending page stays gone while survivor appends',
      () async {
        final controller = build(idOf: (item) => item);
        addTearDown(controller.dispose);
        await loadFirstPage(controller, items: <String>['a', 'b', 'c']);

        final loadingMore = controller.loadMore();
        expect(controller.isLoadingMore, isTrue);
        controller.removeWhere((item) => item == 'a');
        expect(controller.items, <String>['b', 'c']);

        fetcher.complete(1, page(<String>['a', 'd'], cursor: 'cursor-2'));
        await loadingMore;
        expect(controller.items, <String>['b', 'c', 'd']);
      },
    );

    test('drops the matching items and notifies', () async {
      final controller = build();
      addTearDown(controller.dispose);

      await loadFirstPage(controller, items: <String>['a', 'b', 'c']);

      var notifications = 0;
      controller
        ..addListener(() => notifications++)
        ..removeWhere((item) => item == 'b');

      expect(controller.items, <String>['a', 'c']);
      expect(notifications, 1);
    });

    test('a no-op removal does not notify', () async {
      final controller = build();
      addTearDown(controller.dispose);

      await loadFirstPage(controller);

      var notifications = 0;
      controller
        ..addListener(() => notifications++)
        ..removeWhere((item) => item == 'nope');

      expect(controller.items, <String>['a', 'b']);
      expect(notifications, 0);
    });

    test('leaves the cursor and hasMore alone', () async {
      // Server-side page boundaries do not move because the client stopped
      // showing a row.
      final controller = build();
      addTearDown(controller.dispose);

      await loadFirstPage(controller);

      controller.removeWhere((item) => item == 'a');

      expect(controller.cursor, 'cursor-1');
      expect(controller.hasMore, isTrue);
    });
  });

  group('removeById', () {
    test('an id removed before its page lands stays gone when the page '
        'arrives', () async {
      final controller = build(idOf: (item) => item);
      addTearDown(controller.dispose);
      await loadFirstPage(controller, items: <String>['b', 'c']);

      final loadingMore = controller.loadMore();
      expect(controller.isLoadingMore, isTrue);
      var notifications = 0;
      controller
        ..addListener(() => notifications++)
        ..removeById('a');
      expect(controller.items, <String>['b', 'c']);
      expect(notifications, 0);

      fetcher.complete(1, page(<String>['a', 'd'], cursor: 'cursor-2'));
      await loadingMore;
      expect(controller.items, <String>['b', 'c', 'd']);
    });

    test('drops a loaded item, notifies once and keeps the cursor', () async {
      final controller = build(idOf: (item) => item);
      addTearDown(controller.dispose);
      await loadFirstPage(controller, items: <String>['a', 'b', 'c']);

      var notifications = 0;
      controller
        ..addListener(() => notifications++)
        ..removeById('b');

      expect(controller.items, <String>['a', 'c']);
      expect(notifications, 1);
      expect(controller.cursor, 'cursor-1');
    });
  });

  group('replaceItems', () {
    test('exposes the replacement as a new unmodifiable list and notifies '
        'once', () async {
      final controller = build();
      addTearDown(controller.dispose);

      await loadFirstPage(controller, cursor: 'C1');
      final before = controller.items;

      var notifications = 0;
      controller
        ..addListener(() => notifications++)
        ..replaceItems(<String>['a', 'b-with-replies']);

      expect(controller.items, <String>['a', 'b-with-replies']);
      expect(identical(controller.items, before), isFalse);
      // Widgets that captured the old list still see what they rendered.
      expect(before, <String>['a', 'b']);
      expect(() => controller.items.add('x'), throwsUnsupportedError);
      expect(notifications, 1);
    });

    test('does not alias the caller\'s list', () async {
      final controller = build();
      addTearDown(controller.dispose);

      await loadFirstPage(controller, cursor: 'C1');

      final replacement = <String>['a', 'b-with-replies'];
      controller.replaceItems(replacement);
      replacement.add('late mutation');

      expect(controller.items, <String>['a', 'b-with-replies']);
    });

    test('keeps cursor, hasMore, errors and loading flags', () async {
      final controller = build();
      addTearDown(controller.dispose);

      await loadFirstPage(controller, cursor: 'C1');

      controller.replaceItems(<String>['a', 'b-with-replies']);

      expect(controller.cursor, 'C1');
      expect(controller.hasMore, isTrue);
      expect(controller.error, isNull);
      expect(controller.loadMoreError, isNull);
      expect(controller.isLoading, isFalse);
      expect(controller.isLoadingMore, isFalse);
    });

    test('keeps a footer error and a first-page error', () async {
      final controller = build();
      addTearDown(controller.dispose);

      await loadFirstPage(controller, cursor: 'C1');
      final failedRefresh = controller.refresh();
      fetcher.fail(1, NetworkFailure());
      await failedRefresh;
      final failedLoadMore = controller.loadMore();
      fetcher.fail(2, Exception('page 2 exploded'));
      await failedLoadMore;
      final error = controller.error;
      final loadMoreError = controller.loadMoreError;
      expect(error, isNotNull);
      expect(loadMoreError, isNotNull);

      controller.replaceItems(<String>['a', 'b-with-replies']);

      expect(controller.items, <String>['a', 'b-with-replies']);
      expect(controller.error, error);
      expect(controller.loadMoreError, loadMoreError);
      expect(controller.cursor, 'C1');
    });

    test('does not invalidate a load-more already in flight', () async {
      // A reply-subtree merge rewrites the tree while the next top-level
      // page is still loading; that page must still land on the merged tree.
      final controller = build();
      addTearDown(controller.dispose);

      await loadFirstPage(controller, cursor: 'C1');

      final loadingMore = controller.loadMore();
      expect(controller.isLoadingMore, isTrue);
      expect(fetcher.requestedCursors.last, 'C1');

      controller.replaceItems(<String>['a', 'b-with-replies']);
      expect(controller.isLoadingMore, isTrue);

      fetcher.complete(1, page(<String>['c', 'd'], cursor: 'C2'));
      await loadingMore;

      expect(controller.items, <String>['a', 'b-with-replies', 'c', 'd']);
      expect(controller.cursor, 'C2');
      expect(controller.isLoadingMore, isFalse);
      expect(controller.loadMoreError, isNull);
    });
  });

  group('clearError', () {
    test('clears the first-page error and notifies', () async {
      final controller = build();
      addTearDown(controller.dispose);

      await loadFirstPage(controller, cursor: 'C1');
      final failed = controller.refresh();
      fetcher.fail(1, NetworkFailure());
      await failed;
      expect(controller.error, isNotNull);

      var notifications = 0;
      controller
        ..addListener(() => notifications++)
        ..clearError();

      expect(controller.error, isNull);
      expect(notifications, 1);
      expect(controller.items, <String>['a', 'b']);
      expect(controller.cursor, 'C1');
      expect(controller.loadMoreError, isNull);
    });

    test('leaves a footer error in place', () async {
      final controller = build();
      addTearDown(controller.dispose);

      await loadFirstPage(controller, cursor: 'C1');
      final failedRefresh = controller.refresh();
      fetcher.fail(1, NetworkFailure());
      await failedRefresh;
      final failedLoadMore = controller.loadMore();
      fetcher.fail(2, Exception('page 2 exploded'));
      await failedLoadMore;
      final loadMoreError = controller.loadMoreError;
      expect(controller.error, isNotNull);
      expect(loadMoreError, isNotNull);

      controller.clearError();

      expect(controller.error, isNull);
      expect(controller.loadMoreError, loadMoreError);
      expect(controller.items, <String>['a', 'b']);
      expect(controller.cursor, 'C1');
    });

    test('does not notify when there is no error', () async {
      final controller = build();
      addTearDown(controller.dispose);

      await loadFirstPage(controller, cursor: 'C1');

      var notifications = 0;
      controller
        ..addListener(() => notifications++)
        ..clearError();

      expect(controller.error, isNull);
      expect(notifications, 0);
    });
  });

  group('error reporting', () {
    test('a throwing errorMapper falls back to the error text', () async {
      // A mapper that throws used to wedge the controller: the message was
      // computed BEFORE the loading flags were cleared, and the throw
      // escaped refresh() (which promises never to rethrow).
      final controller = build(
        errorMapper: (error) => throw StateError('mapper exploded'),
      );
      addTearDown(controller.dispose);

      final failed = controller.refresh();
      fetcher.fail(0, Exception('boom'));
      await expectLater(failed, completes);

      expect(controller.isLoading, isFalse);
      expect(controller.error, contains('boom'));
    });

    test('a throwing errorMapper does not wedge load-more either', () async {
      final controller = build(
        errorMapper: (error) => throw StateError('mapper exploded'),
      );
      addTearDown(controller.dispose);

      final first = controller.refresh();
      fetcher.complete(0, page(<String>['a'], cursor: 'c1'));
      await first;

      final failed = controller.loadMore();
      fetcher.fail(1, Exception('page 2 exploded'));
      await expectLater(failed, completes);

      expect(controller.isLoadingMore, isFalse);
      expect(controller.loadMoreError, contains('page 2 exploded'));
    });

    test('onUnexpectedError sees first-page and load-more failures', () async {
      final reported = <Object>[];
      final controller = build(
        onUnexpectedError: (error, stack) => reported.add(error),
      );
      addTearDown(controller.dispose);

      final failedFirst = controller.refresh();
      fetcher.fail(0, StateError('first page'));
      await failedFirst;

      final ok = controller.refresh();
      fetcher.complete(1, page(<String>['a'], cursor: 'c1'));
      await ok;

      final failedMore = controller.loadMore();
      fetcher.fail(2, StateError('page 2'));
      await failedMore;

      expect(reported, hasLength(2));
      expect(reported.first, isA<StateError>());
    });

    test('onUnexpectedError sees hydration failures', () async {
      // Vote hydration failing silently is how wrong vote state ships.
      final reported = <Object>[];
      final controller = build(
        onPageLoaded: (newItems) async => throw StateError('vote hydration'),
        onUnexpectedError: (error, stack) => reported.add(error),
      );
      addTearDown(controller.dispose);

      await loadFirstPage(controller);

      expect(reported, hasLength(1));
      expect(reported.single, isA<StateError>());
      // The page itself still loaded.
      expect(controller.items, <String>['a', 'b']);
    });

    test('onUnexpectedError sees failures of superseded requests', () async {
      final reported = <Object>[];
      final controller = build(
        onUnexpectedError: (error, stack) => reported.add(error),
      );
      addTearDown(controller.dispose);

      await loadFirstPage(controller);

      final staleLoadMore = controller.loadMore();
      final refreshed = controller.refresh();
      fetcher.complete(2, page(<String>['x'], cursor: 'cursor-new'));
      await refreshed;
      fetcher.fail(1, StateError('stale boom'));
      await staleLoadMore;

      expect(reported, hasLength(1));
      // ...without polluting the visible state.
      expect(controller.error, isNull);
      expect(controller.loadMoreError, isNull);
    });

    test(
      'a throwing onUnexpectedError does not wedge the controller',
      () async {
        final controller = build(
          onUnexpectedError: (error, stack) => throw StateError('sentry down'),
        );
        addTearDown(controller.dispose);

        final failed = controller.refresh();
        fetcher.fail(0, Exception('boom'));
        await expectLater(failed, completes);

        expect(controller.isLoading, isFalse);
        expect(controller.error, isNotNull);
      },
    );
  });

  group('reset', () {
    test('clears items, cursor, flags and both errors', () async {
      final controller = build();
      addTearDown(controller.dispose);

      await loadFirstPage(controller);
      final failed = controller.loadMore();
      fetcher.fail(1, Exception('page 2 exploded'));
      await failed;

      controller.reset();

      expect(controller.items, isEmpty);
      expect(controller.cursor, isNull);
      expect(controller.hasMore, isFalse);
      expect(controller.isLoading, isFalse);
      expect(controller.isLoadingMore, isFalse);
      expect(controller.error, isNull);
      expect(controller.loadMoreError, isNull);
    });
  });

  group('dispose', () {
    test('a page landing after dispose does not notify or throw', () async {
      final controller = build();

      final future = controller.refresh();
      controller.dispose();
      fetcher.complete(0, page(<String>['a'], cursor: 'c1'));

      await expectLater(future, completes);
    });
  });

  group('session key', () {
    // Opaque per-session keys owned by the test; the controller only
    // compares them.
    final k1 = Object();
    final k2 = Object();
    late Object? currentKey;

    setUp(() => currentKey = k1);

    CursorPaginationController<String> buildKeyed({
      Future<void> Function(List<String> newItems)? onPageLoaded,
    }) {
      final controller = build(
        onPageLoaded: onPageLoaded,
        sessionKeyOf: () => currentKey,
      );
      addTearDown(controller.dispose);
      return controller;
    }

    /// Records every notified state in which the feed would render its
    /// "No posts yet" empty state: not loading, no items, no error.
    List<String> recordFalseEmptyStates(
      CursorPaginationController<String> controller,
    ) {
      final falseEmptyStates = <String>[];
      controller.addListener(() {
        if (!controller.isLoading &&
            controller.items.isEmpty &&
            controller.error == null) {
          falseEmptyStates.add('requests=${fetcher.requestCount}');
        }
      });
      return falseEmptyStates;
    }

    test('S5 a first page requested before a session change is replaced by '
        'a first page requested under the current session', () async {
      final hydrated = <List<String>>[];
      final controller = buildKeyed(
        onPageLoaded: (newItems) async => hydrated.add(newItems),
      );
      final falseEmptyStates = recordFalseEmptyStates(controller);

      final first = controller.refresh();
      currentKey = k2;
      fetcher.complete(0, page(<String>['a', 'b'], cursor: 'cursor-1'));
      await pumpEventQueue();

      expect(fetcher.requestCount, 2);
      expect(fetcher.requestedCursors, <String?>[null, null]);
      expect(controller.isLoading, isTrue);
      expect(controller.items, isEmpty);
      expect(controller.sessionStamp, isNot(same(k1)));

      fetcher.complete(1, page(<String>['c'], cursor: 'cursor-2'));
      expect(await first, isTrue);

      expect(controller.items, <String>['c']);
      expect(controller.cursor, 'cursor-2');
      expect(controller.sessionStamp, same(k2));
      expect(controller.isLoading, isFalse);
      expect(hydrated, <List<String>>[
        <String>['c'],
      ]);
      expect(falseEmptyStates, isEmpty);
    });

    test('S5 the stamp stays on the accepted session until '
        'a refresh under the next session lands', () async {
      final controller = buildKeyed();

      await loadFirstPage(controller);
      expect(controller.sessionStamp, same(k1));

      currentKey = k2;
      final refreshed = controller.refresh();
      expect(controller.sessionStamp, same(k1));

      fetcher.complete(1, page(<String>['c'], cursor: 'cursor-2'));
      expect(await refreshed, isTrue);
      expect(controller.items, <String>['c']);
      expect(controller.sessionStamp, same(k2));
    });

    test(
      'S5 a load-more page from another session is dropped, and the '
      'next load-more reloads the first page under the current session',
      () async {
        final controller = buildKeyed();
        await loadFirstPage(controller);
        expect(controller.items, <String>['a', 'b']);

        final more = controller.loadMore();
        currentKey = k2;
        fetcher.complete(1, page(<String>['c'], cursor: 'cursor-2'));
        await more;

        expect(controller.items, <String>['a', 'b']);
        expect(controller.cursor, 'cursor-1');
        expect(controller.isLoadingMore, isFalse);
        expect(controller.sessionStamp, same(k1));

        final next = controller.loadMore();
        expect(fetcher.requestCount, 3);
        expect(fetcher.requestedCursors[2], isNull);
        fetcher.complete(2, page(<String>['d'], cursor: 'cursor-3'));
        await next;

        expect(controller.items, <String>['d']);
        expect(controller.sessionStamp, same(k2));
      },
    );

    test('S5 a load-more under a stale stamp reloads the first page under '
        'the current session, and pagination resumes', () async {
      currentKey = null;
      final controller = buildKeyed();
      await loadFirstPage(controller);
      expect(controller.sessionStamp, isNull);
      expect(controller.hasMore, isTrue);

      // A guest signs in through a gate and returns to the same feed.
      currentKey = k1;
      final more = controller.loadMore();

      expect(fetcher.requestCount, 2);
      expect(fetcher.requestedCursors[1], isNull);
      fetcher.complete(1, page(<String>['c', 'd'], cursor: 'cursor-2'));
      await more;

      expect(controller.items, <String>['c', 'd']);
      expect(controller.cursor, 'cursor-2');
      expect(controller.sessionStamp, same(k1));
      expect(controller.error, isNull);
      expect(controller.loadMoreError, isNull);

      final next = controller.loadMore();
      expect(fetcher.requestCount, 3);
      expect(fetcher.requestedCursors[2], 'cursor-2');
      fetcher.complete(2, page(<String>['e'], cursor: 'cursor-3'));
      await next;

      expect(controller.items, <String>['c', 'd', 'e']);
      expect(controller.sessionStamp, same(k1));
    });

    test('S5 a first-page failure after a session change is replaced by '
        'a first page requested under the current session', () async {
      final controller = buildKeyed();
      final falseEmptyStates = recordFalseEmptyStates(controller);

      final first = controller.refresh();
      currentKey = k2;
      fetcher.fail(0, NetworkFailure());
      await pumpEventQueue();

      expect(fetcher.requestCount, 2);
      expect(fetcher.requestedCursors, <String?>[null, null]);
      expect(controller.isLoading, isTrue);
      expect(controller.error, isNull);
      expect(controller.errorCause, isNull);

      fetcher.complete(1, page(<String>['c'], cursor: 'cursor-2'));
      expect(await first, isTrue);

      expect(controller.items, <String>['c']);
      expect(controller.sessionStamp, same(k2));
      expect(controller.error, isNull);
      expect(controller.isLoading, isFalse);
      expect(falseEmptyStates, isEmpty);
    });

    test('S5 a session that keeps changing ends the first-page load in a '
        'visible error after three requests', () async {
      final controller = buildKeyed();
      final falseEmptyStates = recordFalseEmptyStates(controller);

      final first = controller.refresh();
      for (var attempt = 0; attempt < 3; attempt++) {
        await pumpEventQueue();
        expect(fetcher.requestCount, attempt + 1);
        currentKey = Object();
        fetcher.complete(attempt, page(<String>['x$attempt'], cursor: 'c'));
      }
      expect(await first, isFalse);
      await pumpEventQueue();

      expect(fetcher.requestCount, 3);
      expect(controller.isLoading, isFalse);
      expect(controller.items, isEmpty);
      expect(controller.error, isNotNull);
      expect(controller.errorCause, isNotNull);
      expect(controller.sessionStamp, isNull);
      expect(falseEmptyStates, isEmpty);
    });

    // Each row leaves page one ['a', 'b'] (cursor-1, stamped k1) on screen
    // with a first-page error while the session is k2; expectedRequests is
    // how many requests that took.
    final staleErrorRows = [
      (
        name: 'the reload a load-more starts fails',
        reachError: (CursorPaginationController<String> controller) async {
          await loadFirstPage(controller);
          currentKey = k2;
          final reload = controller.loadMore();
          expect(fetcher.requestCount, 2, reason: 'the reload was sent');
          expect(fetcher.requestedCursors[1], isNull);
          fetcher.fail(1, NetworkFailure());
          await reload;
        },
        expectedRequests: 2,
      ),
      (
        name: 'the reload a load-more starts ends with the session error',
        reachError: (CursorPaginationController<String> controller) async {
          await loadFirstPage(controller);
          currentKey = k2;
          final reload = controller.loadMore();
          expect(fetcher.requestCount, 2, reason: 'the reload was sent');
          expect(fetcher.requestedCursors[1], isNull);
          fetcher.fail(1, const SessionChangedDuringLoadException());
          await reload;
        },
        expectedRequests: 2,
      ),
      (
        name: 'a refresh failed before the session changed',
        reachError: (CursorPaginationController<String> controller) async {
          await loadFirstPage(controller);
          final failed = controller.refresh();
          fetcher.fail(1, NetworkFailure());
          await failed;
          currentKey = k2;
          // Not awaited: on a controller that reloads here, the reload
          // never lands and the request count below says so.
          unawaited(controller.loadMore());
          await pumpEventQueue();
        },
        expectedRequests: 2,
      ),
    ];
    for (final row in staleErrorRows) {
      test('S5 after ${row.name}, a load-more under the stale stamp sends '
          'nothing until retry reloads page one', () async {
        final controller = buildKeyed();
        await row.reachError(controller);

        for (var call = 0; call < 3; call++) {
          // Not awaited, for the same reason as above.
          unawaited(controller.loadMore());
          await pumpEventQueue();
        }

        expect(
          fetcher.requestCount,
          row.expectedRequests,
          reason:
              'a load-more under the stale stamp sends nothing while '
              'the first-page error shows',
        );
        expect(controller.items, <String>['a', 'b']);
        expect(controller.cursor, 'cursor-1');
        expect(controller.hasMore, isTrue);
        expect(controller.error, isNotNull);
        expect(controller.loadMoreError, isNull);
        expect(controller.sessionStamp, same(k1));

        final retried = controller.retry();
        expect(fetcher.requestCount, 3);
        expect(fetcher.requestedCursors[2], isNull);
        fetcher.complete(2, page(<String>['z'], cursor: 'cursor-9'));
        expect(await retried, isTrue);

        expect(controller.error, isNull);
        expect(controller.sessionStamp, same(k2));
        expect(controller.items, <String>['z']);

        final next = controller.loadMore();
        expect(fetcher.requestCount, 4);
        expect(fetcher.requestedCursors[3], 'cursor-9');
        fetcher.complete(3, page(<String>['y']));
        await next;
        expect(controller.items, <String>['z', 'y']);
      });
    }

    test('S5 under an unchanged session, a load-more after a failed refresh '
        'with items on screen still appends', () async {
      final controller = buildKeyed();
      await loadFirstPage(controller);
      final failed = controller.refresh();
      fetcher.fail(1, NetworkFailure());
      await failed;
      expect(controller.error, isNotNull);

      final more = controller.loadMore();
      expect(fetcher.requestCount, 3);
      expect(fetcher.requestedCursors[2], 'cursor-1');
      fetcher.complete(2, page(<String>['c'], cursor: 'cursor-2'));
      await more;

      expect(controller.items, <String>['a', 'b', 'c']);
      expect(controller.sessionStamp, same(k1));
    });
  });

  group('replaceItemById during a first-page load', () {
    // Items are 'id:version'; the id is the part before the colon.
    String idOf(String item) => item.split(':').first;

    test('a sort change whose first page overlaps a row replacement ends on '
        'the new sort\'s page and cursor', () async {
      var sort = 'hot';
      final requests = <(String, String?)>[];
      final firstNewPage = Completer<CursorPage<String>>();
      var newFirstPageCalls = 0;

      // A replacement is a confirmed server readback, so any first-page
      // read made after it already carries the replaced row's new version.
      Future<CursorPage<String>> fetch(String? cursor) {
        requests.add((sort, cursor));
        if (sort == 'hot') {
          return Future.value(
            page(<String>['h1:v1', 'h2:v1'], cursor: 'hot-c'),
          );
        }
        if (cursor == null) {
          newFirstPageCalls++;
          if (newFirstPageCalls == 1) {
            return firstNewPage.future;
          }
          return Future.value(
            page(<String>['n1:v1', 'h1:v2'], cursor: 'new-c'),
          );
        }
        return Future.value(page(<String>['n2:v1']));
      }

      final controller = CursorPaginationController<String>(
        fetchPage: fetch,
        idOf: idOf,
      );
      addTearDown(controller.dispose);

      expect(await controller.refresh(), isTrue);
      expect(controller.items, <String>['h1:v1', 'h2:v1']);
      expect(controller.cursor, 'hot-c');

      sort = 'new';
      final switched = controller.refresh();
      controller.replaceItemById('h1', (item) => 'h1:v2');
      // The response was read before the replacement landed.
      firstNewPage.complete(page(<String>['n1:v1', 'h1:v1'], cursor: 'new-c'));
      final landed = await switched;

      expect(controller.isLoading, isFalse);
      expect(controller.error, isNull);
      expect(controller.items, <String>['n1:v1', 'h1:v2']);
      expect(controller.cursor, 'new-c');
      expect(landed, isTrue);

      await controller.loadMore();
      expect(requests.last, ('new', 'new-c'));
      expect(controller.items, <String>['n1:v1', 'h1:v2', 'n2:v1']);
    });

    test('a sort change whose first page lacks the replaced row ends on the '
        'new sort\'s page and cursor', () async {
      var sort = 'hot';
      final requests = <(String, String?)>[];
      final firstNewPage = Completer<CursorPage<String>>();
      var newFirstPageCalls = 0;

      Future<CursorPage<String>> fetch(String? cursor) {
        requests.add((sort, cursor));
        if (sort == 'hot') {
          return Future.value(
            page(<String>['h1:v1', 'h2:v1'], cursor: 'hot-c'),
          );
        }
        if (cursor == null) {
          newFirstPageCalls++;
          if (newFirstPageCalls == 1) {
            return firstNewPage.future;
          }
          return Future.value(
            page(<String>['n1:v1', 'n2:v1'], cursor: 'new-c'),
          );
        }
        return Future.value(page(<String>['n3:v1']));
      }

      final controller = CursorPaginationController<String>(
        fetchPage: fetch,
        idOf: idOf,
      );
      addTearDown(controller.dispose);

      await controller.refresh();

      sort = 'new';
      final switched = controller.refresh();
      controller.replaceItemById('h1', (item) => 'h1:v2');
      firstNewPage.complete(page(<String>['n1:v1', 'n2:v1'], cursor: 'new-c'));
      final landed = await switched;

      expect(controller.isLoading, isFalse);
      expect(controller.error, isNull);
      expect(controller.items, <String>['n1:v1', 'n2:v1']);
      expect(controller.cursor, 'new-c');
      expect(landed, isTrue);

      await controller.loadMore();
      expect(requests.last, ('new', 'new-c'));
      expect(controller.items, <String>['n1:v1', 'n2:v1', 'n3:v1']);
    });

    test('a pull-to-refresh overlapping a row replacement replaces the old '
        'list and cursor, so a removed row cannot come back', () async {
      final requests = <String?>[];
      final refreshedFirstPage = Completer<CursorPage<String>>();
      var firstPageCalls = 0;

      // The server deleted 'c' between the initial load and the refresh;
      // the old cursor 'c1' would still page it back in.
      Future<CursorPage<String>> fetch(String? cursor) {
        requests.add(cursor);
        if (cursor == null) {
          firstPageCalls++;
          if (firstPageCalls == 1) {
            return Future.value(
              page(<String>['a:v1', 'b:v1', 'c:v1'], cursor: 'c1'),
            );
          }
          if (firstPageCalls == 2) {
            return refreshedFirstPage.future;
          }
          return Future.value(
            page(<String>['a:v2', 'b:v1', 'd:v1'], cursor: 'c2'),
          );
        }
        if (cursor == 'c1') {
          return Future.value(page(<String>['c:v1', 'e:v1']));
        }
        return Future.value(page(<String>['e:v1']));
      }

      final controller = CursorPaginationController<String>(
        fetchPage: fetch,
        idOf: idOf,
      );
      addTearDown(controller.dispose);

      await controller.refresh();
      controller.removeById('c');
      expect(controller.items, <String>['a:v1', 'b:v1']);

      final refreshing = controller.refresh();
      controller.replaceItemById('a', (item) => 'a:v2');
      refreshedFirstPage.complete(
        page(<String>['a:v1', 'b:v1', 'd:v1'], cursor: 'c2'),
      );
      final landed = await refreshing;

      expect(controller.isLoading, isFalse);
      expect(controller.error, isNull);
      expect(controller.items, <String>['a:v2', 'b:v1', 'd:v1']);
      expect(controller.cursor, 'c2');
      expect(landed, isTrue);

      await controller.loadMore();
      expect(requests.last, 'c2');
      expect(controller.items, <String>['a:v2', 'b:v1', 'd:v1', 'e:v1']);
      expect(controller.items.map(idOf), isNot(contains('c')));
    });
  });
}
