// Acceptance test for comment editing: from post detail, the author's own
// comment opens in the edit screen, saves through CommentService, and the
// card shows the saved text while reads still serve the old text.

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/viewer_authority_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/compose/reply_screen.dart';
import 'package:coves_flutter/screens/home/post_detail_screen.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
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

const _viewerDid = 'did:plc:viewer';
const _ownUri = 'at://did:plc:viewer/social.coves.community.comment/own';
const _oldText = 'My comment before the edit';
const _newText = 'My comment after the edit';

Finder _cardOf(String uri) => find.byWidgetPredicate(
  (widget) => widget is CommentCard && widget.comment.uri == uri,
);

void main() {
  late MockCovesApiService api;
  late MockCommentService commentService;
  late FakeAuthProvider auth;
  late ViewerAuthorityProvider authority;
  late VoteProvider votes;
  late BlockProvider blocks;
  late CommentsProviderCache cache;
  late List<(String, String)> updates;

  setUp(() {
    api = MockCovesApiService();
    commentService = MockCommentService();
    when(api.getViewerAuthority()).thenAnswer((_) async => false);
    auth = FakeAuthProvider(
      signedInDid: _viewerDid,
      signedInHandle: 'viewer.coves.test',
    );
    authority = ViewerAuthorityProvider(apiService: api, authProvider: auth);
    votes = FakeVoteProvider(auth);
    blocks = BlockProvider(apiService: api, authProvider: auth);
    cache = CommentsProviderCache(
      authProvider: auth,
      voteProvider: votes,
      commentService: commentService,
      apiService: api,
      sessionKeyOf: () => authority.sessionKey,
    );
    // Reads keep serving the old text: the edit has not reached the
    // AppView yet.
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
    ).thenAnswer(
      (_) async => CommentsResponse(
        post: null,
        comments: [
          ThreadViewComment(
            comment: fixtureComment(
              uri: _ownUri,
              authorDid: _viewerDid,
              text: _oldText,
            ),
          ),
          liveSibling(),
        ],
      ),
    );
    updates = [];
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
  });

  // Unmount and dispose inside the test body: the provider's periodic
  // time-update timer must be cancelled before the binding checks for
  // pending timers, which happens before tearDowns run.
  void editTest(String description, Future<void> Function(WidgetTester) body) {
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        cache.dispose();
        blocks.dispose();
        votes.dispose();
        authority.dispose();
        auth.dispose();
      }
    });
  }

  Future<void> pumpPostDetail(WidgetTester tester) async {
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
          home: PostDetailScreen(sessionStamp: null, post: removalPost()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Opens the own comment's menu, picks Edit comment, replaces the text
  /// with [_newText] and taps Save.
  Future<void> editOwnComment(WidgetTester tester) async {
    expect(
      find.descendant(of: _cardOf(_ownUri), matching: find.text(_oldText)),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(
        of: _cardOf(_ownUri),
        matching: find.byTooltip('Comment options'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Edit comment'), findsOneWidget);
    await tester.tap(find.text('Edit comment'));
    await tester.pumpAndSettle();

    final field = find.descendant(
      of: find.byType(ReplyScreen),
      matching: find.byType(EditableText),
    );
    await tester.enterText(field, _newText);
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
  }

  editTest('editing the own comment from post detail saves it through '
      'CommentService and the card shows the new text', (tester) async {
    await pumpPostDetail(tester);

    await editOwnComment(tester);

    expect(updates, [(_ownUri, _newText)]);
    expect(find.byType(ReplyScreen), findsNothing);
    expect(
      find.descendant(of: _cardOf(_ownUri), matching: find.text(_newText)),
      findsOneWidget,
    );
    expect(find.text(_oldText), findsNothing);
  });

  editTest('a failed save from post detail shows an error snackbar', (
    tester,
  ) async {
    when(
      commentService.updateComment(
        uri: anyNamed('uri'),
        content: anyNamed('content'),
        facets: anyNamed('facets'),
        record: anyNamed('record'),
      ),
    ).thenAnswer(
      (_) async => throw ApiException('Comment changed', statusCode: 409),
    );
    await pumpPostDetail(tester);

    await editOwnComment(tester);

    expect(find.byType(SnackBar), findsOneWidget);
  });
}
