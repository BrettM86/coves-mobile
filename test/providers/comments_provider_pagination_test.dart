import 'dart:async';

import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/comments_provider.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/comment_service.dart';
import 'package:coves_flutter/services/viewer_state_hydrator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'comments_provider_test.mocks.dart';

/// One getComments call, answered by hand through [response] so each test
/// can interleave refreshes and pages without timers.
class _CommentsRequest {
  _CommentsRequest({
    required this.sort,
    required this.cursor,
    required this.parentRkey,
  });

  final String? sort;
  final String? cursor;

  /// Set only for loadMoreReplies subtree fetches.
  final String? parentRkey;
  final Completer<CommentsResponse> response = Completer<CommentsResponse>();
}

/// Records the comment URIs of every hydrateCommentTree call and applies
/// nothing.
class _RecordingHydrator extends ViewerStateHydrator {
  _RecordingHydrator(AuthProvider authProvider)
    : super(authProvider: authProvider);

  final List<List<String>> commentTreeCalls = <List<String>>[];

  @override
  void hydrateCommentTree(Iterable<ThreadViewComment> nodes) {
    commentTreeCalls.add(nodes.map((node) => node.comment.uri).toList());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testPostUri = 'at://did:plc:test/social.coves.post.record/123';
  const testPostCid = 'test-post-cid';

  late MockAuthProvider mockAuthProvider;
  late MockCovesApiService mockApiService;
  late MockVoteProvider mockVoteProvider;
  late CommentsProvider commentsProvider;
  late List<_CommentsRequest> requests;

  setUp(() {
    mockAuthProvider = MockAuthProvider();
    mockApiService = MockCovesApiService();
    mockVoteProvider = MockVoteProvider();
    requests = <_CommentsRequest>[];

    when(mockAuthProvider.isAuthenticated).thenReturn(true);
    when(mockAuthProvider.getAccessToken())
        .thenAnswer((_) async => 'test-token');

    when(
      mockApiService.getComments(
        postUri: anyNamed('postUri'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        depth: anyNamed('depth'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
        parentRkey: anyNamed('parentRkey'),
      ),
    ).thenAnswer((invocation) {
      final request = _CommentsRequest(
        sort: invocation.namedArguments[#sort] as String?,
        cursor: invocation.namedArguments[#cursor] as String?,
        parentRkey: invocation.namedArguments[#parentRkey] as String?,
      );
      requests.add(request);
      return request.response.future;
    });

    commentsProvider = CommentsProvider(
      mockAuthProvider,
      postUri: testPostUri,
      postCid: testPostCid,
      apiService: mockApiService,
      voteProvider: mockVoteProvider,
    );
  });

  tearDown(() {
    commentsProvider.dispose();
  });

  List<String> displayedUris() =>
      commentsProvider.comments.map((thread) => thread.comment.uri).toList();

  CommentsResponse response(List<String> uris, {String? cursor}) {
    return CommentsResponse(
      post: {},
      comments: uris.map(_createThreadComment).toList(),
      cursor: cursor,
    );
  }

  /// Loads page 1 (`comment-1`, `comment-2`) with cursor C1.
  Future<void> loadFirstPage() async {
    final load = commentsProvider.loadComments(refresh: true);
    await pumpEventQueue();
    requests.single.response.complete(
      response(<String>['comment-1', 'comment-2'], cursor: 'C1'),
    );
    await load;
    expect(displayedUris(), <String>['comment-1', 'comment-2']);
    expect(commentsProvider.hasMore, isTrue);
  }

  group('load-more failure', () {
    test('lands on loadMoreError, stops the scroll trigger, and retries '
        'from the same cursor', () async {
      await loadFirstPage();

      final failingPage = commentsProvider.loadMoreComments();
      await pumpEventQueue();
      expect(requests, hasLength(2));
      expect(requests[1].cursor, 'C1');
      requests[1].response.completeError(
        ApiException('Failed to load comments', statusCode: 500),
      );
      await failingPage;

      expect(commentsProvider.loadMoreError, isNotNull);
      expect(
        commentsProvider.error,
        isNull,
        reason: 'a page failure must not drive the full-screen error',
      );
      expect(displayedUris(), <String>['comment-1', 'comment-2']);

      // The scroll trigger fires on every tick; while the footer error is
      // showing none of those may reach the network. Not awaited: a fetch
      // that did start would never be answered.
      for (var attempt = 0; attempt < 3; attempt++) {
        unawaited(commentsProvider.loadMoreComments());
      }
      await pumpEventQueue();
      expect(
        requests,
        hasLength(2),
        reason: 'loadMoreComments must be a no-op while loadMoreError is set',
      );

      final retry = commentsProvider.retryLoadMore();
      await pumpEventQueue();
      expect(requests, hasLength(3));
      expect(requests[2].cursor, 'C1');
      expect(requests[2].sort, 'hot');
      requests[2].response.complete(response(<String>['comment-3']));
      await retry;

      expect(displayedUris(), <String>['comment-1', 'comment-2', 'comment-3']);
      expect(commentsProvider.loadMoreError, isNull);
      expect(commentsProvider.error, isNull);
    });
  });

  group('duplicate comments across pages', () {
    test('a comment already on page 1 is not appended again', () async {
      await loadFirstPage();

      final nextPage = commentsProvider.loadMoreComments();
      await pumpEventQueue();
      requests[1].response.complete(
        response(<String>['comment-2', 'comment-3']),
      );
      await nextPage;

      expect(displayedUris(), <String>['comment-1', 'comment-2', 'comment-3']);
    });
  });

  group('refresh supersedes', () {
    test('a second refresh fetches immediately and the older response is '
        'discarded', () async {
      final refreshA = commentsProvider.loadComments(refresh: true);
      await pumpEventQueue();
      final refreshB = commentsProvider.loadComments(refresh: true);
      await pumpEventQueue();

      expect(
        requests,
        hasLength(2),
        reason: 'refresh B must start before refresh A completes, not queue',
      );

      requests[1].response.complete(
        response(<String>['comment-b'], cursor: 'CB'),
      );
      await refreshB;
      requests[0].response.complete(
        response(<String>['comment-a'], cursor: 'CA'),
      );
      await refreshA;
      await pumpEventQueue();

      expect(displayedUris(), <String>['comment-b']);
      expect(
        requests,
        hasLength(2),
        reason: 'no queued refresh may run after the requests settle',
      );
    });

    test('a refresh discards a load-more page that lands after it', () async {
      await loadFirstPage();

      final loadMore = commentsProvider.loadMoreComments();
      await pumpEventQueue();
      expect(requests, hasLength(2));

      final refresh = commentsProvider.loadComments(refresh: true);
      await pumpEventQueue();
      expect(
        requests,
        hasLength(3),
        reason: 'a refresh must not wait for an in-flight load-more',
      );
      expect(requests[2].cursor, isNull);

      requests[2].response.complete(
        response(<String>['comment-r'], cursor: 'CR'),
      );
      await refresh;
      requests[1].response.complete(response(<String>['comment-stale']));
      await loadMore;

      expect(displayedUris(), <String>['comment-r']);
    });
  });

  group('sort ownership', () {
    /// Starts the next page and checks it continues [sort] from [cursor],
    /// then lands an empty page so nothing is left in flight.
    Future<void> expectNextPageContinues({
      required String sort,
      required String cursor,
    }) async {
      final requestsBefore = requests.length;
      final nextPage = commentsProvider.loadMoreComments();
      await pumpEventQueue();
      expect(requests, hasLength(requestsBefore + 1));
      expect(requests.last.sort, sort);
      expect(requests.last.cursor, cursor);
      requests.last.response.complete(response(<String>[]));
      await nextPage;
    }

    test('overlapping sort changes where the newest fails keep the loaded '
        'hot thread', () async {
      await loadFirstPage();

      final topChange = commentsProvider.setSortOption('top');
      await pumpEventQueue();
      final newChange = commentsProvider.setSortOption('new');
      await pumpEventQueue();
      expect(requests, hasLength(3));
      expect(requests[1].sort, 'top');
      expect(requests[2].sort, 'new');

      requests[2].response.completeError(
        ApiException('Failed to load comments', statusCode: 500),
      );
      expect(
        await newChange,
        isFalse,
        reason: 'the current sort change failed',
      );

      requests[1].response.complete(
        response(<String>['comment-top'], cursor: 'CT'),
      );
      expect(
        await topChange,
        isTrue,
        reason: 'a superseded sort change is not the failing request',
      );

      expect(
        commentsProvider.sort,
        'hot',
        reason:
            'the label reverts to the sort actually on screen, not to '
            'the superseded top request',
      );
      expect(displayedUris(), <String>['comment-1', 'comment-2']);
      expect(commentsProvider.error, isNull);

      await expectNextPageContinues(sort: 'hot', cursor: 'C1');
    });

    test('overlapping sort changes where the newest succeeds ignore the older '
        'failure', () async {
      await loadFirstPage();

      final topChange = commentsProvider.setSortOption('top');
      await pumpEventQueue();
      final newChange = commentsProvider.setSortOption('new');
      await pumpEventQueue();
      expect(requests, hasLength(3));

      requests[2].response.complete(
        response(<String>['comment-new'], cursor: 'CN'),
      );
      expect(await newChange, isTrue);

      requests[1].response.completeError(
        ApiException('Failed to load comments', statusCode: 500),
      );
      expect(
        await topChange,
        isTrue,
        reason: 'a superseded sort change reports nothing',
      );

      expect(commentsProvider.sort, 'new');
      expect(displayedUris(), <String>['comment-new']);
      expect(commentsProvider.error, isNull);
      expect(commentsProvider.loadMoreError, isNull);
    });

    test('a sort change superseded by a failing refresh reverts the label '
        'and surfaces the refresh error', () async {
      await loadFirstPage();

      final newChange = commentsProvider.setSortOption('new');
      await pumpEventQueue();
      final refresh = commentsProvider.refreshComments();
      await pumpEventQueue();
      expect(requests, hasLength(3));
      expect(requests[1].sort, 'new');
      expect(
        requests[2].sort,
        'new',
        reason: 'the refresh reloads the sort the user just picked',
      );
      expect(requests[2].cursor, isNull);

      requests[2].response.completeError(
        ApiException('Failed to load comments', statusCode: 500),
      );
      await refresh;
      requests[1].response.complete(
        response(<String>['comment-stale-new'], cursor: 'CS'),
      );

      expect(
        await newChange,
        isTrue,
        reason: 'the sort change was superseded; the refresh is what failed',
      );
      expect(commentsProvider.sort, 'hot');
      expect(displayedUris(), <String>['comment-1', 'comment-2']);
      expect(
        commentsProvider.error,
        isNotNull,
        reason: 'a failed pull-to-refresh is reported on the error channel',
      );

      await expectNextPageContinues(sort: 'hot', cursor: 'C1');
    });

    test('a sort change superseded by a successful refresh keeps the new '
        'sort', () async {
      await loadFirstPage();

      final newChange = commentsProvider.setSortOption('new');
      await pumpEventQueue();
      final refresh = commentsProvider.refreshComments();
      await pumpEventQueue();
      expect(requests, hasLength(3));

      requests[2].response.complete(
        response(<String>['comment-refreshed'], cursor: 'CR'),
      );
      await refresh;
      requests[1].response.complete(
        response(<String>['comment-stale-new'], cursor: 'CS'),
      );

      expect(await newChange, isTrue);
      expect(commentsProvider.sort, 'new');
      expect(displayedUris(), <String>['comment-refreshed']);
    });

    test('after a successful sort change, pagination and a later failed '
        'refresh both use the new sort', () async {
      await loadFirstPage();

      final newChange = commentsProvider.setSortOption('new');
      await pumpEventQueue();
      expect(requests, hasLength(2));
      expect(requests[1].sort, 'new');
      requests[1].response.complete(
        response(<String>['comment-new'], cursor: 'CN'),
      );
      expect(await newChange, isTrue);

      final refresh = commentsProvider.refreshComments();
      await pumpEventQueue();
      expect(requests, hasLength(3));
      expect(
        requests[2].sort,
        'new',
        reason: 'the refresh reloads the sort now on screen',
      );
      expect(requests[2].cursor, isNull);
      requests[2].response.completeError(
        ApiException('Failed to load comments', statusCode: 500),
      );
      await refresh;

      expect(
        commentsProvider.sort,
        'new',
        reason:
            'the label reverts to the sort on screen, which the landed sort '
            'change made new',
      );
      expect(displayedUris(), <String>['comment-new']);

      await expectNextPageContinues(sort: 'new', cursor: 'CN');
    });
  });

  group('quiet refresh', () {
    /// Every isLoading value a listener sees, in notification order.
    List<bool> recordLoadingNotifications() {
      final observed = <bool>[];
      commentsProvider.addListener(
        () => observed.add(commentsProvider.isLoading),
      );
      return observed;
    }

    /// First load lands with zero comments and no cursor.
    Future<void> loadEmptyThread() async {
      final load = commentsProvider.loadComments(refresh: true);
      await pumpEventQueue();
      requests.single.response.complete(response(<String>[]));
      await load;
      expect(displayedUris(), isEmpty);
      expect(commentsProvider.isLoading, isFalse);
    }

    test('on an empty thread never shows as loading, from start through '
        'landing', () async {
      await loadEmptyThread();
      final observed = recordLoadingNotifications();

      final quiet = commentsProvider.loadComments(refresh: true, quiet: true);
      await pumpEventQueue();
      expect(requests, hasLength(2));
      expect(commentsProvider.isLoading, isFalse);

      requests[1].response.complete(response(<String>['comment-new']));
      await quiet;

      expect(displayedUris(), <String>['comment-new']);
      expect(commentsProvider.isLoading, isFalse);
      expect(observed, isNotEmpty);
      expect(
        observed,
        everyElement(isFalse),
        reason: 'a quiet refresh must never expose isLoading == true',
      );
    });

    group('quiet then ordinary overlap', () {
      /// Starts a quiet refresh, then an ordinary one on top of it, and
      /// returns their futures (quiet first).
      Future<List<Future<void>>> startQuietThenOrdinary() async {
        await loadEmptyThread();
        final quiet = commentsProvider.loadComments(refresh: true, quiet: true);
        await pumpEventQueue();
        final ordinary = commentsProvider.loadComments(refresh: true);
        await pumpEventQueue();
        expect(requests, hasLength(3));
        expect(
          commentsProvider.isLoading,
          isTrue,
          reason: 'a newer ordinary refresh is visible as loading',
        );
        return <Future<void>>[quiet, ordinary];
      }

      test('the stale quiet response landing first does not clear the '
          'ordinary refresh loading state', () async {
        final futures = await startQuietThenOrdinary();
        final observed = recordLoadingNotifications();

        requests[1].response.complete(response(<String>['comment-quiet']));
        await futures[0];
        await pumpEventQueue();
        expect(
          commentsProvider.isLoading,
          isTrue,
          reason: 'the stale quiet request must not end the ordinary load',
        );
        expect(displayedUris(), isEmpty);
        expect(
          observed,
          everyElement(isTrue),
          reason:
              'no listener may see loading drop before the ordinary '
              'refresh lands',
        );

        requests[2].response.complete(response(<String>['comment-ordinary']));
        await futures[1];

        expect(commentsProvider.isLoading, isFalse);
        expect(displayedUris(), <String>['comment-ordinary']);
      });

      test('the stale quiet response landing after the ordinary one changes '
          'nothing', () async {
        final futures = await startQuietThenOrdinary();

        requests[2].response.complete(response(<String>['comment-ordinary']));
        await futures[1];
        expect(commentsProvider.isLoading, isFalse);
        expect(displayedUris(), <String>['comment-ordinary']);

        final observed = recordLoadingNotifications();
        requests[1].response.complete(response(<String>['comment-quiet']));
        await futures[0];
        await pumpEventQueue();

        expect(commentsProvider.isLoading, isFalse);
        expect(displayedUris(), <String>['comment-ordinary']);
        expect(observed, everyElement(isFalse));
      });
    });

    test('ordinary then quiet overlap: the quiet refresh owns loading and '
        'the stale ordinary response is dropped', () async {
      await loadFirstPage();

      final ordinary = commentsProvider.loadComments(refresh: true);
      await pumpEventQueue();
      expect(commentsProvider.isLoading, isTrue);

      final observed = recordLoadingNotifications();
      final quiet = commentsProvider.loadComments(refresh: true, quiet: true);
      await pumpEventQueue();
      expect(requests, hasLength(3));
      expect(
        commentsProvider.isLoading,
        isFalse,
        reason: 'the current request is quiet',
      );

      requests[1].response.complete(
        response(<String>['comment-stale-ordinary'], cursor: 'CS'),
      );
      await ordinary;
      await pumpEventQueue();
      expect(commentsProvider.isLoading, isFalse);
      expect(displayedUris(), <String>[
        'comment-1',
        'comment-2',
      ], reason: 'the superseded ordinary response must not land');

      requests[2].response.complete(
        response(<String>['comment-quiet'], cursor: 'CQ'),
      );
      await quiet;

      expect(commentsProvider.isLoading, isFalse);
      expect(displayedUris(), <String>['comment-quiet']);
      expect(
        observed,
        everyElement(isFalse),
        reason:
            'once the quiet refresh supersedes, no listener may see '
            'isLoading == true',
      );
    });

    test('createComment on an empty thread shows loading only for the first '
        'ordinary refresh, never for the quiet indexing retries', () async {
      const newCommentUri = 'at://did:plc:test/comment/new';
      final mockCommentService = MockCommentService();
      when(
        mockCommentService.createComment(
          rootUri: anyNamed('rootUri'),
          rootCid: anyNamed('rootCid'),
          parentUri: anyNamed('parentUri'),
          parentCid: anyNamed('parentCid'),
          content: anyNamed('content'),
          contentFacets: anyNamed('contentFacets'),
        ),
      ).thenAnswer(
        (_) async =>
            const CreateCommentResponse(uri: newCommentUri, cid: 'cid-new'),
      );

      // Replace the default provider with one that can create comments.
      commentsProvider.dispose();
      commentsProvider = CommentsProvider(
        mockAuthProvider,
        postUri: testPostUri,
        postCid: testPostCid,
        apiService: mockApiService,
        voteProvider: mockVoteProvider,
        commentService: mockCommentService,
        indexingRetryDelays: const <Duration>[
          Duration.zero,
          Duration.zero,
          Duration.zero,
        ],
      );

      await loadEmptyThread();

      // Number of getComments responses delivered so far (request 0, the
      // empty first load, is already answered).
      var answered = 1;

      // isLoading paired with how many responses had been delivered when a
      // listener was notified. answered == 1 is the window from the
      // ordinary refresh starting until its response is delivered.
      final observed = <(int, bool)>[];
      commentsProvider.addListener(
        () => observed.add((answered, commentsProvider.isLoading)),
      );
      // isLoading read right after each getComments call is observed.
      final loadingAtRequestStart = <int, bool>{};

      // Request 1 is the ordinary refresh after create and misses the new
      // comment; request 2 is the first quiet retry and still misses it;
      // request 3 is the second quiet retry and finds it.
      final answers = <int, List<String>>{
        1: <String>[],
        2: <String>[],
        3: <String>[newCommentUri],
      };

      var created = false;
      final create = commentsProvider
          .createComment(content: 'A new comment')
          .whenComplete(() => created = true);

      while (!created) {
        await pumpEventQueue();
        while (answered < requests.length) {
          loadingAtRequestStart[answered] = commentsProvider.isLoading;
          final uris = answers[answered];
          expect(
            uris,
            isNotNull,
            reason: 'unexpected getComments call #$answered',
          );
          requests[answered].response.complete(response(uris!));
          answered++;
        }
      }
      await create;

      expect(requests, hasLength(4));
      expect(displayedUris(), <String>[newCommentUri]);
      expect(commentsProvider.isLoading, isFalse);

      expect(
        loadingAtRequestStart[1],
        isTrue,
        reason: 'the first refresh after create is ordinary',
      );
      expect(loadingAtRequestStart[2], isFalse);
      expect(loadingAtRequestStart[3], isFalse);

      final loadingObservations = observed
          .where((observation) => observation.$2)
          .map((observation) => observation.$1)
          .toList();
      expect(
        loadingObservations,
        isNotEmpty,
        reason: 'the ordinary refresh after create is visible as loading',
      );
      expect(
        loadingObservations,
        everyElement(1),
        reason:
            'isLoading == true may only be seen before the first '
            'ordinary refresh lands, never during the quiet retries',
      );
    });
  });
  group('reply subtree merges', () {
    const parentUri =
        'at://did:plc:author/social.coves.community.comment/parent';
    const siblingUri =
        'at://did:plc:author/social.coves.community.comment/sibling';
    const replyUri = 'at://did:plc:author/social.coves.community.comment/reply';
    const pageTwoUri =
        'at://did:plc:author/social.coves.community.comment/page-two';

    ThreadViewComment thread(
      String uri, {
      List<ThreadViewComment>? replies,
      bool hasMore = false,
      String? repliesCursor,
    }) {
      return ThreadViewComment(
        comment: _createThreadComment(uri).comment,
        replies: replies,
        hasMore: hasMore,
        repliesCursor: repliesCursor,
      );
    }

    CommentsResponse threads(
      List<ThreadViewComment> comments, {
      String? cursor,
    }) {
      return CommentsResponse(post: {}, comments: comments, cursor: cursor);
    }

    /// The parent's subtree with one fetched reply.
    CommentsResponse subtreeWithReply() {
      return threads(<ThreadViewComment>[
        thread(parentUri, replies: <ThreadViewComment>[thread(replyUri)]),
      ]);
    }

    ThreadViewComment displayedParent() => commentsProvider.comments
        .singleWhere((thread) => thread.comment.uri == parentUri);

    List<String> parentReplyUris() => (displayedParent().replies ?? const [])
        .map((reply) => reply.comment.uri)
        .toList();

    /// Loads page 1: the parent (more replies to fetch) and a sibling, with
    /// cursor C1.
    Future<void> loadThreadWithParent({String? parentRepliesCursor}) async {
      final load = commentsProvider.loadComments(refresh: true);
      await pumpEventQueue();
      requests.single.response.complete(
        threads(<ThreadViewComment>[
          thread(parentUri, hasMore: true, repliesCursor: parentRepliesCursor),
          thread(siblingUri),
        ], cursor: 'C1'),
      );
      await load;
      expect(displayedUris(), <String>[parentUri, siblingUri]);
      expect(displayedParent().hasMore, isTrue);
    }

    /// Starts loadMoreReplies for the parent and returns it with its
    /// request, checking the request is a subtree fetch for the parent.
    Future<(Future<ThreadViewComment?>, _CommentsRequest)>
    startParentSubtreeFetch() async {
      final requestsBefore = requests.length;
      final subtree = commentsProvider.loadMoreReplies(parentUri);
      await pumpEventQueue();
      expect(requests, hasLength(requestsBefore + 1));
      expect(requests.last.parentRkey, 'parent');
      return (subtree, requests.last);
    }

    /// Starts the next top-level page and returns it with its request,
    /// checking it continues from C1.
    Future<(Future<void>, _CommentsRequest)> startNextPage() async {
      final requestsBefore = requests.length;
      final nextPage = commentsProvider.loadMoreComments();
      await pumpEventQueue();
      expect(requests, hasLength(requestsBefore + 1));
      expect(requests.last.parentRkey, isNull);
      expect(requests.last.cursor, 'C1');
      return (nextPage, requests.last);
    }

    test('a merged reply is visible and survives the next page '
        'landing', () async {
      await loadThreadWithParent();

      final (subtree, subtreeRequest) = await startParentSubtreeFetch();
      subtreeRequest.response.complete(subtreeWithReply());
      final merged = await subtree;

      expect(merged, isNotNull);
      expect(parentReplyUris(), <String>[replyUri]);

      final (nextPage, pageRequest) = await startNextPage();
      pageRequest.response.complete(
        threads(<ThreadViewComment>[thread(pageTwoUri)]),
      );
      await nextPage;

      expect(displayedUris(), <String>[parentUri, siblingUri, pageTwoUri]);
      expect(parentReplyUris(), <String>[
        replyUri,
      ], reason: 'the merged reply must survive the page landing');
    });

    test('a merge that lands while the next page is in flight keeps both '
        'the reply and the page', () async {
      await loadThreadWithParent();

      final (nextPage, pageRequest) = await startNextPage();
      final (subtree, subtreeRequest) = await startParentSubtreeFetch();

      subtreeRequest.response.complete(subtreeWithReply());
      expect(await subtree, isNotNull);
      expect(parentReplyUris(), <String>[replyUri]);

      pageRequest.response.complete(
        threads(<ThreadViewComment>[thread(pageTwoUri)]),
      );
      await nextPage;

      expect(displayedUris(), <String>[parentUri, siblingUri, pageTwoUri]);
      expect(parentReplyUris(), <String>[
        replyUri,
      ], reason: 'the page landing must not overwrite the merged reply');
    });

    test('an empty subtree response clears hasMore and the replies cursor, '
        'and the cleared state survives the next page landing', () async {
      await loadThreadWithParent(parentRepliesCursor: 'RC');

      final (subtree, subtreeRequest) = await startParentSubtreeFetch();
      expect(subtreeRequest.cursor, 'RC');
      subtreeRequest.response.complete(threads(<ThreadViewComment>[]));
      expect(await subtree, isNull);

      expect(displayedParent().hasMore, isFalse);
      expect(displayedParent().repliesCursor, isNull);

      final (nextPage, pageRequest) = await startNextPage();
      pageRequest.response.complete(
        threads(<ThreadViewComment>[thread(pageTwoUri)]),
      );
      await nextPage;

      expect(displayedUris(), <String>[parentUri, siblingUri, pageTwoUri]);
      expect(displayedParent().hasMore, isFalse);
      expect(displayedParent().repliesCursor, isNull);
    });

    test(
      'a subtree fetch started before a refresh lands is discarded',
      () async {
        await loadThreadWithParent();

        final (subtree, subtreeRequest) = await startParentSubtreeFetch();

        final refresh = commentsProvider.refreshComments();
        await pumpEventQueue();
        final refreshRequest = requests.last;
        expect(refreshRequest.parentRkey, isNull);
        expect(refreshRequest.cursor, isNull);
        refreshRequest.response.complete(
          threads(<ThreadViewComment>[thread(parentUri)], cursor: 'CR'),
        );
        await refresh;
        expect(displayedUris(), <String>[parentUri]);

        subtreeRequest.response.complete(subtreeWithReply());
        expect(
          await subtree,
          isNull,
          reason: 'the subtree belongs to the tree the refresh replaced',
        );
        expect(
          parentReplyUris(),
          isEmpty,
          reason: 'the stale subtree must not be merged into the new tree',
        );
      },
    );

    test(
      'a subtree fetch is not invalidated by the next page landing',
      () async {
        await loadThreadWithParent();

        final (subtree, subtreeRequest) = await startParentSubtreeFetch();

        final (nextPage, pageRequest) = await startNextPage();
        pageRequest.response.complete(
          threads(<ThreadViewComment>[thread(pageTwoUri)]),
        );
        await nextPage;
        expect(displayedUris(), <String>[parentUri, siblingUri, pageTwoUri]);

        subtreeRequest.response.complete(subtreeWithReply());
        final merged = await subtree;

        expect(
          merged,
          isNotNull,
          reason: 'appending a page does not replace the tree',
        );
        expect(merged!.comment.uri, parentUri);
        expect(parentReplyUris(), <String>[replyUri]);
        expect(displayedUris(), <String>[parentUri, siblingUri, pageTwoUri]);
      },
    );

    test(
      'a subtree fetch started before a failed refresh is still merged',
      () async {
        await loadThreadWithParent();

        final (subtree, subtreeRequest) = await startParentSubtreeFetch();

        final refresh = commentsProvider.refreshComments();
        await pumpEventQueue();
        final refreshRequest = requests.last;
        expect(refreshRequest.parentRkey, isNull);
        refreshRequest.response.completeError(
          ApiException('Failed to load comments', statusCode: 500),
        );
        await refresh;
        expect(commentsProvider.error, isNotNull);
        expect(displayedUris(), <String>[parentUri, siblingUri]);

        subtreeRequest.response.complete(subtreeWithReply());
        final merged = await subtree;

        expect(merged, isNotNull, reason: 'a failed refresh replaced no tree');
        expect(merged!.comment.uri, parentUri);
        expect(parentReplyUris(), <String>[replyUri]);
      },
    );

    group('reply fetches during a sort change', () {
      test('a reply fetch started while a sort change is in flight uses the '
          'sort of the comments on screen', () async {
        await loadThreadWithParent(parentRepliesCursor: 'RC1');

        final topChange = commentsProvider.setSortOption('top');
        await pumpEventQueue();
        final sortRequest = requests.last;
        expect(sortRequest.sort, 'top');
        expect(sortRequest.parentRkey, isNull);

        final (subtree, subtreeRequest) = await startParentSubtreeFetch();
        expect(subtreeRequest.cursor, 'RC1');
        expect(
          subtreeRequest.sort,
          'hot',
          reason:
              'the replies cursor was produced by the hot thread on '
              'screen; the backend rejects it under a different sort',
        );

        subtreeRequest.response.complete(threads(<ThreadViewComment>[]));
        await subtree;
        sortRequest.response.complete(
          threads(<ThreadViewComment>[thread(siblingUri)], cursor: 'CT'),
        );
        await topChange;
      });

      test(
        'replies that land while a sort change is in flight are merged '
        'into the tree on screen and survive the sort change failing',
        () async {
          await loadThreadWithParent();

          final (subtree, subtreeRequest) = await startParentSubtreeFetch();
          expect(subtreeRequest.sort, 'hot');

          final topChange = commentsProvider.setSortOption('top');
          await pumpEventQueue();
          final sortRequest = requests.last;
          expect(sortRequest.sort, 'top');
          expect(sortRequest.parentRkey, isNull);

          subtreeRequest.response.complete(subtreeWithReply());
          final merged = await subtree;

          expect(
            merged,
            isNotNull,
            reason:
                'the hot tree the replies belong to is still on screen; a '
                'sort change that has not landed replaced nothing',
          );
          expect(merged!.comment.uri, parentUri);
          expect(parentReplyUris(), <String>[replyUri]);

          sortRequest.response.completeError(
            ApiException('Failed to load comments', statusCode: 500),
          );
          expect(await topChange, isFalse);

          expect(commentsProvider.sort, 'hot');
          expect(displayedUris(), <String>[parentUri, siblingUri]);
          expect(parentReplyUris(), <String>[
            replyUri,
          ], reason: 'the failed sort change replaced no tree');
        },
      );
    });
  });
  group('refresh bookkeeping', () {
    const parentUri =
        'at://did:plc:author/social.coves.community.comment/parent';
    const siblingUri =
        'at://did:plc:author/social.coves.community.comment/sibling';
    const replyUri = 'at://did:plc:author/social.coves.community.comment/reply';

    late _RecordingHydrator hydrator;

    CommentsProvider buildProvider() {
      return CommentsProvider(
        mockAuthProvider,
        postUri: testPostUri,
        postCid: testPostCid,
        apiService: mockApiService,
        voteProvider: mockVoteProvider,
        hydrator: hydrator,
      );
    }

    setUp(() {
      hydrator = _RecordingHydrator(mockAuthProvider);
      // Replace the default provider with one that reports hydration; the
      // outer tearDown disposes the replacement.
      commentsProvider.dispose();
      commentsProvider = buildProvider();
    });

    test('lastRefreshTime moves only when a refresh lands', () async {
      expect(commentsProvider.lastRefreshTime, isNull);
      expect(commentsProvider.isStale, isTrue);

      // A refresh lands: the parent (more replies to fetch) and a sibling.
      final firstLoad = commentsProvider.loadComments(refresh: true);
      await pumpEventQueue();
      requests.last.response.complete(
        CommentsResponse(
          post: {},
          comments: <ThreadViewComment>[
            ThreadViewComment(
              comment: _createThreadComment(parentUri).comment,
              hasMore: true,
            ),
            _createThreadComment(siblingUri),
          ],
          cursor: 'C1',
        ),
      );
      await firstLoad;
      final firstLanded = commentsProvider.lastRefreshTime;
      expect(firstLanded, isNotNull);
      expect(commentsProvider.isStale, isFalse);

      // A next page lands.
      final nextPage = commentsProvider.loadMoreComments();
      await pumpEventQueue();
      expect(requests.last.cursor, 'C1');
      requests.last.response.complete(response(<String>['comment-3']));
      await nextPage;
      expect(
        commentsProvider.lastRefreshTime,
        same(firstLanded),
        reason: 'a next page is not a refresh',
      );

      // A reply subtree merges.
      final subtree = commentsProvider.loadMoreReplies(parentUri);
      await pumpEventQueue();
      expect(requests.last.parentRkey, 'parent');
      requests.last.response.complete(
        CommentsResponse(
          post: {},
          comments: <ThreadViewComment>[
            ThreadViewComment(
              comment: _createThreadComment(parentUri).comment,
              replies: <ThreadViewComment>[_createThreadComment(replyUri)],
            ),
          ],
        ),
      );
      expect(await subtree, isNotNull);
      expect(
        commentsProvider.lastRefreshTime,
        same(firstLanded),
        reason: 'a reply merge is not a refresh',
      );

      // A refresh fails.
      final failedRefresh = commentsProvider.refreshComments();
      await pumpEventQueue();
      requests.last.response.completeError(
        ApiException('Failed to load comments', statusCode: 500),
      );
      await failedRefresh;
      expect(commentsProvider.error, isNotNull);
      expect(
        commentsProvider.lastRefreshTime,
        same(firstLanded),
        reason: 'a failed refresh landed nothing',
      );

      // Two overlapping refreshes: the newer one lands EMPTY, then the
      // superseded one lands late.
      final supersededRefresh = commentsProvider.refreshComments();
      await pumpEventQueue();
      final supersededRequest = requests.last;
      final currentRefresh = commentsProvider.refreshComments();
      await pumpEventQueue();
      final currentRequest = requests.last;
      expect(currentRequest, isNot(same(supersededRequest)));

      currentRequest.response.complete(response(<String>[]));
      await currentRefresh;
      final emptyLanded = commentsProvider.lastRefreshTime;
      expect(emptyLanded, isNotNull);
      expect(
        emptyLanded,
        isNot(same(firstLanded)),
        reason: 'a successful empty refresh still landed',
      );
      expect(commentsProvider.isStale, isFalse);

      supersededRequest.response.complete(response(<String>['comment-late']));
      await supersededRefresh;
      await pumpEventQueue();
      expect(displayedUris(), isEmpty);
      expect(
        commentsProvider.lastRefreshTime,
        same(emptyLanded),
        reason: 'a superseded refresh landing late changes nothing',
      );
    });

    test('hydration receives only the fresh comments of the page that '
        'landed', () async {
      await loadFirstPage();
      expect(hydrator.commentTreeCalls, <List<String>>[
        <String>['comment-1', 'comment-2'],
      ]);

      final nextPage = commentsProvider.loadMoreComments();
      await pumpEventQueue();
      requests.last.response.complete(
        response(<String>['comment-2', 'comment-3']),
      );
      await nextPage;
      expect(hydrator.commentTreeCalls, <List<String>>[
        <String>['comment-1', 'comment-2'],
        <String>['comment-3'],
      ], reason: 'the duplicate comment-2 is dropped before hydration');

      final supersededRefresh = commentsProvider.refreshComments();
      await pumpEventQueue();
      final supersededRequest = requests.last;
      final currentRefresh = commentsProvider.refreshComments();
      await pumpEventQueue();
      requests.last.response.complete(response(<String>['comment-current']));
      await currentRefresh;
      expect(hydrator.commentTreeCalls.last, <String>['comment-current']);
      final callsBeforeLateResponse = hydrator.commentTreeCalls.length;

      supersededRequest.response.complete(response(<String>['comment-late']));
      await supersededRefresh;
      await pumpEventQueue();
      expect(
        hydrator.commentTreeCalls,
        hasLength(callsBeforeLateResponse),
        reason: 'a superseded response is not hydrated',
      );

      // A response that lands after dispose.
      final disposedProvider = buildProvider();
      final lateRefresh = disposedProvider.loadComments(refresh: true);
      await pumpEventQueue();
      final lateRequest = requests.last;
      disposedProvider.dispose();
      lateRequest.response.complete(response(<String>['comment-disposed']));
      await lateRefresh;
      await pumpEventQueue();
      expect(
        hydrator.commentTreeCalls,
        hasLength(callsBeforeLateResponse),
        reason: 'a response landing after dispose is not hydrated',
      );
    });

    group('after dispose', () {
      test('a late refresh response notifies nobody, hydrates nothing, and '
          'leaves lastRefreshTime alone', () async {
        final disposedProvider = buildProvider();
        final firstLoad = disposedProvider.loadComments(refresh: true);
        await pumpEventQueue();
        requests.last.response.complete(response(<String>['comment-1']));
        await firstLoad;
        final landed = disposedProvider.lastRefreshTime;
        expect(landed, isNotNull);
        final hydrationCalls = hydrator.commentTreeCalls.length;

        final lateRefresh = disposedProvider.loadComments(refresh: true);
        await pumpEventQueue();
        final lateRequest = requests.last;
        var notifications = 0;
        disposedProvider
          ..addListener(() => notifications++)
          ..dispose();

        // Non-empty, so a landing that reached the provider would also
        // restart time updates on the disposed notifier and throw.
        lateRequest.response.complete(response(<String>['comment-late']));
        await lateRefresh;
        await pumpEventQueue();

        expect(notifications, 0);
        expect(hydrator.commentTreeCalls, hasLength(hydrationCalls));
        expect(disposedProvider.lastRefreshTime, same(landed));
      });

      test('a late next-page response notifies nobody, hydrates nothing, and '
          'leaves lastRefreshTime alone', () async {
        final disposedProvider = buildProvider();
        final firstLoad = disposedProvider.loadComments(refresh: true);
        await pumpEventQueue();
        requests.last.response.complete(
          response(<String>['comment-1'], cursor: 'C1'),
        );
        await firstLoad;
        final landed = disposedProvider.lastRefreshTime;
        final hydrationCalls = hydrator.commentTreeCalls.length;

        final lateNextPage = disposedProvider.loadMoreComments();
        await pumpEventQueue();
        final lateRequest = requests.last;
        expect(lateRequest.cursor, 'C1');
        var notifications = 0;
        disposedProvider
          ..addListener(() => notifications++)
          ..dispose();

        lateRequest.response.complete(response(<String>['comment-late']));
        await lateNextPage;
        await pumpEventQueue();

        expect(notifications, 0);
        expect(hydrator.commentTreeCalls, hasLength(hydrationCalls));
        expect(disposedProvider.lastRefreshTime, same(landed));
      });
    });

    test('time updates start when the first non-empty page lands', () async {
      expect(commentsProvider.currentTimeNotifier.value, isNull);

      final emptyLoad = commentsProvider.loadComments(refresh: true);
      await pumpEventQueue();
      requests.last.response.complete(response(<String>[]));
      await emptyLoad;
      expect(
        commentsProvider.currentTimeNotifier.value,
        isNull,
        reason: 'an empty thread has no timestamps to update',
      );

      final load = commentsProvider.loadComments(refresh: true);
      await pumpEventQueue();
      requests.last.response.complete(response(<String>['comment-1']));
      await load;
      expect(commentsProvider.currentTimeNotifier.value, isNotNull);
    });
  });

  group('time updates', () {
    test('start when a next page brings the first comments after an empty '
        'first page', () async {
      expect(commentsProvider.currentTimeNotifier.value, isNull);

      final emptyLoad = commentsProvider.loadComments(refresh: true);
      await pumpEventQueue();
      requests.single.response.complete(response(<String>[], cursor: 'C1'));
      await emptyLoad;
      expect(displayedUris(), isEmpty);
      expect(commentsProvider.hasMore, isTrue);
      expect(
        commentsProvider.currentTimeNotifier.value,
        isNull,
        reason: 'an empty first page has no timestamps to update',
      );

      final nextPage = commentsProvider.loadMoreComments();
      await pumpEventQueue();
      expect(requests, hasLength(2));
      expect(requests.last.cursor, 'C1');
      requests.last.response.complete(response(<String>['comment-1']));
      await nextPage;

      expect(displayedUris(), <String>['comment-1']);
      expect(
        commentsProvider.currentTimeNotifier.value,
        isNotNull,
        reason:
            'the page that put the first comments on screen must start '
            'the time updates',
      );
    });
  });
}

ThreadViewComment _createThreadComment(String uri) {
  return ThreadViewComment(
    comment: CommentView(
      uri: uri,
      cid: 'cid-$uri',
      record: const CommentRecord(content: 'Test comment content'),
      createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
      indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
      author: AuthorView(
        did: 'did:plc:author',
        handle: 'test.user',
        displayName: 'Test User',
      ),
      post: CommentRef(
        uri: 'at://did:plc:test/social.coves.post.record/123',
        cid: 'post-cid',
      ),
      stats: const CommentStats(score: 10, upvotes: 12, downvotes: 2),
    ),
  );
}
