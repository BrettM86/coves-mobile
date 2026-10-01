import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/comments_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/home/focused_thread_screen.dart';
import 'package:coves_flutter/widgets/loading_error_states.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/test_mocks.dart';

// Reply-load failures on the focused thread screen: a malformed comment URI
// (no rkey) makes CommentsProvider.loadMoreReplies throw
// MalformedCommentUriException. The screen must turn that into its normal
// failure UI instead of letting it escape as an uncaught async error:
// - a "Load more replies" tap shows the failure snackbar;
// - the entry hydration of the anchor subtree shows the retryable error
//   state rather than claiming the anchor has no replies.
void main() {
  const postUri = 'at://did:plc:author/social.coves.community.post/post';
  const postCid = 'post-cid';
  const malformedUri = 'at://did:plc:author/social.coves.community.comment/';
  const replyLoadFailureMessage = 'Failed to load replies. Please try again.';

  late MockAuthProvider auth;
  late MockVoteProvider votes;
  late MockCovesApiService api;
  late BlockProvider blocks;
  late CommentsProvider commentsProvider;
  // parentRkey of every getComments call, in order (null = whole tree).
  late List<String?> requests;

  ThreadViewComment thread(
    String rkey, {
    String? uri,
    String? content,
    bool hasMore = false,
    List<ThreadViewComment>? replies,
  }) {
    return ThreadViewComment(
      comment: CommentView(
        uri: uri ?? 'at://did:plc:author/social.coves.community.comment/$rkey',
        cid: 'cid-$rkey',
        record: CommentRecord(content: content ?? 'Comment $rkey'),
        createdAt: DateTime(2025),
        indexedAt: DateTime(2025),
        author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
        post: CommentRef(uri: postUri, cid: postCid),
        stats: CommentStats(replyCount: hasMore ? 3 : 0),
      ),
      replies: replies,
      hasMore: hasMore,
    );
  }

  CommentsResponse response(List<ThreadViewComment> items) =>
      CommentsResponse(post: null, comments: items);

  /// Serves every getComments call from [responder], recording the
  /// parentRkey of each request.
  void stubGetComments(
    CommentsResponse Function(String? parentRkey) responder,
  ) {
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
      return responder(parent);
    });
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
    commentsProvider = CommentsProvider(
      auth,
      postUri: postUri,
      postCid: postCid,
      apiService: api,
      voteProvider: votes,
      commentService: MockCommentService(),
    );
    requests = [];
  });

  tearDown(() {
    commentsProvider.dispose();
    blocks.dispose();
  });

  Widget app(ThreadViewComment anchor) => MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider<VoteProvider>.value(value: votes),
      ChangeNotifierProvider<BlockProvider>.value(value: blocks),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: FocusedThreadScreen(
        thread: anchor,
        ancestors: const [],
        onReply: (content, facets, parent) async {},
        commentsProvider: commentsProvider,
      ),
    ),
  );

  testWidgets('load more replies on a nested reply with a malformed URI shows '
      'the failure snackbar without an uncaught error', (tester) async {
    // Entry hydration of the valid anchor succeeds and delivers a nested
    // reply whose URI has no rkey but advertises more replies.
    stubGetComments((parentRkey) {
      expect(parentRkey, 'anchor', reason: 'only the anchor is hydrated');
      return response([
        thread(
          'anchor',
          content: 'Anchor comment',
          replies: [
            thread(
              'malformed',
              uri: malformedUri,
              content: 'Reply with a malformed URI',
              hasMore: true,
            ),
          ],
        ),
      ]);
    });

    await tester.pumpWidget(app(thread('anchor', content: 'Anchor comment')));
    await tester.pumpAndSettle();
    expect(requests, ['anchor']);
    expect(find.text('Reply with a malformed URI'), findsOneWidget);

    final loadMore = find.text('Load more replies');
    expect(loadMore, findsOneWidget);
    await tester.tap(loadMore);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    expect(tester.takeException(), isNull);
    expect(find.text(replyLoadFailureMessage), findsOneWidget);
    expect(requests, [
      'anchor',
    ], reason: 'a URI without an rkey must never reach the API');
    expect(requests, isNot(contains('')));
  });

  testWidgets('entry hydration of an anchor with a malformed URI shows the '
      'retryable error state without an uncaught error', (tester) async {
    stubGetComments((parentRkey) => response([]));

    await tester.pumpWidget(
      app(thread('anchor', uri: malformedUri, content: 'Malformed anchor')),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Malformed anchor'), findsOneWidget);
    expect(find.byType(InlineError), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('No replies yet'), findsNothing);
    expect(
      requests,
      isEmpty,
      reason: 'a URI without an rkey must never reach the API',
    );
  });
}
