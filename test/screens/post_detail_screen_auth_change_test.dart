import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/post_get_result.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/comments_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/home/focused_thread_screen.dart';
import 'package:coves_flutter/screens/home/post_detail_loader.dart';
import 'package:coves_flutter/screens/home/post_detail_screen.dart';
import 'package:coves_flutter/services/comments_provider_cache.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/viewer_state_hydrator.dart';
import 'package:coves_flutter/services/vote_service.dart';
import 'package:coves_flutter/widgets/comment_card.dart';
import 'package:coves_flutter/widgets/post_action_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/test_mocks.dart';

// The post screen pops back to the first route when the viewer signs out.
// Auth notifications that leave the signed-in account as it was, such as a
// sign-in starting or being cancelled, or a token refresh, are not a
// sign-out and must leave the post where it is. A sign-in or an account
// switch leaves the post where it is too, but the comments cache disposes
// every cached thread when the signed-in DID changes, so the screen must
// move to the cache's live provider for the new account, keep it pinned
// while mounted and release that pin exactly once when disposed.

const _postUri = 'at://did:plc:author/social.coves.community.post/post';
const _postCid = 'post-cid';
const _commentUri = 'at://did:plc:author/social.coves.community.comment/c1';
const _signedInDid = 'did:plc:alice';
const _secondSignedInDid = 'did:plc:bob';
const _signedInVoteUri = 'at://did:plc:alice/social.coves.feed.vote/up1';
const _secondSignedInVoteUri = 'at://did:plc:bob/social.coves.feed.vote/down1';
const _signedInPostVoteUri = 'at://did:plc:alice/social.coves.feed.vote/post1';
const _secondSignedInPostVoteUri =
    'at://did:plc:bob/social.coves.feed.vote/post2';
const _otherPostUri = 'at://did:plc:author/social.coves.community.post/other';
const _focusTargetUri =
    'at://did:plc:author/social.coves.community.comment/target';
const _focusFailedMessage =
    "Couldn't find that comment. It may have been deleted.";

/// Signed-out AuthProvider that can show a sign-in in progress, the way
/// the real provider notifies with isLoading set before OAuth and cleared
/// when the user cancels it.
class _SignInFlowAuthProvider extends FakeAuthProvider {
  bool _isLoading = false;

  @override
  bool get isLoading => _isLoading;

  void startSignIn() {
    _isLoading = true;
    notifyListeners();
  }

  void cancelSignIn() {
    _isLoading = false;
    notifyListeners();
  }
}

/// Records the subject of every vote request instead of sending it.
class _RecordingVoteService extends VoteService {
  final List<String> votedSubjects = [];

  @override
  Future<VoteResponse> createVote({
    required String postUri,
    required String postCid,
    String direction = 'up',
  }) async {
    votedSubjects.add(postUri);
    return const VoteResponse(deleted: true);
  }
}

/// The post as the server returns it to [viewerDid] (null: anonymous). The
/// first account has upvoted the post and the second downvoted it.
PostView _postFor(String? viewerDid) {
  final viewer = switch (viewerDid) {
    _signedInDid => ViewerState(vote: 'up', voteUri: _signedInPostVoteUri),
    _secondSignedInDid => ViewerState(
      vote: 'down',
      voteUri: _secondSignedInPostVoteUri,
    ),
    _ => null,
  };
  return PostView(
    uri: _postUri,
    cid: _postCid,
    rkey: 'post',
    author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
    community: CommunityRef(did: 'did:plc:community', name: 'test'),
    createdAt: DateTime(2025),
    indexedAt: DateTime(2025),
    record: const PostRecord(content: 'Auth change post'),
    stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 1),
    viewer: viewer,
  );
}

FeedViewPost _feedPost() => FeedViewPost(post: _postFor(null));

/// The thread as the server returns it to [viewerDid] (null: anonymous).
/// The first account has upvoted the comment and the second downvoted it.
ThreadViewComment _threadFor(String? viewerDid) {
  final viewer = switch (viewerDid) {
    _signedInDid => CommentViewerState(vote: 'up', voteUri: _signedInVoteUri),
    _secondSignedInDid => CommentViewerState(
      vote: 'down',
      voteUri: _secondSignedInVoteUri,
    ),
    _ => null,
  };
  return ThreadViewComment(
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
  );
}

