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

void main() {
  const postUri = 'at://did:plc:author/social.coves.community.post/post';
  const postCid = 'post-cid';
  const targetContent = 'Early profile comment target';
  const savedOffset = 4500.0;
  const failureMessage =
      "Couldn't find that comment. It may have been deleted.";

  late MockAuthProvider auth;
  late MockVoteProvider votes;
  late MockCovesApiService api;
  late BlockProvider blocks;
  late CommentsProviderCache cache;
  late CommentsProvider comments;
  late ThreadViewComment target;
  late List<ThreadViewComment> threads;
  late List<String?> requests;
  Completer<CommentsResponse>? refresh;
  Completer<CommentsResponse>? subtreeFetch;
  var failSubtree = false;

  ThreadViewComment thread(String rkey, {List<ThreadViewComment>? replies}) {
    return ThreadViewComment(
      comment: CommentView(
        uri: 'at://did:plc:author/social.coves.community.comment/$rkey',
        cid: 'cid-$rkey',
        record: CommentRecord(
          content: rkey == 'target' ? targetContent : 'Comment $rkey',
        ),
        createdAt: DateTime(2025),
        indexedAt: DateTime(2025),
        author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
        post: CommentRef(uri: postUri, cid: postCid),
        stats: CommentStats(replyCount: replies?.length ?? 0),
      ),
      replies: replies,
    );
  }

  CommentsResponse response(List<ThreadViewComment> items) =>
      CommentsResponse(post: null, comments: items);

  ThreadViewComment targetAtDepth(int depth) {
    var nested = target;
    for (var currentDepth = depth - 1; currentDepth >= 0; currentDepth--) {
      nested = thread('depth-$currentDepth', replies: [nested]);
    }
    return nested;
  }

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
    refresh = null;
    subtreeFetch = null;
    failSubtree = false;
    target = thread('target');
    threads = [
      target,
      ...List.generate(80, (index) => thread('filler-$index')),
    ];
    when(api.getComments(
      postUri: anyNamed('postUri'),
      sort: anyNamed('sort'),
      timeframe: anyNamed('timeframe'),
      depth: anyNamed('depth'),
      limit: anyNamed('limit'),
      cursor: anyNamed('cursor'),
      parentRkey: anyNamed('parentRkey'),
    )).thenAnswer((invocation) async {
      final parent = invocation.namedArguments[#parentRkey] as String?;
      requests.add(parent);
      if (parent != null) {
        if (failSubtree) {
          throw Exception('Subtree fetch failed');
        }
        return subtreeFetch == null
            ? response([target])
            : await subtreeFetch!.future;
      }
      return refresh == null ? response(threads) : await refresh!.future;
    });
  });

  Widget app({String? focusCommentUri}) => MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<VoteProvider>.value(value: votes),
          ChangeNotifierProvider<BlockProvider>.value(value: blocks),
          Provider<CommentsProviderCache>.value(value: cache),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: PostDetailScreen(
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
                community: CommunityRef(did: 'did:plc:community', name: 'test'),
                createdAt: DateTime(2025),
                indexedAt: DateTime(2025),
                record: const PostRecord(content: 'Profile navigation post'),
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
      .state<ScrollableState>(find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      ).first)
      .position;

  void testCachedVisit(
    String description,
    Future<void> Function(WidgetTester) body,
  ) {
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        // Dispose the provider's timer before test invariants run,
        // and unmount both routes before disposing their shared cache.
        await tester.pumpWidget(const SizedBox.shrink());
        if (refresh != null && !refresh!.isCompleted) {
          refresh!.complete(response(threads));
          await tester.pump();
        }
        if (subtreeFetch != null && !subtreeFetch!.isCompleted) {
          subtreeFetch!.complete(response([target]));
          await tester.pump();
        }
        cache.dispose();
        blocks.dispose();
      }
    });
  }

  Future<void> cacheScrolledVisit(
    WidgetTester tester, {
    bool collapsed = false,
  }) async {
    if (collapsed) {
      threads[0] = thread('ancestor', replies: [target]);
    }
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    comments = cache.peekProvider(postUri)!;
    expect(requests, [null]);
    if (collapsed) {
      comments.toggleCollapsed(threads.first.comment.uri);
      await tester.pumpAndSettle();
    }
    position(tester).jumpTo(savedOffset);
    await tester.pumpAndSettle();
    expect(position(tester).pixels, closeTo(savedOffset, 1));
    // The early target is outside both the viewport and lazy sliver cache.
    expect(find.text(targetContent), findsNothing);
    expect(comments.scrollPosition, closeTo(savedOffset, 1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(comments.isStale, isFalse);
    requests.clear();
  }

  Future<void> reopenFocused(WidgetTester tester) async {
    refresh = Completer<CommentsResponse>();
    await tester.pumpWidget(app(focusCommentUri: target.comment.uri));
    expect(identical(cache.peekProvider(postUri), comments), isTrue);
    expect(requests, [null], reason: 'A fresh cache must still force refresh');
    expect(comments.isLoading, isTrue);
    refresh!.complete(response(threads));
    // Allow the bounded lazy-sliver scan and route/scroll animations to finish.
    // Keep elapsed time below the failure snackbar dismissal duration.
    for (var frame = 0; frame < 100; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(comments.isLoading, isFalse);
  }

  testCachedVisit('no-focus revisit preserves the cached scroll position',
      (tester) async {
    await cacheScrolledVisit(tester);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(identical(cache.peekProvider(postUri), comments), isTrue);
    expect(position(tester).pixels, closeTo(savedOffset, 1));
    expect(find.text(targetContent), findsNothing);
    expect(requests, isEmpty);
  });

  testCachedVisit('focused revisit reveals an early target above cached scroll',
      (tester) async {
    await cacheScrolledVisit(tester);
    await reopenFocused(tester);

    expect(find.byType(FocusedThreadScreen), findsNothing);
    expect(
      requests,
      [null],
      reason: 'An ordinary in-tree target needs no subtree',
    );
    final targetFinder = find.text(targetContent);
    expect(targetFinder, findsOneWidget);
    final targetRect = tester.getRect(targetFinder);
    final viewport = tester.getRect(find.byType(CustomScrollView));
    final actionBar = tester.getRect(find.byType(PostActionBar));
    expect(targetRect.top, greaterThanOrEqualTo(viewport.top + kToolbarHeight));
    expect(targetRect.bottom, lessThanOrEqualTo(actionBar.top));
    expect(targetFinder.hitTestable(), findsOneWidget);
  });

  testCachedVisit('collapsed in-tree target opens the fetched focused subtree',
      (tester) async {
    await cacheScrolledVisit(tester, collapsed: true);
    await reopenFocused(tester);

    expect(comments.isCollapsed(threads.first.comment.uri), isTrue);
    expect(find.byType(FocusedThreadScreen), findsOneWidget);
    expect(requests.whereType<String>(), contains('target'));
    expect(find.text(targetContent).hitTestable(), findsOneWidget);
  });

  testCachedVisit('collapsed target bypasses the underlying scroll scan',
      (tester) async {
    await cacheScrolledVisit(tester, collapsed: true);
    subtreeFetch = Completer<CommentsResponse>();
    await reopenFocused(tester);

    expect(requests.whereType<String>(), contains('target'));
    expect(position(tester).pixels, 0);

    subtreeFetch!.complete(response([target]));
    await tester.pumpAndSettle();
    expect(find.byType(FocusedThreadScreen), findsOneWidget);

    Navigator.of(tester.element(find.byType(FocusedThreadScreen))).pop();
    await tester.pumpAndSettle();
    expect(position(tester).pixels, 0);
  });

  testCachedVisit('target beyond max depth opens the fetched focused subtree',
      (tester) async {
    threads = [
      targetAtDepth(7),
      ...List.generate(80, (index) => thread('filler-$index')),
    ];
    await cacheScrolledVisit(tester);
    subtreeFetch = Completer<CommentsResponse>();
    await reopenFocused(tester);

    expect(requests.whereType<String>(), contains('target'));
    expect(position(tester).pixels, 0);

    subtreeFetch!.complete(response([target]));
    await tester.pumpAndSettle();
    expect(find.byType(FocusedThreadScreen), findsOneWidget);
    expect(find.text(targetContent).hitTestable(), findsOneWidget);

    Navigator.of(tester.element(find.byType(FocusedThreadScreen))).pop();
    await tester.pumpAndSettle();
    expect(position(tester).pixels, 0);
  });

  testCachedVisit('collapsed target fetch failure shows the existing snackbar',
      (tester) async {
    await cacheScrolledVisit(tester, collapsed: true);
    failSubtree = true;
    await reopenFocused(tester);

    expect(find.byType(FocusedThreadScreen), findsNothing);
    expect(find.text(failureMessage), findsOneWidget);
    expect(requests.whereType<String>(), contains('target'));
  });
}
