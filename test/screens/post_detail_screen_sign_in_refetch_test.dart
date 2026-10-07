import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/home/post_detail_screen.dart';
import 'package:coves_flutter/services/comments_provider_cache.dart';
import 'package:coves_flutter/services/viewer_state_hydrator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/test_mocks.dart';

// Regression: a comment thread loaded while signed out stayed in the
// CommentsProviderCache across sign-in. Reopening the post inside the
// staleness window reused that anonymous thread, which carries no viewer
// vote state, instead of fetching it again with the signed-in session.
void main() {
  const postUri = 'at://did:plc:author/social.coves.community.post/post';
  const postCid = 'post-cid';
  const commentUri = 'at://did:plc:author/social.coves.community.comment/c1';
  const signedInDid = 'did:plc:alice';
  const voteUri = 'at://did:plc:alice/social.coves.feed.vote/vote1';

  ThreadViewComment thread({CommentViewerState? viewer}) {
    return ThreadViewComment(
      comment: CommentView(
        uri: commentUri,
        cid: 'cid-c1',
        record: const CommentRecord(content: 'First comment'),
        createdAt: DateTime(2025),
        indexedAt: DateTime(2025),
        author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
        post: CommentRef(uri: postUri, cid: postCid),
        stats: const CommentStats(upvotes: 1, score: 1),
        viewer: viewer,
      ),
    );
  }

  FeedViewPost post() {
    return FeedViewPost(
      post: PostView(
        uri: postUri,
        cid: postCid,
        rkey: 'post',
        author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
        community: CommunityRef(did: 'did:plc:community', name: 'test'),
        createdAt: DateTime(2025),
        indexedAt: DateTime(2025),
        record: const PostRecord(content: 'Sign-in refetch post'),
        stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 1),
      ),
    );
  }

  testWidgets(
    'reopening a post after sign-in refetches the thread cached while '
    'signed out, carrying the viewer vote state',
    (tester) async {
      final auth = FakeAuthProvider();
      final votes = FakeVoteProvider(auth);
      final api = MockCovesApiService();
      final blocks = BlockProvider(apiService: api, authProvider: auth);
      // One cache for both visits, as the app holds one for its lifetime.
      final cache = CommentsProviderCache(
        authProvider: auth,
        voteProvider: votes,
        commentService: MockCommentService(),
        apiService: api,
        hydrator: ViewerStateHydrator(authProvider: auth, voteProvider: votes),
      );

      final commentRequests = <String>[];
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
        commentRequests.add(invocation.namedArguments[#postUri] as String);
        // The first request is anonymous, so the thread carries no viewer
        // state. Any later request is the signed-in one: the viewer has
        // upvoted the comment.
        final isFirstRequest = commentRequests.length == 1;
        return CommentsResponse(
          post: null,
          comments: [
            thread(
              viewer: isFirstRequest
                  ? null
                  : CommentViewerState(vote: 'up', voteUri: voteUri),
            ),
          ],
        );
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
          home: PostDetailScreen(post: post()),
        ),
      );

      try {
        // First visit, signed out.
        expect(auth.did, isNull);
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();

        expect(commentRequests, [postUri]);
        expect(find.text('First comment'), findsOneWidget);
        final anonymousProvider = cache.peekProvider(postUri);
        expect(anonymousProvider, isNotNull);
        expect(anonymousProvider!.comments, isNotEmpty);
        expect(
          anonymousProvider.isStale,
          isFalse,
          reason:
              'the second visit must fall inside the staleness window, '
              'where the screen would otherwise reuse the cached thread',
        );
        expect(votes.isLiked(commentUri), isFalse);

        // Leave the post, then sign in.
        await tester.pumpWidget(const SizedBox.shrink());
        auth.setSignedInDid(signedInDid);
        await tester.pump();

        // Second visit, signed in.
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();

        expect(
          commentRequests,
          [postUri, postUri],
          reason:
              'reopening the post after sign-in must fetch the thread '
              'again with the signed-in session instead of reusing the '
              'thread cached while signed out',
        );
        expect(find.text('First comment'), findsOneWidget);
        expect(votes.isLiked(commentUri), isTrue);
        expect(votes.getVoteState(commentUri)?.uri, voteUri);
      } finally {
        // Unmount before disposing, so the provider's timer is cancelled and
        // no screen still holds a disposed provider.
        await tester.pumpWidget(const SizedBox.shrink());
        cache.dispose();
        blocks.dispose();
        votes.dispose();
      }
    },
  );
}
