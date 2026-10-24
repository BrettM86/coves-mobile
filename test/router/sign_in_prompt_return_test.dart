import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/main.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/post_get_result.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/comments_provider.dart';
import 'package:coves_flutter/providers/multi_feed_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/auth/login_screen.dart';
import 'package:coves_flutter/screens/home/main_shell_screen.dart';
import 'package:coves_flutter/screens/home/post_detail_screen.dart';
import 'package:coves_flutter/services/comments_provider_cache.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/post_change_broadcast.dart';
import 'package:coves_flutter/services/viewer_state_hydrator.dart';
import 'package:coves_flutter/services/vote_service.dart';
import 'package:coves_flutter/utils/post_detail_route.dart';
import 'package:coves_flutter/widgets/comment_card.dart';
import 'package:coves_flutter/widgets/sign_in_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/sign_in_flow_fakes.dart';
import '../test_helpers/test_mocks.dart';

// Signing in from a prompt (a signed-out comment upvote) must bring the
// user back to the post they were reading, with the thread fetched again
// under the new session, instead of dropping them on /feed. These tests run
// through the production router so the route stack, the router's refresh on
// auth changes and the comments cache's identity cleanup all take part.

const _postUri = 'at://did:plc:author/social.coves.community.post/post';
const _postCid = 'post-cid';
const _commentUri = 'at://did:plc:author/social.coves.community.comment/c1';
const _firstDid = 'did:plc:alice';
const _secondDid = 'did:plc:bob';
const _firstVoteUri = 'at://did:plc:alice/social.coves.feed.vote/up1';
const _secondVoteUri = 'at://did:plc:bob/social.coves.feed.vote/down1';

/// VoteService that records every vote request instead of sending it.
class _RecordingVoteService extends VoteService {
  _RecordingVoteService() : super(sessionKeyOf: () => null);

  final List<String> votedSubjects = [];

  @override
  Future<VoteResponse> createVote({
    required String postUri,
    required String postCid,
    String direction = 'up',
  }) async {
    votedSubjects.add(postUri);
    return const VoteResponse(
      uri: 'at://did:plc:alice/social.coves.feed.vote/replayed',
      cid: 'replayed-cid',
      rkey: 'replayed',
      deleted: false,
    );
  }
}

FeedViewPost _feedPost() {
  return FeedViewPost(
    post: PostView(
      uri: _postUri,
      cid: _postCid,
      rkey: 'post',
      author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
      community: CommunityRef(did: 'did:plc:community', name: 'test'),
      createdAt: DateTime(2025),
      indexedAt: DateTime(2025),
      record: const PostRecord(content: 'Sign-in return post'),
      stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 1),
    ),
  );
}

/// The thread as the server returns it to [viewerDid] (null: anonymous).
/// The first account has upvoted the comment and the second downvoted it.
List<ThreadViewComment> _threadFor(String? viewerDid) {
  final viewer = switch (viewerDid) {
    _firstDid => CommentViewerState(vote: 'up', voteUri: _firstVoteUri),
    _secondDid => CommentViewerState(vote: 'down', voteUri: _secondVoteUri),
    _ => null,
  };
  return [
    ThreadViewComment(
      comment: CommentView(
        uri: _commentUri,
        cid: 'cid-c1',
        record: const CommentRecord(content: 'First comment'),
        createdAt: DateTime(2025),
        indexedAt: DateTime(2025),
        author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
        post: CommentRef(uri: _postUri, cid: _postCid),
        stats: const CommentStats(upvotes: 1, score: 1),
        viewer: viewer,
      ),
    ),
  ];
}