/// A comment outside the post's first page of comments, as its subtree
/// request returns it.
ThreadViewComment _focusTarget() {
  return ThreadViewComment(
    comment: CommentView(
      uri: _focusTargetUri,
      cid: 'cid-target',
      record: const CommentRecord(content: 'Focus target comment'),
      createdAt: DateTime(2025),
      indexedAt: DateTime(2025),
      author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
      post: CommentRef(uri: _postUri, cid: _postCid),
      stats: const CommentStats(upvotes: 1, score: 1),
    ),
  );
}

/// A PostDetailScreen pushed over a base route, with the comments cache,
/// API service, vote and block providers it resolves and the comments and
/// post requests mocked.
class _PostOverBaseRoute {
  _PostOverBaseRoute(this.auth, {int cacheSizeLimit = 15}) {
    votes = VoteProvider(voteService: voteService, authProvider: auth);
    blocks = BlockProvider(apiService: api, authProvider: auth);
    cache = CommentsProviderCache(
      authProvider: auth,
      voteProvider: votes,
      commentService: MockCommentService(),
      apiService: api,
      hydrator: ViewerStateHydrator(authProvider: auth, voteProvider: votes),
      maxSize: cacheSizeLimit,
    );
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
    ).thenAnswer((invocation) async {
      // The server answers for whichever session sent the request.
      final viewerDid = auth.did;
      if (invocation.namedArguments[#parentRkey] != null) {
        subtreeRequestDids.add(viewerDid);
        final held = heldSubtreeResponse;
        heldSubtreeResponse = null;
        return held?.future ??
            CommentsResponse(post: null, comments: [_focusTarget()]);
      }
      commentRequestDids.add(viewerDid);
      return CommentsResponse(post: null, comments: [_threadFor(viewerDid)]);
    });
    // Mockito cannot build a placeholder of the sealed result type while
    // stubbing.
    provideDummy<PostGetResult>(const PostGetNotFound(_postUri));
    when(api.getPost(any)).thenAnswer((_) async {
      // The server answers for whichever session sent the request.
      final viewerDid = auth.did;
      postRequestDids.add(viewerDid);
      final held = heldPostResponse;
      heldPostResponse = null;
      return held?.future ?? PostGetSuccess(_postFor(viewerDid));
    });
  }

  final FakeAuthProvider auth;
  final api = MockCovesApiService();
  final voteService = _RecordingVoteService();
  final navigatorKey = GlobalKey<NavigatorState>();
  late final VoteProvider votes;
  late final BlockProvider blocks;
  late final CommentsProviderCache cache;

  /// The signed-in DID (null: signed out) of each request for the post's
  /// first page of comments.
  final List<String?> commentRequestDids = [];

  /// The signed-in DID of each request for a comment's subtree.
  final List<String?> subtreeRequestDids = [];

  /// When set, the next subtree request waits for the test to complete it.
  Completer<CommentsResponse>? heldSubtreeResponse;

  /// The signed-in DID (null: signed out) of each request for the post
  /// through the API service.
  final List<String?> postRequestDids = [];

  /// When set, the next post request waits for the test to complete it.
  Completer<PostGetResult>? heldPostResponse;

  /// Pumps the base route, pushes the post over it and waits for its thread.
  ///
  /// With [coldLoaded] the route loads the post by URI first, as a link
  /// without the post in its extra does. That first load goes through the
  /// loader's injected fetcher, so it is not in [postRequestDids].
  Future<State<PostDetailScreen>> pumpPost(
    WidgetTester tester, {
    String? focusCommentUri,
    bool coldLoaded = false,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<VoteProvider>.value(value: votes),
          ChangeNotifierProvider<BlockProvider>.value(value: blocks),
          Provider<CovesApiService>.value(value: api),
          Provider<CommentsProviderCache>.value(value: cache),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Text('base route')),
        ),
      ),
    );
    unawaited(
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => coldLoaded
              ? PostDetailLoader(
                  postUri: _postUri,
                  focusCommentUri: focusCommentUri,
                  fetchPost: (_) async => PostGetSuccess(_postFor(auth.did)),
                )
              : PostDetailScreen(
                  post: _feedPost(),
                  focusCommentUri: focusCommentUri,
                ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('First comment'), findsOneWidget);
    expect(find.text('base route'), findsNothing);
    return tester.state<State<PostDetailScreen>>(find.byType(PostDetailScreen));
  }

  /// Unmounts the tree, then disposes the providers. Called from `finally`:
  /// cached comment providers own periodic timers, and the binding fails
  /// the test on a pending timer before tear-downs run.
  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    cache.dispose();
    blocks.dispose();
    votes.dispose();
    auth.dispose();
  }
}

