// Characterization net for the viewer-state hydration the provider-layer
// sites perform today (sites 1, 3, 4 and 5 of the eight).
//
// These tests exist to survive the extraction of that logic into a shared
// hydrator, so they assert ONLY through the public surfaces the refactor
// keeps: VoteProvider.isLiked / getVoteState / getAdjustedScore and
// CommunitySubscriptionProvider.isSubscribed. No private helper is named.
//
// The sites are deliberately NOT interchangeable. Where two of them treat
// the same input differently that difference is pinned on purpose - see the
// "divergence" comments. A test here failing after the refactor means a
// behaviour changed, not that the test is stale.
//
// Follows the existing vote-regression files: a real VoteProvider (the
// routing under test lives there) with a hand-rolled VoteService fake, plus
// the shared generated mocks for the API and auth surfaces.

import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/providers/comments_provider.dart';
import 'package:coves_flutter/providers/community_subscription_provider.dart';
import 'package:coves_flutter/providers/multi_feed_provider.dart';
import 'package:coves_flutter/providers/user_profile_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/services/viewer_state_hydrator.dart';
import 'package:coves_flutter/services/vote_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/test_mocks.dart';

/// A VoteService that answers locally instead of hitting the network.
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

const String communityDid = 'did:plc:community';
const String voteUri = 'at://did:plc:me/social.coves.feed.vote/v1';
const String postUriA = 'at://did:plc:author/social.coves.community.post/p1';
const String postUriB = 'at://did:plc:author/social.coves.community.post/p2';

