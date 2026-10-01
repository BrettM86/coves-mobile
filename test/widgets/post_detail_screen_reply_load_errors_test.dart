import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/comments_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/home/focused_thread_screen.dart';
import 'package:coves_flutter/screens/home/post_detail_screen.dart';
import 'package:coves_flutter/services/comments_provider_cache.dart';
import 'package:coves_flutter/widgets/post_action_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/test_mocks.dart';

// Reply-load failures on the post detail screen:
// - a "Load more replies" tap whose fetch fails in any way (including a
//   malformed comment URI the provider rejects with
//   MalformedCommentUriException) shows the failure snackbar instead of
//   escaping as an uncaught error, while a programming error (an Error such
//   as RangeError) still escapes so it reaches Sentry;
// - a focus subtree fetch discarded because a whole-tree refresh landed
//   mid-flight is not "deleted": the focus is retried against the
//   refreshed tree.
void main() {
  const postUri = 'at://did:plc:author/social.coves.community.post/post';
  const postCid = 'post-cid';
  const targetContent = 'Deep-linked target comment';
  const focusFailureMessage =
      "Couldn't find that comment. It may have been deleted.";
  const replyLoadFailureMessage = 'Failed to load replies. Please try again.';

  late MockAuthProvider auth;
  late MockVoteProvider votes;
  late MockCovesApiService api;
  late BlockProvider blocks;
  late CommentsProviderCache cache;
  late ThreadViewComment target;
  late List<ThreadViewComment> fillers;
  // parentRkey of every getComments call, in order (null = whole tree).
  late List<String?> requests;
  // Whole-tree responses consumed in order; when empty, [fillers] is served.
  late List<Completer<CommentsResponse>> treePages;
  // Subtree responses consumed in order; when empty, [target] is served.
  late List<Completer<CommentsResponse>> subtreePages;

  ThreadViewComment thread(String rkey, {String? uri, bool hasMore = false}) {
    return ThreadViewComment(
      comment: CommentView(
        uri: uri ?? 'at://did:plc:author/social.coves.community.comment/$rkey',
        cid: 'cid-$rkey',
        record: CommentRecord(
          content: rkey == 'target' ? targetContent : 'Comment $rkey',
        ),
        createdAt: DateTime(2025),
        indexedAt: DateTime(2025),
        author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
        post: CommentRef(uri: postUri, cid: postCid),
        stats: CommentStats(replyCount: hasMore ? 3 : 0),
      ),
      hasMore: hasMore,
    );
  }

  CommentsResponse response(List<ThreadViewComment> items) =>
      CommentsResponse(post: null, comments: items);

  Completer<CommentsResponse> completed(List<ThreadViewComment> items) =>
      Completer<CommentsResponse>()..complete(response(items));

  setUp(() {
    auth = MockAuthProvider();
    votes = MockVoteProvider();
    api = MockCovesApiService();
    when(auth.isAuthenticated).thenReturn(false);
    when(votes.isLiked(any)).thenReturn(false);
    when(votes.getVoteState(any)).thenReturn(null);
    when(votes.isPending(any)).thenReturn(false);
    when(votes.getAdjustedScore(any, any))
        .thenAnswer((invocation) => invocation.positionalArguments[1] as int);
    blocks = BlockProvider(apiService: api, authProvider: auth);
    cache = CommentsProviderCache(
      authProvider: auth,
      voteProvider: votes,
      commentService: MockCommentService(),
      apiService: api,
    );
    requests = [];
    treePages = [];
    subtreePages = [];
    target = thread('target');
    fillers = List.generate(80, (index) => thread('filler-$index'));
    when(
      api.getComments(
        postUri: anyNamed('postUri'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        depth: anyNamed('depth'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
        parentRkey: anyNamed('parentRkey'),
      ),
    ).thenAnswer((invocation) async {
      final parent = invocation.namedArguments[#parentRkey] as String?;
      requests.add(parent);
      if (parent != null) {
        return subtreePages.isEmpty
            ? response([target])
            : subtreePages.removeAt(0).future;
      }
      return treePages.isEmpty
          ? response(fillers)
          : treePages.removeAt(0).future;
    });
  });

  /// [screenMounted] false swaps the post screen for a placeholder under the
  /// same MaterialApp, so the screen is disposed while the app's root
  /// ScaffoldMessenger (the one the screen captured) stays on screen.
  Widget app({String? focusCommentUri, bool screenMounted = true}) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<VoteProvider>.value(value: votes),
          ChangeNotifierProvider<BlockProvider>.value(value: blocks),
          Provider<CommentsProviderCache>.value(value: cache),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: !screenMounted
              ? const Scaffold(body: Text('Left the post'))
              : PostDetailScreen(
                  focusCommentUri: focusCommentUri,
                  post: FeedViewPost(
                    post: PostView(
                      uri: postUri,
                      cid: postCid,
                      rkey: 'post',
                      author: AuthorView(
                        did: 'did:plc:author',
                        handle: 'author.test',
                      ),
                      community: CommunityRef(
                        did: 'did:plc:community',
                        name: 'test',
                      ),
                      createdAt: DateTime(2025),
                      indexedAt: DateTime(2025),
                      record: const PostRecord(
                        content: 'Reply load errors post',
                      ),
                      stats: PostStats(
                        upvotes: 0,
                        downvotes: 0,
                        score: 0,
                        commentCount: 81,
                      ),
                    ),
                  ),
                ),
        ),
      );

  ScrollPosition position(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;

  /// Pump frames for the focus scan and scroll animations, staying well
  /// below the snackbar's display duration so a shown snackbar is still
  /// on screen when the test looks for it.
  Future<void> pumpFrames(WidgetTester tester, {int frames = 100}) async {
    for (var frame = 0; frame < frames; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  void testScreen(
    String description,
    Future<void> Function(WidgetTester) body,
  ) {
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        // Dispose the provider's timer before test invariants run, and
        // unmount every route before disposing the shared cache.
        await tester.pumpWidget(const SizedBox.shrink());
        for (final pending in [...treePages, ...subtreePages]) {
          if (!pending.isCompleted) {
            pending.complete(response([]));
          }
        }
        await tester.pump();
        cache.dispose();
        blocks.dispose();
      }
    });
  }

  testScreen('load more replies on a malformed comment URI shows the failure '
      'snackbar without an uncaught error', (tester) async {
    const malformedUri = 'at://did:plc:author/social.coves.community.comment/';
    treePages.add(
      completed([
        thread('malformed', uri: malformedUri, hasMore: true),
        ...fillers.take(3),
      ]),
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(requests, [null]);

    final loadMore = find.text('Load more replies');
    expect(loadMore, findsOneWidget);
    await tester.tap(loadMore);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    expect(tester.takeException(), isNull);
    expect(find.text(replyLoadFailureMessage), findsOneWidget);
    expect(
      requests.whereType<String>(),
      isEmpty,
      reason: 'a URI without an rkey must never reach the API',
    );
  });

  testScreen('a programming error inside load more replies escapes instead '
      'of showing the failure snackbar', (tester) async {
    treePages.add(completed([thread('ranged', hasMore: true)]));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // The subtree future and the tap run in a guarded zone, so an error
    // escaping the tap handler lands in [uncaught] instead of failing the
    // test outright. The future is completed after the tap, once the screen
    // awaits it, so the error is never an unlistened future.
    late Completer<CommentsResponse> failingSubtree;
    final uncaught = <Object>[];
    await runZonedGuarded(() {
      failingSubtree = Completer<CommentsResponse>();
      subtreePages.add(failingSubtree);
      return tester.tap(find.text('Load more replies'));
    }, (error, stack) => uncaught.add(error));
    await tester.pump();
    expect(requests, [null, 'ranged']);
    failingSubtree.completeError(RangeError('index bug'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    expect(uncaught, [isA<RangeError>()]);
    expect(tester.takeException(), isNull);
    expect(find.text(replyLoadFailureMessage), findsNothing);
  });

  testScreen(
    'focusing a malformed comment URI missing from the tree reports it '
    'not found without an uncaught error',
    (tester) async {
      const malformedUri =
          'at://did:plc:author/social.coves.community.comment/';
      await tester.pumpWidget(app(focusCommentUri: malformedUri));
      await pumpFrames(tester, frames: 30);

      expect(tester.takeException(), isNull);
      expect(find.text(focusFailureMessage), findsOneWidget);
      expect(requests, [
        null,
      ], reason: 'a URI without an rkey must never reach the API');
      expect(find.byType(FocusedThreadScreen), findsNothing);
    },
  );

  testScreen(
    'an empty subtree for a focus target missing from the tree reports it '
    'not found once, with no automatic retry',
    (tester) async {
      subtreePages.add(completed([]));
      await tester.pumpWidget(app(focusCommentUri: target.comment.uri));
      await pumpFrames(tester, frames: 30);

      expect(find.text(focusFailureMessage), findsOneWidget);
      expect(requests.whereType<String>(), ['target']);

      // Enough frames for any post-frame or provider-driven retry to run.
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(find.text(focusFailureMessage), findsOneWidget);
      expect(requests.whereType<String>(), [
        'target',
      ], reason: 'a genuine not-found must not be retried automatically');
      expect(find.byType(FocusedThreadScreen), findsNothing);
    },
  );

  group('focus subtree fetch discarded by a mid-flight tree refresh', () {
    late CommentsProvider comments;
    late Completer<CommentsResponse> heldSubtree;
    late Completer<CommentsResponse> midFlightRefresh;

    /// Open the screen focused on a target missing from the loaded tree,
    /// hold its subtree fetch, and land a whole-tree refresh that answers
    /// with [refreshedThreads] while the fetch is still held. Any later
    /// subtree fetches are answered from [laterSubtrees], in order.
    /// [beforeStaleCompletion] runs after the refresh lands and before the
    /// held subtree fetch completes.
    Future<void> holdSubtreeAndRefresh(
      WidgetTester tester,
      List<ThreadViewComment> refreshedThreads, {
      List<Completer<CommentsResponse>> laterSubtrees = const [],
      Future<void> Function()? beforeStaleCompletion,
    }) async {
      treePages.add(completed(fillers));
      heldSubtree = Completer<CommentsResponse>();
      subtreePages
        ..add(heldSubtree)
        ..addAll(laterSubtrees);

      await tester.pumpWidget(app(focusCommentUri: target.comment.uri));
      await pumpFrames(tester, frames: 10);
      comments = cache.peekProvider(postUri)!;
      expect(
        requests,
        [null, 'target'],
        reason:
            'the target is not in the loaded tree, so its subtree is '
            'fetched',
      );
      expect(heldSubtree.isCompleted, isFalse);

      midFlightRefresh = Completer<CommentsResponse>();
      treePages.add(midFlightRefresh);
      unawaited(comments.loadComments(refresh: true));
      await tester.pump();
      expect(requests, [null, 'target', null]);

      midFlightRefresh.complete(response(refreshedThreads));
      await pumpFrames(tester, frames: 10);
      expect(comments.comments.length, refreshedThreads.length);
      await beforeStaleCompletion?.call();

      // The provider discards this response as stale: the tree generation
      // changed while it was in flight.
      heldSubtree.complete(response([target]));
      await pumpFrames(tester);
    }

    testScreen('a refreshed tree holding the target scrolls to it instead of '
        'reporting it deleted', (tester) async {
      await holdSubtreeAndRefresh(tester, [
        ...fillers.take(40),
        target,
        ...fillers.skip(40),
      ]);

      expect(find.text(focusFailureMessage), findsNothing);
      expect(find.byType(FocusedThreadScreen), findsNothing);
      expect(requests.whereType<String>(), [
        'target',
      ], reason: 'the refreshed tree holds the target; no second subtree');
      // The target sits 40 comments down, so only a focus scroll shows it.
      expect(position(tester).pixels, greaterThan(0));
      final targetFinder = find.text(targetContent);
      expect(targetFinder.hitTestable(), findsOneWidget);
      final targetRect = tester.getRect(targetFinder);
      final viewport = tester.getRect(find.byType(CustomScrollView));
      final actionBar = tester.getRect(find.byType(PostActionBar));
      expect(
        targetRect.top,
        greaterThanOrEqualTo(viewport.top + kToolbarHeight),
      );
      expect(targetRect.bottom, lessThanOrEqualTo(actionBar.top));
    });

    testScreen(
      'a refreshed tree still missing the target refetches its subtree '
      'and opens the focused thread',
      (tester) async {
        final retriedSubtree = Completer<CommentsResponse>();
        await holdSubtreeAndRefresh(
          tester,
          [...fillers, thread('posted-since-first-load')],
          laterSubtrees: [retriedSubtree],
        );

        expect(find.text(focusFailureMessage), findsNothing);
        expect(
          requests.whereType<String>(),
          ['target', 'target'],
          reason:
              'the stale discard must retry the focus against the '
              'refreshed tree, which still lacks the target',
        );
        expect(find.byType(FocusedThreadScreen), findsNothing);

        retriedSubtree.complete(response([target]));
        await tester.pumpAndSettle();

        expect(find.byType(FocusedThreadScreen), findsOneWidget);
        expect(find.text(targetContent).hitTestable(), findsOneWidget);
        expect(find.text(focusFailureMessage), findsNothing);
      },
    );

    testScreen(
      'leaving the post before the stale subtree completes neither retries '
      'nor reports the focus',
      (tester) async {
        await holdSubtreeAndRefresh(
          tester,
          [...fillers, thread('posted-since-first-load')],
          beforeStaleCompletion: () async {
            await tester.pumpWidget(
              app(focusCommentUri: target.comment.uri, screenMounted: false),
            );
            await tester.pump();
            expect(find.byType(PostDetailScreen), findsNothing);
            expect(find.text('Left the post'), findsOneWidget);
          },
        );

        expect(tester.takeException(), isNull);
        expect(requests.whereType<String>(), [
          'target',
        ], reason: 'a disposed screen must not retry the focus');
        expect(find.text(focusFailureMessage), findsNothing);
        expect(find.byType(FocusedThreadScreen), findsNothing);
        expect(find.text('Left the post'), findsOneWidget);
      },
    );
  });
}
