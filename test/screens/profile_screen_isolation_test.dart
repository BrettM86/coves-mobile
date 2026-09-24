// Acceptance: every ProfileScreen shows the profile it was opened for.
//
// Two ProfileScreens are on the navigation stack at once in the real app:
// the own Profile tab (`ProfileScreen()`, actor null) and another author's
// page pushed on top of it (`/profile/:actor`). Neither may ever show the
// other's header, posts, or own-profile controls - not while loading, not
// after a failed load, and not after the pushed page is popped.
//
// The tree provides only app-level dependencies (the same set main.dart
// registers). Profile view state is owned by each screen, so no
// UserProfileProvider is provided here.

import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/community_subscription_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/home/profile_screen.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/comment_service.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/profile_cache.dart';
import 'package:coves_flutter/services/streamable_service.dart';
import 'package:coves_flutter/services/viewer_state_hydrator.dart';
import 'package:coves_flutter/widgets/icons/back_icon.dart';
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
const String myDisplayName = 'Me Myself';
const String myPostTitle = 'My own post title';

const String otherDid = 'did:plc:other';
const String otherHandle = 'other.coves.test';
const String otherDisplayName = 'Other Person';
const String otherPostTitle = 'Other author post title';

UserProfile _myProfile() =>
    UserProfile(did: myDid, handle: myHandle, displayName: myDisplayName);

UserProfile _otherProfile() => UserProfile(
  did: otherDid,
  handle: otherHandle,
  displayName: otherDisplayName,
);

FeedViewPost _post({
  required String authorDid,
  required String authorHandle,
  required String rkey,
  required String title,
}) {
  return FeedViewPost(
    post: PostView(
      uri: 'at://did:plc:community/social.coves.community.post/$rkey',
      cid: 'cid-$rkey',
      rkey: rkey,
      author: AuthorView(did: authorDid, handle: authorHandle),
      community: CommunityRef(did: 'did:plc:community', name: 'testcove'),
      createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
      indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
      record: PostRecord(title: title, content: 'Body of $title'),
      stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
    ),
  );
}

/// The own Profile tab's screen.
Finder get _ownScreen => find.byWidgetPredicate(
  (widget) => widget is ProfileScreen && widget.actor == null,
  skipOffstage: false,
);

/// The other author's pushed page.
Finder get _otherScreen => find.byWidgetPredicate(
  (widget) => widget is ProfileScreen && widget.actor == otherDid,
);

Finder _within(Finder scope, Finder matching) =>
    find.descendant(of: scope, matching: matching);

Finder get _editProfileControl => find.byTooltip('Edit Profile');

