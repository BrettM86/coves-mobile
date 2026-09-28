// The community and its feed are fetched side by side, so the feed can land
// while the full-screen community loader (or its error) is still showing.
// A short first page must still page on once the feed's scroll view
// appears, without the user scrolling.

import 'dart:async';

import 'package:coves_flutter/models/community.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/community_subscription_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/community/community_feed_screen.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/streamable_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/test_mocks.dart';
import '../test_helpers/theme_pump.dart';

const String communityDid = 'did:plc:community';
const String communityHandle = 'testcove';

FeedViewPost buildFeedPost({required String rkey, required String title}) {
  return FeedViewPost(
    post: PostView(
      uri: 'at://did:plc:author/social.coves.community.post/$rkey',
      cid: 'cid-$rkey',
      rkey: rkey,
      author: AuthorView(did: 'did:plc:author', handle: 'test.user'),
      community: CommunityRef(did: communityDid, name: communityHandle),
      createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
      indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
      record: PostRecord(title: title, content: 'Body'),
      stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
    ),
  );
}

void main() {
  late MockCovesApiService mockApiService;

  setUp(() {
    mockApiService = MockCovesApiService();
  });

  /// Pumps the screen without settling, so the test decides when each
  /// request lands.
  Future<void> pumpFeedScreen(WidgetTester tester) async {
    final auth = FakeAuthProvider();
    final votes = FakeVoteProvider(auth);
    addTearDown(votes.dispose);
    final subscriptions = FakeSubscriptionProvider(
      authProvider: auth,
      apiService: mockApiService,
    );
    addTearDown(subscriptions.dispose);
    final blocks = BlockProvider(
      apiService: mockApiService,
      authProvider: auth,
    );
    addTearDown(blocks.dispose);

    await pumpUnderAppTheme(
      tester,
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
        child: const CommunityFeedScreen(identifier: communityDid),
      ),
    );
    // Runs the post-frame callback that starts both requests.
    await tester.pump();
  }

  /// Page one is a single post (far short of the viewport) with a cursor,
  /// held until [firstPage] completes; page two answers at once.
  void stubShortFeed(Completer<TimelineResponse> firstPage) {
    when(
      mockApiService.getCommunityFeed(
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
      ),
    ).thenAnswer((_) => firstPage.future);

    when(
      mockApiService.getCommunityFeed(
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: 'c1',
      ),
    ).thenAnswer(
      (_) async => TimelineResponse(
        feed: [buildFeedPost(rkey: 'p2', title: 'Second community post')],
      ),
    );
  }

  TimelineResponse shortFirstPage() {
    return TimelineResponse(
      feed: [buildFeedPost(rkey: 'p1', title: 'First community post')],
      cursor: 'c1',
    );
  }

  void verifySecondPageRequested() {
    verify(
      mockApiService.getCommunityFeed(
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: 'c1',
      ),
    ).called(1);
  }

  testWidgets('a short first page that lands before the community still '
      'pages on once the community loads', (tester) async {
    final community = Completer<CommunityView>();
    final firstPage = Completer<TimelineResponse>();
    when(
      mockApiService.getCommunity(community: anyNamed('community')),
    ).thenAnswer((_) => community.future);
    stubShortFeed(firstPage);

    await pumpFeedScreen(tester);

    firstPage.complete(shortFirstPage());
    await tester.pump();
    await tester.pump();

    community.complete(
      CommunityView(
        did: communityDid,
        name: communityHandle,
        displayName: 'Test Cove',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('First community post'), findsOneWidget);
    expect(find.text('Second community post'), findsOneWidget);
    verifySecondPageRequested();
  });

  testWidgets('a short first page that lands while the community load has '
      'failed pages on once a retry loads the community', (tester) async {
    final firstPage = Completer<TimelineResponse>();
    var communityAttempts = 0;
    when(
      mockApiService.getCommunity(community: anyNamed('community')),
    ).thenAnswer((_) async {
      communityAttempts++;
      if (communityAttempts == 1) {
        throw ApiException('Server error', statusCode: 500);
      }
      return CommunityView(
        did: communityDid,
        name: communityHandle,
        displayName: 'Test Cove',
      );
    });
    stubShortFeed(firstPage);

    await pumpFeedScreen(tester);
    await tester.pump();
    expect(find.text('Community not found'), findsOneWidget);

    firstPage.complete(shortFirstPage());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('First community post'), findsOneWidget);
    expect(find.text('Second community post'), findsOneWidget);
    verifySecondPageRequested();
  });
}
