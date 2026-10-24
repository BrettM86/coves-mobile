import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/moderation.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/post_get_result.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/comments_provider.dart';
import 'package:coves_flutter/providers/viewer_authority_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/compose/reply_screen.dart';
import 'package:coves_flutter/screens/home/focused_thread_screen.dart';
import 'package:coves_flutter/screens/home/post_detail_screen.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/comment_service.dart';
import 'package:coves_flutter/services/comments_provider_cache.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/post_change_broadcast.dart';
import 'package:coves_flutter/services/viewer_state_hydrator.dart';
import 'package:coves_flutter/widgets/comment_card.dart';
import 'package:coves_flutter/widgets/loading_error_states.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/test_mocks.dart';

// A focused thread is pushed over its post as a pageless route and shares
// the post's comments provider. The comments cache disposes that provider
// when the signed-in DID changes (sign-in from a prompt, account switch,
// sign-out), so an open focused thread must move to the cache's live
// provider, fetch its anchor subtree again for the new session, and hold
// its own pin on the provider while open. It must manage this, and posting
// replies, on its own: the router can replace the post screen's State
// underneath it.

const _postUri = 'at://did:plc:author/social.coves.community.post/post';
const _postCid = 'post-cid';
const _firstDid = 'did:plc:alice';
const _secondDid = 'did:plc:bob';
const _otherPostUri = 'at://did:plc:author/social.coves.community.post/other';

/// A reply chain below the focused anchor. Unless the harness puts the
/// anchor in the post's first page, none of it is there, so only subtree
/// fetches load it.
const _chain = [
  'anchor',
  'level1',
  'level2',
  'level3',
  'level4',
  'level5',
  'level6',
  'level7',
  'level8',
  'level9',
];

/// How many levels below the requested comment a subtree response holds,
/// so the anchor's subtree stops at level7 and only a subtree fetched for
/// level6 reaches level8.
const _subtreeLevels = 7;

/// The comments above the anchor, top-level first, when the post's first
/// page contains the anchor. They put the anchor at the post screen's depth
/// limit, where it offers "Read 1 more reply".
const _ancestorChain = [
  'top',
  'parent1',
  'parent2',
  'parent3',
  'parent4',
  'parent5',
];

/// The rkey of the reply the viewer posts to the anchor.
const _postedReplyRkey = 'postedReply';

String _commentUri(String rkey) =>
    'at://did:plc:author/social.coves.community.comment/$rkey';

/// The viewer state the server returns to [viewerDid] (null: anonymous).
/// The first account has upvoted every comment, the second downvoted it.
CommentViewerState? _viewerStateFor(String rkey, String? viewerDid) {
  return switch (viewerDid) {
    _firstDid => CommentViewerState(
      vote: 'up',
      voteUri: 'at://did:plc:alice/social.coves.feed.vote/$rkey',
    ),
    _secondDid => CommentViewerState(
      vote: 'down',
      voteUri: 'at://did:plc:bob/social.coves.feed.vote/$rkey',
    ),
    _ => null,
  };
}

ThreadViewComment _comment(
  String rkey,
  String? viewerDid, {
  List<ThreadViewComment>? replies,
  int replyCount = 0,
  String? content,
  bool isRemoved = false,
  Set<ModerationCapability>? capabilities,
}) {
  final viewer = _viewerStateFor(rkey, viewerDid);
  return ThreadViewComment(
    comment: CommentView(
      uri: _commentUri(rkey),
      cid: 'cid-$rkey',
      record: isRemoved
          ? null
          : CommentRecord(content: content ?? 'Comment $rkey'),
      isDeleted: isRemoved,
      deletionReason: isRemoved ? 'moderator' : null,
      moderation: isRemoved
          ? const ModerationView(state: ModerationState.removed)
          : null,
      createdAt: DateTime(2025),
      indexedAt: DateTime(2025),
      author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
      post: CommentRef(uri: _postUri, cid: _postCid),
      stats: CommentStats(upvotes: 1, score: 1, replyCount: replyCount),
      viewer: capabilities == null
          ? viewer
          : CommentViewerState(
              vote: viewer?.vote,
              voteUri: viewer?.voteUri,
              moderation: capabilities,
            ),
    ),
    replies: replies,
  );
}

/// The subtree rooted at [rkey] as the server returns it to [viewerDid].
/// Once [replyPosted], the anchor also has the viewer's posted reply.
ThreadViewComment _subtreeFor(
  String rkey,
  String? viewerDid, {
  required bool replyPosted,
}) {
  final start = _chain.indexOf(rkey);
  final end = (start + _subtreeLevels).clamp(0, _chain.length - 1);
  ThreadViewComment? below;
  for (var index = end; index >= start; index--) {
    final hasReplyBeyond = index < _chain.length - 1;
    final replies = [
      ?below,
      if (_chain[index] == 'anchor' && replyPosted)
        _comment(_postedReplyRkey, viewerDid),
    ];
    below = _comment(
      _chain[index],
      viewerDid,
      replies: replies.isEmpty ? null : replies,
      replyCount: replies.isEmpty ? (hasReplyBeyond ? 1 : 0) : replies.length,
    );
  }
  return below!;
}

/// The post's first page with the anchor in it, as the server returns it
/// to [viewerDid]: the chain down to the anchor, whose replies the page's
/// depth limit truncates after level1. Deeper replies only arrive through
/// a subtree fetch.
ThreadViewComment _firstPageThroughAnchor(String? viewerDid) {
  var below = _comment(
    'anchor',
    viewerDid,
    replies: [_comment('level1', viewerDid, replyCount: 1)],
    replyCount: 1,
  );
  for (final rkey in _ancestorChain.reversed) {
    below = _comment(rkey, viewerDid, replies: [below], replyCount: 1);
  }
  return below;
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
      record: const PostRecord(content: 'Focused thread post'),
      stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 11),
    ),
  );
}

/// A comments request: the parent rkey (null for the post's first page)
/// and the signed-in DID it was sent with (null: signed out).
typedef _CommentsRequest = ({String? parentRkey, String? viewerDid});

class _HeldRequest {
  _HeldRequest(this.request, this._respond);

  final _CommentsRequest request;
  final CommentsResponse Function(_CommentsRequest request) _respond;
  final completer = Completer<CommentsResponse>();

  void answer() => completer.complete(_respond(request));
}

/// A [FakeVoteProvider] that records the comment of every vote toggle, so a
/// test can tell a disabled vote button from a live one.
class _RecordingVoteProvider extends FakeVoteProvider {
  _RecordingVoteProvider(super.authProvider);

  final List<String> toggledCommentUris = [];

  @override
  Future<bool> toggleVote({
    required String postUri,
    required String postCid,
    String direction = 'up',
  }) {
    toggledCommentUris.add(postUri);
    return super.toggleVote(
      postUri: postUri,
      postCid: postCid,
      direction: direction,
    );
  }
}

/// A post pushed over a base route, with a focused thread for a comment
/// pushed over the post, the comments cache, vote and block providers the
/// screens resolve, and the comments and create-comment requests mocked.
///
/// By default the anchor is outside the post's first page and the post
/// opens to it, pushing the focused thread. With [anchorInFirstPage] the
/// first page holds the anchor at the post screen's depth limit, with its
/// replies truncated, and the viewer opens it from "Read 1 more reply".
class _FocusedThreadOverPost {
  _FocusedThreadOverPost(
    this.auth, {
    int cacheSizeLimit = 15,
    this.anchorInFirstPage = false,
    this.ancestorCapability,
    this.secondAccountIsAdmin = false,
  }) {
    when(api.getViewerAuthority()).thenAnswer(
      (_) async =>
          auth.did == _firstDid ||
          (secondAccountIsAdmin && auth.did == _secondDid),
    );
    authority = ancestorCapability == null
        ? null
        : ViewerAuthorityProvider(apiService: api, authProvider: auth);
    votes = _RecordingVoteProvider(auth);
    blocks = BlockProvider(apiService: api, authProvider: auth);
    cache = CommentsProviderCache(
      authProvider: auth,
      voteProvider: votes,
      commentService: commentService,
      apiService: api,
      hydrator: ViewerStateHydrator(authProvider: auth, voteProvider: votes),
      maxSize: cacheSizeLimit,
      sessionKeyOf: authority == null ? null : () => authority!.sessionKey,
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
      final request = (
        parentRkey: invocation.namedArguments[#parentRkey] as String?,
        viewerDid: auth.did,
      );
      requests.add(request);
      final error = subtreeError;
      if (request.parentRkey != null && error != null) {
        throw error;
      }
      if (holdResponses) {
        final held = _HeldRequest(request, _respond);
        heldRequests.add(held);
        return held.completer.future;
      }
      return _respond(request);
    });
    when(
      commentService.createComment(
        rootUri: anyNamed('rootUri'),
        rootCid: anyNamed('rootCid'),
        parentUri: anyNamed('parentUri'),
        parentCid: anyNamed('parentCid'),
        content: anyNamed('content'),
        contentFacets: anyNamed('contentFacets'),
      ),
    ).thenAnswer((_) async {
      replyPosted = true;
      return CreateCommentResponse(
        uri: _commentUri(_postedReplyRkey),
        cid: 'cid-$_postedReplyRkey',
      );
    });
    // The post screen fetches the post again when the signed-in DID changes.
    // Mockito cannot build a placeholder of the sealed result type while
    // stubbing.
    provideDummy<PostGetResult>(const PostGetNotFound(_postUri));
    when(api.getPost(any))
        .thenAnswer((_) async => PostGetSuccess(_feedPost().post));
  }

