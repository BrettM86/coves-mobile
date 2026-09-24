// A pushed ProfileScreen recovers from a session that ends mid-load and
// from a failed first load.
//
// When the signed-in session ends while the profile is loading, the screen
// shows an actionable error instead of a blank page. Its Retry reruns the
// full screen load: profile, block-state seeding, and posts, for the actor
// the screen was opened with (DID or handle).
//
// The tree provides only app-level dependencies (the same set main.dart
// registers); no UserProfileProvider is provided here.

import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/screens/home/profile_screen.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/pump_helpers.dart';
import '../test_helpers/test_mocks.dart';

const String myDid = 'did:plc:me';

const String otherDid = 'did:plc:other';
const String otherHandle = 'other.coves.test';
const String otherPostTitle = 'Other author post title';

const String sessionChangedMessage =
    'Your session changed. Retry to reload this profile.';

UserProfile _otherProfile({bool blocked = false}) => UserProfile(
  did: otherDid,
  handle: otherHandle,
  viewer: blocked
      ? ProfileViewerState(
          blocked: true,
          blockUri: 'at://$myDid/social.coves.actor.block/other',
        )
      : null,
);

FeedViewPost _otherPost() {
  return FeedViewPost(
    post: PostView(
      uri: 'at://did:plc:community/social.coves.community.post/theirs',
      cid: 'cid-theirs',
      rkey: 'theirs',
      author: AuthorView(did: otherDid, handle: otherHandle),
      community: CommunityRef(did: 'did:plc:community', name: 'testcove'),
      createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
      indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
      record: const PostRecord(
        title: otherPostTitle,
        content: 'Body of $otherPostTitle',
      ),
      stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
    ),
  );
}

CommentView _otherComment(String rkey, String content) {
  return CommentView(
    uri: 'at://$otherDid/social.coves.community.comment/$rkey',
    cid: 'cid-$rkey',
    record: CommentRecord(content: content),
    createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
    indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
    author: AuthorView(did: otherDid, handle: otherHandle),
    post: CommentRef(
      uri: 'at://did:plc:community/social.coves.community.post/parent',
      cid: 'cid-parent',
    ),
    stats: const CommentStats(score: 1, upvotes: 1),
  );
}

Finder get _retryButton => find.widgetWithText(ElevatedButton, 'Retry');

