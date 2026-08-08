// Characterization net for the viewer-state hydration performed inside
// widgets (sites 2, 7 and 8 of the eight hydration sites), driven through
// the real screens.
//
// Asserted only through CommunitySubscriptionProvider.isSubscribed and
// VoteProvider.isLiked / getVoteState, so the net survives the extraction
// of the hydration logic into a shared service.
//
// The two community-subscription sites disagree about a null `subscribed`
// and that disagreement is load bearing:
//
//   * the LIST site skips a community whose `viewer` is null, but coerces a
//     present-viewer's null `subscribed` to false;
//   * the SINGLE-community site skips whenever `subscribed` is null.
//
// Both halves are pinned below.

import 'package:coves_flutter/models/community.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/community_subscription_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/community/community_feed_screen.dart';
import 'package:coves_flutter/screens/home/communities_discovery_screen.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/streamable_service.dart';
import 'package:coves_flutter/services/vote_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/test_mocks.dart';

class _FakeAuthProvider extends AuthProvider {
  _FakeAuthProvider({required bool authenticated})
    : _isAuthenticated = authenticated;

  final bool _isAuthenticated;

  @override
  bool get isAuthenticated => _isAuthenticated;

  @override
  bool get isLoading => false;
}

/// A subscription provider whose sign-in load is a no-op, so nothing races
/// the seeding under test.
class _TestSubscriptionProvider extends CommunitySubscriptionProvider {
  _TestSubscriptionProvider({
    required super.authProvider,
    required super.apiService,
  });

  @override
  Future<void> loadSubscribedCommunities() async {}
}

const String communityDid = 'did:plc:community';
const String communityHandle = 'testcove';
const String postUri = 'at://did:plc:author/social.coves.community.post/p1';
const String voteUri = 'at://did:plc:me/social.coves.feed.vote/v1';

CommunityView buildCommunity({CommunityViewerState? viewer}) {
  return CommunityView(
    did: communityDid,
    name: communityHandle,
    displayName: 'Test Cove',
    viewer: viewer,
  );
}

FeedViewPost buildFeedPost({
  String? vote,
  String? refVoteUri,
  CommunityRefViewerState? communityViewer,
}) {
  return FeedViewPost(
    post: PostView(
      uri: postUri,
      cid: 'cid-p1',
      rkey: 'p1',
      author: AuthorView(did: 'did:plc:author', handle: 'test.user'),
      community: CommunityRef(
        did: communityDid,
        name: communityHandle,
        viewer: communityViewer,
      ),
      createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
      indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
      record: const PostRecord(title: 'Title', content: 'Body'),
      stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
      viewer: ViewerState(vote: vote, voteUri: refVoteUri),
    ),
  );
}

