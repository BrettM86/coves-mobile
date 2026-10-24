import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/post_get_result.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/home/focused_thread_screen.dart';
import 'package:coves_flutter/screens/home/post_detail_loader.dart';
import 'package:coves_flutter/screens/home/post_detail_screen.dart';
import 'package:coves_flutter/services/comments_provider_cache.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/post_change_broadcast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_providers.dart' show viewerAuthorityRegistration;
import '../test_helpers/test_mocks.dart';

/// A deep-linked focus comment past the depth cutoff needs a subtree fetch
/// and then pushes a [FocusedThreadScreen]. A route the user pushed over the
/// post while that fetch was pending must stay on top.
void main() {
  const postUri = 'at://did:plc:author/social.coves.community.post/post';
  const postCid = 'post-cid';
  const targetUri = 'at://did:plc:author/social.coves.community.comment/target';

  late MockAuthProvider auth;
  late MockVoteProvider votes;
  late MockCovesApiService api;
  late BlockProvider blocks;
  late CommentsProviderCache cache;
  late GlobalKey<NavigatorState> navigatorKey;
  late ThreadViewComment target;
  late List<ThreadViewComment> threads;
  late Completer<CommentsResponse> subtreeFetch;

  ThreadViewComment thread(String rkey, {List<ThreadViewComment>? replies}) {
    return ThreadViewComment(
      comment: CommentView(
        uri: 'at://did:plc:author/social.coves.community.comment/$rkey',
        cid: 'cid-$rkey',
        record: CommentRecord(content: 'Comment $rkey'),
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

  /// [target] nested past the thread's depth cutoff, so focusing it needs a
  /// subtree fetch and a [FocusedThreadScreen].
  ThreadViewComment targetAtDepth(int depth) {
    var nested = target;
    for (var currentDepth = depth - 1; currentDepth >= 0; currentDepth--) {
      nested = thread('depth-$currentDepth', replies: [nested]);
    }
    return nested;
  }

  final post = PostView(
    uri: postUri,
    cid: postCid,
    rkey: 'post',
    author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
    community: CommunityRef(did: 'did:plc:community', name: 'test'),
    createdAt: DateTime(2025),
    indexedAt: DateTime(2025),
    record: const PostRecord(content: 'Focus post'),
    stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 41),
  );

  setUp(() {
    auth = MockAuthProvider();
    votes = MockVoteProvider();
    api = MockCovesApiService();
    when(api.getViewerAuthority()).thenAnswer((_) async => false);
    when(auth.isAuthenticated).thenReturn(true);
    when(auth.isLoading).thenReturn(false);
    when(auth.did).thenReturn('did:plc:viewer');
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
    navigatorKey = GlobalKey<NavigatorState>();
    target = thread('target');
    threads = [
      targetAtDepth(7),
      ...List.generate(40, (index) => thread('f$index')),
    ];
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
      if (invocation.namedArguments[#parentRkey] != null) {
        return subtreeFetch.future;
      }
      if (invocation.namedArguments[#cursor] != null) {
        return response([]);
      }
      return response(threads);
    });
  });

  /// Frames enough for the post fetch, the thread load, the bounded focus
  /// scan and route transitions, but short of the snackbar timeout.
  Future<void> settle(WidgetTester tester) async {
    for (var frame = 0; frame < 100; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// Mounts a home route and pushes the post route above it, as the
  /// notifications screen's `context.push` does.
  /// The subtree response is held until the test completes it. Created here,
  /// inside the test body, so its completion runs in the test's fake-async
  /// zone that [settle] drives.
  Future<void> openPost(WidgetTester tester) async {
    subtreeFetch = Completer<CommentsResponse>();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<PostChangeBroadcast>.value(value: PostChangeBroadcast()),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<VoteProvider>.value(value: votes),
          ChangeNotifierProvider<BlockProvider>.value(value: blocks),
          Provider<CommentsProviderCache>.value(value: cache),
          Provider<CovesApiService>.value(value: api),
          viewerAuthorityRegistration(auth: auth, apiService: api),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          theme: AppTheme.dark,
          home: const Scaffold(body: Text('Notifications')),
        ),
      ),
    );
    unawaited(
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => PostDetailLoader(
            postUri: postUri,
            fetchPost: (_) async => PostGetSuccess(post),
            focusCommentUri: targetUri,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('the focus comment subtree fetch landing with the post on top '
      'pushes the focused thread', (tester) async {
    try {
      await openPost(tester);

      subtreeFetch.complete(response([target]));
      await settle(tester);

      expect(find.byType(FocusedThreadScreen), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      if (!subtreeFetch.isCompleted) {
        subtreeFetch.complete(response([target]));
      }
      await tester.pump();
      cache.dispose();
      blocks.dispose();
    }
  });

  testWidgets('the focus comment subtree fetch landing under a route pushed '
      'over the post pushes no focused thread', (tester) async {
    try {
      await openPost(tester);
      expect(find.byType(PostDetailScreen), findsOneWidget);
      expect(
        find.byType(FocusedThreadScreen, skipOffstage: false),
        findsNothing,
      );

      unawaited(
        navigatorKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Other page')),
          ),
        ),
      );
      await settle(tester);

      subtreeFetch.complete(response([target]));
      await settle(tester);

      expect(
        find.byType(FocusedThreadScreen, skipOffstage: false),
        findsNothing,
      );
      expect(
        ModalRoute.of(tester.element(find.text('Other page')))!.isCurrent,
        isTrue,
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      if (!subtreeFetch.isCompleted) {
        subtreeFetch.complete(response([target]));
      }
      await tester.pump();
      cache.dispose();
      blocks.dispose();
    }
  });
}