  final FakeAuthProvider auth;

  /// Whether the server's first page holds the anchor. Clearing it after
  /// the focused thread opened drops the anchor from later first pages.
  bool anchorInFirstPage;
  final ModerationCapability? ancestorCapability;

  /// Whether the second account is an instance admin too, so the server
  /// returns it the same admin capability on the ancestor as the first.
  final bool secondAccountIsAdmin;
  late final ViewerAuthorityProvider? authority;
  final api = MockCovesApiService();
  final commentService = MockCommentService();
  final navigatorKey = GlobalKey<NavigatorState>();
  late final _RecordingVoteProvider votes;
  late final BlockProvider blocks;
  late final CommentsProviderCache cache;

  /// What the post's route shows. Replacing it replaces the post screen's
  /// State under the focused thread, as the router's rebuild of a post
  /// page does, while the pageless focused thread route stays.
  late final postRouteContent = ValueNotifier<Widget>(
    PostDetailScreen(
      sessionStamp: null,
      post: _feedPost(),
      focusCommentUri: anchorInFirstPage ? null : _commentUri('anchor'),
    ),
  );

  /// Whether the server has the reply the viewer posted to the anchor.
  bool replyPosted = false;

  /// Every comments request, in the order sent.
  final List<_CommentsRequest> requests = [];

  /// While set, every subtree request fails with this error.
  Exception? subtreeError;

  /// While true, the server answers every subtree request with no comments.
  bool emptySubtrees = false;

  /// The server's answer to [request]: the post's first page, or the
  /// subtree rooted at the requested comment.
  CommentsResponse _respond(_CommentsRequest request) {
    final parentRkey = request.parentRkey;
    final ThreadViewComment comments;
    if (parentRkey != null && emptySubtrees) {
      return CommentsResponse(post: null, comments: []);
    } else if (parentRkey != null) {
      comments = _subtreeFor(
        parentRkey,
        request.viewerDid,
        replyPosted: replyPosted,
      );
    } else if (anchorInFirstPage) {
      comments = _firstPageThroughAnchor(request.viewerDid);
    } else {
      comments = _comment('top', request.viewerDid);
    }
    final capability = ancestorCapability;
    final ancestorRkey = anchorInFirstPage ? 'parent5' : 'level5';
    final ancestor = comments.findByUri(_commentUri(ancestorRkey));
    if (capability != null && ancestor != null) {
      final isFirstAccount = request.viewerDid == _firstDid;
      final isAdmin = isFirstAccount || secondAccountIsAdmin;
      return CommentsResponse(
        post: null,
        comments: [
          comments.replaceDescendant(
            _comment(
              ancestorRkey,
              request.viewerDid,
              replies: ancestor.replies,
              replyCount: ancestor.comment.stats.replyCount,
              content: isFirstAccount
                  ? 'Admin ancestor'
                  : isAdmin
                  ? 'Fresh admin ancestor'
                  : 'Fresh ordinary ancestor',
              isRemoved: isAdmin && capability == ModerationCapability.restore,
              capabilities: isAdmin ? {capability} : const {},
            ),
          ),
        ],
      );
    }
    return CommentsResponse(post: null, comments: [comments]);
  }

  /// While true, comments requests wait in [heldRequests] for the test to
  /// answer them.
  bool holdResponses = false;
  final List<_HeldRequest> heldRequests = [];

  /// Pumps the base route, pushes the post over it and opens the focused
  /// thread on the anchor: the post opens it on its own, or with
  /// [anchorInFirstPage] the viewer taps the anchor's "Read 1 more reply".
  /// With [expectLoadedThread] false it does not require the anchor's
  /// replies to show once opened, for a test whose subtree fetch fails.
  Future<void> openFocusedThread(
    WidgetTester tester, {
    bool expectLoadedThread = true,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<PostChangeBroadcast>.value(value: PostChangeBroadcast()),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          if (authority != null)
            ChangeNotifierProvider<ViewerAuthorityProvider>.value(
              value: authority!,
            ),
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
          builder: (_) => ValueListenableBuilder<Widget>(
            valueListenable: postRouteContent,
            builder: (context, content, child) => content,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (anchorInFirstPage) {
      await tester.tap(
        find.descendant(
          of: find.byType(PostDetailScreen),
          matching: find.text('Read 1 more reply'),
        ),
      );
      await tester.pumpAndSettle();
    }
    _expectNoErrors(tester, 'after opening the focused thread');
    expect(find.byType(FocusedThreadScreen), findsOneWidget);
    if (expectLoadedThread) {
      expect(_focusedCommentCard('level1'), findsOneWidget);
    }
  }

  /// Opens the focused thread, then a nested focused thread from its
  /// "Read 1 more reply" link at the depth limit, anchored at level6.
  Future<void> openNestedFocusedThread(WidgetTester tester) async {
    await openFocusedThread(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(FocusedThreadScreen),
        matching: find.text('Read 1 more reply'),
      ),
    );
    await tester.pumpAndSettle();
    _expectNoErrors(tester, 'after opening the nested focused thread');
    expect(
      find.byType(FocusedThreadScreen, skipOffstage: false),
      findsNWidgets(2),
    );
    expect(_focusedCommentCard('level8'), findsOneWidget);
  }

  /// Replaces the post screen with a placeholder, as the router's cold-path
  /// rebuild does while it reloads the post, leaving the focused thread as
  /// the only screen on the post's comments provider.
  Future<void> replacePostScreen(WidgetTester tester) async {
    postRouteContent.value = const Scaffold(body: Text('post reloading'));
    await tester.pumpAndSettle();
    expect(find.byType(PostDetailScreen, skipOffstage: false), findsNothing);
    expect(find.byType(FocusedThreadScreen), findsOneWidget);
  }

  /// Answers every held request for the post's first page
  /// ([subtrees] false) or for a comment subtree ([subtrees] true), in the
  /// order they were sent.
  void answerHeld({required bool subtrees}) {
    final ready = heldRequests
        .where((held) => (held.request.parentRkey != null) == subtrees)
        .toList();
    heldRequests.removeWhere(ready.contains);
    for (final held in ready) {
      held.answer();
    }
  }

  /// Stops holding requests, answers every one still held, including any
  /// sent while answering, and lets the screens settle.
  Future<void> answerAllAndSettle(WidgetTester tester) async {
    holdResponses = false;
    while (heldRequests.isNotEmpty) {
      final ready = [...heldRequests];
      heldRequests.clear();
      for (final held in ready) {
        held.answer();
      }
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  /// Unmounts the tree, then disposes the providers. Called from `finally`:
  /// cached comment providers own periodic timers, and the binding fails
  /// the test on a pending timer before tear-downs run.
  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    cache.dispose();
    blocks.dispose();
    votes.dispose();
    authority?.dispose();
    auth.dispose();
    postRouteContent.dispose();
  }
}

/// Room for the whole focused reply chain, so every comment card in it is
/// built and hit-testable without scrolling.
void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Pumps a few frames without settling, so requests sent from listeners
/// and post-frame callbacks go out while responses are held.
Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
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

/// The card of the comment [rkey] in the visible focused thread.
Finder _focusedCommentCard(String rkey) {
  return find.descendant(
    of: find.byType(FocusedThreadScreen),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is CommentCard && widget.comment.uri == _commentUri(rkey),
    ),
  );
}

/// The vote button with the given accessibility [label] ('Upvote comment'
/// / 'Remove upvote', 'Downvote comment' / 'Remove downvote') on the card
/// of the comment [rkey] in the visible focused thread.
Finder _focusedVoteButton(String rkey, String label) {
  return find.descendant(
    of: _focusedCommentCard(rkey),
    matching: find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    ),
  );
}