/// Fails unless the post is still mounted on its own route, with the base
/// route under it and its thread rendered.
void _expectPostStaysOnItsRoute(
  WidgetTester tester,
  _PostOverBaseRoute harness,
  State<PostDetailScreen> screenState,
  String notification,
) {
  expect(
    find.byType(PostDetailScreen),
    findsOneWidget,
    reason: '$notification must not pop the post',
  );
  expect(
    tester.state<State<PostDetailScreen>>(find.byType(PostDetailScreen)),
    same(screenState),
  );
  expect(
    ModalRoute.of(tester.element(find.byType(PostDetailScreen)))?.isCurrent,
    isTrue,
  );
  expect(
    harness.navigatorKey.currentState!.canPop(),
    isTrue,
    reason: 'the base route must stay under the post',
  );
  expect(find.text('base route'), findsNothing);
  expect(find.text('First comment'), findsOneWidget);
  expect(tester.takeException(), isNull);
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

/// Fails unless the comments provider the post screen exposes to its
/// comment cards is the cache's live provider for the post.
void _expectRendersLiveCommentsProvider(
  WidgetTester tester,
  _PostOverBaseRoute harness,
  String change,
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
        'after $change the post screen must render the cache\'s live '
        'comments provider, never one the cache has disposed',
  );
}

/// The comment's vote button with the given accessibility [label]
/// ('Upvote comment' / 'Remove upvote', 'Downvote comment' /
/// 'Remove downvote'), which tracks the viewer's vote.
Finder _commentVoteButton(String label) {
  return find.descendant(
    of: find.byType(CommentCard),
    matching: find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    ),
  );
}

/// The post's vote button in the action bar with the given accessibility
/// [label] ('Upvote post' / 'Remove upvote'), which tracks the viewer's vote.
Finder _postVoteButton(String label) {
  return find.descendant(
    of: find.byType(PostActionBar),
    matching: find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    ),
  );
}

/// The Retry action offered when the post's vote could not be refetched.
Finder _postVoteRetry() => find.widgetWithText(SnackBarAction, 'Retry');

/// Fails unless the post's vote button shows with its score but cannot act:
/// it is disabled, exposes no tap action, and a tap sends no vote request.
/// The signed-out load carries no vote, so the button is labelled to upvote.
Future<void> _expectPostVoteCannotAct(
  WidgetTester tester,
  _PostOverBaseRoute harness,
  String phase,
) async {
  final button = _postVoteButton('Upvote post');
  expect(button, findsOneWidget, reason: 'the post vote must show $phase');
  expect(
    tester.getSemantics(button),
    isSemantics(
      label: 'Upvote post',
      value: 'Score 0',
      hasEnabledState: true,
      isEnabled: false,
      hasTapAction: false,
    ),
    reason: 'the post vote must be disabled with no tap action $phase',
  );
  await tester.tap(button, warnIfMissed: false);
  await tester.pump();
  expect(
    harness.voteService.votedSubjects,
    isEmpty,
    reason:
        'a tap on the post vote must send no vote request $phase: the '
        'server toggles off a vote in the same direction, so a tap against '
        'unhydrated state can delete the account\'s existing vote',
  );
}

/// Fails unless the post's vote button shows the first account's hydrated
/// upvote and a tap on it sends a vote request for the post.
Future<void> _expectPostVoteActsOnHydratedUpvote(
  WidgetTester tester,
  _PostOverBaseRoute harness,
) async {
  expect(harness.votes.isLiked(_postUri), isTrue);
  expect(harness.votes.getVoteState(_postUri)?.uri, _signedInPostVoteUri);
  final button = _postVoteButton('Remove upvote');
  expect(button, findsOneWidget);
  expect(
    tester.getSemantics(button),
    isSemantics(isEnabled: true, hasTapAction: true),
  );
  await tester.tap(button);
  await tester.pump();
  expect(harness.voteService.votedSubjects, [_postUri]);
}

/// Acquires and releases another post. With a cache size limit of one,
/// this evicts the post's provider unless an owner still has it pinned.
void _applyEvictionPressure(CommentsProviderCache cache) {
  cache
    ..acquireProvider(postUri: _otherPostUri, postCid: 'other-cid')
    ..releaseProvider(_otherPostUri);
}

