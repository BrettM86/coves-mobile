import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/moderation.dart';
import 'package:coves_flutter/models/moderation_action.dart';
import 'package:coves_flutter/models/moderation_subject_state.dart';
import 'package:coves_flutter/models/post_get_result.dart';
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
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/comment_removal_fixtures.dart';
import '../test_helpers/error_copy_rows.dart';
import '../test_helpers/fake_providers.dart';
import '../test_helpers/test_mocks.dart';

Finder _cardOf(String uri) => find.byWidgetPredicate(
  (widget) => widget is CommentCard && widget.comment.uri == uri,
);

Finder get _removeButton => find.ancestor(
  of: find.text('Remove'),
  matching: find.bySubtype<ButtonStyleButton>(),
);

void main() {
  late MockCovesApiService api;

  setUp(() {
    api = MockCovesApiService();
    when(api.getViewerAuthority()).thenAnswer((_) async => true);
  });

  testWidgets(
    'B1 Remove comment shows only for the remove token under the current '
    'session, also on the viewer\'s own comment',
    (tester) async {
      final rows = [
        (
          name: "another author's comment with the token",
          own: false,
          token: true,
          revoked: false,
          stale: false,
        ),
        (
          name: "the viewer's own comment with the token",
          own: true,
          token: true,
          revoked: false,
          stale: false,
        ),
        (
          name: 'no remove token',
          own: false,
          token: false,
          revoked: false,
          stale: false,
        ),
        (
          name: 'authority revoked',
          own: false,
          token: true,
          revoked: true,
          stale: false,
        ),
        (
          name: 'stale session stamp',
          own: false,
          token: true,
          revoked: false,
          stale: true,
        ),
      ];

      final observed = <String, Set<String>>{};
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
                  comment: fixtureComment(
                    uri: targetUri,
                    authorDid: row.own ? adminDid : targetAuthorDid,
                    text: targetText,
                    parentUri: rootUri,
                    capabilities: row.token
                        ? const {ModerationCapability.remove}
                        : const {},
                  ),
                  sessionStamp: stamp,
                  reloadAfterModeration: () async => true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Comment options'));
        await tester.pumpAndSettle();
        observed[row.name] = {
          for (final label in ['Remove comment', 'Delete comment'])
            if (find.text(label).evaluate().isNotEmpty) label,
        };

        await tester.pumpWidget(const SizedBox.shrink());
        blocks.dispose();
        authority.dispose();
        auth.dispose();
      }

      expect(observed, {
        "another author's comment with the token": {'Remove comment'},
        "the viewer's own comment with the token": {
          'Remove comment',
          'Delete comment',
        },
        'no remove token': <String>{},
        'authority revoked': <String>{},
        'stale session stamp': <String>{},
      });
    },
  );

  group('post detail', () {
    late FakeAuthProvider auth;
    late ViewerAuthorityProvider authority;
    late VoteProvider votes;
    late BlockProvider blocks;
    late CommentsProviderCache cache;
    late List<String?> threadRequests;

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
      threadRequests = [];
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
        threadRequests.add(invocation.namedArguments[#parentRkey] as String?);
        return CommentsResponse(post: null, comments: liveThreads());
      });
      when(api.getModerationSubjectState(targetUri))
          .thenAnswer((_) async => targetClearState());
      when(
        api.removeContent(
          subject: anyNamed('subject'),
          expectedVersion: anyNamed('expectedVersion'),
          idempotencyKey: anyNamed('idempotencyKey'),
          reason: anyNamed('reason'),
          privateNote: anyNamed('privateNote'),
        ),
      ).thenAnswer(
        (_) async => ModerationMutationResult.fromJson(removeContentJson()),
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
    }

    Finder targetPlaceholder() => find.descendant(
      of: _cardOf(targetUri),
      matching: find.text('[Removed by server admin]'),
    );

    /// Answers every getComments call with [answer], recording each
    /// request's parentRkey (null for the top-level thread).
    void answerThreadRequests(
      Future<CommentsResponse> Function(String? parentRkey) answer,
    ) {
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
      ).thenAnswer((invocation) {
        final parentRkey = invocation.namedArguments[#parentRkey] as String?;
        threadRequests.add(parentRkey);
        return answer(parentRkey);
      });
    }

    void removeContentThrows(Object error) {
      when(
        api.removeContent(
          subject: anyNamed('subject'),
          expectedVersion: anyNamed('expectedVersion'),
          idempotencyKey: anyNamed('idempotencyKey'),
          reason: anyNamed('reason'),
          privateNote: anyNamed('privateNote'),
        ),
      ).thenThrow(error);
    }

    /// Opens C's menu, picks "Remove comment", chooses Spam, enters
    /// [note] when given and taps Remove. Leaves the answer unsettled for
    /// the caller.
    Future<void> submitRemovalOfTarget(
      WidgetTester tester, {
      String? note,
    }) async {
      await tester.tap(
        find.descendant(
          of: _cardOf(targetUri),
          matching: find.byTooltip('Comment options'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Remove comment'), findsOneWidget);
      await tester.tap(find.text('Remove comment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spam'));
      await tester.pumpAndSettle();
      if (note != null) {
        await tester.enterText(find.byType(TextField), note);
        await tester.pump();
      }
      await tester.tap(_removeButton);
    }

    /// Lets animations run without waiting for a held request.
    Future<void> pumpWhileHeld(WidgetTester tester) async {
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Finder targetOptions() => find.descendant(
      of: _cardOf(targetUri),
      matching: find.byTooltip('Comment options'),
    );

    /// Answers the whole thread live at once and holds every read of C
    /// ('c') on the returned completer.
    Completer<CommentsResponse> holdReadBackOfTarget() {
      final readBack = Completer<CommentsResponse>();
      answerThreadRequests(
        (parentRkey) => parentRkey == 'c'
            ? readBack.future
            : Future.value(
                CommentsResponse(post: null, comments: liveThreads()),
              ),
      );
      return readBack;
    }

    /// C read back as the server serves it once removed: the placeholder
    /// carrying the `restore` token, with C1 and C2 and more to load.
    CommentsResponse servedRemovedTargetPage() =>
        CommentsResponse(post: null, comments: [serverRemovedTargetThread()]);

    /// Opens C's placeholder menu and expects it to offer Restore comment.
    Future<void> expectTargetOffersRestore(WidgetTester tester) async {
      expect(targetOptions(), findsOneWidget);
      await tester.tap(targetOptions());
      await tester.pumpAndSettle();
      expect(find.text('Restore comment'), findsOneWidget);
    }

    postDetailTest(
      'B3 removing nested reply C shows the placeholder in place and keeps '
      'its replies, then reads C back and offers Restore comment',
      (tester) async {
        final readBack = holdReadBackOfTarget();
        await pumpPostDetail(tester);
        expect(find.text(targetText), findsOneWidget);
        expect(threadRequests, [null]);
        threadRequests.clear();

        await tester.tap(
          find.descendant(
            of: _cardOf(targetUri),
            matching: find.byTooltip('Comment options'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Remove comment'), findsOneWidget);
        await tester.tap(find.text('Remove comment'));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text('Remove comment'),
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Spam'));
        await tester.pumpAndSettle();
        await tester.tap(_removeButton);
        await tester.pumpAndSettle();

        expect(find.byType(BottomSheet), findsNothing);
        expect(
          find.descendant(
            of: _cardOf(targetUri),
            matching: find.text('[Removed by server admin]'),
          ),
          findsOneWidget,
        );
        expect(find.text('Comment C to remove'), findsNothing);
        expect(
          find.descendant(
            of: _cardOf(targetUri),
            matching: find.byTooltip('Comment options'),
          ),
          findsNothing,
        );
        for (final text in [
          'Reply C1',
          'Reply C2',
          'Root comment R',
          'Sibling comment S',
        ]) {
          expect(find.text(text), findsOneWidget, reason: text);
        }
        expect(find.text('Load more replies'), findsOneWidget);
        expect(find.text('Comment removed'), findsOneWidget);
        expect(threadRequests, ['c'], reason: 'one read of C, no thread read');

        readBack.complete(servedRemovedTargetPage());
        await tester.pumpAndSettle();

        expect(find.byType(PostDetailScreen), findsOneWidget);
        expect(targetPlaceholder(), findsOneWidget);
        for (final text in ['Reply C1', 'Reply C2', 'Load more replies']) {
          expect(find.text(text), findsOneWidget, reason: text);
        }
        await expectTargetOffersRestore(tester);
        expect(threadRequests, ['c']);
      },
    );

    postDetailTest(
      'R6 Restore comment on the read-back placeholder restores the removal '
      'the server has now and brings C back quietly',
      (tester) async {
        final readBack = holdReadBackOfTarget();
        // The removal reads C clear; the restore reads it removed under a
        // newer action and version than the removal's own answer
        // ('removal-1', 'v2').
        var stateReads = 0;
        when(api.getModerationSubjectState(targetUri)).thenAnswer(
          (_) async => ++stateReads == 1
              ? targetClearState()
              : ModerationSubjectState.fromJson(const {
                  'subject': targetUri,
                  'version': 'v5',
                  'moderation': {'state': 'removed'},
                  'recordState': 'present',
                  'currentSubject': {'uri': targetUri, 'cid': targetCid},
                  'localRemoval': {
                    'serviceDid': localRemovalServiceDid,
                    'actionId': 'removal-2',
                  },
                }),
        );
        when(
          api.restoreContent(
            actionId: anyNamed('actionId'),
            expectedVersion: anyNamed('expectedVersion'),
            idempotencyKey: anyNamed('idempotencyKey'),
            reason: anyNamed('reason'),
            reviewedSubject: anyNamed('reviewedSubject'),
            privateNote: anyNamed('privateNote'),
          ),
        ).thenAnswer(
          (_) async => ModerationMutationResult.fromJson(restoreContentJson()),
        );
        await pumpPostDetail(tester);
        threadRequests.clear();

        await submitRemovalOfTarget(tester);
        await tester.pumpAndSettle();
        expect(targetPlaceholder(), findsOneWidget);
        expect(threadRequests, ['c']);
        readBack.complete(servedRemovedTargetPage());
        await tester.pumpAndSettle();

        await expectTargetOffersRestore(tester);
        await tester.tap(find.text('Restore comment'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text('Rule violation'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.ancestor(
            of: find.text('Restore'),
            matching: find.bySubtype<ButtonStyleButton>(),
          ),
        );
        await tester.pumpAndSettle();

        final sent = verify(
          api.restoreContent(
            actionId: captureAnyNamed('actionId'),
            expectedVersion: captureAnyNamed('expectedVersion'),
            idempotencyKey: anyNamed('idempotencyKey'),
            reason: anyNamed('reason'),
            reviewedSubject: anyNamed('reviewedSubject'),
            privateNote: anyNamed('privateNote'),
          ),
        ).captured;
        expect(sent, ['removal-2', 'v5']);
        expect(threadRequests, ['c', null]);
        expect(find.byType(BottomSheet), findsNothing);
        expect(
          find.descendant(
            of: _cardOf(targetUri),
            matching: find.text('Comment C to remove'),
          ),
          findsOneWidget,
        );
        expect(targetPlaceholder(), findsNothing);
      },
    );

    final unusableSessionRows = [
      (
        name: 'authority was revoked',
        change: (WidgetTester tester) async {
          authority.markRevoked();
          await tester.pumpAndSettle();
        },
      ),
    ];
    for (final row in unusableSessionRows) {
      postDetailTest(
        'R9 a read-back landing after ${row.name} delivers the restore token '
        'but offers no Restore comment',
        (tester) async {
          final readBack = holdReadBackOfTarget();
          await pumpPostDetail(tester);
          threadRequests.clear();

          await submitRemovalOfTarget(tester);
          await tester.pumpAndSettle();
          expect(targetPlaceholder(), findsOneWidget);

          await row.change(tester);
          readBack.complete(servedRemovedTargetPage());
          await tester.pumpAndSettle();

          expect(
            tester
                .widget<CommentCard>(_cardOf(targetUri))
                .comment
                .viewer
                ?.moderation,
            contains(ModerationCapability.restore),
          );
          expect(targetPlaceholder(), findsOneWidget);
          expect(targetOptions(), findsNothing);
        },
      );
    }

    postDetailTest(
      'R9 a read-back landing after the session switched to another admin '
      'account is dropped with the old session\'s provider, and the thread '
      'shows what the server serves the new account',
      (tester) async {
        final readBack = holdReadBackOfTarget();
        await pumpPostDetail(tester);
        threadRequests.clear();

        await submitRemovalOfTarget(tester);
        await tester.pumpAndSettle();
        expect(targetPlaceholder(), findsOneWidget);

        // The detail refetches the post's vote for the new account.
        provideDummy<PostGetResult>(PostGetNotFound(removalPost().post.uri));
        when(api.getPost(removalPost().post.uri))
            .thenAnswer((_) async => PostGetSuccess(removalPost().post));
        // No sign-out in between: the cache still drops the provider on the
        // DID change, and the screen loads the thread for the new account.
        auth.setSignedInDid('did:plc:otheradmin');
        await tester.pumpAndSettle();
        expect(authority.isInstanceAdmin, isTrue);
        expect(threadRequests, ['c', null]);

        readBack.complete(servedRemovedTargetPage());
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<CommentCard>(_cardOf(targetUri))
              .comment
              .viewer
              ?.moderation,
          isNot(contains(ModerationCapability.restore)),
        );
        expect(targetPlaceholder(), findsNothing);
        expect(
          find.descendant(
            of: _cardOf(targetUri),
            matching: find.text('Comment C to remove'),
          ),
          findsOneWidget,
        );
      },
    );

    group('B6 recovery', () {
      postDetailTest(
        'B6 ContentChanged closes the sheet and reloads the thread quietly',
        (tester) async {
          removeContentThrows(
            ApiException(
              'Edited',
              statusCode: 400,
              errorCode: 'ContentChanged',
            ),
          );
          await pumpPostDetail(tester);
          final provider = tester
              .element(_cardOf(rootUri))
              .read<CommentsProvider>();
          final reload = Completer<CommentsResponse>();
          threadRequests.clear();
          answerThreadRequests((_) => reload.future);

          await submitRemovalOfTarget(tester);
          await pumpWhileHeld(tester);

          expect(threadRequests, [null]);
          for (final text in [
            'Root comment R',
            'Comment C to remove',
            'Reply C1',
            'Reply C2',
            'Sibling comment S',
          ]) {
            expect(find.text(text), findsOneWidget, reason: text);
          }
          expect(find.byType(FullScreenLoading), findsNothing);
          expect(provider.isLoading, isFalse);

          reload.complete(
            CommentsResponse(
              post: null,
              comments: liveThreads(targetBody: serverTargetText),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byType(BottomSheet), findsNothing);
          expect(
            find.descendant(
              of: _cardOf(targetUri),
              matching: find.text('Comment C as the server has it now'),
            ),
            findsOneWidget,
          );
          expect(
            find.text(
              'The author edited this comment. Review the new version '
              'before acting.',
            ),
            findsOneWidget,
          );
        },
      );

      postDetailTest(
        'B6 ContentChanged whose quiet reload fails says the latest version '
        "couldn't load and keeps C",
        (tester) async {
          removeContentThrows(
            ApiException(
              'Edited',
              statusCode: 400,
              errorCode: 'ContentChanged',
            ),
          );
          await pumpPostDetail(tester);
          final reload = Completer<CommentsResponse>();
          threadRequests.clear();
          answerThreadRequests((_) => reload.future);

          await submitRemovalOfTarget(tester);
          await pumpWhileHeld(tester);
          expect(threadRequests, [null]);

          reload.completeError(NetworkException('Unreachable'));
          await tester.pumpAndSettle();

          expect(find.byType(BottomSheet), findsNothing);
          expect(
            find.text("Couldn't load the latest version. Try again."),
            findsOneWidget,
          );
          expect(
            find.text(
              'The author edited this comment. Review the new version '
              'before acting.',
            ),
            findsNothing,
          );
          expect(
            find.text('This item changed. Showing the latest version.'),
            findsNothing,
          );
          expect(
            find.descendant(
              of: _cardOf(targetUri),
              matching: find.text('Comment C to remove'),
            ),
            findsOneWidget,
          );
        },
      );

      postDetailTest(
        'B6 ModerationUnavailable leaves C unchanged and offers Try again',
        (tester) async {
          removeContentThrows(
            ServerException(
              'Unavailable',
              statusCode: 503,
              errorCode: 'ModerationUnavailable',
            ),
          );
          await pumpPostDetail(tester);
          threadRequests.clear();

          await submitRemovalOfTarget(tester);
          await tester.pumpAndSettle();

          expect(
            find.descendant(
              of: find.byType(BottomSheet),
              matching: find.text('Try again'),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: _cardOf(targetUri),
              matching: find.text('Comment C to remove'),
            ),
            findsOneWidget,
          );
          expect(targetPlaceholder(), findsNothing);
          expect(threadRequests, isEmpty);
        },
      );

      postDetailTest(
        'B6 an unchanged success shows the placeholder, says the comment was '
        'already removed, then reads C back and offers Restore comment',
        (tester) async {
          final readBack = holdReadBackOfTarget();
          when(
            api.removeContent(
              subject: anyNamed('subject'),
              expectedVersion: anyNamed('expectedVersion'),
              idempotencyKey: anyNamed('idempotencyKey'),
              reason: anyNamed('reason'),
              privateNote: anyNamed('privateNote'),
            ),
          ).thenAnswer(
            (_) async => ModerationMutationResult.fromJson(
              removeContentJson(outcome: 'unchanged', withAction: false),
            ),
          );
          await pumpPostDetail(tester);
          threadRequests.clear();

          await submitRemovalOfTarget(tester);
          await tester.pumpAndSettle();

          expect(find.byType(BottomSheet), findsNothing);
          expect(targetPlaceholder(), findsOneWidget);
          expect(targetOptions(), findsNothing);
          expect(find.text('Comment was already removed'), findsOneWidget);
          expect(threadRequests, ['c']);

          readBack.complete(servedRemovedTargetPage());
          await tester.pumpAndSettle();

          expect(find.byType(PostDetailScreen), findsOneWidget);
          await expectTargetOffersRestore(tester);
          expect(threadRequests, ['c']);
        },
      );

      postDetailTest(
        'B6 a StateConflict whose current state is removed shows the '
        'placeholder, then reads C back and offers Restore comment',
        (tester) async {
          final readBack = holdReadBackOfTarget();
          var stateReads = 0;
          when(api.getModerationSubjectState(targetUri)).thenAnswer(
            (_) async =>
                ++stateReads == 1 ? targetClearState() : targetRemovedState(),
          );
          removeContentThrows(
            ApiException(
              'Conflict',
              statusCode: 400,
              errorCode: 'StateConflict',
            ),
          );
          await pumpPostDetail(tester);
          threadRequests.clear();

          await submitRemovalOfTarget(tester);
          await tester.pumpAndSettle();

          expect(find.byType(BottomSheet), findsNothing);
          expect(targetPlaceholder(), findsOneWidget);
          expect(targetOptions(), findsNothing);
          expect(
            find.text('Someone else already removed this comment.'),
            findsOneWidget,
          );
          expect(threadRequests, ['c']);

          readBack.complete(servedRemovedTargetPage());
          await tester.pumpAndSettle();

          expect(find.byType(PostDetailScreen), findsOneWidget);
          await expectTargetOffersRestore(tester);
          expect(threadRequests, ['c']);
        },
      );
      postDetailTest(
        'B6 Try again after ModerationUnavailable replays the same key, '
        'reason and note without re-reading the state',
        (tester) async {
          var removals = 0;
          when(
            api.removeContent(
              subject: anyNamed('subject'),
              expectedVersion: anyNamed('expectedVersion'),
              idempotencyKey: anyNamed('idempotencyKey'),
              reason: anyNamed('reason'),
              privateNote: anyNamed('privateNote'),
            ),
          ).thenAnswer((_) async {
            if (++removals == 1) {
              throw ServerException(
                'Unavailable',
                statusCode: 503,
                errorCode: 'ModerationUnavailable',
              );
            }
            return ModerationMutationResult.fromJson(removeContentJson());
          });
          await pumpPostDetail(tester);
          threadRequests.clear();

          await submitRemovalOfTarget(tester, note: 'review note');
          await tester.pumpAndSettle();
          await tester.tap(
            find.ancestor(
              of: find.descendant(
                of: find.byType(BottomSheet),
                matching: find.text('Try again'),
              ),
              matching: find.bySubtype<ButtonStyleButton>(),
            ),
          );
          await tester.pumpAndSettle();

          final sent = verify(
            api.removeContent(
              subject: anyNamed('subject'),
              expectedVersion: anyNamed('expectedVersion'),
              idempotencyKey: captureAnyNamed('idempotencyKey'),
              reason: captureAnyNamed('reason'),
              privateNote: captureAnyNamed('privateNote'),
            ),
          ).captured;
          expect(sent, hasLength(6));
          expect(
            sent[0],
            isA<String>().having(
              (key) => key.isNotEmpty,
              'non-empty key',
              true,
            ),
          );
          expect(sent.sublist(0, 3), [
            sent[0],
            ModerationReason.spam,
            'review note',
          ]);
          expect(sent.sublist(3), sent.sublist(0, 3));
          verify(api.getModerationSubjectState(targetUri)).called(1);
          expect(find.byType(BottomSheet), findsNothing);
          expect(targetPlaceholder(), findsOneWidget);
          expect(threadRequests, ['c']);
        },
      );

      postDetailTest(
        'B6 Forbidden closes the sheet, revokes admin tools and keeps C',
        (tester) async {
          removeContentThrows(
            ApiException('Forbidden', statusCode: 403, errorCode: 'Forbidden'),
          );
          await pumpPostDetail(tester);
          threadRequests.clear();

          await submitRemovalOfTarget(tester);
          await tester.pumpAndSettle();

          expect(find.byType(BottomSheet), findsNothing);
          expect(find.text('You no longer have admin access.'), findsOneWidget);
          expect(authority.isRevoked, isTrue);
          expect(
            find.descendant(
              of: _cardOf(targetUri),
              matching: find.text('Comment C to remove'),
            ),
            findsOneWidget,
          );
          await tester.tap(
            find.descendant(
              of: _cardOf(targetUri),
              matching: find.byTooltip('Comment options'),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Report comment'), findsOneWidget);
          expect(find.text('Remove comment'), findsNothing);
          expect(threadRequests, isEmpty);
        },
      );

      postDetailTest(
        'B6 a StateConflict whose current state is not removed keeps the '
        'sheet open to confirm again and keeps C',
        (tester) async {
          var stateReads = 0;
          when(api.getModerationSubjectState(targetUri)).thenAnswer((_) async {
            stateReads++;
            return targetClearState();
          });
          removeContentThrows(
            ApiException(
              'Conflict',
              statusCode: 400,
              errorCode: 'StateConflict',
            ),
          );
          await pumpPostDetail(tester);
          threadRequests.clear();

          await submitRemovalOfTarget(tester);
          await tester.pumpAndSettle();

          expect(stateReads, 2, reason: 'the conflict re-read the state');
          expect(
            find.descendant(
              of: find.byType(BottomSheet),
              matching: find.text(
                'Someone else acted on this first. Confirm again.',
              ),
            ),
            findsOneWidget,
          );
          expect(_removeButton, findsOneWidget);
          expect(
            find.descendant(
              of: _cardOf(targetUri),
              matching: find.text('Comment C to remove'),
            ),
            findsOneWidget,
          );
          expect(targetPlaceholder(), findsNothing);
          expect(threadRequests, isEmpty);
        },
      );
    });
  });

  testWidgets('a failed delete of the own comment shows the shared copy', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final auth = FakeAuthProvider(
      signedInDid: targetAuthorDid,
      signedInHandle: 'commenter.coves.test',
    );
    addTearDown(auth.dispose);
    final authority = ViewerAuthorityProvider(
      apiService: api,
      authProvider: auth,
    );
    addTearDown(authority.dispose);
    final blocks = BlockProvider(apiService: api, authProvider: auth);
    addTearDown(blocks.dispose);

    for (final row in errorCopyRows(
      'Could not delete comment. Please try again.',
    )) {
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
                comment: fixtureComment(
                  uri: targetUri,
                  authorDid: targetAuthorDid,
                  text: targetText,
                  parentUri: rootUri,
                ),
                sessionStamp: null,
                onDelete: (_) async => throw row.error,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Comment options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete comment'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(row.expected),
        ),
        findsOneWidget,
        reason: row.name,
      );
      if (row.rawText != null) {
        expect(
          find.textContaining(row.rawText!),
          findsNothing,
          reason: row.name,
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
