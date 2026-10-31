import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/moderation.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/viewer_authority_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/compose/reply_screen.dart';
import 'package:coves_flutter/screens/home/focused_thread_screen.dart';
import 'package:coves_flutter/services/comment_service.dart';
import 'package:coves_flutter/services/comments_provider_cache.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/post_change_broadcast.dart';
import 'package:coves_flutter/services/streamable_service.dart';
import 'package:coves_flutter/widgets/comment_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/comment_removal_fixtures.dart';
import '../test_helpers/fake_providers.dart';
import '../test_helpers/test_mocks.dart';

const _editedText = 'Comment C after the edit';

Finder _textOnCard(String uri, String text) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is CommentCard && widget.comment.uri == uri,
  ),
  matching: find.text(text),
);

/// Opens the focused thread on C under ancestor R (both on the screen's
/// snapshot, not in the provider tree, which holds only S), edits the
/// [edited] row (default C; the viewer is its author) to [_editedText] and
/// saves. [anchorRead] answers the screen's read of C's subtree when given
/// (else it serves nothing); [beforeSave] runs while the composer is open.
Future<void> _editSnapshotOnlyComment(
  WidgetTester tester, {
  ({String uri, String authorDid, String text}) edited = (
    uri: targetUri,
    authorDid: targetAuthorDid,
    text: targetText,
  ),
  Completer<CommentsResponse>? anchorRead,
  Future<void> Function()? beforeSave,
  void Function()? expectSaved,
}) async {
  final api = MockCovesApiService();
  final commentService = MockCommentService();
  when(api.getViewerAuthority()).thenAnswer((_) async => false);
  // The viewer wrote the edited row.
  final auth = FakeAuthProvider(
    signedInDid: edited.authorDid,
    signedInHandle: 'commenter.coves.test',
  );
  final authority = ViewerAuthorityProvider(
    apiService: api,
    authProvider: auth,
  );
  final votes = FakeVoteProvider(auth);
  final blocks = BlockProvider(apiService: api, authProvider: auth);
  final cache = CommentsProviderCache(
    authProvider: auth,
    voteProvider: votes,
    commentService: commentService,
    apiService: api,
    sessionKeyOf: () => authority.sessionKey,
  );
  // The provider's loaded tree holds only S; reads never serve the edit.
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
    if (invocation.namedArguments[#parentRkey] == null) {
      return CommentsResponse(post: null, comments: [liveSibling()]);
    }
    return anchorRead?.future ??
        CommentsResponse(post: null, comments: const []);
  });
  final updates = <(String, String)>[];
  when(
    commentService.updateComment(
      uri: anyNamed('uri'),
      content: anyNamed('content'),
      facets: anyNamed('facets'),
      record: anyNamed('record'),
    ),
  ).thenAnswer((invocation) async {
    final uri = invocation.namedArguments[#uri] as String;
    updates.add((uri, invocation.namedArguments[#content] as String));
    return UpdateCommentResponse(uri: uri, cid: 'cid-new');
  });

  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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

  // While the anchor read is held the screen shows a progress indicator,
  // so frames are pumped for a fixed time instead of settling.
  Future<void> settle() async {
    if (anchorRead == null || anchorRead.isCompleted) {
      await tester.pumpAndSettle();
      return;
    }
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  try {
    final provider = cache.acquireProvider(
      postUri: removalPostUri,
      postCid: removalPostCid,
    );
    await provider.loadComments(refresh: true);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<PostChangeBroadcast>.value(value: PostChangeBroadcast()),
          Provider<CovesApiService>.value(value: api),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<ViewerAuthorityProvider>.value(
            value: authority,
          ),
          ChangeNotifierProvider<VoteProvider>.value(value: votes),
          ChangeNotifierProvider<BlockProvider>.value(value: blocks),
          Provider<CommentsProviderCache>.value(value: cache),
          Provider<StreamableService>.value(value: StreamableService()),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: FocusedThreadScreen(
            thread: liveTarget(),
            ancestors: [liveRoot()],
            commentsProvider: provider,
            parentPost: removalPost().post,
          ),
        ),
      ),
    );
    await settle();
    expect(_textOnCard(edited.uri, edited.text), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byWidgetPredicate(
          (widget) => widget is CommentCard && widget.comment.uri == edited.uri,
        ),
        matching: find.byTooltip('Comment options'),
      ),
    );
    await settle();
    expect(find.text('Edit comment'), findsOneWidget);
    await tester.tap(find.text('Edit comment'));
    await settle();
    await tester.enterText(
      find.descendant(
        of: find.byType(ReplyScreen),
        matching: find.byType(EditableText),
      ),
      _editedText,
    );
    await tester.pump();
    await beforeSave?.call();
    await tester.tap(find.text('Save'));
    await settle();

    expect(updates, [(edited.uri, _editedText)]);
    expect(find.byType(ReplyScreen), findsNothing);
    expect(_textOnCard(edited.uri, _editedText), findsOneWidget);
    expect(find.text(edited.text), findsNothing);
    expectSaved?.call();
  } finally {
    // The provider's time-update timer must stop before the binding
    // checks for pending timers.
    await tester.pumpWidget(const SizedBox.shrink());
    cache.dispose();
    blocks.dispose();
    votes.dispose();
    authority.dispose();
    auth.dispose();
  }
}

void main() {
  testWidgets(
    'editing a comment that is on the focused screen\'s snapshot '
    'but not in the provider tree shows the new text after Save',
    _editSnapshotOnlyComment,
  );

  testWidgets(
    'editing the viewer\'s own ancestor row shows the new text on that row '
    'after Save',
    (tester) => _editSnapshotOnlyComment(
      tester,
      edited: (uri: rootUri, authorDid: 'did:plc:rootauthor', text: rootText),
    ),
  );

  testWidgets('F5 the snapshot patch keeps the stats the snapshot node took '
      'while the composer was open', (tester) async {
    final anchorRead = Completer<CommentsResponse>();
    await _editSnapshotOnlyComment(
      tester,
      anchorRead: anchorRead,
      beforeSave: () async {
        // C's subtree read lands while the composer is open, with newer
        // stats for C.
        final live = liveTarget();
        anchorRead.complete(
          CommentsResponse(
            post: null,
            comments: [
              ThreadViewComment(
                comment: fixtureComment(
                  uri: targetUri,
                  authorDid: targetAuthorDid,
                  text: targetText,
                  parentUri: rootUri,
                  capabilities: const {ModerationCapability.remove},
                  stats: const CommentStats(score: 9, replyCount: 5),
                ),
                replies: live.replies,
                hasMore: live.hasMore,
                repliesCursor: live.repliesCursor,
              ),
            ],
          ),
        );
        await tester.pump();
        expect(
          tester
              .widget<CommentCard>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is CommentCard && widget.comment.uri == targetUri,
                  skipOffstage: false,
                ),
              )
              .comment
              .stats
              .score,
          9,
        );
      },
      expectSaved: () {
        final card = tester.widget<CommentCard>(
          find.byWidgetPredicate(
            (widget) =>
                widget is CommentCard && widget.comment.uri == targetUri,
          ),
        );
        expect(card.comment.content, _editedText);
        expect(card.comment.stats.score, 9);
        expect(card.comment.stats.replyCount, 5);
      },
    );
  });
}
