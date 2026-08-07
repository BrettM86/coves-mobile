// Regression test for the "merge-preserved subtree node clobbers a
// confirmed vote" bug (found in review of the applyServerVoteState
// consolidation).
//
// The subtree merge in loadMoreReplies preserves earlier-hydrated branches
// whose viewer snapshots are old. Vote state must be applied from the nodes
// the response actually delivered, never from the merged tree: once a vote
// has been confirmed through another surface (its score adjustment cleared),
// re-applying a preserved stale snapshot would blind-adopt it and roll the
// confirmed vote back - heart off, score down by one.
//
// Uses a real VoteProvider (the routing under test lives there) with a
// hand-rolled VoteService fake, mirroring the other vote regression files.

import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/comments_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/services/vote_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/test_mocks.dart';

class _FakeVoteService implements VoteService {
  _FakeVoteService({required this.response});

  VoteResponse response;

  @override
  Future<VoteResponse> createVote({
    required String postUri,
    required String postCid,
    String direction = 'up',
  }) async {
    return response;
  }
}

ThreadViewComment buildThreadComment({
  required String uri,
  String? vote,
  String? voteUri,
  List<ThreadViewComment>? replies,
  bool hasMore = false,
}) {
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
      stats: const CommentStats(score: 5, upvotes: 5),
      viewer: CommentViewerState(vote: vote, voteUri: voteUri),
    ),
    replies: replies,
    hasMore: hasMore,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CommentsProvider subtree-merge vote-state regression', () {
    const testPostUri = 'at://did:plc:test/social.coves.post.record/123';
    const testPostCid = 'test-post-cid';
    const parentUri =
        'at://did:plc:author/social.coves.community.comment/parentrkey1';
    const childUri =
        'at://did:plc:author/social.coves.community.comment/childrkey1';
    const voteUri = 'at://did:plc:me/social.coves.feed.vote/v1';

    late MockAuthProvider mockAuthProvider;
    late MockCovesApiService mockApiService;
    late VoteProvider voteProvider;
    late CommentsProvider commentsProvider;

    setUp(() {
      mockAuthProvider = MockAuthProvider();
      mockApiService = MockCovesApiService();

      when(mockAuthProvider.isAuthenticated).thenReturn(true);
      when(
        mockAuthProvider.getAccessToken(),
      ).thenAnswer((_) async => 'test-token');

      voteProvider = VoteProvider(
        voteService: _FakeVoteService(
          response: const VoteResponse(
            uri: voteUri,
            cid: 'bafyvote',
            rkey: 'v1',
            deleted: false,
          ),
        ),
        authProvider: mockAuthProvider,
      );

      commentsProvider = CommentsProvider(
        mockAuthProvider,
        postUri: testPostUri,
        postCid: testPostCid,
        apiService: mockApiService,
        voteProvider: voteProvider,
      );
    });

    tearDown(() {
      commentsProvider.dispose();
      voteProvider.dispose();
    });

    void stubSubtreeResponse(ThreadViewComment node) {
      when(
        mockApiService.getComments(
          postUri: anyNamed('postUri'),
          sort: anyNamed('sort'),
          timeframe: anyNamed('timeframe'),
          depth: anyNamed('depth'),
          limit: anyNamed('limit'),
          parentRkey: argThat(isNotNull, named: 'parentRkey'),
        ),
      ).thenAnswer((_) async => CommentsResponse(post: {}, comments: [node]));
    }

    test('a preserved stale subtree node must not roll back a vote '
        'confirmed through another surface', () async {
      // Initial tree: parent with child, both unvoted.
      when(
        mockApiService.getComments(
          postUri: anyNamed('postUri'),
          sort: anyNamed('sort'),
          timeframe: anyNamed('timeframe'),
          depth: anyNamed('depth'),
          limit: anyNamed('limit'),
          cursor: anyNamed('cursor'),
        ),
      ).thenAnswer(
        (_) async => CommentsResponse(
          post: {},
          comments: [
            buildThreadComment(
              uri: parentUri,
              replies: [buildThreadComment(uri: childUri)],
            ),
          ],
        ),
      );
      await commentsProvider.loadComments(refresh: true);

      // The user likes the child; the appview has not indexed it yet.
      await voteProvider.toggleVote(postUri: childUri, postCid: 'cid-child');
      expect(voteProvider.isLiked(childUri), true);
      expect(voteProvider.getAdjustedScore(childUri, 5), 6);

      // The vote gets CONFIRMED via another surface sharing the global
      // VoteProvider (e.g. the profile comments tab refreshing with a
      // caught-up snapshot): the adjustment clears, server score is truth.
      voteProvider.applyServerVoteState(
        postUri: childUri,
        voteDirection: 'up',
        voteUri: voteUri,
      );
      expect(voteProvider.isLiked(childUri), true);
      expect(voteProvider.getAdjustedScore(childUri, 6), 6);

      // Back in the thread: load-more on the parent hits the response's
      // depth cutoff (parent returns with no replies). The merge preserves
      // the child branch - whose snapshot still says "not voted".
      stubSubtreeResponse(buildThreadComment(uri: parentUri));
      final result = await commentsProvider.loadMoreReplies(parentUri);

      // The branch survives for display...
      expect(
        result!.replies!.map((r) => r.comment.uri),
        contains(childUri),
      );

      // ...and the confirmed vote survives the merge: the stale preserved
      // snapshot must not be blind-adopted. (Bug: heart flipped off and
      // the score dropped by one here.)
      expect(voteProvider.isLiked(childUri), true);
      expect(voteProvider.getAdjustedScore(childUri, 6), 6);
    });

    test('subtree nodes the response delivers still land: a caught-up '
        'snapshot clears the outstanding adjustment', () async {
      when(
        mockApiService.getComments(
          postUri: anyNamed('postUri'),
          sort: anyNamed('sort'),
          timeframe: anyNamed('timeframe'),
          depth: anyNamed('depth'),
          limit: anyNamed('limit'),
          cursor: anyNamed('cursor'),
        ),
      ).thenAnswer(
        (_) async => CommentsResponse(
          post: {},
          comments: [
            buildThreadComment(
              uri: parentUri,
              replies: [buildThreadComment(uri: childUri)],
            ),
          ],
        ),
      );
      await commentsProvider.loadComments(refresh: true);

      await voteProvider.toggleVote(postUri: childUri, postCid: 'cid-child');
      expect(voteProvider.getAdjustedScore(childUri, 5), 6);

      // This response DOES deliver the child, with the vote indexed.
      stubSubtreeResponse(
        buildThreadComment(
          uri: parentUri,
          replies: [
            buildThreadComment(uri: childUri, vote: 'up', voteUri: voteUri),
          ],
        ),
      );
      await commentsProvider.loadMoreReplies(parentUri);

      expect(voteProvider.isLiked(childUri), true);
      // Server score 6 already includes the vote - no double count.
      expect(voteProvider.getAdjustedScore(childUri, 6), 6);
    });
  });
}
