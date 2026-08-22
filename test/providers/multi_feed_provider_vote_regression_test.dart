// Regression test for the "pagination clobbers an optimistic vote" bug.
//
// Scenario (i) of the vote-state spec: cursor drift (or the same post
// appearing in more than one feed) makes a post already on page 1 come back
// in the page-2 response with a stale viewer/stats snapshot. The pagination
// path used to blind-adopt that snapshot, dropping the optimistic vote.
//
// Uses a real VoteProvider with a hand-rolled VoteService fake plus the
// shared generated mocks for the API and auth surfaces.

import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/multi_feed_provider.dart';
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

FeedViewPost buildFeedPost({
  required String uri,
  String? vote,
  String? voteUri,
  int score = 0,
}) {
  return FeedViewPost(
    post: PostView(
      uri: uri,
      cid: 'cid-$uri',
      rkey: uri.split('/').last,
      author: AuthorView(did: 'did:plc:author', handle: 'test.user'),
      community: CommunityRef(did: 'did:plc:community', name: 'testcove'),
      createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
      indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
      record: const PostRecord(title: 'Title', content: 'Body'),
      stats: PostStats(
        upvotes: score,
        downvotes: 0,
        score: score,
        commentCount: 0,
      ),
      viewer: ViewerState(vote: vote, voteUri: voteUri),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MultiFeedProvider vote-state regression', () {
    const postUri = 'at://did:plc:author/social.coves.community.post/p1';
    const postCid = 'cid-at://did:plc:author/social.coves.community.post/p1';
    const voteUri = 'at://did:plc:viewer/social.coves.feed.vote/456';

    late MockAuthProvider mockAuthProvider;
    late MockCovesApiService mockApiService;
    late _FakeVoteService fakeVoteService;
    late VoteProvider voteProvider;
    late MultiFeedProvider feedProvider;

    setUp(() {
      mockAuthProvider = MockAuthProvider();
      mockApiService = MockCovesApiService();

      when(mockAuthProvider.isAuthenticated).thenReturn(true);
      when(mockAuthProvider.did).thenReturn('did:plc:viewer');
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

      feedProvider = MultiFeedProvider(
        mockAuthProvider,
        apiService: mockApiService,
        voteProvider: voteProvider,
      );
    });

    tearDown(() {
      feedProvider.dispose();
      voteProvider.dispose();
    });

    /// Stubs getDiscover to answer [pages] in order, one per call.
    void stubDiscoverPages(List<TimelineResponse> pages) {
      var call = 0;
      when(
        mockApiService.getDiscover(
          sort: anyNamed('sort'),
          timeframe: anyNamed('timeframe'),
          limit: anyNamed('limit'),
          cursor: anyNamed('cursor'),
        ),
      ).thenAnswer((_) async {
        final page = pages[call < pages.length ? call : pages.length - 1];
        call++;
        return page;
      });
    }

    test('a duplicated post on the next page must not clobber an optimistic '
        'vote', () async {
      stubDiscoverPages([
        TimelineResponse(feed: [buildFeedPost(uri: postUri)], cursor: 'page-2'),
        // Cursor drift re-delivers the same post, still unvoted and with
        // the pre-vote score.
        TimelineResponse(
          feed: [
            buildFeedPost(uri: postUri),
            buildFeedPost(
              uri: 'at://did:plc:author/social.coves.community.post/p2',
            ),
          ],
        ),
      ]);

      await feedProvider.loadFeed(FeedType.discover, refresh: true);
      expect(voteProvider.isLiked(postUri), false);

      // The user likes the post before paginating; the appview has not
      // indexed the vote yet.
      await voteProvider.toggleVote(postUri: postUri, postCid: postCid);
      expect(voteProvider.isLiked(postUri), true);
      expect(voteProvider.getAdjustedScore(postUri, 0), 1);

      await feedProvider.loadMore(FeedType.discover);

      // Both the vote and its optimistic adjustment must survive.
      expect(voteProvider.isLiked(postUri), true);
      expect(voteProvider.getAdjustedScore(postUri, 0), 1);
    });

    test('a post re-delivered by cursor drift is shown once', () async {
      const otherUri = 'at://did:plc:author/social.coves.community.post/p2';
      const thirdUri = 'at://did:plc:author/social.coves.community.post/p3';

      stubDiscoverPages([
        TimelineResponse(
          feed: [buildFeedPost(uri: postUri), buildFeedPost(uri: otherUri)],
          cursor: 'page-2',
        ),
        // The hot-sort cursor moved under us: page 2 starts with the post
        // that closed page 1.
        TimelineResponse(
          feed: [buildFeedPost(uri: otherUri), buildFeedPost(uri: thirdUri)],
        ),
      ]);

      await feedProvider.loadFeed(FeedType.discover, refresh: true);
      await feedProvider.loadMore(FeedType.discover);

      final uris = feedProvider
          .getState(FeedType.discover)
          .posts
          .map((p) => p.post.uri)
          .toList();
      expect(uris, [postUri, otherUri, thirdUri]);
      expect(feedProvider.getState(FeedType.discover).hasMore, false);
    });

    test(
      'pagination still adopts viewer state for posts new to the provider',
      () async {
        const otherUri = 'at://did:plc:author/social.coves.community.post/p2';

        stubDiscoverPages([
          TimelineResponse(
            feed: [buildFeedPost(uri: postUri)],
            cursor: 'page-2',
          ),
          TimelineResponse(
            feed: [
              buildFeedPost(
                uri: otherUri,
                vote: 'up',
                voteUri: voteUri,
                score: 3,
              ),
            ],
          ),
        ]);

        await feedProvider.loadFeed(FeedType.discover, refresh: true);
        await feedProvider.loadMore(FeedType.discover);

        expect(voteProvider.isLiked(otherUri), true);
        expect(voteProvider.getVoteState(otherUri)?.uri, voteUri);
        expect(voteProvider.getAdjustedScore(otherUri, 3), 3);
      },
    );

    test(
      'a refresh whose snapshot has caught up clears the adjustment',
      () async {
        stubDiscoverPages([
          TimelineResponse(feed: [buildFeedPost(uri: postUri)]),
          // Refresh after the appview indexed the vote: score 1 already
          // includes it and the viewer state confirms it.
          TimelineResponse(
            feed: [
              buildFeedPost(
                uri: postUri,
                vote: 'up',
                voteUri: voteUri,
                score: 1,
              ),
            ],
          ),
        ]);

        await feedProvider.loadFeed(FeedType.discover, refresh: true);
        await voteProvider.toggleVote(postUri: postUri, postCid: postCid);
        expect(voteProvider.getAdjustedScore(postUri, 0), 1);

        await feedProvider.loadFeed(FeedType.discover, refresh: true);

        expect(voteProvider.isLiked(postUri), true);
        // No double count: the server score of 1 stands on its own.
        expect(voteProvider.getAdjustedScore(postUri, 1), 1);
      },
    );
  });
}