void main() {
  testWidgets(
    'given a signed-out viewer on a pushed post, when a sign-in starts and '
    'is then cancelled, then the post stays on its route',
    (tester) async {
      final harness = _PostOverBaseRoute(_SignInFlowAuthProvider());
      final auth = harness.auth as _SignInFlowAuthProvider;
      try {
        final screenState = await harness.pumpPost(tester);

        auth.startSignIn();
        await tester.pumpAndSettle();
        expect(auth.did, isNull);
        _expectPostStaysOnItsRoute(
          tester,
          harness,
          screenState,
          'a sign-in starting while signed out',
        );

        auth.cancelSignIn();
        await tester.pumpAndSettle();
        expect(auth.did, isNull);
        _expectPostStaysOnItsRoute(
          tester,
          harness,
          screenState,
          'a cancelled sign-in',
        );
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  testWidgets(
    'given a signed-in viewer on a pushed post, when auth notifies with the '
    'same account, then the post stays on its route',
    (tester) async {
      final harness = _PostOverBaseRoute(
        FakeAuthProvider(signedInDid: _signedInDid),
      );
      try {
        final screenState = await harness.pumpPost(tester);
        final requestsBeforeNotification = harness.commentRequestDids.length;

        harness.auth.notifyWithoutChange();
        await tester.pumpAndSettle();
        expect(harness.auth.did, _signedInDid);
        _expectPostStaysOnItsRoute(
          tester,
          harness,
          screenState,
          'a same-account notification such as a token refresh',
        );
        expect(
          harness.commentRequestDids.length,
          requestsBeforeNotification,
          reason:
              'a same-account notification must not reload the thread from '
              'its first page',
        );
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  testWidgets(
    'given a signed-in viewer on a pushed post, when they sign out, then the '
    'post pops back to the first route',
    (tester) async {
      final harness = _PostOverBaseRoute(
        FakeAuthProvider(signedInDid: _signedInDid),
      );
      try {
        await harness.pumpPost(tester);

        harness.auth.setSignedInDid(null);
        await tester.pumpAndSettle();

        expect(find.byType(PostDetailScreen), findsNothing);
        expect(find.text('base route'), findsOneWidget);
        expect(harness.navigatorKey.currentState!.canPop(), isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  testWidgets(
    'given a signed-out viewer on a pushed post, when they sign in while it '
    'is mounted, then the same screen renders the live thread refetched '
    'with their vote',
    (tester) async {
      final harness = _PostOverBaseRoute(FakeAuthProvider());
      try {
        final screenState = await harness.pumpPost(tester);
        expect(harness.commentRequestDids, [null]);
        expect(_commentVoteButton('Upvote comment'), findsOneWidget);
        final requestsBeforeSignIn = harness.commentRequestDids.length;

        harness.auth.setSignedInDid(_signedInDid);
        await tester.pump();
        _expectNoErrors(tester, 'on the frame after signing in');
        await tester.pumpAndSettle();
        _expectNoErrors(tester, 'after signing in settled');

        _expectPostStaysOnItsRoute(tester, harness, screenState, 'signing in');
        _expectRendersLiveCommentsProvider(tester, harness, 'signing in');
        expect(
          harness.commentRequestDids.skip(requestsBeforeSignIn),
          contains(_signedInDid),
          reason: 'the thread must be fetched again with the new session',
        );
        expect(harness.votes.isLiked(_commentUri), isTrue);
        expect(harness.votes.getVoteState(_commentUri)?.uri, _signedInVoteUri);
        expect(_commentVoteButton('Remove upvote'), findsOneWidget);
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  testWidgets(
    'given a signed-in viewer on a pushed post, when they switch accounts '
    'while it is mounted, then the same screen renders the live thread '
    'refetched with the new account\'s vote',
    (tester) async {
      final harness = _PostOverBaseRoute(
        FakeAuthProvider(signedInDid: _signedInDid),
      );
      try {
        final screenState = await harness.pumpPost(tester);
        expect(harness.commentRequestDids, [_signedInDid]);
        expect(_commentVoteButton('Remove upvote'), findsOneWidget);
        final requestsBeforeSwitch = harness.commentRequestDids.length;

        harness.auth.setSignedInDid(_secondSignedInDid);
        await tester.pump();
        _expectNoErrors(tester, 'on the frame after switching accounts');
        await tester.pumpAndSettle();
        _expectNoErrors(tester, 'after switching accounts settled');

        _expectPostStaysOnItsRoute(
          tester,
          harness,
          screenState,
          'switching accounts',
        );
        _expectRendersLiveCommentsProvider(
          tester,
          harness,
          'switching accounts',
        );
        expect(
          harness.commentRequestDids.skip(requestsBeforeSwitch),
          contains(_secondSignedInDid),
          reason: 'the thread must be fetched again for the second account',
        );
        expect(harness.votes.isLiked(_commentUri), isFalse);
        expect(harness.votes.getVoteState(_commentUri)?.direction, 'down');
        expect(
          harness.votes.getVoteState(_commentUri)?.uri,
          _secondSignedInVoteUri,
        );
        expect(_commentVoteButton('Upvote comment'), findsOneWidget);
        expect(_commentVoteButton('Remove downvote'), findsOneWidget);
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  testWidgets(
    'given a signed-out viewer on a cold-loaded post, when they sign in while '
    'it is mounted, then the post\'s own vote shows their existing upvote',
    (tester) async {
      final harness = _PostOverBaseRoute(FakeAuthProvider());
      try {
        await harness.pumpPost(tester, coldLoaded: true);
        expect(harness.votes.isLiked(_postUri), isFalse);
        expect(_postVoteButton('Upvote post'), findsOneWidget);

        harness.auth.setSignedInDid(_signedInDid);
        await tester.pump();
        _expectNoErrors(tester, 'on the frame after signing in');
        await tester.pumpAndSettle();
        _expectNoErrors(tester, 'after signing in settled');

        expect(
          harness.votes.isLiked(_postUri),
          isTrue,
          reason:
              'the post loaded while signed out carries no vote, so the '
              'action bar would act on a vote state the account does not have',
        );
        expect(harness.votes.getVoteState(_postUri)?.uri, _signedInPostVoteUri);
        expect(_postVoteButton('Remove upvote'), findsOneWidget);
        expect(harness.postRequestDids, [
          _signedInDid,
        ], reason: 'the post must be fetched again with the new session');
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  testWidgets(
    'given a signed-out viewer on a cold-loaded post, when the account '
    'changes again before the sign-in\'s post refetch lands, then that '
    'refetch\'s vote is not applied',
    (tester) async {
      final harness = _PostOverBaseRoute(FakeAuthProvider());
      final firstAccountPostResponse = Completer<PostGetResult>();
      try {
        await harness.pumpPost(tester, coldLoaded: true);
        harness.heldPostResponse = firstAccountPostResponse;

        harness.auth.setSignedInDid(_signedInDid);
        await tester.pumpAndSettle();
        harness.auth.setSignedInDid(_secondSignedInDid);
        await tester.pumpAndSettle();
        _expectNoErrors(tester, 'after switching accounts settled');
        expect(harness.postRequestDids, [_signedInDid, _secondSignedInDid]);
        expect(harness.votes.getVoteState(_postUri)?.direction, 'down');

        firstAccountPostResponse.complete(
          PostGetSuccess(_postFor(_signedInDid)),
        );
        await tester.pumpAndSettle();
        _expectNoErrors(tester, 'after the first account\'s post landed');

        expect(
          harness.votes.isLiked(_postUri),
          isFalse,
          reason:
              'the post fetched for the first account must not apply its '
              'vote once the second account is signed in',
        );
        expect(harness.votes.getVoteState(_postUri)?.direction, 'down');
        expect(
          harness.votes.getVoteState(_postUri)?.uri,
          _secondSignedInPostVoteUri,
        );
        expect(_postVoteButton('Upvote post'), findsOneWidget);
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  testWidgets(
    'given a signed-out viewer on a cold-loaded post, when they sign in and '
    'the post refetch is slow, then the post\'s vote cannot act until the '
    'refetch lands',
    (tester) async {
      final harness = _PostOverBaseRoute(FakeAuthProvider());
      final semantics = tester.ensureSemantics();
      final postResponse = Completer<PostGetResult>();
      try {
        await harness.pumpPost(tester, coldLoaded: true);
        harness.heldPostResponse = postResponse;

        harness.auth.setSignedInDid(_signedInDid);
        await tester.pump();
        _expectNoErrors(tester, 'on the frame after signing in');
        await _expectPostVoteCannotAct(
          tester,
          harness,
          'on the frame after signing in',
        );
        await tester.pumpAndSettle();
        await _expectPostVoteCannotAct(
          tester,
          harness,
          'while the post refetch is in flight',
        );
        expect(harness.postRequestDids, [_signedInDid]);

        postResponse.complete(PostGetSuccess(_postFor(_signedInDid)));
        await tester.pumpAndSettle();
        _expectNoErrors(tester, 'after the post refetch landed');

        expect(_postVoteRetry(), findsNothing);
        await _expectPostVoteActsOnHydratedUpvote(tester, harness);
      } finally {
        semantics.dispose();
        await harness.dispose(tester);
      }
    },
  );

  testWidgets(
    'given a signed-in viewer on a cold-loaded post, when they switch '
    'accounts and a vote tap lands before the action bar rebuilds, then no '
    'vote request is sent while the post refetch is in flight',
    (tester) async {
      final harness = _PostOverBaseRoute(
        FakeAuthProvider(signedInDid: _signedInDid),
      );
      final postResponse = Completer<PostGetResult>();
      try {
        await harness.pumpPost(tester, coldLoaded: true);
        harness.heldPostResponse = postResponse;
        // The tap handler the action bar installed while voting could act.
        final onVoteTap = tester
            .widget<PostActionBar>(find.byType(PostActionBar))
            .onVoteTap!;

        harness.auth.setSignedInDid(_secondSignedInDid);
        // No frame has run, so the old tap handler is still installed.
        onVoteTap();
        await tester.pump();
        _expectNoErrors(tester, 'after the tap before the rebuild');

        expect(harness.postRequestDids, [_secondSignedInDid]);
        expect(
          harness.voteService.votedSubjects,
          isEmpty,
          reason:
              'a tap that reaches the old handler must send no vote request '
              'before the new account\'s post refetch lands: the server '
              'toggles off a vote in the same direction, so it can delete '
              'the account\'s existing vote',
        );
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  testWidgets(
    'given a signed-out viewer on a cold-loaded post, when they sign in and '
    'the post refetch throws, then the post\'s vote stays unable to act and '
    'a successful Retry enables it with their vote',
    (tester) async {
      final harness = _PostOverBaseRoute(FakeAuthProvider());
      final semantics = tester.ensureSemantics();
      final postResponse = Completer<PostGetResult>();
      try {
        await harness.pumpPost(tester, coldLoaded: true);
        harness.heldPostResponse = postResponse;

        harness.auth.setSignedInDid(_signedInDid);
        await tester.pump();
        postResponse.completeError(Exception('connection reset'));
        await tester.pumpAndSettle();
        _expectNoErrors(tester, 'after the post refetch threw');

        await _expectPostVoteCannotAct(
          tester,
          harness,
          'after the post refetch threw',
        );
        expect(_postVoteRetry(), findsOneWidget);

        await tester.tap(_postVoteRetry());
        await tester.pumpAndSettle();
        _expectNoErrors(tester, 'after the retried refetch landed');

        expect(harness.postRequestDids, [_signedInDid, _signedInDid]);
        expect(_postVoteRetry(), findsNothing);
        await _expectPostVoteActsOnHydratedUpvote(tester, harness);
      } finally {
        semantics.dispose();
        await harness.dispose(tester);
      }
    },
  );

  testWidgets(
    'given a signed-out viewer on a cold-loaded post, when they sign in and '
    'the post refetch returns no post, then the post\'s vote stays unable to '
    'act and a successful Retry enables it with their vote',
    (tester) async {
      final harness = _PostOverBaseRoute(FakeAuthProvider());
      final semantics = tester.ensureSemantics();
      final postResponse = Completer<PostGetResult>();
      try {
        await harness.pumpPost(tester, coldLoaded: true);
        harness.heldPostResponse = postResponse;

        harness.auth.setSignedInDid(_signedInDid);
        await tester.pump();
        postResponse.complete(const PostGetNotFound(_postUri));
        await tester.pumpAndSettle();
        _expectNoErrors(tester, 'after the post refetch returned no post');

        await _expectPostVoteCannotAct(
          tester,
          harness,
          'after the post refetch returned no post',
        );
        expect(_postVoteRetry(), findsOneWidget);

        await tester.tap(_postVoteRetry());
        await tester.pumpAndSettle();
        _expectNoErrors(tester, 'after the retried refetch landed');

        expect(harness.postRequestDids, [_signedInDid, _signedInDid]);
        expect(_postVoteRetry(), findsNothing);
        await _expectPostVoteActsOnHydratedUpvote(tester, harness);
      } finally {
        semantics.dispose();
        await harness.dispose(tester);
      }
    },
  );

  testWidgets(
    'given a post whose vote refetch failed, when Retry is tapped, then the '
    'post is fetched again and the vote stays unable to act until a fetch '
    'succeeds',
    (tester) async {
      final harness = _PostOverBaseRoute(FakeAuthProvider());
      final semantics = tester.ensureSemantics();
      final firstResponse = Completer<PostGetResult>();
      final retriedResponse = Completer<PostGetResult>();
      try {
        await harness.pumpPost(tester, coldLoaded: true);
        harness.heldPostResponse = firstResponse;
        harness.auth.setSignedInDid(_signedInDid);
        await tester.pump();
        firstResponse.complete(const PostGetNotFound(_postUri));
        await tester.pumpAndSettle();
        expect(harness.postRequestDids, [_signedInDid]);

        harness.heldPostResponse = retriedResponse;
        await tester.tap(_postVoteRetry());
        await tester.pumpAndSettle();
        expect(harness.postRequestDids, [
          _signedInDid,
          _signedInDid,
        ], reason: 'Retry must fetch the post again under the same session');
        await _expectPostVoteCannotAct(
          tester,
          harness,
          'while the retried refetch is in flight',
        );

        retriedResponse.completeError(Exception('connection reset'));
        await tester.pumpAndSettle();
        _expectNoErrors(tester, 'after the retried refetch threw');
        await _expectPostVoteCannotAct(
          tester,
          harness,
          'after the retried refetch threw',
        );
        expect(_postVoteRetry(), findsOneWidget);

        await tester.tap(_postVoteRetry());
        await tester.pumpAndSettle();
        expect(harness.postRequestDids, [
          _signedInDid,
          _signedInDid,
          _signedInDid,
        ]);
        await _expectPostVoteActsOnHydratedUpvote(tester, harness);
      } finally {
        semantics.dispose();
        await harness.dispose(tester);
      }
    },
  );

  testWidgets(
    'given a signed-out viewer on a cold-loaded post, when the sign-in\'s '
    'post refetch fails after a later account change\'s refetch landed, '
    'then the later account\'s vote stays able to act',
    (tester) async {
      final harness = _PostOverBaseRoute(FakeAuthProvider());
      final firstAccountPostResponse = Completer<PostGetResult>();
      try {
        await harness.pumpPost(tester, coldLoaded: true);
        harness.heldPostResponse = firstAccountPostResponse;

        harness.auth.setSignedInDid(_signedInDid);
        await tester.pumpAndSettle();
        harness.auth.setSignedInDid(_secondSignedInDid);
        await tester.pumpAndSettle();
        expect(harness.postRequestDids, [_signedInDid, _secondSignedInDid]);

        firstAccountPostResponse.completeError(Exception('connection reset'));
        await tester.pumpAndSettle();
        _expectNoErrors(tester, 'after the first account\'s refetch threw');

        expect(_postVoteRetry(), findsNothing);
        await tester.tap(_postVoteButton('Upvote post'));
        await tester.pump();
        expect(
          harness.voteService.votedSubjects,
          [_postUri],
          reason:
              'a refetch for an account that is no longer signed in must '
              'not disable the current account\'s hydrated vote',
        );
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  testWidgets(
    'given a pushed post and a cache at its size limit, when the viewer '
    'signs in, then the post\'s provider stays pinned while the screen is '
    'mounted and becomes evictable once it is disposed',
    (tester) async {
      final harness = _PostOverBaseRoute(FakeAuthProvider(), cacheSizeLimit: 1);
      try {
        await harness.pumpPost(tester);
        // Control: before any identity change the mounted screen's pin
        // keeps its provider through the same pressure.
        _applyEvictionPressure(harness.cache);
        expect(harness.cache.hasProvider(_postUri), isTrue);

        harness.auth.setSignedInDid(_signedInDid);
        await tester.pumpAndSettle();
        _expectNoErrors(tester, 'after signing in settled');
        final liveProvider = harness.cache.peekProvider(_postUri);

        _applyEvictionPressure(harness.cache);
        expect(
          harness.cache.hasProvider(_postUri),
          isTrue,
          reason:
              'the mounted post screen must keep its post\'s provider '
              'pinned after the viewer signs in',
        );
        expect(harness.cache.peekProvider(_postUri), same(liveProvider));
        _expectRendersLiveCommentsProvider(
          tester,
          harness,
          'signing in and cache pressure',
        );
        _expectNoErrors(tester, 'after cache pressure');

        harness.navigatorKey.currentState!.pop();
        await tester.pumpAndSettle();
        _expectNoErrors(tester, 'after closing the post');
        expect(find.byType(PostDetailScreen), findsNothing);

        _applyEvictionPressure(harness.cache);
        expect(
          harness.cache.hasProvider(_postUri),
          isFalse,
          reason:
              'a disposed post screen must release its pin, leaving the '
              'provider evictable',
        );
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  testWidgets(
    'given a pushed post and a second owner that acquired it after an '
    'account switch, when the screen is disposed, then the second owner '
    'still holds its pin',
    (tester) async {
      final harness = _PostOverBaseRoute(
        FakeAuthProvider(signedInDid: _signedInDid),
        cacheSizeLimit: 1,
      );
      try {
        await harness.pumpPost(tester);

        harness.auth.setSignedInDid(_secondSignedInDid);
        await tester.pumpAndSettle();
        _expectNoErrors(tester, 'after switching accounts settled');

        // Another owner of the same post, such as a second screen for it.
        final secondOwnerProvider = harness.cache.acquireProvider(
          postUri: _postUri,
          postCid: _postCid,
        );

        harness.navigatorKey.currentState!.pop();
        await tester.pumpAndSettle();
        _expectNoErrors(tester, 'after closing the post');
        expect(find.byType(PostDetailScreen), findsNothing);

        _applyEvictionPressure(harness.cache);
        expect(
          harness.cache.peekProvider(_postUri),
          same(secondOwnerProvider),
          reason:
              'disposing the post screen must release only its own pin, '
              'not the pin of an owner that acquired the post after the '
              'account switch',
        );

        harness.cache.releaseProvider(_postUri);
        _applyEvictionPressure(harness.cache);
        expect(
          harness.cache.hasProvider(_postUri),
          isFalse,
          reason: 'with every owner released the provider must be evictable',
        );
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  testWidgets('given a pushed post and a second owner that acquired it after a '
      'sign-out, when the screen is disposed, then the second owner still '
      'holds its pin', (tester) async {
    final harness = _PostOverBaseRoute(
      FakeAuthProvider(signedInDid: _signedInDid),
      cacheSizeLimit: 1,
    );
    try {
      await harness.pumpPost(tester);

      harness.auth.setSignedInDid(null);
      // The cache has cleared, and the post screen stays mounted until its
      // route finishes popping. Another owner of the same post acquires it
      // in that window.
      expect(find.byType(PostDetailScreen), findsOneWidget);
      final secondOwnerProvider = harness.cache.acquireProvider(
        postUri: _postUri,
        postCid: _postCid,
      );

      await tester.pumpAndSettle();
      _expectNoErrors(tester, 'after signing out settled');
      expect(find.byType(PostDetailScreen), findsNothing);

      _applyEvictionPressure(harness.cache);
      expect(
        harness.cache.peekProvider(_postUri),
        same(secondOwnerProvider),
        reason:
            'the sign-out cleared the post screen\'s pin, so disposing it '
            'must not release the pin of an owner that acquired the post '
            'after the sign-out',
      );

      harness.cache.releaseProvider(_postUri);
      _applyEvictionPressure(harness.cache);
      expect(
        harness.cache.hasProvider(_postUri),
        isFalse,
        reason: 'with every owner released the provider must be evictable',
      );
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets(
    'given a post opened to focus a comment outside its loaded thread, when '
    'the account changes while that comment\'s subtree is loading, then the '
    'old provider\'s result is not acted on',
    (tester) async {
      final harness = _PostOverBaseRoute(
        FakeAuthProvider(signedInDid: _signedInDid),
      );
      final oldSubtreeResponse = Completer<CommentsResponse>();
      harness.heldSubtreeResponse = oldSubtreeResponse;
      try {
        await harness.pumpPost(tester, focusCommentUri: _focusTargetUri);
        expect(harness.subtreeRequestDids, [
          _signedInDid,
        ], reason: 'the focus must be fetching the target\'s subtree');
        final oldProvider = harness.cache.peekProvider(_postUri);

        harness.auth.setSignedInDid(_secondSignedInDid);
        await tester.pumpAndSettle();
        _expectNoErrors(tester, 'after switching accounts settled');
        expect(harness.cache.peekProvider(_postUri), isNot(same(oldProvider)));

        oldSubtreeResponse.complete(
          CommentsResponse(post: null, comments: [_focusTarget()]),
        );
        await tester.pumpAndSettle();

        _expectNoErrors(tester, 'after the old subtree response landed');
        expect(
          find.text(_focusFailedMessage),
          findsNothing,
          reason:
              'the disposed provider\'s focus result must not show the '
              'focus failure',
        );
        expect(
          find.byElementPredicate(
            (element) =>
                element.widget is CommentCard &&
                element.findAncestorWidgetOfExactType<FocusedThreadScreen>() !=
                    null &&
                identical(
                  Provider.of<CommentsProvider>(element, listen: false),
                  oldProvider,
                ),
            skipOffstage: false,
          ),
          findsNothing,
          reason:
              'no focused thread may open from the disposed provider\'s '
              'focus result',
        );
        expect(find.byType(PostDetailScreen, skipOffstage: false), findsOne);
      } finally {
        await harness.dispose(tester);
      }
    },
  );
}