FeedViewPost buildFeedPost({
  required String uri,
  String? vote,
  String? voteUri,
  CommunityRefViewerState? communityViewer,
  int score = 0,
}) {
  return FeedViewPost(
    post: PostView(
      uri: uri,
      cid: 'cid-$uri',
      rkey: uri.split('/').last,
      author: AuthorView(did: 'did:plc:author', handle: 'test.user'),
      community: CommunityRef(
        did: communityDid,
        name: 'testcove',
        viewer: communityViewer,
      ),
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

CommentView buildComment({required String uri, String? vote, String? voteUri}) {
  return CommentView(
    uri: uri,
    cid: 'cid-$uri',
    record: const CommentRecord(content: 'Test comment content'),
    createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
    indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
    author: AuthorView(did: 'did:plc:author', handle: 'test.user'),
    post: CommentRef(
      uri: 'at://did:plc:test/social.coves.post.record/123',
      cid: 'post-cid',
    ),
    stats: const CommentStats(score: 5, upvotes: 5),
    viewer: CommentViewerState(vote: vote, voteUri: voteUri),
  );
}

ThreadViewComment buildThreadComment({
  required String uri,
  String? vote,
  String? voteUri,
  List<ThreadViewComment>? replies,
}) {
  return ThreadViewComment(
    comment: buildComment(uri: uri, vote: vote, voteUri: voteUri),
    replies: replies,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAuthProvider mockAuthProvider;
  late MockCovesApiService mockApiService;
  late VoteProvider voteProvider;

  setUp(() {
    mockAuthProvider = MockAuthProvider();
    mockApiService = MockCovesApiService();

    when(mockAuthProvider.isAuthenticated).thenReturn(true);
    when(mockAuthProvider.did).thenReturn('did:plc:me');
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
  });

  tearDown(() {
    voteProvider.dispose();
  });

  CommunitySubscriptionProvider newSubscriptionProvider() {
    final provider = CommunitySubscriptionProvider(
      authProvider: mockAuthProvider,
      apiService: mockApiService,
    );
    addTearDown(provider.dispose);
    return provider;
  }

  /// Stubs getDiscover to answer [pages] in order, repeating the last.
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

  /// Stubs getAuthorPosts to answer [pages] in order, repeating the last.
  void stubAuthorPostsPages(List<TimelineResponse> pages) {
    var call = 0;
    when(
      mockApiService.getAuthorPosts(
        actor: anyNamed('actor'),
        filter: anyNamed('filter'),
        community: anyNamed('community'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((_) async {
      final page = pages[call < pages.length ? call : pages.length - 1];
      call++;
      return page;
    });
  }

  void stubActorComments(List<CommentView> comments) {
    when(
      mockApiService.getActorComments(
        actor: anyNamed('actor'),
        community: anyNamed('community'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((_) async => ActorCommentsResponse(comments: comments));
  }

  void stubThreadResponse(List<ThreadViewComment> comments) {
    when(
      mockApiService.getComments(
        postUri: anyNamed('postUri'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        depth: anyNamed('depth'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((_) async => CommentsResponse(post: {}, comments: comments));
  }

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

  MultiFeedProvider newFeedProvider({
    VoteProvider? votes,
    CommunitySubscriptionProvider? subscriptions,
  }) {
    final provider = MultiFeedProvider(
      mockAuthProvider,
      apiService: mockApiService,
      voteProvider: votes,
      subscriptionProvider: subscriptions,
    );
    addTearDown(provider.dispose);
    return provider;
  }

  Future<UserProfileProvider> newProfileProvider({
    VoteProvider? votes,
    ViewerStateHydrator? hydrator,
  }) async {
    const profileDid = 'did:plc:profileowner';
    final provider = UserProfileProvider(
      mockAuthProvider,
      apiService: mockApiService,
      voteProvider: votes,
      hydrator: hydrator,
      commentService: MockCommentService(),
    );
    addTearDown(provider.dispose);

    when(mockApiService.getProfile(actor: anyNamed('actor'))).thenAnswer(
      (_) async => UserProfile(did: profileDid, handle: 'owner.test'),
    );
    await provider.loadProfile(profileDid);
    return provider;
  }

  CommentsProvider newCommentsProvider({
    VoteProvider? votes,
    ViewerStateHydrator? hydrator,
  }) {
    final provider = CommentsProvider(
      mockAuthProvider,
      postUri: 'at://did:plc:test/social.coves.post.record/123',
      postCid: 'test-post-cid',
      apiService: mockApiService,
      voteProvider: votes,
      hydrator: hydrator,
    );
    addTearDown(provider.dispose);
    return provider;
  }

  group('feed hydration - votes and subscriptions (MultiFeedProvider)', () {
    test('C1 applies the vote snapshot for every post, including a null '
        'direction that clears a vote removed elsewhere', () async {
      // Adopted from an earlier surface, no local mutation outstanding.
      voteProvider.applyServerVoteState(
        postUri: postUriB,
        voteDirection: 'up',
        voteUri: voteUri,
      );
      expect(voteProvider.isLiked(postUriB), true);

      stubDiscoverPages([
        TimelineResponse(
          feed: [
            buildFeedPost(uri: postUriA, vote: 'up', voteUri: voteUri),
            // Vote removed on another device: the null direction is applied,
            // never ignored.
            buildFeedPost(uri: postUriB),
          ],
        ),
      ]);

      final feed = newFeedProvider(votes: voteProvider);
      await feed.loadFeed(FeedType.discover, refresh: true);

      expect(voteProvider.isLiked(postUriA), true);
      expect(voteProvider.getVoteState(postUriA)?.uri, voteUri);
      expect(voteProvider.isLiked(postUriB), false);
    });

    test('C2 applies the subscription snapshot when '
        'community.viewer.subscribed is set', () async {
      final subscriptions = newSubscriptionProvider();
      stubDiscoverPages([
        TimelineResponse(
          feed: [
            buildFeedPost(
              uri: postUriA,
              communityViewer: CommunityRefViewerState(subscribed: true),
            ),
          ],
        ),
      ]);

      final feed = newFeedProvider(
        votes: voteProvider,
        subscriptions: subscriptions,
      );
      await feed.loadFeed(FeedType.discover, refresh: true);

      expect(subscriptions.isSubscribed(communityDid), true);
    });

    test('C3 skips the subscription when community.viewer.subscribed is '
        'null, leaving known state untouched', () async {
      final subscriptions = newSubscriptionProvider()
        ..setInitialSubscriptionState(
          communityDid: communityDid,
          isSubscribed: true,
        );

      stubDiscoverPages([
        TimelineResponse(
          feed: [
            // viewer present but subscribed omitted...
            buildFeedPost(
              uri: postUriA,
              communityViewer: CommunityRefViewerState(),
            ),
            // ...and viewer absent entirely.
            buildFeedPost(uri: postUriB),
          ],
        ),
      ]);

      final feed = newFeedProvider(
        votes: voteProvider,
        subscriptions: subscriptions,
      );
      await feed.loadFeed(FeedType.discover, refresh: true);

      // Not coerced to false: the snapshot said nothing, so nothing is said.
      expect(subscriptions.isSubscribed(communityDid), true);
    });

    test('C4 hydrates nothing when unauthenticated, and everything from the '
        'same response when authenticated', () async {
      stubDiscoverPages([
        TimelineResponse(
          feed: [
            buildFeedPost(
              uri: postUriA,
              vote: 'up',
              voteUri: voteUri,
              communityViewer: CommunityRefViewerState(subscribed: true),
            ),
          ],
        ),
      ]);

      final signedOutSubscriptions = newSubscriptionProvider();
      when(mockAuthProvider.isAuthenticated).thenReturn(false);
      final signedOutFeed = newFeedProvider(
        votes: voteProvider,
        subscriptions: signedOutSubscriptions,
      );
      await signedOutFeed.loadFeed(FeedType.discover, refresh: true);

      expect(voteProvider.isLiked(postUriA), false);
      expect(voteProvider.getVoteState(postUriA), isNull);
      expect(signedOutSubscriptions.isSubscribed(communityDid), false);

      // Positive control: identical input, authenticated.
      final signedInSubscriptions = newSubscriptionProvider();
      when(mockAuthProvider.isAuthenticated).thenReturn(true);
      final signedInFeed = newFeedProvider(
        votes: voteProvider,
        subscriptions: signedInSubscriptions,
      );
      await signedInFeed.loadFeed(FeedType.discover, refresh: true);

      expect(voteProvider.isLiked(postUriA), true);
      expect(voteProvider.getVoteState(postUriA)?.uri, voteUri);
      expect(signedInSubscriptions.isSubscribed(communityDid), true);
    });

    test('C5 skips vote hydration when the vote provider is absent while '
        'still applying subscriptions', () async {
      final subscriptions = newSubscriptionProvider();
      stubDiscoverPages([
        TimelineResponse(
          feed: [
            buildFeedPost(
              uri: postUriA,
              vote: 'up',
              voteUri: voteUri,
              communityViewer: CommunityRefViewerState(subscribed: true),
            ),
          ],
        ),
      ]);

      final feed = newFeedProvider(subscriptions: subscriptions);
      await feed.loadFeed(FeedType.discover, refresh: true);

      // The unwired provider never hears about the vote...
      expect(voteProvider.isLiked(postUriA), false);
      // ...but the loop did run: subscriptions landed.
      expect(subscriptions.isSubscribed(communityDid), true);
    });

    test('C12a hydrates a cursor-drift duplicate because it iterates the '
        'raw response feed', () async {
      stubDiscoverPages([
        TimelineResponse(
          feed: [buildFeedPost(uri: postUriA, vote: 'up', voteUri: voteUri)],
          cursor: 'page-2',
        ),
        // Cursor drift re-delivers the same post with the vote gone. No
        // local mutation is outstanding, so the snapshot is adopted.
        TimelineResponse(
          feed: [buildFeedPost(uri: postUriA), buildFeedPost(uri: postUriB)],
        ),
      ]);

      final feed = newFeedProvider(votes: voteProvider);
      await feed.loadFeed(FeedType.discover, refresh: true);
      expect(voteProvider.isLiked(postUriA), true);

      await feed.loadMore(FeedType.discover);

      // DIVERGENCE (D3): the duplicate IS hydrated here. The
      // CursorPaginationController-backed sites skip it - see C12b.
      expect(voteProvider.isLiked(postUriA), false);
    });
  });

  group('profile posts hydration - votes only (UserProfileProvider)', () {
    test('C6 applies votes but never subscriptions, even though the feed '
        'carries community viewer state and the subscription surface is '
        'fully wired', () async {
      final subscriptions = newSubscriptionProvider();
      // Deliberately wired for BOTH votes and subscriptions, and handed to
      // the profile provider directly: "no subscription seeded" below can
      // then only come from the traversal this surface chose, never from a
      // dependency that happened to be missing.
      final hydrator = ViewerStateHydrator(
        authProvider: mockAuthProvider,
        voteProvider: voteProvider,
        subscriptionProvider: subscriptions,
      );

      final posts = [
        buildFeedPost(
          uri: postUriA,
          vote: 'up',
          voteUri: voteUri,
          communityViewer: CommunityRefViewerState(subscribed: true),
        ),
      ];
      stubAuthorPostsPages([TimelineResponse(feed: posts)]);

      final profile = await newProfileProvider(hydrator: hydrator);
      await profile.loadPosts(refresh: true);

      expect(voteProvider.isLiked(postUriA), true);
      // DIVERGENCE (D1): profile posts hydrate votes only. If this ever
      // starts passing subscriptions through, that is a behaviour change.
      expect(subscriptions.isSubscribed(communityDid), false);

      // Positive control: the SAME hydrator over the SAME posts through the
      // votes-and-subscriptions traversal does seed. So the assertion above
      // is about which traversal the profile surface picks - not about an
      // unwired provider or an input that says nothing.
      hydrator.hydrateFeed(posts);
      expect(subscriptions.isSubscribed(communityDid), true);
    });

    test('C5 profile posts load without hydrating when no vote provider is '
        'wired', () async {
      stubAuthorPostsPages([
        TimelineResponse(
          feed: [buildFeedPost(uri: postUriA, vote: 'up', voteUri: voteUri)],
        ),
      ]);

      // Positive control FIRST: the identical page through a wired hydrator
      // does reach the vote surface, so "nothing was hydrated" below cannot
      // be blamed on an input that carries nothing.
      final wiredVotes = MockVoteProvider();
      final wired = await newProfileProvider(
        hydrator: ViewerStateHydrator(
          authProvider: mockAuthProvider,
          voteProvider: wiredVotes,
        ),
      );
      await wired.loadPosts(refresh: true);
      verify(
        wiredVotes.applyServerVoteState(
          postUri: postUriA,
          voteDirection: 'up',
          voteUri: voteUri,
        ),
      ).called(1);

      // With no vote provider there is nothing to verify against - the
      // whole point is that no collaborator exists - so the assertion is
      // that the page still loads rather than dereferencing a null.
      // (viewer_state_hydrator_test.dart covers the null-provider gate
      // directly, on the hydrator itself.)
      final unwired = await newProfileProvider(
        hydrator: ViewerStateHydrator(authProvider: mockAuthProvider),
      );
      await unwired.loadPosts(refresh: true);

      expect(unwired.postsState.error, isNull);
      expect(unwired.postsState.posts, hasLength(1));
    });

    test('C12b skips a cursor-drift duplicate because the pagination '
        'controller only hands over deduplicated new items', () async {
      stubAuthorPostsPages([
        TimelineResponse(
          feed: [buildFeedPost(uri: postUriA, vote: 'up', voteUri: voteUri)],
          cursor: 'page-2',
        ),
        TimelineResponse(
          feed: [buildFeedPost(uri: postUriA), buildFeedPost(uri: postUriB)],
        ),
      ]);

      final profile = await newProfileProvider(votes: voteProvider);
      await profile.loadPosts(refresh: true);
      expect(voteProvider.isLiked(postUriA), true);

      await profile.loadMorePosts();

      // DIVERGENCE (D3), the other half of C12a: the duplicate was dropped
      // before hydration, so its stale snapshot never lands.
      expect(voteProvider.isLiked(postUriA), true);
      expect(voteProvider.getVoteState(postUriA)?.uri, voteUri);
      // The genuinely new item on the same page still hydrates.
      expect(voteProvider.isLiked(postUriB), false);
      expect(profile.postsState.posts, hasLength(2));
    });
  });

  group('profile comments hydration - flat list (UserProfileProvider)', () {
    const commentUriA = 'at://did:plc:author/social.coves.comment.record/c1';
    const commentUriB = 'at://did:plc:author/social.coves.comment.record/c2';

    test('C7 applies the vote snapshot for every comment, including a null '
        'direction', () async {
      voteProvider.applyServerVoteState(
        postUri: commentUriB,
        voteDirection: 'up',
        voteUri: voteUri,
      );

      stubActorComments([
        buildComment(uri: commentUriA, vote: 'up', voteUri: voteUri),
        buildComment(uri: commentUriB),
      ]);

      final profile = await newProfileProvider(votes: voteProvider);
      await profile.loadComments(refresh: true);

      expect(voteProvider.isLiked(commentUriA), true);
      expect(voteProvider.getVoteState(commentUriA)?.uri, voteUri);
      expect(voteProvider.isLiked(commentUriB), false);
    });

    test('C5 profile comments load without hydrating when no vote provider '
        'is wired', () async {
      stubActorComments([
        buildComment(uri: commentUriA, vote: 'up', voteUri: voteUri),
      ]);

      // Positive control: the same page through a wired hydrator does hand
      // the snapshot over.
      final wiredVotes = MockVoteProvider();
      final wired = await newProfileProvider(
        hydrator: ViewerStateHydrator(
          authProvider: mockAuthProvider,
          voteProvider: wiredVotes,
        ),
      );
      await wired.loadComments(refresh: true);
      verify(
        wiredVotes.applyServerVoteState(
          postUri: commentUriA,
          voteDirection: 'up',
          voteUri: voteUri,
        ),
      ).called(1);

      final unwired = await newProfileProvider(
        hydrator: ViewerStateHydrator(authProvider: mockAuthProvider),
      );
      await unwired.loadComments(refresh: true);

      expect(unwired.commentsState.error, isNull);
      expect(unwired.commentsState.comments, hasLength(1));
    });
  });

  group('comment tree hydration - recursive (CommentsProvider)', () {
    const rootUri = 'at://did:plc:author/social.coves.community.comment/root';
    const childUri = 'at://did:plc:author/social.coves.community.comment/kid';
    const grandchildUri =
        'at://did:plc:author/social.coves.community.comment/gk';

    test('C8 recurses to every depth of the delivered tree', () async {
      stubThreadResponse([
        buildThreadComment(
          uri: rootUri,
          vote: 'up',
          voteUri: voteUri,
          replies: [
            buildThreadComment(
              uri: childUri,
              vote: 'up',
              voteUri: voteUri,
              replies: [
                buildThreadComment(
                  uri: grandchildUri,
                  vote: 'up',
                  voteUri: voteUri,
                ),
              ],
            ),
          ],
        ),
      ]);

      final comments = newCommentsProvider(votes: voteProvider);
      await comments.loadComments(refresh: true);

      expect(voteProvider.isLiked(rootUri), true);
      expect(voteProvider.isLiked(childUri), true);
      expect(voteProvider.isLiked(grandchildUri), true);
      expect(voteProvider.getVoteState(grandchildUri)?.uri, voteUri);
    });

    test('C5 the comment tree loads without hydrating when no vote provider '
        'is wired', () async {
      stubThreadResponse([
        buildThreadComment(uri: rootUri, vote: 'up', voteUri: voteUri),
      ]);

      // Positive control: the same tree through a wired hydrator does hand
      // the snapshot over.
      final wiredVotes = MockVoteProvider();
      final wired = newCommentsProvider(
        hydrator: ViewerStateHydrator(
          authProvider: mockAuthProvider,
          voteProvider: wiredVotes,
        ),
      );
      await wired.loadComments(refresh: true);
      verify(
        wiredVotes.applyServerVoteState(
          postUri: rootUri,
          voteDirection: 'up',
          voteUri: voteUri,
        ),
      ).called(1);

      final comments = newCommentsProvider(
        hydrator: ViewerStateHydrator(authProvider: mockAuthProvider),
      );
      await comments.loadComments(refresh: true);

      expect(comments.error, isNull);
      expect(comments.comments, hasLength(1));
    });

    test('C9 applies only the nodes the response delivered, so a preserved '
        'stale branch cannot roll back a confirmed vote', () async {
      stubThreadResponse([
        buildThreadComment(
          uri: rootUri,
          replies: [buildThreadComment(uri: childUri)],
        ),
      ]);

      final comments = newCommentsProvider(votes: voteProvider);
      await comments.loadComments(refresh: true);

      // The user likes the child; the appview has not indexed it yet.
      await voteProvider.toggleVote(postUri: childUri, postCid: 'cid-child');
      expect(voteProvider.getAdjustedScore(childUri, 5), 6);

      // Another surface sharing the VoteProvider confirms the vote, which
      // clears the outstanding adjustment.
      voteProvider.applyServerVoteState(
        postUri: childUri,
        voteDirection: 'up',
        voteUri: voteUri,
      );
      expect(voteProvider.getAdjustedScore(childUri, 6), 6);

      // Load-more on the root hits the depth cutoff: the response carries no
      // replies, so the merge preserves the stale child branch.
      stubSubtreeResponse(buildThreadComment(uri: rootUri));
      final subtree = await comments.loadMoreReplies(rootUri);

      expect(
        subtree!.replies!.map((r) => r.comment.uri),
        contains(childUri),
      );
      // The preserved node was never delivered, so it was never applied.
      expect(voteProvider.isLiked(childUri), true);
      expect(voteProvider.getAdjustedScore(childUri, 6), 6);
    });
  });
}