void main() {
  late FakeAuthProvider authProvider;
  late MockCovesApiService apiService;

  /// getProfile answers, in call order.
  late List<Future<UserProfile> Function()> profileResponses;

  setUp(() {
    authProvider = FakeAuthProvider(signedInDid: myDid);
    apiService = MockCovesApiService();
    profileResponses = [];

    when(apiService.getProfile(actor: anyNamed('actor'))).thenAnswer((_) {
      if (profileResponses.isEmpty) {
        throw StateError('Unexpected extra getProfile call');
      }
      return profileResponses.removeAt(0)();
    });

    when(
      apiService.getAuthorPosts(
        actor: anyNamed('actor'),
        filter: anyNamed('filter'),
        community: anyNamed('community'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((_) async => TimelineResponse(feed: [_otherPost()]));
  });

  tearDown(() {
    authProvider.dispose();
  });

  /// Pumps the app on a placeholder home and pushes the real
  /// `/profile/:actor` route for [actor].
  Future<void> pumpPushedProfile(WidgetTester tester, String actor) async {
    // Phone layout
    tester.view.physicalSize = const Size(540, 960);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (context, state) =>
              const Scaffold(body: Text('Home placeholder')),
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
        providers: profileScreenProviders(
          auth: authProvider,
          apiService: apiService,
          commentService: MockCommentService(),
        ),
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await pumpFrames(tester);

    unawaited(router.push('/profile/$actor'));
    await pumpFrames(tester);
  }

  void verifyAuthorPostsNeverRequested() {
    verifyNever(
      apiService.getAuthorPosts(
        actor: anyNamed('actor'),
        filter: anyNamed('filter'),
        community: anyNamed('community'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    );
  }

  void verifyAuthorPostsRequestedForOther() {
    verify(
      apiService.getAuthorPosts(
        actor: argThat(equals(otherDid), named: 'actor'),
        filter: anyNamed('filter'),
        community: anyNamed('community'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).called(greaterThanOrEqualTo(1));
  }

  void expectOtherProfileWithPosts() {
    expect(find.text('Failed to load profile'), findsNothing);
    expect(find.text('@$otherHandle'), findsWidgets);
    expect(find.text(otherPostTitle), findsOneWidget);
  }

  group('ProfileScreen when the session ends during the first load', () {
    testWidgets('shows the session-changed error with Retry, never a blank '
        'page, and Retry loads the profile and its posts', (tester) async {
      final pendingProfile = Completer<UserProfile>();
      profileResponses
        ..add(() => pendingProfile.future)
        ..add(() => Future.value(_otherProfile()));

      await pumpPushedProfile(tester, otherDid);
      expect(
        find.byType(CircularProgressIndicator),
        findsWidgets,
        reason: 'precondition: the profile load is pending',
      );

      authProvider.setSignedInDid(null);
      await pumpFrames(tester);

      expect(find.text('Failed to load profile'), findsOneWidget);
      expect(find.text(sessionChangedMessage), findsOneWidget);
      expect(_retryButton, findsOneWidget);
      expect(find.text('No profile loaded'), findsNothing);

      pendingProfile.completeError(AuthenticationException('Session expired'));
      await pumpFrames(tester);

      expect(find.text('Failed to load profile'), findsOneWidget);
      expect(find.text(sessionChangedMessage), findsOneWidget);
      expect(_retryButton, findsOneWidget);
      expect(find.text('No profile loaded'), findsNothing);
      verifyAuthorPostsNeverRequested();

      await tester.tap(_retryButton);
      await pumpFrames(tester);

      expectOtherProfileWithPosts();
      verifyAuthorPostsRequestedForOther();
      expect(tester.takeException(), isNull);
    });
  });

  group('ProfileScreen Retry after a session change with comments '
      'loaded', () {
    const commentAText = 'Comment A before the session change';
    const commentBText = 'Comment B after Retry';
    const anotherDid = 'did:plc:another-account';

    /// getActorComments answers with these comments; tests replace them.
    late List<CommentView> actorComments;

    setUp(() {
      actorComments = [_otherComment('a', commentAText)];
      when(
        apiService.getActorComments(
          actor: anyNamed('actor'),
          community: anyNamed('community'),
          limit: anyNamed('limit'),
          cursor: anyNamed('cursor'),
        ),
      ).thenAnswer(
        (_) async => ActorCommentsResponse(comments: List.of(actorComments)),
      );
    });

    /// Verifies [count] unverified first-page comment requests for other.
    void verifyFirstCommentsPageRequested(int count) {
      verify(
        apiService.getActorComments(
          actor: otherDid,
          community: anyNamed('community'),
          limit: anyNamed('limit'),
          cursor: argThat(isNull, named: 'cursor'),
        ),
      ).called(count);
    }

    void verifyNoCommentsRequest() {
      verifyNever(
        apiService.getActorComments(
          actor: anyNamed('actor'),
          community: anyNamed('community'),
          limit: anyNamed('limit'),
          cursor: anyNamed('cursor'),
        ),
      );
    }

    /// Whether the profile tab labeled [label] is the selected one (the
    /// selected tab's label is bold).
    bool isTabSelected(WidgetTester tester, String label) {
      final labelText = tester.widget<Text>(find.text(label));
      return labelText.style?.fontWeight == FontWeight.bold;
    }

    /// Pushes other's profile with posts loaded, opens Comments (comment A),
    /// then switches the signed-in account so the session-changed error
    /// shows. [backToPosts] switches back to Posts before the switch.
    Future<void> loadCommentsThenChangeSession(
      WidgetTester tester, {
      required Future<UserProfile> Function() retryProfileResponse,
      bool backToPosts = false,
    }) async {
      profileResponses
        ..add(() => Future.value(_otherProfile()))
        ..add(retryProfileResponse);

      await pumpPushedProfile(tester, otherDid);
      expectOtherProfileWithPosts();

      await tester.tap(find.text('Comments'));
      await pumpFrames(tester);
      verifyFirstCommentsPageRequested(1);
      expect(find.text(commentAText), findsOneWidget, reason: 'precondition');

      if (backToPosts) {
        await tester.tap(find.text('Posts'));
        await pumpFrames(tester);
        expect(isTabSelected(tester, 'Posts'), isTrue, reason: 'precondition');
      }

      authProvider.setSignedInDid(anotherDid);
      await pumpFrames(tester);
      expect(find.text(sessionChangedMessage), findsOneWidget);
      expect(_retryButton, findsOneWidget);
    }

    testWidgets('Retry with the Comments tab selected requests the first '
        'comments page again and shows the comments', (tester) async {
      await loadCommentsThenChangeSession(
        tester,
        retryProfileResponse: () => Future.value(_otherProfile()),
      );

      actorComments = [_otherComment('b', commentBText)];
      await tester.tap(_retryButton);
      await pumpFrames(tester);

      expect(isTabSelected(tester, 'Comments'), isTrue);
      verifyFirstCommentsPageRequested(1);
      expect(find.text(commentBText), findsOneWidget);
      expect(find.text('No comments yet'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Retry with the Posts tab selected loads no comments until '
        'Comments is tapped, which requests and shows them', (tester) async {
      await loadCommentsThenChangeSession(
        tester,
        retryProfileResponse: () => Future.value(_otherProfile()),
        backToPosts: true,
      );

      actorComments = [_otherComment('b', commentBText)];
      await tester.tap(_retryButton);
      await pumpFrames(tester);

      expect(isTabSelected(tester, 'Posts'), isTrue);
      expectOtherProfileWithPosts();
      verifyNoCommentsRequest();

      await tester.tap(find.text('Comments'));
      await pumpFrames(tester);

      verifyFirstCommentsPageRequested(1);
      expect(find.text(commentBText), findsOneWidget);
      expect(find.text('No comments yet'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failed Retry with the Comments tab selected requests no '
        'comments and keeps the error with Retry', (tester) async {
      await loadCommentsThenChangeSession(
        tester,
        retryProfileResponse: () =>
            Future.error(NetworkException('Connection refused')),
      );

      await tester.tap(_retryButton);
      await pumpFrames(tester);

      verifyNoCommentsRequest();
      expect(find.text('Failed to load profile'), findsOneWidget);
      expect(_retryButton, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('ProfileScreen Retry after a failed first load', () {
    testWidgets('reruns the full load: header, posts, and seeded block '
        'state', (tester) async {
      profileResponses
        ..add(() => Future.error(NetworkException('Connection refused')))
        ..add(() => Future.value(_otherProfile(blocked: true)));

      await pumpPushedProfile(tester, otherDid);
      expect(
        find.text('Failed to load profile'),
        findsOneWidget,
        reason: 'precondition: the first load failed',
      );

      await tester.tap(_retryButton);
      await pumpFrames(tester);

      expectOtherProfileWithPosts();
      verifyAuthorPostsRequestedForOther();
      final blockProvider = tester
          .element(find.byType(ProfileScreen))
          .read<BlockProvider>();
      expect(blockProvider.isUserBlocked(otherDid), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('for a screen opened by handle, requests the handle again '
        'and shows the profile', (tester) async {
      profileResponses
        ..add(() => Future.error(NetworkException('Connection refused')))
        ..add(() => Future.value(_otherProfile()));

      await pumpPushedProfile(tester, otherHandle);
      expect(
        find.text('Failed to load profile'),
        findsOneWidget,
        reason: 'precondition: the first load failed',
      );

      await tester.tap(_retryButton);
      await pumpFrames(tester);

      verify(apiService.getProfile(actor: otherHandle)).called(2);
      expectOtherProfileWithPosts();
      expect(tester.takeException(), isNull);
    });
  });
}
