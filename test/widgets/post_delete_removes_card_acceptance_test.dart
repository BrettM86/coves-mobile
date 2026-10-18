// Acceptance: deleting a post from its feed card removes that card from the
// feed it was deleted from, without refetching the feed.
//
// The author opens the card's overflow menu, taps "Delete post" and confirms
// with "Delete". Once `CovesApiService.deletePost` succeeds, the deleted
// post's card must be gone from the list and the other post's card must
// stay, on every feed surface a card lives on:
//
//   * home (Discover and For You, both backed by the app-wide
//     MultiFeedProvider): the post leaves both tabs, including the one the
//     author did not delete it from;
//   * a community feed (the screen's own pagination controller);
//   * the author's own profile, Posts tab (the screen's UserProfileProvider).
//
// A post deleted from a community feed pushed over Home, or from the Profile
// tab, also leaves the home feeds (Discover and For You), which stay alive
// underneath on the app-wide MultiFeedProvider.
//
// Each surface runs on its real screen and real feed owner. Only the API
// boundary is mocked. Every fixture page has a null cursor, so no list ever
// pages on its own, and the feed fetch count is pinned: removing the card
// must not cost a refetch.

import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/community.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/community_subscription_provider.dart';
import 'package:coves_flutter/providers/multi_feed_provider.dart';
import 'package:coves_flutter/providers/viewer_authority_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/community/community_feed_screen.dart';
import 'package:coves_flutter/screens/home/feed_screen.dart';
import 'package:coves_flutter/screens/home/main_shell_screen.dart';
import 'package:coves_flutter/screens/home/profile_screen.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/post_change_broadcast.dart';
import 'package:coves_flutter/services/streamable_service.dart';
import 'package:coves_flutter/services/viewer_state_hydrator.dart';
import 'package:coves_flutter/widgets/feed_page.dart';
import 'package:coves_flutter/widgets/post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/test_mocks.dart';

const String myDid = 'did:plc:me';
const String myHandle = 'me.coves.test';
const String otherDid = 'did:plc:other';
const String otherHandle = 'other.coves.test';
const String communityDid = 'did:plc:community';
const String communityHandle = 'testcove';

/// The signed-in author's post, the one deleted in every case.
const String deletedPostUri =
    'at://did:plc:community/social.coves.community.post/deleted';

/// The post that must survive the deletion.
const String keptPostUri =
    'at://did:plc:community/social.coves.community.post/kept';

FeedViewPost _post({
  required String uri,
  required String rkey,
  required String authorDid,
  required String authorHandle,
  required String title,
}) {
  return FeedViewPost(
    post: PostView(
      uri: uri,
      cid: 'cid-$rkey',
      rkey: rkey,
      author: AuthorView(did: authorDid, handle: authorHandle),
      community: CommunityRef(did: communityDid, name: communityHandle),
      createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
      indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
      record: PostRecord(title: title, content: 'Body of $title'),
      stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
    ),
  );
}

/// Post A: written by the signed-in user, so its menu offers "Delete post".
FeedViewPost _deletedPost() => _post(
  uri: deletedPostUri,
  rkey: 'deleted',
  authorDid: myDid,
  authorHandle: myHandle,
  title: 'Post to delete',
);

/// Post B, by [authorDid]: someone else on shared feeds, the author on
/// their own profile.
FeedViewPost _keptPost({
  String authorDid = otherDid,
  String authorHandle = otherHandle,
}) => _post(
  uri: keptPostUri,
  rkey: 'kept',
  authorDid: authorDid,
  authorHandle: authorHandle,
  title: 'Post that stays',
);

/// The rendered [PostCard] for the post at [uri], anywhere under [within]
/// (the whole tree when null). Offstage cards count, so an "absent" check
/// also catches a card kept alive off screen.
Finder _postCard(String uri, {Finder? within}) {
  final card = find.byWidgetPredicate(
    (widget) => widget is PostCard && widget.post.post.uri == uri,
    skipOffstage: false,
  );
  if (within == null) {
    return card;
  }
  return find.descendant(of: within, matching: card, skipOffstage: false);
}

