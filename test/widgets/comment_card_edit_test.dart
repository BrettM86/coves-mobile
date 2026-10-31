import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/post_change_broadcast.dart';
import 'package:coves_flutter/widgets/comment_card.dart';
import 'package:coves_flutter/widgets/comment_thread.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers/comment_removal_fixtures.dart';
import '../test_helpers/fake_providers.dart';
import '../test_helpers/test_mocks.dart';

const _viewerDid = 'did:plc:viewer';

/// The viewer's own comment once deleted: the placeholder the server serves,
/// with no record and the `handle.invalid` author.
CommentView _ownTombstone() => CommentView(
  uri: targetUri,
  cid: targetCid,
  isDeleted: true,
  deletionReason: 'author',
  createdAt: DateTime.utc(2025),
  indexedAt: DateTime.utc(2025),
  author: AuthorView(did: _viewerDid, handle: 'handle.invalid'),
  post: CommentRef(uri: removalPostUri, cid: removalPostCid),
  stats: const CommentStats(),
);

void main() {
  late MockCovesApiService api;

  setUp(() => api = MockCovesApiService());

  /// Pumps [body] under a viewer signed in as [signedInDid] (null: signed
  /// out), with the providers a comment row reads
  Future<FakeAuthProvider> pumpSignedIn(
    WidgetTester tester, {
    required String? signedInDid,
    required Widget body,
  }) async {
    final auth = FakeAuthProvider(
      signedInDid: signedInDid,
      signedInHandle: signedInDid == null ? null : 'viewer.coves.test',
    );
    final blocks = BlockProvider(apiService: api, authProvider: auth);
    addTearDown(() {
      blocks.dispose();
      auth.dispose();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<PostChangeBroadcast>.value(value: PostChangeBroadcast()),
          Provider<CovesApiService>.value(value: api),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<VoteProvider>(
            create: (_) => FakeVoteProvider(auth),
          ),
          ChangeNotifierProvider<BlockProvider>.value(value: blocks),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(body: SingleChildScrollView(child: body)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return auth;
  }

  /// Pumps one [CommentCard] for [comment] under a viewer signed in as
  /// [signedInDid] (null: signed out), with the parent post loaded so the
  /// menu is offered in every row.
  Future<FakeAuthProvider> pumpCard(
    WidgetTester tester, {
    required CommentView comment,
    required String? signedInDid,
    void Function(CommentView comment)? onEdit,
  }) => pumpSignedIn(
    tester,
    signedInDid: signedInDid,
    body: CommentCard(
      comment: comment,
      sessionStamp: null,
      parentPost: removalPost().post,
      onEdit: onEdit,
    ),
  );

  testWidgets('B6 Edit comment shows only on the signed-in author\'s live '
      'comment', (tester) async {
    final rows = <({String name, CommentView comment, String? signedInDid})>[
      (
        name: "the viewer's own comment",
        comment: fixtureComment(
          uri: targetUri,
          authorDid: _viewerDid,
          text: targetText,
        ),
        signedInDid: _viewerDid,
      ),
      (
        name: "another user's comment",
        comment: fixtureComment(
          uri: targetUri,
          authorDid: targetAuthorDid,
          text: targetText,
        ),
        signedInDid: _viewerDid,
      ),
      (
        name: 'signed out',
        comment: fixtureComment(
          uri: targetUri,
          authorDid: _viewerDid,
          text: targetText,
        ),
        signedInDid: null,
      ),
      (
        name: "the viewer's own deleted comment",
        comment: _ownTombstone(),
        signedInDid: _viewerDid,
      ),
    ];

    final observed = <String, bool>{};
    for (final row in rows) {
      await pumpCard(
        tester,
        comment: row.comment,
        signedInDid: row.signedInDid,
        onEdit: (_) {},
      );
      final options = find.byTooltip('Comment options');
      if (options.evaluate().isNotEmpty) {
        await tester.tap(options);
        await tester.pumpAndSettle();
      }
      observed[row.name] = find.text('Edit comment').evaluate().isNotEmpty;
      await tester.pumpWidget(const SizedBox.shrink());
    }

    expect(observed, {
      "the viewer's own comment": true,
      "another user's comment": false,
      'signed out': false,
      "the viewer's own deleted comment": false,
    });
  });

  testWidgets('B6 tapping Edit comment hands the comment to onEdit', (
    tester,
  ) async {
    final own = fixtureComment(
      uri: targetUri,
      authorDid: _viewerDid,
      text: targetText,
    );
    final edited = <CommentView>[];
    await pumpCard(
      tester,
      comment: own,
      signedInDid: _viewerDid,
      onEdit: edited.add,
    );

    await tester.tap(find.byTooltip('Comment options'));
    await tester.pumpAndSettle();
    expect(find.text('Edit comment'), findsOneWidget);
    await tester.tap(find.text('Edit comment'));
    await tester.pumpAndSettle();

    expect(edited, [same(own)]);
  });

  testWidgets('CommentThread hands a nested reply to onEdit', (tester) async {
    const replyUri = 'at://did:plc:viewer/social.coves.community.comment/r1';
    final reply = fixtureComment(
      uri: replyUri,
      authorDid: _viewerDid,
      text: 'My nested reply',
      parentUri: targetUri,
    );
    final edited = <CommentView>[];
    await pumpSignedIn(
      tester,
      signedInDid: _viewerDid,
      body: CommentThread(
        thread: ThreadViewComment(
          comment: fixtureComment(
            uri: targetUri,
            authorDid: targetAuthorDid,
            text: targetText,
          ),
          replies: [ThreadViewComment(comment: reply)],
        ),
        sessionStamp: null,
        parentPost: removalPost().post,
        onEdit: edited.add,
      ),
    );

    final replyCard = find.byWidgetPredicate(
      (widget) => widget is CommentCard && widget.comment.uri == replyUri,
    );
    expect(replyCard, findsOneWidget, reason: 'the nested reply renders');
    await tester.tap(
      find.descendant(
        of: replyCard,
        matching: find.byTooltip('Comment options'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit comment'));
    await tester.pumpAndSettle();

    expect(edited, [same(reply)]);
  });
}