const _voteButtonLabels = {
  'Upvote comment',
  'Remove upvote',
  'Downvote comment',
  'Remove downvote',
};

/// The upvote and downvote buttons, in that order, on the card of the
/// comment [rkey] in the visible focused thread, whatever their state.
Finder _focusedVoteButtons(String rkey) {
  return find.descendant(
    of: _focusedCommentCard(rkey),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          _voteButtonLabels.contains(widget.properties.label),
    ),
  );
}

/// Every comment card in the visible focused thread.
Finder _focusedCommentCards() {
  return find.descendant(
    of: find.byType(FocusedThreadScreen),
    matching: find.byType(CommentCard),
  );
}

/// The visible focused thread's loading indicator.
Finder _focusedLoading() {
  return find.descendant(
    of: find.byType(FocusedThreadScreen),
    matching: find.byType(InlineLoading),
  );
}

/// The visible focused thread's retryable error.
Finder _focusedError() {
  return find.descendant(
    of: find.byType(FocusedThreadScreen),
    matching: find.byType(InlineError),
  );
}

/// Fails unless the visible focused thread shows its loading indicator in
/// place of every comment of the signed-out snapshot, with no error.
void _expectLoadingInPlaceOfSnapshot(String phase) {
  expect(
    _focusedCommentCards(),
    findsNothing,
    reason:
        'the snapshot was loaded signed out, so none of its comments may '
        'show in the signed-in session $phase',
  );
  expect(_focusedLoading(), findsOneWidget, reason: 'loading $phase');
  expect(_focusedError(), findsNothing, reason: 'no error $phase');
}