/// The home [FeedPage] rendering [feedType].
Finder _feedPage(FeedType feedType) => find.byWidgetPredicate(
  (widget) => widget is FeedPage && widget.feedType == feedType,
  skipOffstage: false,
);

/// A tall phone layout, so both cards sit on screen below each surface's
/// header without scrolling.
void _usePhoneLayout(WidgetTester tester) {
  tester.view.physicalSize = const Size(540, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// The delete flow awaits HapticFeedback; without a handler the platform
/// channel call never completes in tests.
void _answerPlatformChannel(WidgetTester tester) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (methodCall) async => null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
}

/// Opens [card]'s overflow menu, taps "Delete post" and confirms.
Future<void> _deleteFromCard(WidgetTester tester, Finder card) async {
  final menuButton = find.descendant(
    of: card,
    matching: find.byTooltip('Post options'),
  );
  expect(menuButton, findsOneWidget);
  await tester.tap(menuButton);
  await tester.pumpAndSettle();

  await tester.tap(find.text('Delete post'));
  await tester.pumpAndSettle();

  expect(find.text('Delete Post'), findsOneWidget);
  await tester.tap(find.text('Delete'));
  await tester.pumpAndSettle();
}

/// The app-level wiring main.dart registers for the home and community
/// feeds, with the real app-wide MultiFeedProvider over the mocked API.
List<SingleChildWidget> _appProviders({
  required AuthProvider authProvider,
  required CovesApiService apiService,
}) {
  return [
    Provider<CovesApiService>.value(value: apiService),
    ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
    ChangeNotifierProvider<VoteProvider>(
      create: (_) => FakeVoteProvider(authProvider),
    ),
    ChangeNotifierProvider<CommunitySubscriptionProvider>(
      create: (_) => FakeSubscriptionProvider(
        authProvider: authProvider,
        apiService: apiService,
      ),
    ),
    ChangeNotifierProvider<BlockProvider>(
      create: (_) =>
          BlockProvider(apiService: apiService, authProvider: authProvider),
    ),
    Provider<ViewerStateHydrator>(
      create: (context) => ViewerStateHydrator(
        authProvider: authProvider,
        voteProvider: context.read<VoteProvider>(),
        subscriptionProvider: context.read<CommunitySubscriptionProvider>(),
      ),
    ),
    Provider<PostChangeBroadcast>(create: (_) => PostChangeBroadcast()),
    viewerAuthorityRegistration(auth: authProvider, apiService: apiService),
    ChangeNotifierProvider<MultiFeedProvider>(
      create: (context) {
        final authority = context.read<ViewerAuthorityProvider>();
        return MultiFeedProvider(
          authProvider,
          apiService: apiService,
          hydrator: context.read<ViewerStateHydrator>(),
          postChangeBroadcast: context.read<PostChangeBroadcast>(),
          sessionKeyOf: () => authority.sessionKey,
        );
      },
    ),
    Provider<StreamableService>.value(value: StreamableService()),
  ];
}

void main() {
  late FakeAuthProvider authProvider;
  late MockCovesApiService apiService;

  setUp(() {
    authProvider = FakeAuthProvider(
      signedInDid: myDid,
      signedInHandle: myHandle,
    );
    apiService = MockCovesApiService();
    when(apiService.deletePost(uri: anyNamed('uri'))).thenAnswer((_) async {});
    when(apiService.getViewerAuthority()).thenAnswer((_) async => false);
  });

  tearDown(() {
    authProvider.dispose();
  });

  void expectDeletedOnceWithDeletedPostUri() {
    expect(
      verify(apiService.deletePost(uri: captureAnyNamed('uri'))).captured,
      [deletedPostUri],
    );
  }

  testWidgets('home: deleting a post from Discover removes its card there '
      'and from For You, without refetching either feed', (tester) async {
    _usePhoneLayout(tester);
    _answerPlatformChannel(tester);

    var discoverFetches = 0;
    var timelineFetches = 0;
    when(
      apiService.getDiscover(
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((_) async {
      discoverFetches++;
      return TimelineResponse(feed: [_deletedPost(), _keptPost()]);
    });
    when(
      apiService.getTimeline(
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((_) async {
      timelineFetches++;
      return TimelineResponse(feed: [_deletedPost(), _keptPost()]);
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: _appProviders(
          authProvider: authProvider,
          apiService: apiService,
        ),
        child: MaterialApp(theme: AppTheme.dark, home: const FeedScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final discoverFetchesAfterLoad = discoverFetches;
    final timelineFetchesAfterLoad = timelineFetches;

    final discoverPage = _feedPage(FeedType.discover);
    final forYouPage = _feedPage(FeedType.forYou);

    // Both tabs show both posts before the delete.
    expect(_postCard(deletedPostUri, within: discoverPage), findsOneWidget);
    expect(_postCard(keptPostUri, within: discoverPage), findsOneWidget);

    await tester.tap(find.text('For You'));
    await tester.pumpAndSettle();
    expect(_postCard(deletedPostUri, within: forYouPage), findsOneWidget);
    expect(_postCard(keptPostUri, within: forYouPage), findsOneWidget);

    await tester.tap(find.text('Discover'));
    await tester.pumpAndSettle();

    await _deleteFromCard(
      tester,
      _postCard(deletedPostUri, within: discoverPage),
    );

    expectDeletedOnceWithDeletedPostUri();
    expect(_postCard(deletedPostUri, within: discoverPage), findsNothing);
    expect(_postCard(keptPostUri, within: discoverPage), findsOneWidget);

    // The author switches to the other tab: the post is gone there too.
    await tester.tap(find.text('For You'));
    await tester.pumpAndSettle();
    expect(_postCard(deletedPostUri, within: forYouPage), findsNothing);
    expect(_postCard(keptPostUri, within: forYouPage), findsOneWidget);

    expect(discoverFetches, discoverFetchesAfterLoad);
    expect(timelineFetches, timelineFetchesAfterLoad);
    expect(tester.takeException(), isNull);
  });

  testWidgets('community feed: deleting a post removes its card without '
      'refetching the feed', (tester) async {
    _usePhoneLayout(tester);
    _answerPlatformChannel(tester);

    when(apiService.getCommunity(community: anyNamed('community'))).thenAnswer(
      (_) async => CommunityView(
        did: communityDid,
        name: communityHandle,
        displayName: 'Test Cove',
      ),
    );
    var communityFeedFetches = 0;
    when(
      apiService.getCommunityFeed(
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((_) async {
      communityFeedFetches++;
      return TimelineResponse(feed: [_deletedPost(), _keptPost()]);
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: _appProviders(
          authProvider: authProvider,
          apiService: apiService,
        ),
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const CommunityFeedScreen(identifier: communityDid),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final communityFeedFetchesAfterLoad = communityFeedFetches;

    expect(_postCard(deletedPostUri), findsOneWidget);
    expect(_postCard(keptPostUri), findsOneWidget);

    await _deleteFromCard(tester, _postCard(deletedPostUri));

    expectDeletedOnceWithDeletedPostUri();
    expect(_postCard(deletedPostUri), findsNothing);
    expect(_postCard(keptPostUri), findsOneWidget);
    expect(communityFeedFetches, communityFeedFetchesAfterLoad);
    expect(tester.takeException(), isNull);
  });

  testWidgets("profile: deleting a post from the author's own Posts tab "
      'removes its card without refetching the posts', (tester) async {
    _usePhoneLayout(tester);
    _answerPlatformChannel(tester);

    when(apiService.getProfile(actor: myDid))
        .thenAnswer((_) async => UserProfile(did: myDid, handle: myHandle));
    var authorPostsFetches = 0;
    when(
      apiService.getAuthorPosts(
        actor: myDid,
        filter: anyNamed('filter'),
        community: anyNamed('community'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((_) async {
      authorPostsFetches++;
      return TimelineResponse(
        feed: [
          _deletedPost(),
          _keptPost(authorDid: myDid, authorHandle: myHandle),
        ],
      );
    });

    // App-level dependencies only: the screen owns its UserProfileProvider.
    await tester.pumpWidget(
      MultiProvider(
        providers: profileScreenProviders(
          auth: authProvider,
          apiService: apiService,
          commentService: MockCommentService(),
        ),
        child: MaterialApp(theme: AppTheme.dark, home: const ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final authorPostsFetchesAfterLoad = authorPostsFetches;

    expect(_postCard(deletedPostUri), findsOneWidget);
    expect(_postCard(keptPostUri), findsOneWidget);

    await _deleteFromCard(tester, _postCard(deletedPostUri));

    expectDeletedOnceWithDeletedPostUri();
    expect(_postCard(deletedPostUri), findsNothing);
    expect(_postCard(keptPostUri), findsOneWidget);
    expect(authorPostsFetches, authorPostsFetchesAfterLoad);
    expect(tester.takeException(), isNull);
  });

  group('a delete elsewhere also leaves the kept-alive home feeds', () {
    // Every feed fetch keeps returning the deleted post, and the fetch counts
    // are pinned: a card that leaves Home was removed by the delete, not by
    // a refetch.
    late int discoverFetches;
    late int timelineFetches;

    setUp(() {
      discoverFetches = 0;
      timelineFetches = 0;
      when(
        apiService.getDiscover(
          sort: anyNamed('sort'),
          timeframe: anyNamed('timeframe'),
          limit: anyNamed('limit'),
          cursor: anyNamed('cursor'),
        ),
      ).thenAnswer((_) async {
        discoverFetches++;
        return TimelineResponse(feed: [_deletedPost(), _keptPost()]);
      });
      when(
        apiService.getTimeline(
          sort: anyNamed('sort'),
          timeframe: anyNamed('timeframe'),
          limit: anyNamed('limit'),
          cursor: anyNamed('cursor'),
        ),
      ).thenAnswer((_) async {
        timelineFetches++;
        return TimelineResponse(feed: [_deletedPost(), _keptPost()]);
      });
    });

    /// Both home tabs show both posts; leaves Discover selected.
    Future<void> expectHomeShowsBothPostsInBothTabs(WidgetTester tester) async {
      expect(
        _postCard(deletedPostUri, within: _feedPage(FeedType.discover)),
        findsOneWidget,
      );
      await tester.tap(find.text('For You'));
      await tester.pumpAndSettle();
      expect(
        _postCard(deletedPostUri, within: _feedPage(FeedType.forYou)),
        findsOneWidget,
      );
      await tester.tap(find.text('Discover'));
      await tester.pumpAndSettle();
    }

    /// The deleted post is gone from both home tabs, the kept post stays,
    /// and neither home feed was refetched after [discoverFetchesAfterLoad]
    /// and [timelineFetchesAfterLoad].
    Future<void> expectHomeDropsOnlyTheDeletedPost(
      WidgetTester tester, {
      required int discoverFetchesAfterLoad,
      required int timelineFetchesAfterLoad,
    }) async {
      final discoverPage = _feedPage(FeedType.discover);
      expect(_postCard(deletedPostUri, within: discoverPage), findsNothing);
      expect(_postCard(keptPostUri, within: discoverPage), findsOneWidget);

      await tester.tap(find.text('For You'));
      await tester.pumpAndSettle();
      final forYouPage = _feedPage(FeedType.forYou);
      expect(_postCard(deletedPostUri, within: forYouPage), findsNothing);
      expect(_postCard(keptPostUri, within: forYouPage), findsOneWidget);

      expect(discoverFetches, discoverFetchesAfterLoad);
      expect(timelineFetches, timelineFetchesAfterLoad);
    }

    testWidgets('from a community feed pushed over Home: after going back, '
        'the card is gone from Discover and For You', (tester) async {
      _usePhoneLayout(tester);
      _answerPlatformChannel(tester);

      when(apiService.getCommunity(community: anyNamed('community')))
          .thenAnswer(
            (_) async => CommunityView(
              did: communityDid,
              name: communityHandle,
              displayName: 'Test Cove',
            ),
          );
      when(
        apiService.getCommunityFeed(
          community: anyNamed('community'),
          sort: anyNamed('sort'),
          timeframe: anyNamed('timeframe'),
          limit: anyNamed('limit'),
          cursor: anyNamed('cursor'),
        ),
      ).thenAnswer(
        (_) async => TimelineResponse(feed: [_deletedPost(), _keptPost()]),
      );

      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MultiProvider(
          providers: _appProviders(
            authProvider: authProvider,
            apiService: apiService,
          ),
          child: MaterialApp(
            theme: AppTheme.dark,
            navigatorKey: navigatorKey,
            home: const FeedScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final discoverFetchesAfterLoad = discoverFetches;
      final timelineFetchesAfterLoad = timelineFetches;
      await expectHomeShowsBothPostsInBothTabs(tester);

      unawaited(
        navigatorKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const CommunityFeedScreen(identifier: communityDid),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final communityScreen = find.byType(CommunityFeedScreen);
      await _deleteFromCard(
        tester,
        _postCard(deletedPostUri, within: communityScreen),
      );
      expectDeletedOnceWithDeletedPostUri();
      expect(_postCard(deletedPostUri, within: communityScreen), findsNothing);

      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(communityScreen, findsNothing);

      await expectHomeDropsOnlyTheDeletedPost(
        tester,
        discoverFetchesAfterLoad: discoverFetchesAfterLoad,
        timelineFetchesAfterLoad: timelineFetchesAfterLoad,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('from the Profile tab: back on the Home tab, the card is gone '
        'from Discover and For You', (tester) async {
      _usePhoneLayout(tester);
      _answerPlatformChannel(tester);

      when(apiService.getProfile(actor: myDid))
          .thenAnswer((_) async => UserProfile(did: myDid, handle: myHandle));
      when(
        apiService.getAuthorPosts(
          actor: myDid,
          filter: anyNamed('filter'),
          community: anyNamed('community'),
          limit: anyNamed('limit'),
          cursor: anyNamed('cursor'),
        ),
      ).thenAnswer(
        (_) async => TimelineResponse(
          feed: [
            _deletedPost(),
            _keptPost(authorDid: myDid, authorHandle: myHandle),
          ],
        ),
      );

      // The shell keeps Home alive in its IndexedStack while the Profile tab
      // is shown, as the app does.
      await tester.pumpWidget(
        MultiProvider(
          providers: profileScreenProviders(
            auth: authProvider,
            apiService: apiService,
            commentService: MockCommentService(),
          ),
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const MainShellScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final discoverFetchesAfterLoad = discoverFetches;
      final timelineFetchesAfterLoad = timelineFetches;
      await expectHomeShowsBothPostsInBothTabs(tester);

      Finder navItem(String label) => find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == label,
      );

      await tester.tap(navItem('Me'));
      await tester.pumpAndSettle();

      final profileScreen = find.byType(ProfileScreen);
      await _deleteFromCard(
        tester,
        _postCard(deletedPostUri, within: profileScreen),
      );
      expectDeletedOnceWithDeletedPostUri();
      expect(_postCard(deletedPostUri, within: profileScreen), findsNothing);

      await tester.tap(navItem('Home'));
      await tester.pumpAndSettle();

      await expectHomeDropsOnlyTheDeletedPost(
        tester,
        discoverFetchesAfterLoad: discoverFetchesAfterLoad,
        timelineFetchesAfterLoad: timelineFetchesAfterLoad,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
