import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/moderation_action.dart';
import 'package:coves_flutter/models/moderation_subject_state.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/comments_provider.dart';
import 'package:coves_flutter/providers/viewer_authority_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/home/post_detail_screen.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/comments_provider_cache.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/post_change_broadcast.dart';
import 'package:coves_flutter/services/streamable_service.dart';
import 'package:coves_flutter/widgets/comment_card.dart';
import 'package:coves_flutter/widgets/loading_error_states.dart';
import 'package:coves_flutter/widgets/moderation/moderation_action_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/comment_removal_fixtures.dart';
import '../test_helpers/fake_providers.dart';
import '../test_helpers/test_mocks.dart';

Finder _cardOf(String uri) => find.byWidgetPredicate(
  (widget) => widget is CommentCard && widget.comment.uri == uri,
);

Finder _optionsOf(String uri) => find.descendant(
  of: _cardOf(uri),
  matching: find.byTooltip('Comment options'),
);

Finder get _targetPlaceholder => find.descendant(
  of: _cardOf(targetUri),
  matching: find.text('[Removed by server admin]'),
);

final Finder _sheet = find.byWidgetPredicate(
  (widget) => widget is ModerationActionSheet,
);

/// The sheet's confirm button, found by type because its label becomes a
/// spinner while the request is in flight.
final Finder _confirmButton = find.descendant(
  of: _sheet,
  matching: find.bySubtype<FilledButton>(),
);