void main() {
  late MockCovesApiService mockApiService;

  setUp(() {
    mockApiService = MockCovesApiService();
  });

  VoteProvider buildVoteProvider(AuthProvider auth) {
    final provider = VoteProvider(
      voteService: VoteService(
        sessionGetter: () async => null,
        didGetter: () => null,
      ),
      authProvider: auth,
    );
    addTearDown(provider.dispose);
    return provider;
  }

  CommunitySubscriptionProvider buildSubscriptionProvider(AuthProvider auth) {
    final provider = _TestSubscriptionProvider(
      authProvider: auth,
      apiService: mockApiService,
    );
    addTearDown(provider.dispose);
    return provider;
  }

  group('community LIST subscription seeding (discovery screen)', () {
    void stubListCommunities(List<CommunityView> communities) {
      when(
        mockApiService.listCommunities(
          limit: anyNamed('limit'),
          cursor: anyNamed('cursor'),
          sort: anyNamed('sort'),
          subscribed: anyNamed('subscribed'),
        ),
      ).thenAnswer((_) async => CommunitiesResponse(communities: communities));
    }

    Future<CommunitySubscriptionProvider> pumpDiscovery(
      WidgetTester tester, {
      required bool seededSubscribed,
    }) async {
      final auth = _FakeAuthProvider(authenticated: true);
      final subscriptions = buildSubscriptionProvider(auth)
        ..setInitialSubscriptionState(
          communityDid: communityDid,
          isSubscribed: seededSubscribed,
        );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<CovesApiService>.value(value: mockApiService),
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider<CommunitySubscriptionProvider>.value(
              value: subscriptions,
            ),
          ],
          // The screen is normally embedded in MainShellScreen, which owns
          // the Scaffold its Material widgets need.
          child: const MaterialApp(
            home: Scaffold(body: CommunitiesDiscoveryScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return subscriptions;
    }

    testWidgets('C11a skips a community whose viewer is null, leaving known '
        'state untouched', (tester) async {
      stubListCommunities([buildCommunity()]);

      final subscriptions = await pumpDiscovery(
        tester,
        seededSubscribed: true,
      );

      expect(subscriptions.isSubscribed(communityDid), true);
    });

    testWidgets('C11b coerces a present viewer\'s null subscribed to false', (
      tester,
    ) async {
      stubListCommunities([buildCommunity(viewer: CommunityViewerState())]);

      final subscriptions = await pumpDiscovery(
        tester,
        seededSubscribed: true,
      );

      // DIVERGENCE: the single-community site (C11c) skips this same input.
      expect(subscriptions.isSubscribed(communityDid), false);
    });

    testWidgets('a present viewer with subscribed true is applied', (
      tester,
    ) async {
      stubListCommunities([
        buildCommunity(viewer: CommunityViewerState(subscribed: true)),
      ]);

      final subscriptions = await pumpDiscovery(
        tester,
        seededSubscribed: false,
      );

      expect(subscriptions.isSubscribed(communityDid), true);
    });
  });

  group('community feed screen hydration', () {
    void stubCommunity(CommunityView community) {
      when(
        mockApiService.getCommunity(community: anyNamed('community')),
      ).thenAnswer((_) async => community);
    }

    void stubFeed(List<FeedViewPost> feed) {
      when(
        mockApiService.getCommunityFeed(
          community: anyNamed('community'),
          sort: anyNamed('sort'),
          timeframe: anyNamed('timeframe'),
          limit: anyNamed('limit'),
          cursor: anyNamed('cursor'),
        ),
      ).thenAnswer((_) async => TimelineResponse(feed: feed));
    }

    Future<void> pumpFeedScreen(
      WidgetTester tester, {
      required AuthProvider auth,
      required VoteProvider votes,
      required CommunitySubscriptionProvider subscriptions,
    }) async {
      final blocks = BlockProvider(
        apiService: mockApiService,
        authProvider: auth,
      );
      addTearDown(blocks.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<CovesApiService>.value(value: mockApiService),
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider<VoteProvider>.value(value: votes),
            ChangeNotifierProvider<CommunitySubscriptionProvider>.value(
              value: subscriptions,
            ),
            ChangeNotifierProvider<BlockProvider>.value(value: blocks),
            Provider<StreamableService>(create: (_) => StreamableService()),
          ],
          child: const MaterialApp(
            home: CommunityFeedScreen(identifier: communityHandle),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('C11c skips the single community when subscribed is null, '
        'leaving known state untouched', (tester) async {
      stubCommunity(buildCommunity(viewer: CommunityViewerState()));
      stubFeed(const []);

      final auth = _FakeAuthProvider(authenticated: true);
      final votes = buildVoteProvider(auth);
      final subscriptions = buildSubscriptionProvider(auth)
        ..setInitialSubscriptionState(
          communityDid: communityDid,
          isSubscribed: true,
        );

      await pumpFeedScreen(
        tester,
        auth: auth,
        votes: votes,
        subscriptions: subscriptions,
      );

      // DIVERGENCE: the list site (C11b) coerces this same input to false.
      expect(subscriptions.isSubscribed(communityDid), true);
    });

    testWidgets('the single community IS applied when subscribed is set', (
      tester,
    ) async {
      stubCommunity(
        buildCommunity(viewer: CommunityViewerState(subscribed: false)),
      );
      stubFeed(const []);

      final auth = _FakeAuthProvider(authenticated: true);
      final votes = buildVoteProvider(auth);
      final subscriptions = buildSubscriptionProvider(auth)
        ..setInitialSubscriptionState(
          communityDid: communityDid,
          isSubscribed: true,
        );

      await pumpFeedScreen(
        tester,
        auth: auth,
        votes: votes,
        subscriptions: subscriptions,
      );

      expect(subscriptions.isSubscribed(communityDid), false);
    });

    testWidgets('C2/C1 the community feed page seeds both votes and '
        'subscriptions when signed in', (tester) async {
      stubCommunity(buildCommunity());
      stubFeed([
        buildFeedPost(
          vote: 'up',
          refVoteUri: voteUri,
          communityViewer: CommunityRefViewerState(subscribed: true),
        ),
      ]);

      final auth = _FakeAuthProvider(authenticated: true);
      final votes = buildVoteProvider(auth);
      final subscriptions = buildSubscriptionProvider(auth);

      await pumpFeedScreen(
        tester,
        auth: auth,
        votes: votes,
        subscriptions: subscriptions,
      );

      expect(votes.isLiked(postUri), true);
      expect(votes.getVoteState(postUri)?.uri, voteUri);
      expect(subscriptions.isSubscribed(communityDid), true);
    });

    testWidgets('C4 the community feed page seeds nothing when signed out, '
        'on identical input', (tester) async {
      stubCommunity(buildCommunity());
      stubFeed([
        buildFeedPost(
          vote: 'up',
          refVoteUri: voteUri,
          communityViewer: CommunityRefViewerState(subscribed: true),
        ),
      ]);

      final auth = _FakeAuthProvider(authenticated: false);
      final votes = buildVoteProvider(auth);
      final subscriptions = buildSubscriptionProvider(auth);

      await pumpFeedScreen(
        tester,
        auth: auth,
        votes: votes,
        subscriptions: subscriptions,
      );

      expect(votes.isLiked(postUri), false);
      expect(votes.getVoteState(postUri), isNull);
      expect(subscriptions.isSubscribed(communityDid), false);
    });

    testWidgets('C3 the community feed page skips a post whose community '
        'viewer says nothing about subscribed', (tester) async {
      stubCommunity(buildCommunity());
      stubFeed([
        buildFeedPost(communityViewer: CommunityRefViewerState()),
      ]);

      final auth = _FakeAuthProvider(authenticated: true);
      final votes = buildVoteProvider(auth);
      final subscriptions = buildSubscriptionProvider(auth)
        ..setInitialSubscriptionState(
          communityDid: communityDid,
          isSubscribed: true,
        );

      await pumpFeedScreen(
        tester,
        auth: auth,
        votes: votes,
        subscriptions: subscriptions,
      );

      expect(subscriptions.isSubscribed(communityDid), true);
    });
  });
}
