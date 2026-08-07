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
  }) {
    return CursorPaginationController<String>(
      fetchPage: fetcher.call,
      onPageLoaded: onPageLoaded,
      errorMapper: errorMapper,
      idOf: idOf,
      onUnexpectedError: onUnexpectedError,
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
    test('a refresh started during a loadMore discards the stale page',
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
    });

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

      expect(
        hydrated,
        <List<String>>[
          <String>['a', 'b'],
          <String>['x'],
        ],
      );
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

      expect(
        hydrated,
        <List<String>>[
          <String>['a', 'b'],
          <String>['c'],
        ],
      );
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
  });

  group('empty pages', () {
    test('an empty load-more page ends the feed even with a cursor',
        () async {
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

      expect(
        hydrated,
        <List<String>>[
          <String>['a', 'b'],
          <String>['c'],
        ],
      );
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

    test('onUnexpectedError sees first-page and load-more failures',
        () async {
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

    test('a throwing onUnexpectedError does not wedge the controller',
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
    });
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
}