/// Lets animations run without waiting for a held request.
Future<void> _pumpWhileHeld(WidgetTester tester) async {
  for (var frame = 0; frame < 10; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late MockCovesApiService api;

  setUp(() {
    api = MockCovesApiService();
    when(api.getViewerAuthority()).thenAnswer((_) async => true);
  });

  void answerRestore(Future<ModerationMutationResult> Function() answer) {
    when(
      api.restoreContent(
        actionId: anyNamed('actionId'),
        expectedVersion: anyNamed('expectedVersion'),
        idempotencyKey: anyNamed('idempotencyKey'),
        reason: anyNamed('reason'),
        reviewedSubject: anyNamed('reviewedSubject'),
        privateNote: anyNamed('privateNote'),
      ),
    ).thenAnswer((_) => answer());
  }

  testWidgets(
    'B1 the removed placeholder offers only Restore comment for the restore '
    'token under the current session',
    (tester) async {
      final rows = [
        (
          name: 'restore token, live authority, current session',
          token: true,
          revoked: false,
          stale: false,
        ),
        (name: 'no restore token', token: false, revoked: false, stale: false),
        (name: 'authority revoked', token: true, revoked: true, stale: false),
        (name: 'stale session stamp', token: true, revoked: false, stale: true),
      ];

      // Null when the card has no "Comment options" trigger, else the
      // labels of the open menu's items.
      final observed = <String, List<String?>?>{};
      for (final row in rows) {
        final auth = FakeAuthProvider(
          signedInDid: adminDid,
          signedInHandle: 'admin.coves.test',
        );
        final authority = ViewerAuthorityProvider(
          apiService: api,
          authProvider: auth,
        );
        final blocks = BlockProvider(apiService: api, authProvider: auth);
        await tester.pump();
        final stamp = authority.sessionKey;
        if (row.stale) {
          // The same account signs out and back in: a new session.
          auth
            ..setSignedInDid(null)
            ..setSignedInDid(adminDid);
          await tester.pump();
        }
        if (row.revoked) {
          authority.markRevoked();
        }
        expect(stamp, isNotNull, reason: row.name);
        expect(authority.sessionKey == stamp, !row.stale, reason: row.name);
        expect(authority.isRevoked, row.revoked, reason: row.name);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<PostChangeBroadcast>.value(value: PostChangeBroadcast()),
              Provider<CovesApiService>.value(value: api),
              ChangeNotifierProvider<AuthProvider>.value(value: auth),
              ChangeNotifierProvider<ViewerAuthorityProvider>.value(
                value: authority,
              ),
              ChangeNotifierProvider<VoteProvider>(
                create: (_) => FakeVoteProvider(auth),
              ),
              ChangeNotifierProvider<BlockProvider>.value(value: blocks),
            ],
            child: MaterialApp(
              theme: AppTheme.dark,
              home: Scaffold(
                body: CommentCard(
                  comment: serverRemovedTarget(restoreToken: row.token),
                  sessionStamp: stamp,
                  parentPost: removalPost().post,
                  reloadAfterModeration: () async => true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('[Removed by server admin]'),
          findsOneWidget,
          reason: row.name,
        );

        final trigger = find.byTooltip('Comment options');
        if (trigger.evaluate().isEmpty) {
          observed[row.name] = null;
        } else {
          await tester.tap(trigger);
          await tester.pumpAndSettle();
          observed[row.name] = [
            for (final item in tester.widgetList<MenuItemButton>(
              find.byType(MenuItemButton),
            ))
              switch (item.child) {
                final Text text => text.data,
                final other => other.runtimeType.toString(),
              },
          ];
          for (final label in [
            'Remove comment',
            'Delete comment',
            'Share',
            'Copy link',
            'Report comment',
          ]) {
            expect(find.text(label), findsNothing, reason: row.name);
          }
        }

        await tester.pumpWidget(const SizedBox.shrink());
        blocks.dispose();
        authority.dispose();
        auth.dispose();
      }

      expect(observed, {
        'restore token, live authority, current session': ['Restore comment'],
        'no restore token': null,
        'authority revoked': null,
        'stale session stamp': null,
      });
    },
  );

  group('post detail', () {
    late FakeAuthProvider auth;
    late ViewerAuthorityProvider authority;
    late VoteProvider votes;
    late BlockProvider blocks;
    late CommentsProviderCache cache;

    /// Answers every getComments call with [answer].
    void answerThreadRequests(Future<CommentsResponse> Function() answer) {
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
      ).thenAnswer((_) => answer());
    }

    void restoreThrows(ApiException error) =>
        answerRestore(() async => throw error);

    setUp(() {
      auth = FakeAuthProvider(
        signedInDid: adminDid,
        signedInHandle: 'admin.coves.test',
      );
      authority = ViewerAuthorityProvider(apiService: api, authProvider: auth);
      votes = FakeVoteProvider(auth);
      blocks = BlockProvider(apiService: api, authProvider: auth);
      cache = CommentsProviderCache(
        authProvider: auth,
        voteProvider: votes,
        commentService: MockCommentService(),
        apiService: api,
        sessionKeyOf: () => authority.sessionKey,
      );
      answerThreadRequests(
        () async =>
            CommentsResponse(post: null, comments: threadsWithRemovedTarget()),
      );
      when(api.getModerationSubjectState(targetUri))
          .thenAnswer((_) async => targetRemovedState());
      answerRestore(
        () async => ModerationMutationResult.fromJson(restoreContentJson()),
      );
    });

    // Unmount and dispose inside the test body: the provider's periodic
    // time-update timer must be cancelled before the binding checks for
    // pending timers, which happens before tearDowns run.
    void postDetailTest(
      String description,
      Future<void> Function(WidgetTester) body,
    ) {
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
      expect(_targetPlaceholder, findsOneWidget);
    }

    /// Opens C's menu, picks "Restore comment" and chooses Rule violation.
    Future<void> openRestoreSheetForTarget(WidgetTester tester) async {
      expect(_optionsOf(targetUri), findsOneWidget);
      await tester.tap(_optionsOf(targetUri));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore comment'));
      await tester.pumpAndSettle();
      expect(_sheet, findsOneWidget);
      await tester.tap(
        find.descendant(of: _sheet, matching: find.text('Rule violation')),
      );
      await tester.pumpAndSettle();
    }

    /// Opens the sheet, picks a reason, presses confirm and lets the answer
    /// and any reload finish.
    Future<void> restoreTarget(WidgetTester tester) async {
      await openRestoreSheetForTarget(tester);
      await tester.tap(_confirmButton);
      await tester.pumpAndSettle();
    }

    postDetailTest(
      'B2 an admin restores removed reply C from its placeholder and the '
      'thread brings it back quietly with its replies',
      (tester) async {
        final restoreAnswer = Completer<ModerationMutationResult>();
        answerRestore(() => restoreAnswer.future);
        await pumpPostDetail(tester);
        expect(find.text(targetText), findsNothing);

        expect(_optionsOf(targetUri), findsOneWidget);
        await tester.tap(_optionsOf(targetUri));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Restore comment'));
        await tester.pumpAndSettle();

        expect(_sheet, findsOneWidget);
        expect(
          find.descendant(of: _sheet, matching: find.text('Restore comment')),
          findsOneWidget,
        );
        expect(find.text('Doxing'), findsNothing);

        await tester.tap(
          find.descendant(of: _sheet, matching: find.text('Rule violation')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.descendant(of: _sheet, matching: find.byType(TextField)),
          'restore note',
        );
        await tester.pump();
        await tester.tap(_confirmButton);
        await tester.pump();
        await tester.pump();

        // The reason and note chosen in the sheet are what the request sends.
        final sent = verify(
          api.restoreContent(
            actionId: anyNamed('actionId'),
            expectedVersion: anyNamed('expectedVersion'),
            idempotencyKey: anyNamed('idempotencyKey'),
            reason: captureAnyNamed('reason'),
            reviewedSubject: anyNamed('reviewedSubject'),
            privateNote: captureAnyNamed('privateNote'),
          ),
        ).captured;
        expect(sent, [ModerationReason.ruleViolation, 'restore note']);

        expect(_targetPlaceholder, findsOneWidget);
        expect(
          tester.widget<ButtonStyleButton>(_confirmButton).onPressed,
          isNull,
        );

        final reload = Completer<CommentsResponse>();
        answerThreadRequests(() => reload.future);
        restoreAnswer.complete(
          ModerationMutationResult.fromJson(restoreContentJson()),
        );
        await _pumpWhileHeld(tester);

        expect(find.text(siblingText), findsOneWidget);
        expect(find.text(rootText), findsOneWidget);
        expect(find.byType(FullScreenLoading), findsNothing);

        reload.complete(CommentsResponse(post: null, comments: liveThreads()));
        await tester.pumpAndSettle();

        expect(_sheet, findsNothing);
        expect(
          find.descendant(
            of: _cardOf(targetUri),
            matching: find.text('Comment C to remove'),
          ),
          findsOneWidget,
        );
        expect(find.text('Reply C1'), findsOneWidget);
        expect(find.text('Reply C2'), findsOneWidget);
        expect(find.text('[Removed by server admin]'), findsNothing);
        expect(find.text('Comment restored'), findsOneWidget);
      },
    );

    postDetailTest(
      "B2 a restore whose reload fails says the latest version couldn't load",
      (tester) async {
        await pumpPostDetail(tester);
        answerThreadRequests(() async => throw NetworkException('Unreachable'));

        await restoreTarget(tester);

        expect(_sheet, findsNothing);
        expect(
          find.text(
            "Comment restored, but couldn't load the latest version. "
            'Try again.',
          ),
          findsOneWidget,
        );
        expect(find.text('Comment restored'), findsNothing);
      },
    );

    postDetailTest(
      'a restore answered with a present record that still reads removed '
      'clears the local removal and says Comment restored once the reload '
      'lands',
      (tester) async {
        answerRestore(
          () async => ModerationMutationResult.fromJson(
            restoreContentJson(moderationState: 'removed'),
          ),
        );
        await pumpPostDetail(tester);
        final provider = tester
            .element(_cardOf(targetUri))
            .read<CommentsProvider>();
        final removed = ModerationMutationResult.fromJson(removeContentJson());
        provider.markCommentRemoved(
          commentUri: targetUri,
          state: removed.state,
          action: removed.action,
        );
        await tester.pumpAndSettle();
        expect(
          provider.applyRemovalOverlay(liveTarget()).comment.isDeleted,
          isTrue,
        );

        final reload = Completer<CommentsResponse>();
        answerThreadRequests(() => reload.future);
        await openRestoreSheetForTarget(tester);
        await tester.tap(_confirmButton);
        await _pumpWhileHeld(tester);

        final target = provider.applyRemovalOverlay(liveTarget()).comment;
        expect(target.isDeleted, isFalse);
        expect(target.record?.content, 'Comment C to remove');
        expect(find.text('Comment restored'), findsNothing);

        reload.complete(CommentsResponse(post: null, comments: liveThreads()));
        await tester.pumpAndSettle();

        expect(_sheet, findsNothing);
        expect(
          find.descendant(
            of: _cardOf(targetUri),
            matching: find.text('Comment C to remove'),
          ),
          findsOneWidget,
        );
        expect(find.text('Comment restored'), findsOneWidget);
      },
    );

    group('B3 a restore the reload still hides keeps the placeholder', () {
      for (final row in [
        (
          name: 'the author deleted it',
          restored: restoreContentJson(recordState: 'deleted'),
          state: targetRemovedState(),
          message: 'Restored, but the author deleted it, so it stays hidden.',
        ),
        (
          name: 'the record is unavailable',
          restored: restoreContentJson(recordState: 'unavailable'),
          state: targetRemovedState(),
          message: "Restored, but it can't be shown right now.",
        ),
        (
          name: 'no local removal',
          restored: restoreContentJson(),
          state: targetClearState(),
          message: 'This is no longer removed.',
        ),
      ]) {
        postDetailTest('B3 ${row.name}', (tester) async {
          when(api.getModerationSubjectState(targetUri))
              .thenAnswer((_) async => row.state);
          answerRestore(
            () async => ModerationMutationResult.fromJson(row.restored),
          );
          await pumpPostDetail(tester);

          await restoreTarget(tester);

          expect(_sheet, findsNothing);
          expect(_targetPlaceholder, findsOneWidget);
          expect(find.text(row.message), findsOneWidget);
        });
      }
    });

    group('B4 a rejected restore', () {
      for (final row in [
        (
          name: 'DecisionNotFound reloads the thread',
          error: ApiException(
            'DecisionNotFound',
            statusCode: 404,
            errorCode: 'DecisionNotFound',
          ),
          message: null,
        ),
        (
          name: 'StateConflict reloads the thread and says it changed',
          error: ApiException(
            'StateConflict',
            statusCode: 400,
            errorCode: 'StateConflict',
          ),
          message: 'This item changed. Showing the latest version.',
        ),
        (
          name: 'ContentChanged reloads the thread and asks to restore again',
          error: ApiException(
            'ContentChanged',
            statusCode: 400,
            errorCode: 'ContentChanged',
          ),
          message: 'The author edited this comment. Try restoring again.',
        ),
      ]) {
        postDetailTest('B4 ${row.name}', (tester) async {
          restoreThrows(row.error);
          await pumpPostDetail(tester);
          answerThreadRequests(
            () async => CommentsResponse(post: null, comments: liveThreads()),
          );

          await restoreTarget(tester);

          expect(_sheet, findsNothing);
          expect(
            find.descendant(
              of: _cardOf(targetUri),
              matching: find.text('Comment C to remove'),
            ),
            findsOneWidget,
          );
          final message = row.message;
          if (message != null) {
            expect(find.text(message), findsOneWidget);
          }
        });
      }

      postDetailTest(
        "B4 StateConflict whose reload fails says the latest version couldn't "
        'load',
        (tester) async {
          restoreThrows(
            ApiException(
              'StateConflict',
              statusCode: 400,
              errorCode: 'StateConflict',
            ),
          );
          await pumpPostDetail(tester);
          answerThreadRequests(
            () async => throw NetworkException('Unreachable'),
          );

          await restoreTarget(tester);

          expect(_sheet, findsNothing);
          expect(
            find.text("Couldn't load the latest version. Try again."),
            findsOneWidget,
          );
          expect(
            find.text('This item changed. Showing the latest version.'),
            findsNothing,
          );
        },
      );

      postDetailTest(
        'B4 Forbidden closes the sheet, revokes admin tools and hides the '
        "placeholder's menu",
        (tester) async {
          restoreThrows(
            ApiException('Forbidden', statusCode: 403, errorCode: 'Forbidden'),
          );
          await pumpPostDetail(tester);

          await restoreTarget(tester);

          expect(_sheet, findsNothing);
          expect(authority.isRevoked, isTrue);
          expect(_targetPlaceholder, findsOneWidget);
          expect(_optionsOf(targetUri), findsNothing);
        },
      );
    });
  });
}