void main() {
  late FakeAuthProvider authProvider;
  late MockCovesApiService apiService;
  late MockCommentService commentService;

  /// When non-null, other's getProfile answers with this future instead of
  /// resolving immediately.
  Completer<UserProfile>? otherProfileCompleter;

  setUp(() {
    authProvider = FakeAuthProvider(
      signedInDid: myDid,
      signedInHandle: myHandle,
    );
    apiService = MockCovesApiService();
    commentService = MockCommentService();
    otherProfileCompleter = null;

    when(apiService.getProfile(actor: anyNamed('actor'))).thenAnswer((
      invocation,
    ) {
      final actor = invocation.namedArguments[#actor] as String;
      if (actor == myDid) {
        return Future.value(_myProfile());
      }
      if (actor == otherDid) {
        return otherProfileCompleter?.future ?? Future.value(_otherProfile());
      }
      throw StateError('Unexpected getProfile actor: $actor');
    });

    when(
      apiService.getAuthorPosts(
        actor: anyNamed('actor'),
        filter: anyNamed('filter'),
        community: anyNamed('community'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((invocation) async {
      final actor = invocation.namedArguments[#actor] as String;
      if (actor == myDid) {
        return TimelineResponse(
          feed: [
            _post(
              authorDid: myDid,
              authorHandle: myHandle,
              rkey: 'mine',
              title: myPostTitle,
            ),
          ],
        );
      }
      if (actor == otherDid) {
        return TimelineResponse(
          feed: [
            _post(
              authorDid: otherDid,
              authorHandle: otherHandle,
              rkey: 'theirs',
              title: otherPostTitle,
            ),
          ],
        );
      }
      throw StateError('Unexpected getAuthorPosts actor: $actor');
    });
  });

  tearDown(() {
    authProvider.dispose();
  });

  /// Pumps the app with the own profile at `/feed` (standing in for the
  /// Profile tab) and the real `/profile/:actor` route for other authors.
  Future<GoRouter> pumpApp(WidgetTester tester) async {
    // Phone layout
    tester.view.physicalSize = const Size(540, 960);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/feed',
      routes: [
        GoRoute(
          path: '/feed',
          builder: (context, state) => const ProfileScreen(),
        ),
        GoRoute(
          path: '/profile/:actor',
          builder: (context, state) =>
              ProfileScreen(actor: state.pathParameters['actor']),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          Provider<CovesApiService>.value(value: apiService),
          Provider<CommentService>.value(value: commentService),
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
            create: (_) => BlockProvider(
              apiService: apiService,
              authProvider: authProvider,
            ),
          ),
          Provider<ViewerStateHydrator>(
            create: (context) => ViewerStateHydrator(
              authProvider: authProvider,
              voteProvider: context.read<VoteProvider>(),
            ),
          ),
          Provider<StreamableService>.value(value: StreamableService()),
          Provider<ProfileCache>(
            create: (_) => ProfileCache(authProvider),
            dispose: (_, cache) => cache.dispose(),
          ),
        ],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await pumpFrames(tester);
    return router;
  }

  void expectOwnScreenShowsOnlyMine(WidgetTester tester) {
    expect(_ownScreen, findsOneWidget);
    expect(_within(_ownScreen, find.text('@$myHandle')), findsWidgets);
    expect(_within(_ownScreen, find.text(myPostTitle)), findsOneWidget);
    expect(_within(_ownScreen, _editProfileControl), findsOneWidget);

    expect(_within(_ownScreen, find.text('@$otherHandle')), findsNothing);
    expect(_within(_ownScreen, find.text(otherDid)), findsNothing);
    expect(_within(_ownScreen, find.text(otherPostTitle)), findsNothing);
  }

  void expectOtherScreenShowsNothingOfMine() {
    expect(_otherScreen, findsOneWidget);
    expect(_within(_otherScreen, find.text('@$myHandle')), findsNothing);
    expect(_within(_otherScreen, find.text(myDid)), findsNothing);
    expect(_within(_otherScreen, find.text(myDisplayName)), findsNothing);
    expect(_within(_otherScreen, find.text(myPostTitle)), findsNothing);
    expect(_within(_otherScreen, _editProfileControl), findsNothing);
  }

  Future<void> tapBackOnOtherScreen(WidgetTester tester) async {
    await tester.tap(_within(_otherScreen, find.byType(BackIcon)));
    await pumpFrames(tester);
  }

  testWidgets('own profile keeps my header, posts, and edit control after '
      "another author's page is pushed on top and popped", (tester) async {
    final router = await pumpApp(tester);

    expectOwnScreenShowsOnlyMine(tester);

    unawaited(router.push('/profile/$otherDid'));
    await pumpFrames(tester);

    expectOtherScreenShowsNothingOfMine();
    expect(_within(_otherScreen, find.text('@$otherHandle')), findsWidgets);
    expect(_within(_otherScreen, find.text(otherPostTitle)), findsOneWidget);

    await tapBackOnOtherScreen(tester);

    expect(_otherScreen, findsNothing);
    expectOwnScreenShowsOnlyMine(tester);
  });

  testWidgets("another author's page never shows my profile while its load "
      'is pending, nor after it fails', (tester) async {
    final router = await pumpApp(tester);
    expectOwnScreenShowsOnlyMine(tester);

    final completer = Completer<UserProfile>();
    otherProfileCompleter = completer;

    unawaited(router.push('/profile/$otherDid'));

    // Check each frame of the push while the request is outstanding.
    await tester.pump();
    expectOtherScreenShowsNothingOfMine();
    await tester.pump();
    expectOtherScreenShowsNothingOfMine();
    await tester.pump(const Duration(milliseconds: 600));
    expectOtherScreenShowsNothingOfMine();
    expect(
      _within(_otherScreen, find.byType(CircularProgressIndicator)),
      findsWidgets,
    );

    completer.completeError(NetworkException('Connection refused'));
    await pumpFrames(tester);

    expect(
      _within(_otherScreen, find.text('Failed to load profile')),
      findsOneWidget,
    );
    expectOtherScreenShowsNothingOfMine();
    expect(tester.takeException(), isNull);
  });

  testWidgets("popping another author's page while its profile is still "
      'loading, then completing that load, leaves my profile unchanged', (
    tester,
  ) async {
    final router = await pumpApp(tester);
    expectOwnScreenShowsOnlyMine(tester);

    final completer = Completer<UserProfile>();
    otherProfileCompleter = completer;

    unawaited(router.push('/profile/$otherDid'));
    await pumpFrames(tester);
    expectOtherScreenShowsNothingOfMine();

    await tapBackOnOtherScreen(tester);
    expect(_otherScreen, findsNothing);

    completer.complete(_otherProfile());
    await pumpFrames(tester);

    expect(tester.takeException(), isNull);
    expectOwnScreenShowsOnlyMine(tester);
    // The abandoned page's late profile must not start its posts load.
    verifyNever(
      apiService.getAuthorPosts(
        actor: argThat(equals(otherDid), named: 'actor'),
        filter: anyNamed('filter'),
        community: anyNamed('community'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    );
  });
}
