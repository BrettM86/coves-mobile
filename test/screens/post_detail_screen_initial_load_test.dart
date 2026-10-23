import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/home/post_detail_screen.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/comments_provider_cache.dart';
import 'package:coves_flutter/services/post_change_broadcast.dart';
import 'package:coves_flutter/widgets/loading_error_states.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/test_mocks.dart';

// Regression: while the first comments request was pending, or after it
// failed with no comments loaded, the post detail screen replaced the whole
// page (post, app bar and back button) with a full-screen loader or error,
// although the post itself was already in hand. The post and the way back
// must stay visible, and a first-load failure belongs in the comments area.
void main() {
  const postUri = 'at://did:plc:author/social.coves.community.post/post';
  const postCid = 'post-cid';
  const postTitle = 'Initial load post title';
  const postBody = 'Initial load post body';

  late MockAuthProvider auth;
  late MockVoteProvider votes;
  late MockCovesApiService api;
  late BlockProvider blocks;
  late CommentsProviderCache cache;
  late List<Completer<CommentsResponse>> requests;

  CommentsResponse onePage(String rkey) => CommentsResponse(
    post: null,
    comments: [
      ThreadViewComment(
        comment: CommentView(
          uri: 'at://did:plc:author/social.coves.community.comment/$rkey',
          cid: 'cid-$rkey',
          record: CommentRecord(content: 'Comment $rkey'),
          createdAt: DateTime(2025),
          indexedAt: DateTime(2025),
          author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
          post: CommentRef(uri: postUri, cid: postCid),
          stats: const CommentStats(),
        ),
      ),
    ],
  );

  setUp(() {
    auth = MockAuthProvider();
    votes = MockVoteProvider();
    api = MockCovesApiService();
    when(auth.isAuthenticated).thenReturn(false);
    when(auth.did).thenReturn(null);
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
    ).thenAnswer((_) {
      final request = Completer<CommentsResponse>();
      requests.add(request);
      return request.future;
    });
  });

  /// The screen on a route pushed over a home route, as when a post is
  /// opened from the feed, so the app bar shows a back button.
  Widget app({int commentCount = 1}) => MultiProvider(
    providers: [
      Provider<PostChangeBroadcast>.value(value: PostChangeBroadcast()),
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider<VoteProvider>.value(value: votes),
      ChangeNotifierProvider<BlockProvider>.value(value: blocks),
      Provider<CommentsProviderCache>.value(value: cache),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PostDetailScreen(
                    sessionStamp: null,
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
                          title: postTitle,
                          content: postBody,
                        ),
                        stats: PostStats(
                          upvotes: 0,
                          downvotes: 0,
                          score: 0,
                          commentCount: commentCount,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              child: const Text('Open post'),
            ),
          ),
        ),
      ),
    ),
  );

  /// Opens the post and lets the push transition finish while the first
  /// comments request stays pending.
  Future<void> openPost(WidgetTester tester, {int commentCount = 1}) async {
    await tester.pumpWidget(app(commentCount: commentCount));
    await tester.tap(find.text('Open post'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(requests, hasLength(1));
  }

  void testScreen(
    String description,
    Future<void> Function(WidgetTester) body,
  ) {
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        for (final request in requests) {
          if (!request.isCompleted) {
            request.complete(CommentsResponse(post: null, comments: []));
          }
        }
        await tester.pump();
        cache.dispose();
        blocks.dispose();
      }
    });
  }

  testScreen('while the first comments request is pending, the post and the '
      'back button are visible', (tester) async {
    await openPost(tester);

    expect(find.text(postTitle), findsOneWidget);
    expect(find.text(postBody, findRichText: true), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.byType(FullScreenLoading), findsNothing);
    final spinner = find.byType(InlineLoading);
    expect(spinner, findsOneWidget);
    expect(
      tester.getTopLeft(spinner).dy,
      greaterThan(tester.getBottomLeft(find.text(postTitle)).dy),
      reason: 'the first-load spinner belongs in the comments area',
    );
  });

  testScreen('while the first comments request is pending on a post with a '
      'zero comment count, the header does not claim the thread is empty', (
    tester,
  ) async {
    await openPost(tester, commentCount: 0);

    expect(find.byType(InlineLoading), findsOneWidget);
    expect(find.text('No comments yet'), findsNothing);
    expect(find.text('Be the first to comment'), findsNothing);
  });

  testScreen('after a failed first comments request on a post with a zero '
      'comment count, the header does not claim the thread is empty', (
    tester,
  ) async {
    await openPost(tester, commentCount: 0);

    requests.single.completeError(ApiException('First load failed'));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('No comments yet'), findsNothing);
    expect(find.text('Be the first to comment'), findsNothing);
  });

  testScreen('a first load that resolves empty on a post with a zero comment '
      'count shows the empty state', (tester) async {
    await openPost(tester, commentCount: 0);

    requests.single.complete(CommentsResponse(post: null, comments: []));
    await tester.pumpAndSettle();

    expect(find.text('No comments yet'), findsOneWidget);
  });

  testScreen('a failed first comments request keeps the post and shows an '
      'inline Retry below it that reloads the comments', (tester) async {
    await openPost(tester);

    requests.single.completeError(ApiException('First load failed'));
    await tester.pumpAndSettle();

    expect(find.text(postTitle), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    final retry = find.text('Retry');
    expect(retry, findsOneWidget);
    expect(
      tester.getTopLeft(retry).dy,
      greaterThan(tester.getBottomLeft(find.text(postTitle)).dy),
      reason: 'the error belongs in the comments area, below the post',
    );

    await tester.tap(retry);
    await tester.pump();
    expect(requests, hasLength(2), reason: 'Retry must reload the comments');
    requests[1].complete(onePage('after-retry'));
    await tester.pumpAndSettle();

    expect(find.text('Comment after-retry'), findsOneWidget);
    expect(find.text(postTitle), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });
}