/// Answers platform calls, such as the haptic feedback the comment card and
/// the composer await, which never complete in widget tests without a
/// handler.
void _answerPlatformCalls(WidgetTester tester) {
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

/// Fails unless the comments provider [focusedScreen] exposes to its
/// comment cards is the cache's live provider for the post.
void _expectExposesLiveCommentsProvider(
  WidgetTester tester,
  _FocusedThreadOverPost harness,
  Finder focusedScreen,
  String change,
) {
  final commentCard = tester.element(
    find
        .descendant(
          of: focusedScreen,
          matching: find.byType(CommentCard, skipOffstage: false),
          skipOffstage: false,
        )
        .first,
  );
  expect(
    Provider.of<CommentsProvider>(commentCard, listen: false),
    same(harness.cache.peekProvider(_postUri)),
    reason:
        'after $change the focused thread must expose the cache\'s live '
        'comments provider, never one the cache has disposed',
  );
}

/// Fails unless [route] is still the visible route, with the focused
/// thread on it.
void _expectFocusedThreadStaysOpen(
  WidgetTester tester,
  ModalRoute<Object?> route,
  String change,
) {
  expect(
    find.byType(FocusedThreadScreen),
    findsOneWidget,
    reason: '$change must leave the focused thread open',
  );
  expect(
    ModalRoute.of(tester.element(find.byType(FocusedThreadScreen))),
    same(route),
  );
  expect(route.isCurrent, isTrue);
}

ModalRoute<Object?> _visibleFocusedRoute(WidgetTester tester) {
  return ModalRoute.of(tester.element(find.byType(FocusedThreadScreen)))!;
}

/// Opens the reply composer on the focused anchor, submits [content] and
/// pumps for long enough to post it and close the composer. Returns the
/// errors thrown by the submission, which runs unawaited from the tap.
///
/// Pumps a fixed time rather than settling: a failed submission can leave
/// the composer's progress spinner running.
Future<List<Object>> _replyToFocusedAnchor(
  WidgetTester tester,
  String content,
) async {
  _answerPlatformCalls(tester);
  await tester.tap(
    find
        .descendant(
          of: _focusedCommentCard('anchor'),
          matching: find.text('Comment anchor', findRichText: true),
        )
        .first,
  );
  await tester.pumpAndSettle();
  _expectNoErrors(tester, 'after opening the reply composer');
  final composer = find.byType(ReplyScreen);
  expect(composer, findsOneWidget);

  await tester.enterText(
    find.descendant(of: composer, matching: find.byType(TextField)),
    content,
  );
  await tester.pump();
  final submissionErrors = <Object>[];
  await runZonedGuarded(
    () =>
        tester.tap(find.descendant(of: composer, matching: find.text('Send'))),
    (error, stack) => submissionErrors.add(error),
  );
  for (var frame = 0; frame < 10; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return submissionErrors;
}

/// Acquires and releases another post. With a cache size limit of one,
/// this evicts the post's provider unless an owner still has it pinned.
void _applyEvictionPressure(CommentsProviderCache cache) {
  cache
    ..acquireProvider(postUri: _otherPostUri, postCid: 'other-cid')
    ..releaseProvider(_otherPostUri);
}

void main() {
  // Each order of the two fetches that follow a sign-in: the post screen
  // refreshes the post's first page, the focused thread its anchor
  // subtree. A subtree response that lands after a first-page refresh is
  // discarded by the provider, so the focused thread must still end up
  // with a subtree fetched for the new account.
  for (final rootLandsFirst in [true, false]) {
    final order = rootLandsFirst
        ? 'the post\'s refresh lands before the focused subtree'
        : 'the focused subtree lands before the post\'s refresh';

    testWidgets(
      'given a signed-out viewer in a focused thread over a post, when they '
      'sign in and $order, then the focused thread stays open on the live '
      'provider with their vote on a reply outside the post\'s first page',
      (tester) async {
        _useTallViewport(tester);
        final harness = _FocusedThreadOverPost(FakeAuthProvider());
        try {
          await harness.openFocusedThread(tester);
          final focusedRoute = _visibleFocusedRoute(tester);
          expect(harness.votes.isLiked(_commentUri('level1')), isFalse);
          final requestsBeforeSignIn = harness.requests.length;

          harness.holdResponses = true;
          harness.auth.setSignedInDid(_firstDid);
          await _pumpFrames(tester);
          _expectNoErrors(tester, 'while the refetches are in flight');

          harness.answerHeld(subtrees: !rootLandsFirst);
          await _pumpFrames(tester);
          harness.answerHeld(subtrees: rootLandsFirst);
          await _pumpFrames(tester);
          await harness.answerAllAndSettle(tester);
          _expectNoErrors(tester, 'after the refetches settled');

          expect(
            harness.votes.isLiked(_commentUri('level1')),
            isTrue,
            reason:
                'the focused thread must fetch its anchor subtree again for '
                'the new session when $order',
          );
          expect(_focusedVoteButton('level1', 'Remove upvote'), findsOneWidget);
          _expectFocusedThreadStaysOpen(tester, focusedRoute, 'signing in');
          _expectExposesLiveCommentsProvider(
            tester,
            harness,
            find.byType(FocusedThreadScreen),
            'signing in',
          );
          expect(
            harness.requests.skip(requestsBeforeSignIn),
            contains((parentRkey: 'anchor', viewerDid: _firstDid)),
          );
        } finally {
          await harness.dispose(tester);
        }
      },
    );
  }

  testWidgets(
    'given a signed-in viewer in a focused thread over a post, when they '
    'switch accounts, then the focused thread stays open on the live '
    'provider with the new account\'s vote on a reply outside the post\'s '
    'first page',
    (tester) async {
      _useTallViewport(tester);
      final harness = _FocusedThreadOverPost(
        FakeAuthProvider(signedInDid: _firstDid),
      );
      try {
        await harness.openFocusedThread(tester);
        final focusedRoute = _visibleFocusedRoute(tester);
        expect(_focusedVoteButton('level1', 'Remove upvote'), findsOneWidget);
        final requestsBeforeSwitch = harness.requests.length;

        harness.auth.setSignedInDid(_secondDid);
        await tester.pump();
        _expectNoErrors(tester, 'on the frame after switching accounts');
        await tester.pumpAndSettle();
        _expectNoErrors(tester, 'after switching accounts settled');

        _expectFocusedThreadStaysOpen(
          tester,
          focusedRoute,
          'switching accounts',
        );
        _expectExposesLiveCommentsProvider(
          tester,
          harness,
          find.byType(FocusedThreadScreen),
          'switching accounts',
        );
        expect(
          harness.requests.skip(requestsBeforeSwitch),
          contains((parentRkey: 'anchor', viewerDid: _secondDid)),
          reason: 'the anchor subtree must be fetched for the second account',
        );
        expect(harness.votes.isLiked(_commentUri('level1')), isFalse);
        expect(
          harness.votes.getVoteState(_commentUri('level1'))?.direction,
          'down',
        );
        expect(_focusedVoteButton('level1', 'Remove downvote'), findsOneWidget);
        expect(_focusedVoteButton('level1', 'Upvote comment'), findsOneWidget);
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  testWidgets(
    'given a focused thread whose post screen underneath was replaced, when '
    'the viewer signs in, then the focused thread on its own moves to the '
    'live provider and refetches its subtree with their vote',
    (tester) async {
      _useTallViewport(tester);
      final harness = _FocusedThreadOverPost(FakeAuthProvider());
      try {
        await harness.openFocusedThread(tester);
        await harness.replacePostScreen(tester);
        final focusedRoute = _visibleFocusedRoute(tester);
        final requestsBeforeSignIn = harness.requests.length;

        harness.auth.setSignedInDid(_firstDid);
        await tester.pump();
        _expectNoErrors(tester, 'on the frame after signing in');
        await tester.pumpAndSettle();
        _expectNoErrors(tester, 'after signing in settled');

        _expectFocusedThreadStaysOpen(tester, focusedRoute, 'signing in');
        _expectExposesLiveCommentsProvider(
          tester,
          harness,
          find.byType(FocusedThreadScreen),
          'signing in with no post screen underneath',
        );
        expect(
          harness.requests.skip(requestsBeforeSignIn),
          contains((parentRkey: 'anchor', viewerDid: _firstDid)),
          reason: 'the anchor subtree must be fetched for the new session',
        );
        expect(harness.votes.isLiked(_commentUri('level1')), isTrue);
        expect(_focusedVoteButton('level1', 'Remove upvote'), findsOneWidget);
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  testWidgets(
    'given a nested focused thread over a focused thread over a post, when '
    'the viewer signs in, then both stay open on the live provider and the '
    'nested one refetches its subtree with their vote',
    (tester) async {
      _useTallViewport(tester);
      final harness = _FocusedThreadOverPost(FakeAuthProvider());
      try {
        await harness.openNestedFocusedThread(tester);
        final nestedRoute = _visibleFocusedRoute(tester);
        final outerRoute = ModalRoute.of(
          tester.element(
            find.byType(FocusedThreadScreen, skipOffstage: false).first,
          ),
        )!;
        expect(outerRoute, isNot(same(nestedRoute)));
        expect(harness.votes.isLiked(_commentUri('level8')), isFalse);
        final requestsBeforeSignIn = harness.requests.length;

        harness.auth.setSignedInDid(_firstDid);
        await tester.pump();
        _expectNoErrors(tester, 'on the frame after signing in');
        await tester.pumpAndSettle();
        _expectNoErrors(tester, 'after signing in settled');

        _expectFocusedThreadStaysOpen(tester, nestedRoute, 'signing in');
        expect(
          outerRoute.isActive,
          isTrue,
          reason: 'the outer focused thread must stay under the nested one',
        );
        _expectExposesLiveCommentsProvider(
          tester,
          harness,
          find.byType(FocusedThreadScreen),
          'signing in (nested thread)',
        );
        _expectExposesLiveCommentsProvider(
          tester,
          harness,
          find.byType(FocusedThreadScreen, skipOffstage: false).first,
          'signing in (outer thread)',
        );
        final requestsAfterSignIn = harness.requests.skip(requestsBeforeSignIn);
        expect(
          requestsAfterSignIn,
          contains((parentRkey: 'level6', viewerDid: _firstDid)),
          reason: 'the nested anchor subtree must be fetched again',
        );
        expect(
          requestsAfterSignIn,
          contains((parentRkey: 'anchor', viewerDid: _firstDid)),
          reason: 'the outer anchor subtree must be fetched again',
        );
        expect(harness.votes.isLiked(_commentUri('level8')), isTrue);
        expect(_focusedVoteButton('level8', 'Remove upvote'), findsOneWidget);
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  testWidgets(
    'given a focused thread over a replaced post screen and a cache at its '
    'size limit, when the viewer signs in, then the focused thread keeps '
    'the post\'s provider pinned while open and releases it when closed',
    (tester) async {
      _useTallViewport(tester);
      final harness = _FocusedThreadOverPost(
        FakeAuthProvider(),
        cacheSizeLimit: 1,
      );
      try {
        await harness.openFocusedThread(tester);
        // Control: the post screen's pin keeps the provider through the
        // same pressure.
        _applyEvictionPressure(harness.cache);
        expect(harness.cache.hasProvider(_postUri), isTrue);
        await harness.replacePostScreen(tester);

        harness.auth.setSignedInDid(_firstDid);
        await tester.pumpAndSettle();
        _expectNoErrors(tester, 'after signing in settled');
        final liveProvider = harness.cache.peekProvider(_postUri);

        _applyEvictionPressure(harness.cache);
        expect(
          harness.cache.hasProvider(_postUri),
          isTrue,
          reason:
              'the open focused thread must keep the post\'s provider pinned '
              'after the viewer signs in',
        );
        expect(harness.cache.peekProvider(_postUri), same(liveProvider));
        _expectExposesLiveCommentsProvider(
          tester,
          harness,
          find.byType(FocusedThreadScreen),
          'signing in and cache pressure',
        );
        _expectNoErrors(tester, 'after cache pressure');

        // A notification that keeps the DID, as a token refresh or the
        // start of a sign-in sends, must not take another pin.
        harness.auth.notifyWithoutChange();
        await tester.pumpAndSettle();
        _expectNoErrors(tester, 'after a notification that kept the DID');

        harness.navigatorKey.currentState!.pop();
        await tester.pumpAndSettle();
        _expectNoErrors(tester, 'after closing the focused thread');
        expect(find.byType(FocusedThreadScreen), findsNothing);
        expect(find.text('post reloading'), findsOneWidget);

        _applyEvictionPressure(harness.cache);
        expect(
          harness.cache.hasProvider(_postUri),
          isFalse,
          reason:
              'a closed focused thread must release its pin, leaving the '
              'provider evictable',
        );
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  testWidgets(
    'given a focused thread over a replaced post screen and a second owner '
    'that acquired the post after an account switch, when the focused '
    'thread closes, then the second owner still holds its pin',
    (tester) async {
      _useTallViewport(tester);
      final harness = _FocusedThreadOverPost(
        FakeAuthProvider(signedInDid: _firstDid),
        cacheSizeLimit: 1,
      );
      try {
        await harness.openFocusedThread(tester);
        await harness.replacePostScreen(tester);

        harness.auth.setSignedInDid(_secondDid);
        await tester.pumpAndSettle();
        _expectNoErrors(tester, 'after switching accounts settled');

        // Another owner of the same post, such as the post screen the
        // router mounts again once it has reloaded the post.
        final secondOwnerProvider = harness.cache.acquireProvider(
          postUri: _postUri,
          postCid: _postCid,
        );

        harness.navigatorKey.currentState!.pop();
        await tester.pumpAndSettle();
        _expectNoErrors(tester, 'after closing the focused thread');
        expect(find.byType(FocusedThreadScreen), findsNothing);

        _applyEvictionPressure(harness.cache);
        expect(
          harness.cache.peekProvider(_postUri),
          same(secondOwnerProvider),
          reason:
              'closing the focused thread must release only its own pin, '
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

  testWidgets(
    'given a signed-in viewer in a focused thread over a post, when they '
    'sign out, then the post and the focused thread pop back to the first '
    'route',
    (tester) async {
      _useTallViewport(tester);
      final harness = _FocusedThreadOverPost(
        FakeAuthProvider(signedInDid: _firstDid),
      );
      try {
        await harness.openFocusedThread(tester);

        harness.auth.setSignedInDid(null);
        await tester.pumpAndSettle();

        _expectNoErrors(tester, 'after signing out');
        expect(
          find.byType(FocusedThreadScreen, skipOffstage: false),
          findsNothing,
        );
        expect(
          find.byType(PostDetailScreen, skipOffstage: false),
          findsNothing,
        );
        expect(find.text('base route'), findsOneWidget);
        expect(harness.navigatorKey.currentState!.canPop(), isFalse);
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  // Replying from a focused thread after signing in from a sign-in prompt:
  // the router may have replaced the post screen underneath by then, and
  // the reply must not depend on that screen.
  for (final postScreenReplaced in [false, true]) {
    final underneath = postScreenReplaced
        ? 'whose post screen underneath was replaced'
        : 'over its post screen';

    testWidgets(
      'given a signed-out viewer in a focused thread $underneath, when they '
      'sign in and reply to the anchor, then the reply is posted and '
      'confirmed, the composer closes and the reply shows in the thread',
      (tester) async {
        _useTallViewport(tester);
        final harness = _FocusedThreadOverPost(FakeAuthProvider());
        try {
          await harness.openFocusedThread(tester);
          if (postScreenReplaced) {
            await harness.replacePostScreen(tester);
          }
          harness.auth.setSignedInDid(_firstDid);
          await tester.pumpAndSettle();
          _expectNoErrors(tester, 'after signing in settled');
          final focusedRoute = _visibleFocusedRoute(tester);

          final submissionErrors = await _replyToFocusedAnchor(
            tester,
            'Thanks for the context',
          );

          expect(
            submissionErrors,
            isEmpty,
            reason: 'submitting the reply must not throw',
          );
          _expectNoErrors(tester, 'after submitting the reply');
          verify(
            harness.commentService.createComment(
              rootUri: _postUri,
              rootCid: _postCid,
              parentUri: _commentUri('anchor'),
              parentCid: 'cid-anchor',
              content: 'Thanks for the context',
              contentFacets: anyNamed('contentFacets'),
            ),
          ).called(1);
          expect(find.text('Reply posted'), findsOneWidget);
          expect(
            find.byType(ReplyScreen),
            findsNothing,
            reason: 'the composer must close once the reply is posted',
          );
          _expectFocusedThreadStaysOpen(tester, focusedRoute, 'replying');
          _expectExposesLiveCommentsProvider(
            tester,
            harness,
            find.byType(FocusedThreadScreen),
            'replying',
          );
          expect(_focusedCommentCard(_postedReplyRkey), findsOneWidget);
        } finally {
          await harness.dispose(tester);
        }
      },
    );
  }

  testWidgets(
    'given a signed-in viewer in a focused thread over its post screen, when '
    'posting a reply to the anchor fails, then the comment error shows, the '
    'composer stays open with the draft and the subtree is not refetched',
    (tester) async {
      _useTallViewport(tester);
      final harness = _FocusedThreadOverPost(
        FakeAuthProvider(signedInDid: _firstDid),
      );
      try {
        await harness.openFocusedThread(tester);
        when(
          harness.commentService.createComment(
            rootUri: anyNamed('rootUri'),
            rootCid: anyNamed('rootCid'),
            parentUri: anyNamed('parentUri'),
            parentCid: anyNamed('parentCid'),
            content: anyNamed('content'),
            contentFacets: anyNamed('contentFacets'),
          ),
        ).thenAnswer(
          (_) async => throw ApiException('Rejected', statusCode: 500),
        );
        final requestsBeforeReply = harness.requests.length;

        final submissionErrors = await _replyToFocusedAnchor(
          tester,
          'Thanks for the context',
        );

        // ReplyScreen catches the rethrown failure to keep itself open, so
        // nothing escapes the submission.
        expect(submissionErrors, isEmpty);
        _expectNoErrors(tester, 'after the reply failed');
        verify(
          harness.commentService.createComment(
            rootUri: _postUri,
            rootCid: _postCid,
            parentUri: _commentUri('anchor'),
            parentCid: 'cid-anchor',
            content: 'Thanks for the context',
            contentFacets: anyNamed('contentFacets'),
          ),
        ).called(1);
        expect(
          find.text('Could not post comment. Please try again.'),
          findsOneWidget,
        );
        expect(find.text('Reply posted', skipOffstage: false), findsNothing);
        final composer = find.byType(ReplyScreen);
        expect(
          composer,
          findsOneWidget,
          reason: 'a failed reply must leave the composer open',
        );
        expect(
          tester
              .widget<TextField>(
                find.descendant(of: composer, matching: find.byType(TextField)),
              )
              .controller!
              .text,
          'Thanks for the context',
          reason: 'the draft must survive a failed reply',
        );
        expect(
          harness.requests
              .skip(requestsBeforeReply)
              .where((request) => request.parentRkey == 'anchor'),
          isEmpty,
          reason: 'a failed reply must not refetch the anchor subtree',
        );
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  testWidgets(
    'given a reply to the anchor in flight, when the focused thread is '
    'removed under the composer and the reply then fails, then the comment '
    'error still shows',
    (tester) async {
      _useTallViewport(tester);
      final harness = _FocusedThreadOverPost(
        FakeAuthProvider(signedInDid: _firstDid),
      );
      try {
        await harness.openFocusedThread(tester);
        final focusedRoute = _visibleFocusedRoute(tester);
        // Made when the request is sent, inside the zone the submission runs
        // in: a future's error does not reach a listener in another error
        // zone
        late final Completer<CreateCommentResponse> createComment;
        when(
          harness.commentService.createComment(
            rootUri: anyNamed('rootUri'),
            rootCid: anyNamed('rootCid'),
            parentUri: anyNamed('parentUri'),
            parentCid: anyNamed('parentCid'),
            content: anyNamed('content'),
            contentFacets: anyNamed('contentFacets'),
          ),
        ).thenAnswer((_) {
          createComment = Completer<CreateCommentResponse>();
          return createComment.future;
        });

        final submissionErrors = await _replyToFocusedAnchor(
          tester,
          'Thanks for the context',
        );
        expect(submissionErrors, isEmpty);
        expect(find.byType(ReplyScreen), findsOneWidget);

        harness.navigatorKey.currentState!.removeRoute(focusedRoute);
        await tester.pump();
        expect(
          find.byType(FocusedThreadScreen, skipOffstage: false),
          findsNothing,
        );

        createComment.completeError(ApiException('Rejected', statusCode: 500));
        for (var frame = 0; frame < 5; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        _expectNoErrors(tester, 'after the reply failed');
        expect(
          find.text('Could not post comment. Please try again.'),
          findsOneWidget,
          reason: 'the composer leaves reporting the failure to its parent',
        );
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  // The "continue this thread" case: the anchor is in the post's first page
  // with its replies truncated by depth, so the deeper replies exist only in
  // the anchor's subtree. After a sign-in the post screen refreshes the
  // whole thread and the focused thread its anchor subtree, in either order.
  for (final subtreeLandsFirst in [true, false]) {
    final order = subtreeLandsFirst
        ? 'the focused subtree lands before the post\'s refresh'
        : 'the post\'s refresh lands before the focused subtree';

    testWidgets(
      'given a signed-out viewer in a focused thread opened from "Read 1 '
      'more reply" on an anchor in the post\'s first page, when they sign in '
      'and $order, then the focused thread keeps the replies only the '
      'anchor\'s subtree has, with their votes',
      (tester) async {
        _useTallViewport(tester);
        final harness = _FocusedThreadOverPost(
          FakeAuthProvider(),
          anchorInFirstPage: true,
        );
        try {
          await harness.openFocusedThread(tester);
          final focusedRoute = _visibleFocusedRoute(tester);
          expect(
            _focusedCommentCard('level6'),
            findsOneWidget,
            reason: 'control: the anchor\'s subtree shows replies past level1',
          );

          harness.holdResponses = true;
          harness.auth.setSignedInDid(_firstDid);
          await _pumpFrames(tester);
          _expectNoErrors(tester, 'while the refetches are in flight');
          expect(
            harness.heldRequests.map((held) => held.request),
            containsAll(<_CommentsRequest>[
              (parentRkey: null, viewerDid: _firstDid),
              (parentRkey: 'anchor', viewerDid: _firstDid),
            ]),
          );

          harness.answerHeld(subtrees: subtreeLandsFirst);
          await _pumpFrames(tester);
          harness.answerHeld(subtrees: !subtreeLandsFirst);
          await _pumpFrames(tester);
          await harness.answerAllAndSettle(tester);
          _expectNoErrors(tester, 'after the refetches settled');

          for (final rkey in ['level2', 'level6']) {
            expect(
              _focusedCommentCard(rkey),
              findsOneWidget,
              reason:
                  '$rkey is only in the anchor\'s subtree, so the focused '
                  'thread must keep showing it when $order',
            );
          }
          expect(harness.votes.isLiked(_commentUri('level6')), isTrue);
          expect(_focusedVoteButton('level6', 'Remove upvote'), findsOneWidget);
          _expectFocusedThreadStaysOpen(tester, focusedRoute, 'signing in');
          _expectExposesLiveCommentsProvider(
            tester,
            harness,
            find.byType(FocusedThreadScreen),
            'signing in',
          );
        } finally {
          await harness.dispose(tester);
        }
      },
    );
  }

  testWidgets('given a signed-in viewer in a focused thread whose post screen '
      'underneath was replaced, when they sign out, then the focused thread '
      'moves to the live provider and holds one pin on it until closed', (
    tester,
  ) async {
    _useTallViewport(tester);
    final harness = _FocusedThreadOverPost(
      FakeAuthProvider(signedInDid: _firstDid),
      cacheSizeLimit: 1,
    );
    try {
      await harness.openFocusedThread(tester);
      await harness.replacePostScreen(tester);

      harness.auth.setSignedInDid(null);
      await tester.pump();
      _expectNoErrors(tester, 'on the frame after signing out');
      await tester.pumpAndSettle();
      _expectNoErrors(tester, 'after signing out settled');

      expect(
        find.byType(FocusedThreadScreen),
        findsOneWidget,
        reason: 'with no post screen underneath nothing pops it',
      );
      _expectExposesLiveCommentsProvider(
        tester,
        harness,
        find.byType(FocusedThreadScreen),
        'signing out with no post screen underneath',
      );
      final liveProvider = harness.cache.peekProvider(_postUri);
      expect(liveProvider, isNotNull);

      _applyEvictionPressure(harness.cache);
      expect(
        harness.cache.peekProvider(_postUri),
        same(liveProvider),
        reason:
            'the open focused thread must keep the post\'s provider pinned '
            'after the viewer signs out',
      );

      // Another owner of the same post, such as the post screen the
      // router mounts again once it has reloaded the post.
      final secondOwnerProvider = harness.cache.acquireProvider(
        postUri: _postUri,
        postCid: _postCid,
      );
      expect(secondOwnerProvider, same(liveProvider));

      harness.navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      _expectNoErrors(tester, 'after closing the focused thread');
      expect(find.byType(FocusedThreadScreen), findsNothing);

      _applyEvictionPressure(harness.cache);
      expect(
        harness.cache.peekProvider(_postUri),
        same(secondOwnerProvider),
        reason:
            'closing the focused thread must release only its own pin, '
            'not the second owner\'s',
      );

      harness.cache.releaseProvider(_postUri);
      _applyEvictionPressure(harness.cache);
      expect(
        harness.cache.hasProvider(_postUri),
        isFalse,
        reason:
            'the focused thread must hold exactly one pin, so with every '
            'owner released the provider is evictable',
      );
    } finally {
      await harness.dispose(tester);
    }
  });

  // After a sign-in the focused thread's snapshot carries the signed-out
  // session's viewer state, and the vote provider holds no vote for it. Its
  // comments must not be shown with live vote and reply controls until the
  // new session's subtree lands: a tap on upvote could otherwise delete a
  // vote the account already has.
  testWidgets(
    'given a signed-out viewer in a focused thread whose snapshot has '
    'replies, when they sign in and the new session\'s subtree is still in '
    'flight, then the thread shows a loader in place of the snapshot until '
    'the subtree lands with their votes',
    (tester) async {
      _useTallViewport(tester);
      final harness = _FocusedThreadOverPost(FakeAuthProvider());
      try {
        await harness.openFocusedThread(tester);
        expect(
          _focusedCommentCard('level3'),
          findsOneWidget,
          reason: 'control: the snapshot has replies',
        );

        harness.holdResponses = true;
        harness.auth.setSignedInDid(_firstDid);
        await _pumpFrames(tester);
        _expectNoErrors(tester, 'while the subtree is in flight');
        expect(
          harness.heldRequests.map((held) => held.request),
          contains((parentRkey: 'anchor', viewerDid: _firstDid)),
        );
        _expectLoadingInPlaceOfSnapshot('while the subtree is in flight');

        harness.answerHeld(subtrees: true);
        await _pumpFrames(tester);
        _expectNoErrors(tester, 'after the subtree landed');

        expect(_focusedLoading(), findsNothing);
        expect(_focusedVoteButton('anchor', 'Remove upvote'), findsOneWidget);
        expect(_focusedVoteButton('level1', 'Remove upvote'), findsOneWidget);
        expect(_focusedVoteButton('level6', 'Remove upvote'), findsOneWidget);

        await harness.answerAllAndSettle(tester);
        _expectNoErrors(tester, 'after the post\'s refresh settled');
        expect(_focusedVoteButton('level1', 'Remove upvote'), findsOneWidget);
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  testWidgets(
    'given a signed-out viewer in a focused thread, when they sign in and '
    'the post\'s refresh lands while the first subtree fetch is in flight, '
    'then the thread keeps loading through the second fetch, never shows '
    'an error, and then shows the replies with their votes',
    (tester) async {
      _useTallViewport(tester);
      final harness = _FocusedThreadOverPost(FakeAuthProvider());
      try {
        await harness.openFocusedThread(tester);
        final requestsBeforeSignIn = harness.requests.length;

        harness.holdResponses = true;
        harness.auth.setSignedInDid(_firstDid);
        await _pumpFrames(tester);
        _expectNoErrors(tester, 'while the fetches are in flight');
        expect(
          harness.heldRequests.map((held) => held.request),
          containsAll(<_CommentsRequest>[
            (parentRkey: null, viewerDid: _firstDid),
            (parentRkey: 'anchor', viewerDid: _firstDid),
          ]),
        );
        _expectLoadingInPlaceOfSnapshot('while the fetches are in flight');

        harness.answerHeld(subtrees: false);
        await _pumpFrames(tester);
        _expectNoErrors(tester, 'after the post\'s refresh landed');
        _expectLoadingInPlaceOfSnapshot('after the post\'s refresh landed');

        // The provider discards this subtree: the refresh landed after its
        // fetch started.
        harness.answerHeld(subtrees: true);
        await _pumpFrames(tester);
        _expectNoErrors(tester, 'after the first subtree was discarded');
        _expectLoadingInPlaceOfSnapshot(
          'after the first subtree was discarded',
        );
        expect(
          harness.requests
              .skip(requestsBeforeSignIn)
              .where(
                (request) =>
                    request == (parentRkey: 'anchor', viewerDid: _firstDid),
              ),
          hasLength(2),
          reason: 'the discarded subtree fetch must be followed by another',
        );

        await harness.answerAllAndSettle(tester);
        _expectNoErrors(tester, 'after the second subtree landed');
        expect(_focusedLoading(), findsNothing);
        expect(_focusedError(), findsNothing);
        expect(_focusedVoteButton('anchor', 'Remove upvote'), findsOneWidget);
        expect(_focusedVoteButton('level1', 'Remove upvote'), findsOneWidget);
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  for (final failure in ['fails', 'returns no subtree']) {
    testWidgets(
      'given a signed-out viewer in a focused thread whose snapshot has '
      'replies, when they sign in and the new session\'s subtree fetch '
      '$failure, then a retryable error replaces the snapshot and Retry '
      'shows the replies with their votes',
      (tester) async {
        _useTallViewport(tester);
        final harness = _FocusedThreadOverPost(FakeAuthProvider());
        try {
          await harness.openFocusedThread(tester);
          expect(
            _focusedCommentCard('level3'),
            findsOneWidget,
            reason: 'control: the snapshot has replies',
          );
          if (failure == 'fails') {
            harness.subtreeError = ApiException('Unavailable', statusCode: 503);
          } else {
            harness.emptySubtrees = true;
          }

          harness.auth.setSignedInDid(_firstDid);
          await tester.pumpAndSettle();
          _expectNoErrors(tester, 'after the subtree fetch $failure');

          expect(
            _focusedError(),
            findsOneWidget,
            reason:
                'a subtree fetch that $failure after a sign-in must show a '
                'retryable error, whatever the snapshot holds',
          );
          final retry = find.descendant(
            of: _focusedError(),
            matching: find.text('Retry'),
          );
          expect(retry, findsOneWidget);
          expect(
            _focusedCommentCards(),
            findsNothing,
            reason:
                'the signed-out snapshot must not show in the signed-in '
                'session after its subtree fetch $failure',
          );

          harness
            ..subtreeError = null
            ..emptySubtrees = false;
          await tester.tap(retry);
          await tester.pumpAndSettle();
          _expectNoErrors(tester, 'after Retry');

          expect(_focusedError(), findsNothing);
          expect(_focusedLoading(), findsNothing);
          expect(_focusedVoteButton('anchor', 'Remove upvote'), findsOneWidget);
          expect(_focusedVoteButton('level1', 'Remove upvote'), findsOneWidget);
        } finally {
          await harness.dispose(tester);
        }
      },
    );
  }

  // Ancestors come from the snapshot taken when the focused thread opened
  // and are never fetched here. After a sign-in only an ancestor in the
  // post's newly loaded tree has its vote state for the new session.
  testWidgets(
    'given a signed-out viewer in a nested focused thread whose ancestors '
    'are outside the post\'s first page, when they sign in, then tapping an '
    'ancestor\'s vote buttons or its text does nothing',
    (tester) async {
      _useTallViewport(tester);
      final harness = _FocusedThreadOverPost(FakeAuthProvider());
      try {
        await harness.openNestedFocusedThread(tester);
        expect(
          _focusedCommentCard('level5'),
          findsOneWidget,
          reason: 'control: level5 is an ancestor of the nested thread',
        );

        harness.auth.setSignedInDid(_firstDid);
        await tester.pumpAndSettle();
        _expectNoErrors(tester, 'after signing in settled');
        expect(
          harness.cache
              .peekProvider(_postUri)!
              .comments
              .any((root) => root.findByUri(_commentUri('level5')) != null),
          isFalse,
          reason: 'control: the ancestor is outside the post\'s first page',
        );

        final voteButtons = _focusedVoteButtons('level5');
        expect(voteButtons, findsNWidgets(2));
        expect(voteButtons.hitTestable(), findsNWidgets(2));
        final voteStateBefore = harness.votes.getVoteState(
          _commentUri('level5'),
        );
        _answerPlatformCalls(tester);

        await tester.tap(voteButtons.first);
        await tester.pumpAndSettle();
        await tester.tap(voteButtons.last);
        await tester.pumpAndSettle();
        _expectNoErrors(tester, 'after tapping the ancestor\'s votes');
        expect(
          harness.votes.toggledCommentUris,
          isEmpty,
          reason:
              'an ancestor outside the new session\'s loaded tree must not '
              'send a vote',
        );
        expect(
          harness.votes.getVoteState(_commentUri('level5')),
          same(voteStateBefore),
        );
        expect(
          tester
              .widgetList<Semantics>(voteButtons)
              .map((button) => button.properties.enabled),
          [false, false],
          reason: 'the disabled vote buttons must report it',
        );

        await tester.tap(
          find
              .descendant(
                of: _focusedCommentCard('level5'),
                matching: find.text('Comment level5', findRichText: true),
              )
              .first,
        );
        await tester.pumpAndSettle();
        _expectNoErrors(tester, 'after tapping the ancestor\'s text');
        expect(
          find.byType(ReplyScreen),
          findsNothing,
          reason:
              'an ancestor outside the new session\'s loaded tree must not '
              'open the reply composer',
        );
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  testWidgets(
    'given a signed-out viewer in a focused thread opened from "Read 1 more '
    'reply" on an anchor in the post\'s first page, when they sign in, then '
    'an ancestor in the new first page keeps its votes',
    (tester) async {
      _useTallViewport(tester);
      final harness = _FocusedThreadOverPost(
        FakeAuthProvider(),
        anchorInFirstPage: true,
      );
      try {
        await harness.openFocusedThread(tester);
        expect(
          _focusedCommentCard('parent5'),
          findsOneWidget,
          reason: 'control: parent5 is an ancestor of the focused thread',
        );

        harness.auth.setSignedInDid(_firstDid);
        await tester.pumpAndSettle();
        _expectNoErrors(tester, 'after signing in settled');

        expect(_focusedVoteButton('parent5', 'Remove upvote'), findsOneWidget);
        final voteButtons = _focusedVoteButtons('parent5');
        expect(
          tester
              .widgetList<Semantics>(voteButtons)
              .map((button) => button.properties.enabled),
          [true, true],
        );
        expect(voteButtons.hitTestable(), findsNWidgets(2));
        _answerPlatformCalls(tester);

        await tester.tap(voteButtons.first);
        await tester.pumpAndSettle();
        expect(harness.votes.toggledCommentUris, [
          _commentUri('parent5'),
        ], reason: 'an ancestor in the new first page must keep its votes');
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  for (final capability in [
    ModerationCapability.remove,
    ModerationCapability.restore,
  ]) {
    for (final freshAncestor in [false, true]) {
      final action = capability == ModerationCapability.remove
          ? 'Remove comment'
          : 'Restore comment';
      final boundary = freshAncestor
          ? 'fresh B ancestor replaces A content and capabilities'
          : 'retained A ancestor absent from B tree has no admin action';
      testWidgets('P-C1 admin A to ordinary B: $action, $boundary', (
        tester,
      ) async {
        _useTallViewport(tester);
        final harness = _FocusedThreadOverPost(
          FakeAuthProvider(signedInDid: _firstDid),
          anchorInFirstPage: freshAncestor,
          ancestorCapability: capability,
        );
        final ancestorRkey = freshAncestor ? 'parent5' : 'level5';
        Finder options() => find.descendant(
          of: _focusedCommentCard(ancestorRkey),
          matching: find.byTooltip('Comment options'),
        );
        Future<void> openOptions() async {
          await tester.ensureVisible(options());
          await tester.tap(options());
          await _pumpFrames(tester);
        }

        try {
          if (freshAncestor) {
            await harness.openFocusedThread(tester);
          } else {
            await harness.openNestedFocusedThread(tester);
          }
          final firstProvider = harness.cache.peekProvider(_postUri)!;
          final firstSession = harness.authority!.sessionKey;
          expect(
            harness.authority!.status,
            ViewerAuthorityStatus.instanceAdmin,
          );
          expect(firstProvider.sessionStamp, firstSession);
          await openOptions();
          expect(
            find.text(action),
            findsOneWidget,
            reason: 'control: the current admin A ancestor offers its tool',
          );
          await tester.tap(options());
          await tester.pumpAndSettle();

          harness.holdResponses = true;
          harness.auth.setSignedInDid(_secondDid);
          await _pumpFrames(tester);
          _expectNoErrors(tester, 'during the account B loading boundary');
          expect(harness.auth.did, _secondDid);
          expect(harness.authority!.status, ViewerAuthorityStatus.notAdmin);
          expect(harness.authority!.sessionKey, isNot(firstSession));
          expect(
            harness.cache.peekProvider(_postUri),
            isNot(same(firstProvider)),
          );
          expect(
            harness.heldRequests.map((held) => held.request),
            contains((
              parentRkey: freshAncestor ? 'anchor' : 'level6',
              viewerDid: _secondDid,
            )),
          );
          if (options().evaluate().isNotEmpty) {
            await openOptions();
            expect(
              find.text(action),
              findsNothing,
              reason: 'A capabilities must stay unavailable while B loads',
            );
            await tester.tap(options());
            await tester.pump();
          }

          await harness.answerAllAndSettle(tester);
          _expectNoErrors(tester, 'after account B responses landed');
          _expectExposesLiveCommentsProvider(
            tester,
            harness,
            find.byType(FocusedThreadScreen),
            'switching from admin A to B',
          );
          final provider = harness.cache.peekProvider(_postUri)!;
          expect(provider.sessionStamp, harness.authority!.sessionKey);
          final loadedAncestor = provider.comments
              .map((root) => root.findByUri(_commentUri(ancestorRkey)))
              .nonNulls;
          expect(
            loadedAncestor,
            freshAncestor ? hasLength(1) : isEmpty,
            reason: 'control: B actually loaded the selected ancestor input',
          );
          expect(_focusedCommentCard(ancestorRkey), findsOneWidget);
          if (freshAncestor) {
            expect(
              loadedAncestor.single.comment.content,
              'Fresh ordinary ancestor',
            );
            expect(loadedAncestor.single.comment.viewer!.moderation, isEmpty);
            expect(
              find.descendant(
                of: _focusedCommentCard(ancestorRkey),
                matching: find.text(
                  'Fresh ordinary ancestor',
                  findRichText: true,
                ),
              ),
              findsOneWidget,
              reason:
                  'the rendered ancestor must use B content, not A snapshot',
            );
            expect(
              tester
                  .widget<CommentCard>(_focusedCommentCard(ancestorRkey))
                  .comment
                  .viewer!
                  .moderation,
              isEmpty,
              reason: 'the rendered ancestor must use B capabilities',
            );
          }
          if (options().evaluate().isNotEmpty) {
            await openOptions();
          }
          verifyNever(harness.api.getModerationSubjectState(any));
          expect(
            find.text('Remove comment'),
            findsNothing,
            reason: 'retained A capabilities must not offer Remove under B',
          );
          expect(
            find.text('Restore comment'),
            findsNothing,
            reason: 'retained A capabilities must not offer Restore under B',
          );
        } finally {
          await harness.dispose(tester);
        }
      });
    }
  }

  // Switching to another admin: an ancestor B's tree loaded carries B's
  // stamp, so B's own capabilities on it are honored at once, while an
  // ancestor retained from A's snapshot keeps A's stamp and offers nothing.
  for (final capability in [
    ModerationCapability.remove,
    ModerationCapability.restore,
  ]) {
    for (final freshAncestor in [false, true]) {
      final action = capability == ModerationCapability.remove
          ? 'Remove comment'
          : 'Restore comment';
      final boundary = freshAncestor
          ? 'fresh B ancestor offers B admin action and replies against B'
          : 'retained A ancestor absent from B tree has no admin action';
      testWidgets('P-C1 admin A to admin B: $action, $boundary', (
        tester,
      ) async {
        _useTallViewport(tester);
        final harness = _FocusedThreadOverPost(
          FakeAuthProvider(signedInDid: _firstDid),
          anchorInFirstPage: freshAncestor,
          ancestorCapability: capability,
          secondAccountIsAdmin: true,
        );
        final ancestorRkey = freshAncestor ? 'parent5' : 'level5';
        Finder options() => find.descendant(
          of: _focusedCommentCard(ancestorRkey),
          matching: find.byTooltip('Comment options'),
        );
        Future<void> openOptions() async {
          await tester.ensureVisible(options());
          await tester.tap(options());
          await _pumpFrames(tester);
        }

        try {
          if (freshAncestor) {
            await harness.openFocusedThread(tester);
          } else {
            await harness.openNestedFocusedThread(tester);
          }
          final firstSession = harness.authority!.sessionKey;
          await openOptions();
          expect(
            find.text(action),
            findsOneWidget,
            reason: 'control: the current admin A ancestor offers its tool',
          );
          await tester.tap(options());
          await tester.pumpAndSettle();

          harness.auth.setSignedInDid(_secondDid);
          await tester.pumpAndSettle();
          _expectNoErrors(tester, 'after switching to admin B settled');
          expect(harness.auth.did, _secondDid);
          expect(
            harness.authority!.status,
            ViewerAuthorityStatus.instanceAdmin,
            reason: 'control: B is an admin too',
          );
          expect(harness.authority!.sessionKey, isNot(firstSession));
          final provider = harness.cache.peekProvider(_postUri)!;
          expect(provider.sessionStamp, harness.authority!.sessionKey);
          final loadedAncestor = provider.comments
              .map((root) => root.findByUri(_commentUri(ancestorRkey)))
              .nonNulls
              .toList();
          expect(
            loadedAncestor,
            freshAncestor ? hasLength(1) : isEmpty,
            reason: 'control: B actually loaded the selected ancestor input',
          );
          expect(_focusedCommentCard(ancestorRkey), findsOneWidget);

          if (!freshAncestor) {
            if (options().evaluate().isNotEmpty) {
              await openOptions();
            }
            expect(
              find.text('Remove comment'),
              findsNothing,
              reason: 'a retained A ancestor must not offer Remove under B',
            );
            expect(
              find.text('Restore comment'),
              findsNothing,
              reason: 'a retained A ancestor must not offer Restore under B',
            );
            return;
          }

          expect(loadedAncestor.single.comment.viewer!.moderation, {
            capability,
          }, reason: 'control: B\'s response grants B the capability');
          expect(
            options(),
            findsOneWidget,
            reason:
                'the fresh ancestor loaded under B must offer B\'s admin '
                'tools without waiting for a moderation reload',
          );
          await openOptions();
          expect(
            find.text(action),
            findsOneWidget,
            reason:
                'the fresh ancestor loaded under B must offer B\'s admin '
                'tools without waiting for a moderation reload',
          );
          await tester.tap(options());
          await tester.pumpAndSettle();

          if (capability == ModerationCapability.remove) {
            // The ancestor is the reply entry point: its composer must
            // preview and reply against B's loaded row, not A's snapshot.
            _answerPlatformCalls(tester);
            final ancestorText = find
                .descendant(
                  of: _focusedCommentCard(ancestorRkey),
                  matching: find.text(
                    'Fresh admin ancestor',
                    findRichText: true,
                  ),
                )
                .first;
            await tester.ensureVisible(ancestorText);
            await tester.pumpAndSettle();
            await tester.tap(ancestorText);
            await tester.pumpAndSettle();
            _expectNoErrors(tester, 'after opening the ancestor composer');
            final composer = find.byType(ReplyScreen);
            expect(composer, findsOneWidget);
            final replyTarget = tester.widget<ReplyScreen>(composer).comment;
            expect(
              replyTarget,
              same(loadedAncestor.single),
              reason: 'the composer must reply to B\'s freshly loaded row',
            );
            expect(replyTarget!.comment.content, 'Fresh admin ancestor');
            expect(replyTarget.comment.viewer!.moderation, {capability});
          }
        } finally {
          await harness.dispose(tester);
        }
      });
    }
  }

  testWidgets(
    'given a signed-in viewer in a focused thread, when its anchor subtree '
    'fetch fails with RootNotFound, then the thread is replaced by the '
    'unavailable state, and Check again shows the anchor\'s replies with '
    'live votes once the post is served again',
    (tester) async {
      _useTallViewport(tester);
      final harness =
          _FocusedThreadOverPost(
              FakeAuthProvider(signedInDid: _firstDid),
              anchorInFirstPage: true,
            )
            ..subtreeError = NotFoundException(
              'Post not found',
              errorCode: 'RootNotFound',
            );
      try {
        await harness.openFocusedThread(tester, expectLoadedThread: false);
        expect(
          harness.requests,
          contains((parentRkey: 'anchor', viewerDid: _firstDid)),
          reason: 'control: the focused thread fetched the anchor subtree',
        );

        Finder inFocusedThread(Finder finder) => find.descendant(
          of: find.byType(FocusedThreadScreen),
          matching: finder,
        );

        expect(
          inFocusedThread(find.text('This post is no longer available')),
          findsOneWidget,
        );
        expect(inFocusedThread(find.text('Retry')), findsNothing);
        for (final rkey in ['parent5', 'anchor', 'level1']) {
          expect(
            inFocusedThread(find.text('Comment $rkey', findRichText: true)),
            findsNothing,
            reason: 'the unavailable state replaces $rkey',
          );
        }
        expect(
          inFocusedThread(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics &&
                  _voteButtonLabels.contains(widget.properties.label),
            ),
          ),
          findsNothing,
        );
        final checkAgain = inFocusedThread(find.text('Check again'));
        expect(checkAgain, findsOneWidget);

        // The post is served again, its first page no longer holds the
        // anchor, and the anchor now has the viewer's reply.
        harness
          ..subtreeError = null
          ..anchorInFirstPage = false
          ..replyPosted = true;
        final requestsBeforeCheck = harness.requests.length;
        await tester.tap(checkAgain);
        await tester.pumpAndSettle();
        _expectNoErrors(tester, 'after Check again');

        final requestsAfterCheck = harness.requests.skip(requestsBeforeCheck);
        expect(
          requestsAfterCheck,
          contains((parentRkey: null, viewerDid: _firstDid)),
          reason: 'Check again fetches the thread\'s first page',
        );
        expect(
          requestsAfterCheck,
          contains((parentRkey: 'anchor', viewerDid: _firstDid)),
          reason: 'the anchor is not in that page, so its subtree is fetched',
        );
        expect(
          inFocusedThread(find.text('This post is no longer available')),
          findsNothing,
        );
        expect(
          inFocusedThread(
            find.text('Comment $_postedReplyRkey', findRichText: true),
          ),
          findsWidgets,
        );
        final replyVotes = _focusedVoteButtons(_postedReplyRkey);
        expect(replyVotes, findsNWidgets(2));
        expect(
          tester
              .widgetList<Semantics>(replyVotes)
              .map((button) => button.properties.enabled),
          [true, true],
        );
        expect(replyVotes.hitTestable(), findsNWidgets(2));
        expect(
          tester
              .widget<CommentCard>(_focusedCommentCard(_postedReplyRkey))
              .votingEnabled,
          isTrue,
        );
      } finally {
        await harness.dispose(tester);
      }
    },
  );
}
