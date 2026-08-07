// Regression test for the "heart flips off on profile refresh" bug.
//
// Scenario (h) of the vote-state spec: a comment is voted on optimistically,
// then the profile's comment list is refreshed inside the appview's indexing
// window so the snapshot still carries `viewer.vote == null`. The refresh
// path used to blind-adopt that snapshot, clobbering the optimistic vote.
//
// Uses a real VoteProvider (the logic under test lives there) with a
// hand-rolled VoteService fake, plus the shared generated mocks for the API
// and auth surfaces.

import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/providers/user_profile_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/services/vote_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/test_mocks.dart';

/// A VoteService that answers locally instead of hitting the network.
///
/// VoteService's only public member is [createVote], so implementing the
/// interface is cheaper than another round of mockito codegen.
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

CommentView buildComment({
  required String uri,
  String? vote,
  String? voteUri,
  int score = 5,
}) {
  return CommentView(
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
    stats: CommentStats(score: score, upvotes: score),
    viewer: CommentViewerState(vote: vote, voteUri: voteUri),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UserProfileProvider vote-state regression', () {
    const profileDid = 'did:plc:profileowner';
    const commentUri = 'at://did:plc:author/social.coves.comment.record/c1';
    const commentCid = 'cid-c1';
    const voteUri = 'at://did:plc:profileowner/social.coves.feed.vote/456';

    late MockAuthProvider mockAuthProvider;
    late MockCovesApiService mockApiService;
    late MockCommentService mockCommentService;
    late _FakeVoteService fakeVoteService;
    late VoteProvider voteProvider;
    late UserProfileProvider profileProvider;

    setUp(() async {
      mockAuthProvider = MockAuthProvider();
      mockApiService = MockCovesApiService();
      mockCommentService = MockCommentService();

      when(mockAuthProvider.isAuthenticated).thenReturn(true);
      when(mockAuthProvider.did).thenReturn(profileDid);
      when(
        mockAuthProvider.getAccessToken(),
      ).thenAnswer((_) async => 'test-token');

      fakeVoteService = _FakeVoteService(
        response: const VoteResponse(
          uri: voteUri,
          cid: 'bafyvote',
          rkey: '456',
          deleted: false,
        ),
      );
      voteProvider = VoteProvider(
        voteService: fakeVoteService,
        authProvider: mockAuthProvider,
      );

      profileProvider = UserProfileProvider(
        mockAuthProvider,
        apiService: mockApiService,
        voteProvider: voteProvider,
        commentService: mockCommentService,
      );

      when(mockApiService.getProfile(actor: anyNamed('actor'))).thenAnswer(
        (_) async => UserProfile(did: profileDid, handle: 'me.test'),
      );

      await profileProvider.loadProfile(profileDid);
    });

    tearDown(() {
      profileProvider.dispose();
      voteProvider.dispose();
    });

    test('refresh with a stale viewer snapshot must not clobber an '
        'optimistic vote', () async {
      // The user likes the comment from a thread view; the appview has not
      // indexed it yet, so the local +1 adjustment is still outstanding.
      await voteProvider.toggleVote(postUri: commentUri, postCid: commentCid);
      expect(voteProvider.isLiked(commentUri), true);
      expect(voteProvider.getAdjustedScore(commentUri, 5), 6);

      // Opening the profile refreshes the comment list within the indexing
      // window: the snapshot still says "not voted", score still 5.
      when(
        mockApiService.getActorComments(
          actor: anyNamed('actor'),
          community: anyNamed('community'),
          limit: anyNamed('limit'),
          cursor: anyNamed('cursor'),
        ),
      ).thenAnswer(
        (_) async =>
            ActorCommentsResponse(comments: [buildComment(uri: commentUri)]),
      );

      await profileProvider.loadComments(refresh: true);

      // The heart must stay lit and the score must still read 6.
      expect(voteProvider.isLiked(commentUri), true);
      expect(voteProvider.getAdjustedScore(commentUri, 5), 6);
    });

    test(
      'refresh with a caught-up viewer snapshot clears the adjustment',
      () async {
        await voteProvider.toggleVote(postUri: commentUri, postCid: commentCid);
        expect(voteProvider.getAdjustedScore(commentUri, 5), 6);

        // This time the appview has indexed the vote: score 6 already
        // includes it and the viewer state confirms it.
        when(
          mockApiService.getActorComments(
            actor: anyNamed('actor'),
            community: anyNamed('community'),
            limit: anyNamed('limit'),
            cursor: anyNamed('cursor'),
          ),
        ).thenAnswer(
          (_) async => ActorCommentsResponse(
            comments: [
              buildComment(
                uri: commentUri,
                vote: 'up',
                voteUri: voteUri,
                score: 6,
              ),
            ],
          ),
        );

        await profileProvider.loadComments(refresh: true);

        expect(voteProvider.isLiked(commentUri), true);
        // No double count: 6 stays 6.
        expect(voteProvider.getAdjustedScore(commentUri, 6), 6);
      },
    );

    test('loadPosts seeds vote state so a liked post lights up when the '
        'profile is its first surface', () async {
      const postUri = 'at://did:plc:author/social.coves.community.post/p1';
      const postVoteUri = 'at://did:plc:profileowner/social.coves.feed.vote/p';

      when(
        mockApiService.getAuthorPosts(
          actor: anyNamed('actor'),
          filter: anyNamed('filter'),
          community: anyNamed('community'),
          limit: anyNamed('limit'),
          cursor: anyNamed('cursor'),
        ),
      ).thenAnswer(
        (_) async => TimelineResponse(
          feed: [
            FeedViewPost(
              post: PostView(
                uri: postUri,
                cid: 'cid-p1',
                rkey: 'p1',
                author: AuthorView(did: profileDid, handle: 'me.test'),
                community: CommunityRef(
                  did: 'did:plc:community',
                  name: 'test-community',
                ),
                createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
                indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
                record: const PostRecord(title: 'T', content: 'c'),
                stats: PostStats(
                  upvotes: 3,
                  downvotes: 0,
                  score: 3,
                  commentCount: 0,
                ),
                viewer: ViewerState(vote: 'up', voteUri: postVoteUri),
              ),
            ),
          ],
        ),
      );

      await profileProvider.loadPosts(refresh: true);

      expect(voteProvider.isLiked(postUri), true);
      expect(voteProvider.getVoteState(postUri)?.uri, postVoteUri);
    });

    test('refresh still adopts a cross-device vote removal for untouched '
        'comments', () async {
      // Adopted from an earlier load, no local mutation outstanding.
      voteProvider.applyServerVoteState(
        postUri: commentUri,
        voteDirection: 'up',
        voteUri: voteUri,
      );
      expect(voteProvider.isLiked(commentUri), true);

      // The vote was removed on another device.
      when(
        mockApiService.getActorComments(
          actor: anyNamed('actor'),
          community: anyNamed('community'),
          limit: anyNamed('limit'),
          cursor: anyNamed('cursor'),
        ),
      ).thenAnswer(
        (_) async =>
            ActorCommentsResponse(comments: [buildComment(uri: commentUri)]),
      );

      await profileProvider.loadComments(refresh: true);

      expect(voteProvider.isLiked(commentUri), false);
    });
  });
}
