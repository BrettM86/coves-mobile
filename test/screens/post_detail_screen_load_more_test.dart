import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/home/post_detail_screen.dart';
import 'package:coves_flutter/services/comments_provider_cache.dart';
import 'package:coves_flutter/widgets/loading_error_states.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/test_mocks.dart';

// Regression: the post detail scroll trigger called loadMoreComments on
// every scroll notification near the end of the thread, and a failing page
// was retried back to back while the user stayed there during an outage.
// A failed page must now stop the trigger until the footer's Retry.
void main() {
  const postUri = 'at://did:plc:author/social.coves.community.post/post';
  const postCid = 'post-cid';

  late MockAuthProvider auth;
  late MockVoteProvider votes;
  late MockCovesApiService api;
  late BlockProvider blocks;
  late CommentsProviderCache cache;
  late int nextPageCalls;
  late bool failNextPage;

  ThreadViewComment thread(String rkey) {
    return ThreadViewComment(
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
    );
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
    nextPageCalls = 0;
    failNextPage = true;
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
      final cursor = invocation.namedArguments[#cursor] as String?;
      if (cursor == null) {
        return CommentsResponse(
          post: null,
          comments: List.generate(40, (index) => thread('first-$index')),
          cursor: 'cursor-1',
        );
      }
      nextPageCalls++;
      if (failNextPage) {
        throw Exception('Network error');
      }
      return CommentsResponse(post: null, comments: [thread('second-page')]);
    });
  });

  Widget app() => MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider<VoteProvider>.value(value: votes),
      ChangeNotifierProvider<BlockProvider>.value(value: blocks),
      Provider<CommentsProviderCache>.value(value: cache),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: PostDetailScreen(
        post: FeedViewPost(
          post: PostView(
            uri: postUri,
            cid: postCid,
            rkey: 'post',
            author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
            community: CommunityRef(did: 'did:plc:community', name: 'test'),
            createdAt: DateTime(2025),
            indexedAt: DateTime(2025),
            record: const PostRecord(content: 'Load more post'),
            stats: PostStats(
              upvotes: 0,
              downvotes: 0,
              score: 0,
              commentCount: 41,
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

  /// Scroll to the end, past the listener's throttle window in real time
  /// (the throttle reads the wall clock, which fake async does not move).
  Future<void> scrollToEnd(WidgetTester tester, {double offsetBack = 0}) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    final scroll = position(tester);
    scroll.jumpTo(scroll.maxScrollExtent - offsetBack);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('a failed page stops the scroll trigger until the footer Retry', (
    tester,
  ) async {
    try {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(nextPageCalls, 0);

      await scrollToEnd(tester);

      expect(nextPageCalls, 1);
      expect(find.byType(InlineError), findsOneWidget);

      // Further scrolling near the end must not re-request the page.
      await scrollToEnd(tester, offsetBack: 50);
      await scrollToEnd(tester);
      await scrollToEnd(tester, offsetBack: 10);

      expect(nextPageCalls, 1);
      expect(find.byType(InlineError), findsOneWidget);

      failNextPage = false;
      await tester.tap(
        find.descendant(
          of: find.byType(InlineError),
          matching: find.text('Retry'),
        ),
      );
      await tester.pumpAndSettle();

      expect(nextPageCalls, 2);
      expect(find.byType(InlineError), findsNothing);
      final scroll = position(tester);
      scroll.jumpTo(scroll.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text('Comment second-page'), findsOneWidget);
    } finally {
      // Dispose the provider's timer before test invariants run.
      await tester.pumpWidget(const SizedBox.shrink());
      cache.dispose();
      blocks.dispose();
    }
  });
}