/// The production router over the app-level providers a post detail, the
/// login screen and the /feed shell resolve, with the network mocked.
class _RouterHarness {
  _RouterHarness() {
    votes = VoteProvider(voteService: voteService, authProvider: auth);
    blocks = BlockProvider(apiService: api, authProvider: auth);
    feeds = IdleFeedProvider(auth, apiService: api);
    cache = CommentsProviderCache(
      authProvider: auth,
      voteProvider: votes,
      commentService: MockCommentService(),
      apiService: api,
      hydrator: ViewerStateHydrator(authProvider: auth, voteProvider: votes),
    );
    router = createRouter(auth, eula, guidelines);

    when(
      api.getComments(
        postUri: anyNamed('postUri'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        depth: anyNamed('depth'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
        parentRkey: anyNamed('parentRkey'),
      ),
    ).thenAnswer((_) async {
      // The server answers for whichever session sent the request.
      final viewerDid = auth.did;
      commentRequestDids.add(viewerDid);
      return CommentsResponse(post: null, comments: _threadFor(viewerDid));
    });
    // A post pushed with an extra is rebuilt through the cold path on the
    // router's first refresh, which loads the post by URI. Mockito cannot
    // build a placeholder of the sealed result type while stubbing.
    // The cold-load loader stamps the post with the viewer's authority.
    when(api.getViewerAuthority()).thenAnswer((_) async => false);
    when(api.getUnreadCount()).thenAnswer((_) async => 0);
    provideDummy<PostGetResult>(const PostGetNotFound(_postUri));
    when(api.getPost(any))
        .thenAnswer((_) async => PostGetSuccess(_feedPost().post));
  }

  final auth = GatedSignInAuthProvider();
  final eula = AcceptedEulaProvider();
  final guidelines = AcceptedGuidelinesProvider();
  final api = MockCovesApiService();
  final voteService = _RecordingVoteService();
  late final VoteProvider votes;
  late final BlockProvider blocks;
  late final MultiFeedProvider feeds;
  late final CommentsProviderCache cache;
  late final GoRouter router;

  /// The signed-in DID (null: signed out) of each comments request.
  final List<String?> commentRequestDids = [];

  Widget app() {
    return MultiProvider(
      providers: [
        Provider<PostChangeBroadcast>.value(value: PostChangeBroadcast()),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<VoteProvider>.value(value: votes),
        ChangeNotifierProvider<BlockProvider>.value(value: blocks),
        ChangeNotifierProvider<MultiFeedProvider>.value(value: feeds),
        Provider<CovesApiService>.value(value: api),
        Provider<CommentsProviderCache>.value(value: cache),
        viewerAuthorityRegistration(auth: auth, apiService: api),
        unreadNotificationCountRegistration(auth: auth, apiService: api),
      ],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    );
  }

  /// Unmounts the app, then disposes what the tree used.
  ///
  /// Called from `finally` rather than addTearDown: cached comment providers
  /// own periodic timers, and the binding fails the test on a pending timer
  /// before tear-downs run.
  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    cache.dispose();
    feeds.dispose();
    blocks.dispose();
    votes.dispose();
    router.dispose();
    guidelines.dispose();
    eula.dispose();
    auth.dispose();
  }
}

/// Forces the phone layout with room for the post and its comment. A width
/// just under the tablet breakpoint keeps the login screen's copy from
/// overflowing in the test font, whose glyphs are wider than the app's.
void _usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(590, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Fails if an exception was reported or an error widget is in the tree.
void _expectNoErrors(WidgetTester tester, String phase) {
  expect(tester.takeException(), isNull, reason: 'exception $phase');
  expect(
    find.byType(ErrorWidget, skipOffstage: false),
    findsNothing,
    reason: 'error widget $phase',
  );
}

/// The comment's vote button with the given accessibility [label]
/// ('Upvote comment' / 'Remove upvote', 'Downvote comment' /
/// 'Remove downvote'), which tracks the viewer's vote.
Finder _commentVoteButton(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == label,
  );
}

/// Fails unless the comments provider the post screen exposes to its
/// comment cards is the cache's live provider for the post.
void _expectRendersLiveCommentsProvider(
  WidgetTester tester,
  _RouterHarness harness,
) {
  final commentCard = tester.element(
    find
        .descendant(
          of: find.byType(PostDetailScreen),
          matching: find.byType(CommentCard),
        )
        .first,
  );
  expect(
    Provider.of<CommentsProvider>(commentCard, listen: false),
    same(harness.cache.peekProvider(_postUri)),
    reason:
        'the post screen must render the cache\'s live comments provider, '
        'never one the cache has disposed',
  );
}

String get _postLocation => '/post/${Uri.encodeComponent(_postUri)}';

/// Opens the post from /feed the way a post card does: pushed, with the
/// post as the route extra.
Future<void> _openPostFromFeed(
  WidgetTester tester,
  _RouterHarness harness,
) async {
  await tester.pumpWidget(harness.app());
  harness.router.go('/feed');
  await tester.pumpAndSettle();
  expect(find.byType(MainShellScreen), findsOneWidget);

  unawaited(
    harness.router.push(
      _postLocation,
      extra: PostDetailRouteExtra(post: _feedPost(), sessionStamp: null),
    ),
  );
  await tester.pumpAndSettle();
  _expectNoErrors(tester, 'after opening the post');
  expect(find.text('First comment'), findsOneWidget);
}

/// Signs in on the visible login screen, pumping frames between the
/// provider's loading notification and its signed-in notification.
Future<void> _signInOnLoginScreen(
  WidgetTester tester,
  _RouterHarness harness,
  String did,
) async {
  expect(find.byType(LoginScreen), findsOneWidget);
  await tester.enterText(find.byType(TextFormField), 'alice.test');
  await tester.tap(find.text('Sign in'));
  await tester.pump();
  expect(harness.auth.isAwaitingOAuth, isTrue);
  expect(harness.auth.isLoading, isTrue);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
  _expectNoErrors(tester, 'while the sign-in is waiting on OAuth');

  harness.auth.completeOAuth(did);
  await tester.pump();
  _expectNoErrors(tester, 'on the frame after the sign-in completed');
  await tester.pump(const Duration(milliseconds: 100));
  _expectNoErrors(tester, 'shortly after the sign-in completed');
  await tester.pumpAndSettle();
  _expectNoErrors(tester, 'after the sign-in settled');
  expect(harness.auth.did, did);
}

void main() {
  testWidgets(
    'given a signed-out viewer on a post opened from /feed, when they upvote '
    'a comment and sign in from the prompt, then they are back on the post '
    'with the thread refetched for the new session and no vote sent',
    (tester) async {
      _usePhoneViewport(tester);
      final harness = _RouterHarness();
      try {
        await _openPostFromFeed(tester, harness);
        expect(harness.commentRequestDids, [null]);
        expect(harness.votes.isLiked(_commentUri), isFalse);

        await tester.tap(_commentVoteButton('Upvote comment'));
        await tester.pumpAndSettle();
        _expectNoErrors(tester, 'after tapping the upvote');
        expect(find.byType(SignInDialog), findsOneWidget);

        await tester.tap(find.text('Sign In'));
        await tester.pumpAndSettle();
        _expectNoErrors(tester, 'after confirming the sign-in prompt');

        await _signInOnLoginScreen(tester, harness, _firstDid);

        expect(
          find.byType(LoginScreen),
          findsNothing,
          reason: 'the login screen must close after a successful sign-in',
        );
        expect(
          find.byType(PostDetailScreen),
          findsOneWidget,
          reason:
              'signing in from a prompt must return to the post the user '
              'was reading, not land on /feed',
        );
        final postRoute = ModalRoute.of(
          tester.element(find.byType(PostDetailScreen)),
        );
        expect(postRoute?.isCurrent, isTrue);
        expect(find.byType(MainShellScreen), findsNothing);
        _expectRendersLiveCommentsProvider(tester, harness);

        expect(
          harness.commentRequestDids,
          contains(_firstDid),
          reason: 'the thread must be fetched again with the new session',
        );
        expect(find.text('First comment'), findsOneWidget);
        expect(harness.votes.isLiked(_commentUri), isTrue);
        expect(harness.votes.getVoteState(_commentUri)?.uri, _firstVoteUri);
        expect(_commentVoteButton('Remove upvote'), findsOneWidget);

        expect(
          harness.voteService.votedSubjects,
          isEmpty,
          reason: 'the upvote that prompted the sign-in is not replayed',
        );
        _expectNoErrors(tester, 'at the end');
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  testWidgets(
    'given a post detail mounted through the router, when the signed-in '
    'account changes while it stays mounted, then the same screen stays up '
    'and refetches the thread for each new account',
    (tester) async {
      _usePhoneViewport(tester);
      final harness = _RouterHarness();
      try {
        await _openPostFromFeed(tester, harness);

        // go_router drops the non-JSON extra, so its first refresh after the
        // push rebuilds the post through the cold path with a new State. Let
        // that happen first, from a provider other than auth, so the State
        // captured below is the one the account changes must keep.
        harness.guidelines.notifyWithoutChange();
        await tester.pumpAndSettle();
        _expectNoErrors(tester, 'after the cold-path rebuild');
        expect(find.text('First comment'), findsOneWidget);
        final screenState = tester.state<State<PostDetailScreen>>(
          find.byType(PostDetailScreen),
        );
        final requestsBeforeSignIn = harness.commentRequestDids.length;

        harness.auth.switchAccount(_firstDid);
        await tester.pump();
        _expectNoErrors(tester, 'on the frame after signing in');
        await tester.pumpAndSettle();
        _expectNoErrors(tester, 'after signing in settled');

        expect(
          tester.state<State<PostDetailScreen>>(find.byType(PostDetailScreen)),
          same(screenState),
          reason: 'signing in must not replace the mounted post screen',
        );
        expect(screenState.mounted, isTrue);
        _expectRendersLiveCommentsProvider(tester, harness);
        expect(
          harness.commentRequestDids.skip(requestsBeforeSignIn),
          contains(_firstDid),
          reason: 'the thread must be fetched again for the first account',
        );
        expect(find.text('First comment'), findsOneWidget);
        expect(harness.votes.isLiked(_commentUri), isTrue);
        expect(_commentVoteButton('Remove upvote'), findsOneWidget);

        final requestsBeforeSwitch = harness.commentRequestDids.length;
        harness.auth.switchAccount(_secondDid);
        await tester.pump();
        _expectNoErrors(tester, 'on the frame after switching accounts');
        await tester.pumpAndSettle();
        _expectNoErrors(tester, 'after switching accounts settled');

        expect(
          tester.state<State<PostDetailScreen>>(find.byType(PostDetailScreen)),
          same(screenState),
          reason: 'switching accounts must not replace the mounted screen',
        );
        expect(screenState.mounted, isTrue);
        _expectRendersLiveCommentsProvider(tester, harness);
        expect(
          harness.commentRequestDids.skip(requestsBeforeSwitch),
          contains(_secondDid),
          reason: 'the thread must be fetched again for the second account',
        );
        expect(find.text('First comment'), findsOneWidget);
        expect(harness.votes.isLiked(_commentUri), isFalse);
        expect(harness.votes.getVoteState(_commentUri)?.direction, 'down');
        expect(_commentVoteButton('Upvote comment'), findsOneWidget);
        expect(_commentVoteButton('Remove downvote'), findsOneWidget);
        expect(harness.voteService.votedSubjects, isEmpty);
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  testWidgets(
    'given a cold-start /login with nothing under it, when sign-in succeeds, '
    'then the app lands on /feed',
    (tester) async {
      _usePhoneViewport(tester);
      final harness = _RouterHarness();
      try {
        await tester.pumpWidget(harness.app());
        harness.router.go('/login');
        await tester.pumpAndSettle();
        _expectNoErrors(tester, 'after opening /login');
        expect(harness.router.canPop(), isFalse);

        await _signInOnLoginScreen(tester, harness, _firstDid);

        expect(find.byType(LoginScreen), findsNothing);
        expect(find.byType(MainShellScreen), findsOneWidget);
        expect(
          harness.router.routerDelegate.currentConfiguration.uri.path,
          '/feed',
        );
        expect(harness.router.canPop(), isFalse);
      } finally {
        await harness.dispose(tester);
      }
    },
  );
}
