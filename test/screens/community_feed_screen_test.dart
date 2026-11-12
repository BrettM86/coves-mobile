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
import 'package:coves_flutter/providers/display_preferences_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/community/community_feed_screen.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/post_change_broadcast.dart';
import 'package:coves_flutter/services/streamable_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/community_feed_harness.dart';
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
  Future<void> pumpFeedScreen(
    WidgetTester tester, {
    PostChangeBroadcast? broadcast,
    FakeAuthProvider? signedIn,
    DateTime Function()? paginationClock,
    DisplayPreferencesProvider? displayPreferences,
  }) async {
    final auth = signedIn ?? FakeAuthProvider();
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
          Provider<PostChangeBroadcast>(
            create: (_) => broadcast ?? PostChangeBroadcast(),
          ),
          viewerAuthorityRegistration(auth: auth, apiService: mockApiService),
          unloadedMultiFeedProvider(auth: auth, apiService: mockApiService),
          if (displayPreferences != null)
            ChangeNotifierProvider<DisplayPreferencesProvider>.value(
              value: displayPreferences,
            ),
        ],
        child: CommunityFeedScreen(
          identifier: communityDid,
          paginationClock: paginationClock,
        ),
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
    when(mockApiService.getCommunity(community: anyNamed('community')))
        .thenAnswer((_) => community.future);
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
    when(mockApiService.getCommunity(community: anyNamed('community')))
        .thenAnswer((_) async {
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
    expect(find.text('Failed to load community'), findsOneWidget);

    firstPage.complete(shortFirstPage());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('First community post'), findsOneWidget);
    expect(find.text('Second community post'), findsOneWidget);
    verifySecondPageRequested();
  });

  testWidgets('a post removed before its page is loaded does not appear when '
      'the in-flight page lands', (tester) async {
    final broadcast = PostChangeBroadcast();
    final pageTwo = Completer<TimelineResponse>();
    when(mockApiService.getCommunity(community: anyNamed('community')))
        .thenAnswer(
          (_) async => CommunityView(
            did: communityDid,
            name: communityHandle,
            displayName: 'Test Cove',
          ),
        );
    when(
      mockApiService.getCommunityFeed(
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
      ),
    ).thenAnswer((_) async => shortFirstPage());
    when(
      mockApiService.getCommunityFeed(
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: 'c1',
      ),
    ).thenAnswer((_) => pageTwo.future);

    await pumpFeedScreen(tester, broadcast: broadcast);
    await tester.pump();
    await tester.pump();
    expect(find.text('First community post'), findsOneWidget);
    verifySecondPageRequested();

    broadcast.removePost(
      'at://did:plc:author/social.coves.community.post/gone',
    );
    pageTwo.complete(
      TimelineResponse(
        feed: [
          buildFeedPost(rkey: 'gone', title: 'Removed community post'),
          buildFeedPost(rkey: 'p2', title: 'Second community post'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Removed community post'), findsNothing);
    expect(find.text('First community post'), findsOneWidget);
    expect(find.text('Second community post'), findsOneWidget);
  });

  testWidgets('a reload that fails after an account change is not retried '
      'until the user taps Retry', (tester) async {
    when(mockApiService.getViewerAuthority()).thenAnswer((_) async => false);
    when(mockApiService.getCommunity(community: anyNamed('community')))
        .thenAnswer(
          (_) async => CommunityView(
            did: communityDid,
            name: communityHandle,
            displayName: 'Test Cove',
          ),
        );

    final heldPageTwo = Completer<TimelineResponse>();
    final requestedCursors = <String?>[];
    // What a page-one request gets: the first page, then (after the account
    // change) a failure 150 ms after it is sent, then the retried page.
    var pageOneAnswer = 'first page';
    when(
      mockApiService.getCommunityFeed(
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((invocation) {
      final cursor = invocation.namedArguments[#cursor] as String?;
      requestedCursors.add(cursor);
      if (cursor == 'c1') {
        return heldPageTwo.future;
      }
      return switch (pageOneAnswer) {
        'first page' => Future.value(
          TimelineResponse(
            feed: [
              buildFeedPost(rkey: 'p1', title: 'First community post'),
              buildFeedPost(rkey: 'p2', title: 'Second community post'),
            ],
            cursor: 'c1',
          ),
        ),
        'fails' => Future<TimelineResponse>.delayed(
          const Duration(milliseconds: 150),
          () => throw NetworkException('offline'),
        ),
        _ => Future.value(
          TimelineResponse(
            feed: [buildFeedPost(rkey: 'p3', title: 'Third community post')],
          ),
        ),
      };
    });

    // The throttle reads this clock; every timed pump below advances it by
    // the same amount.
    var now = DateTime.utc(2026, 1, 2);
    Future<void> advance(Duration elapsed) async {
      now = now.add(elapsed);
      await tester.pump(elapsed);
    }

    // Tall enough that the two posts and the footer below them fit.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final auth = FakeAuthProvider(signedInDid: 'did:plc:first');
    await pumpFeedScreen(tester, signedIn: auth, paginationClock: () => now);
    await tester.pump();
    await tester.pump();

    expect(find.text('First community post'), findsOneWidget);
    expect(find.text('Second community post'), findsOneWidget);
    expect(requestedCursors, <String?>[
      null,
      'c1',
    ], reason: 'the viewport-fill load-more for c1 is out');

    pageOneAnswer = 'fails';
    auth.setSignedInDid('did:plc:second');
    final requestsBeforeAccountChange = requestedCursors.length;
    int pageOneRequestsSinceAccountChange() => requestedCursors
        .skip(requestsBeforeAccountChange)
        .where((cursor) => cursor == null)
        .length;

    // The held page lands from the old session and is dropped; the next
    // load-more reloads page one under the new one.
    heldPageTwo.complete(
      TimelineResponse(
        feed: [buildFeedPost(rkey: 'stale', title: 'Old session post')],
        cursor: 'c2',
      ),
    );
    await advance(const Duration(milliseconds: 100));
    expect(
      pageOneRequestsSinceAccountChange(),
      1,
      reason: 'the reload under the new session was sent',
    );

    for (var step = 0; step < 20; step++) {
      await advance(const Duration(milliseconds: 100));
    }

    expect(pageOneRequestsSinceAccountChange(), 1);
    expect(find.text('Old session post'), findsNothing);
    expect(find.text('First community post'), findsOneWidget);
    expect(find.text('Second community post'), findsOneWidget);
    final footer = find.byKey(const ValueKey<String>('community_feed_footer'));
    expect(
      find.descendant(
        of: footer,
        matching: find.text('No connection. Please check your internet.'),
      ),
      findsOneWidget,
    );
    final retry = find.descendant(of: footer, matching: find.text('Retry'));
    expect(retry, findsOneWidget);

    pageOneAnswer = 'retried page';
    await tester.tap(retry);
    await advance(const Duration(milliseconds: 100));

    expect(pageOneRequestsSinceAccountChange(), 2);
    expect(find.text('Third community post'), findsOneWidget);
    expect(find.text('First community post'), findsNothing);
    expect(find.text('Second community post'), findsNothing);
    expect(
      find.text('No connection. Please check your internet.'),
      findsNothing,
    );
  });

  group('collapsed top bar software logo', () {
    void stubBridgedCommunity({String name = 'science'}) {
      when(mockApiService.getCommunity(community: anyNamed('community')))
          .thenAnswer(
            (_) async => CommunityView(
              did: communityDid,
              name: name,
              origin: 'lemmy.world',
              originSoftware: 'lemmy',
            ),
          );
      when(
        mockApiService.getCommunityFeed(
          community: anyNamed('community'),
          sort: anyNamed('sort'),
          timeframe: anyNamed('timeframe'),
          limit: anyNamed('limit'),
        ),
      ).thenAnswer(
        (_) async => TimelineResponse(
          feed: [
            for (var index = 0; index < 20; index++)
              buildFeedPost(rkey: 'p$index', title: 'Post $index'),
          ],
        ),
      );
    }

    Future<DisplayPreferencesProvider> displayWith({
      required bool showSoftwareLogos,
    }) async {
      SharedPreferences.setMockInitialValues({
        DisplayPreferencesProvider.showSoftwareLogosKey: showSoftwareLogos,
      });
      final display = DisplayPreferencesProvider();
      await display.initialize();
      addTearDown(display.dispose);
      return display;
    }

    Future<void> collapse(WidgetTester tester) async {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();
    }

    /// Logos drawn inside the collapsed bar, the top toolbar strip.
    Iterable<Rect> logosInTopBar(WidgetTester tester) {
      final barBottom =
          kToolbarHeight +
          tester.view.padding.top / tester.view.devicePixelRatio;
      return find
          .bySemanticsLabel('Lemmy')
          .evaluate()
          .map((element) => tester.getRect(find.byWidget(element.widget)))
          .where((rect) => rect.top >= 0 && rect.bottom <= barBottom + 1);
    }

    testWidgets('a bridged community shows its logo after the collapsed name', (
      tester,
    ) async {
      stubBridgedCommunity();
      await pumpFeedScreen(
        tester,
        displayPreferences: await displayWith(showSoftwareLogos: true),
      );
      await tester.pumpAndSettle();
      expect(logosInTopBar(tester), isEmpty);

      await collapse(tester);

      final logos = logosInTopBar(tester).toList();
      expect(logos, hasLength(1));
      expect(
        logos.single.left,
        greaterThanOrEqualTo(tester.getRect(find.text('!science')).right),
      );
    });

    testWidgets('a native community has no logo in the collapsed bar', (
      tester,
    ) async {
      stubBridgedCommunity();
      when(mockApiService.getCommunity(community: anyNamed('community')))
          .thenAnswer(
            (_) async => CommunityView(
              did: communityDid,
              name: 'science',
              origin: 'coves.social',
            ),
          );
      await pumpFeedScreen(tester);
      await tester.pumpAndSettle();

      await collapse(tester);

      expect(find.text('!science'), findsOneWidget);
      expect(find.bySemanticsLabel('Lemmy'), findsNothing);
    });

    testWidgets('the collapsed bar logo hides when logos are off', (
      tester,
    ) async {
      stubBridgedCommunity();
      await pumpFeedScreen(
        tester,
        displayPreferences: await displayWith(showSoftwareLogos: false),
      );
      await tester.pumpAndSettle();

      await collapse(tester);

      expect(find.text('!science'), findsOneWidget);
      expect(find.bySemanticsLabel('Lemmy'), findsNothing);
    });

    testWidgets('a long collapsed name ellipsizes and keeps the logo visible', (
      tester,
    ) async {
      const name = 'averyveryverylongcommunitynamethatcannotfitonscreen';
      stubBridgedCommunity(name: name);
      await pumpFeedScreen(
        tester,
        displayPreferences: await displayWith(showSoftwareLogos: true),
      );
      await tester.pumpAndSettle();

      await collapse(tester);

      final title = tester.renderObject<RenderParagraph>(find.text('!$name'));
      expect(title.didExceedMaxLines, isTrue);
      final logos = logosInTopBar(tester).toList();
      expect(logos, hasLength(1));
      final screenWidth =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(logos.single.right, lessThanOrEqualTo(screenWidth));
      expect(tester.takeException(), isNull);
    });
  });

  group('community load error title', () {
    void stubEmptyFeed() {
      when(
        mockApiService.getCommunityFeed(
          community: anyNamed('community'),
          sort: anyNamed('sort'),
          timeframe: anyNamed('timeframe'),
          limit: anyNamed('limit'),
        ),
      ).thenAnswer((_) async => TimelineResponse(feed: []));
    }

    // (case, thrown error, expected title, expected detail line)
    final cases = <(String, Exception, String, String)>[
      (
        'no connection',
        NetworkException('Connection refused'),
        'Failed to load community',
        'No connection. Please check your internet.',
      ),
      (
        'a server error',
        ServerException('Internal error', statusCode: 500),
        'Failed to load community',
        'Server error. Please try again later.',
      ),
      (
        'an unclassified failure',
        Exception('boom'),
        'Failed to load community',
        'Could not load community. Please try again.',
      ),
      (
        'a 404',
        NotFoundException('Community not found'),
        'Community not found',
        'Content not found. It may have been removed.',
      ),
    ];

    for (final (label, error, title, detail) in cases) {
      testWidgets('$label shows "$title" with its detail and Retry', (
        tester,
      ) async {
        when(mockApiService.getCommunity(community: anyNamed('community')))
            .thenThrow(error);
        stubEmptyFeed();

        await pumpFeedScreen(tester);
        await tester.pumpAndSettle();

        expect(find.text(title), findsOneWidget);
        expect(find.text(detail), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        final otherTitle = title == 'Community not found'
            ? 'Failed to load community'
            : 'Community not found';
        expect(find.text(otherTitle), findsNothing);
      });
    }
  });

  group('feed sort header scrolling', () {
    const searchButtonKey = ValueKey<String>('community_feed_search_button');
    const searchFieldKey = ValueKey<String>('community_feed_search_field');

    Future<void> pumpLongFeed(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      when(mockApiService.getCommunity(community: anyNamed('community')))
          .thenAnswer((_) async => buildFeedTestCommunity());
      when(
        mockApiService.getCommunityFeed(
          community: anyNamed('community'),
          sort: anyNamed('sort'),
          timeframe: anyNamed('timeframe'),
          limit: anyNamed('limit'),
          cursor: anyNamed('cursor'),
        ),
      ).thenAnswer(
        (_) async => TimelineResponse(
          feed: [
            for (var i = 0; i < 30; i++)
              buildFeedTestPost(rkey: 'post-$i', title: 'Post $i'),
          ],
        ),
      );

      await pumpCommunityFeedScreen(tester, mockApiService);
      await tester.pumpAndSettle();
    }

    Future<void> scrollFeedDown(WidgetTester tester) async {
      final feed = find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      );
      await tester.drag(feed.first, const Offset(0, -1500));
      await tester.pumpAndSettle();
    }

    testWidgets('the sort chips scroll away with the community header', (
      tester,
    ) async {
      await pumpLongFeed(tester);
      expect(find.text('Hot').hitTestable(), findsOneWidget);

      await scrollFeedDown(tester);

      expect(find.text('Hot').hitTestable(), findsNothing);
      expect(find.byKey(searchButtonKey).hitTestable(), findsNothing);
    });

    testWidgets('an open search field stays on screen while the feed scrolls', (
      tester,
    ) async {
      await pumpLongFeed(tester);
      await tester.tap(find.byKey(searchButtonKey));
      await tester.pumpAndSettle();
      expect(find.byKey(searchFieldKey).hitTestable(), findsOneWidget);

      expect(find.text('Post 0').hitTestable(), findsOneWidget);

      await scrollFeedDown(tester);

      expect(
        find.text('Post 0').hitTestable(),
        findsNothing,
        reason: 'the feed actually scrolled',
      );
      expect(find.byKey(searchFieldKey).hitTestable(), findsOneWidget);
    });
  });
}
