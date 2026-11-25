// The own profile's header collapses away on scroll: once the user scrolls
// down far enough, the top bar (with its Edit Profile / Share / Menu
// actions) is gone entirely and the Posts/Comments/Likes tab bar (key
// 'profile_tab_bar') is pinned at the very top of the screen, directly
// under the status bar. The status-bar inset is left as space above the
// 48px tab strip, so the strip spans inset..inset+48 and the tab labels
// never sit under the status bar. At rest the header is unchanged.

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/screens/home/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/pump_helpers.dart';
import '../test_helpers/test_mocks.dart';

const String myDid = 'did:plc:me';
const String myHandle = 'me.coves.test';

/// The status-bar inset the screen is pumped with.
const double statusBarInset = 24;

/// Where the 'Posts' tab label's vertical center sits below the top edge of
/// the visible 48px tab strip (measured on the at-rest tab bar today).
const double postsLabelCenterInStrip = 20;

/// The distance from the bottom of the joined date (the lowest header text)
/// to the top of the 'Posts' tab label at rest (measured today): the tabs
/// follow the header details with no blank gap.
const double headerToTabsGapAtRest = 22.5;

FeedViewPost _post(int index) {
  final rkey = 'own-$index';
  return FeedViewPost(
    post: PostView(
      uri: 'at://did:plc:community/social.coves.community.post/$rkey',
      cid: 'cid-$rkey',
      rkey: rkey,
      author: AuthorView(did: myDid, handle: myHandle),
      community: CommunityRef(did: 'did:plc:community', name: 'test-community'),
      createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
      indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
      record: PostRecord(title: 'Own post $index', content: 'body $index'),
      stats: PostStats(upvotes: 1, downvotes: 0, score: 1, commentCount: 0),
    ),
  );
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
    when(apiService.getViewerAuthority()).thenAnswer((_) async => false);
    when(apiService.getProfile(actor: myDid)).thenAnswer(
      (_) async => UserProfile(
        did: myDid,
        handle: myHandle,
        bio: 'A short bio',
        createdAt: DateTime.parse('2025-06-15T12:00:00Z'),
      ),
    );
    // Enough own posts to scroll the header far out of view.
    when(
      apiService.getAuthorPosts(
        actor: myDid,
        filter: anyNamed('filter'),
        community: anyNamed('community'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer(
      (_) async =>
          TimelineResponse(feed: [for (var i = 1; i <= 15; i++) _post(i)]),
    );
  });

  tearDown(() {
    authProvider.dispose();
  });

  Future<void> pumpProfile(WidgetTester tester) async {
    tester.view.physicalSize = const Size(540, 960);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(top: statusBarInset);
    tester.view.viewPadding = const FakeViewPadding(top: statusBarInset);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);

    final router = GoRouter(
      initialLocation: '/profile',
      routes: [
        GoRoute(
          path: '/profile',
          builder: (context, state) => const ProfileScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: profileScreenProviders(
          auth: authProvider,
          apiService: apiService,
          commentService: MockCommentService(),
        ),
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await pumpFrames(tester);
  }

  final tabBar = find.byKey(const ValueKey('profile_tab_bar'));
  final postsTabLabel = find.descendant(
    of: tabBar,
    matching: find.text('Posts'),
  );

  /// The vertical distance from the bottom of the lowest header text (the
  /// joined date) to the top of the 'Posts' tab label.
  double headerToTabsGap(WidgetTester tester) {
    return tester.getTopLeft(postsTabLabel).dy -
        tester.getBottomLeft(find.textContaining('Joined')).dy;
  }

  testWidgets('at rest the top bar actions are visible and the tabs follow the '
      'header details', (tester) async {
    await pumpProfile(tester);

    expect(find.byTooltip('Edit Profile').hitTestable(), findsOneWidget);
    expect(find.byTooltip('Menu').hitTestable(), findsOneWidget);
    expect(
      headerToTabsGap(tester),
      moreOrLessEquals(headerToTabsGapAtRest, epsilon: 1),
    );
  });

  testWidgets('after a long scroll the top bar is gone and the tab bar is '
      'pinned directly under the status bar', (tester) async {
    await pumpProfile(tester);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
    await pumpFrames(tester);

    expect(find.byTooltip('Edit Profile').hitTestable(), findsNothing);
    expect(find.byTooltip('Menu').hitTestable(), findsNothing);
    // The label is never under the status bar...
    expect(
      tester.getTopLeft(postsTabLabel).dy,
      greaterThanOrEqualTo(statusBarInset),
    );
    // ...and the 48px strip starts right at the inset: the label sits at the
    // same place within the strip as at rest, offset by the inset only.
    expect(
      tester.getCenter(postsTabLabel).dy,
      moreOrLessEquals(statusBarInset + postsLabelCenterInStrip, epsilon: 1),
    );
  });

  testWidgets('scrolling back to the top brings the top bar back with no gap '
      'above the tabs', (tester) async {
    await pumpProfile(tester);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
    await pumpFrames(tester);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 3000));
    await pumpFrames(tester);

    expect(find.byTooltip('Edit Profile').hitTestable(), findsOneWidget);
    expect(find.byTooltip('Menu').hitTestable(), findsOneWidget);
    expect(
      headerToTabsGap(tester),
      moreOrLessEquals(headerToTabsGapAtRest, epsilon: 1),
    );
  });
}
