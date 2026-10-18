import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/moderation.dart';
import 'package:coves_flutter/models/moderation_subject_state.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/comments_provider.dart';
import 'package:coves_flutter/providers/viewer_authority_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/home/focused_thread_screen.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/comments_provider_cache.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/post_change_broadcast.dart';
import 'package:coves_flutter/services/streamable_service.dart';
import 'package:coves_flutter/widgets/comment_card.dart';
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

Finder _textOnCard(String uri, String text) =>
    find.descendant(of: _cardOf(uri), matching: find.text(text));

Finder _optionsOf(String uri) => find.descendant(
  of: _cardOf(uri),
  matching: find.byTooltip('Comment options'),
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

const _placeholder = '[Removed by server admin]';

/// R as the server serves it while C is removed: its only loaded reply is
/// C's placeholder.
ThreadViewComment _rootWithRemovedTarget() => threadsWithRemovedTarget().first;

ThreadViewComment _reply1Thread() => liveTarget().replies![0];

ThreadViewComment _reply2Thread() => liveTarget().replies![1];

/// R live with C live as its only loaded reply, carrying the `remove` token
/// so a removal attempt on R can trigger a reload of the screen's snapshots.
ThreadViewComment _removableRoot() => ThreadViewComment(
  comment: fixtureComment(
    uri: rootUri,
    authorDid: 'did:plc:rootauthor',
    text: rootText,
    capabilities: const {ModerationCapability.remove},
  ),
  replies: [liveTarget()],
);

/// R's moderation state before any removal, as getSubjectState serves it.
const _rootClearState = ModerationSubjectState(
  subject: rootUri,
  version: 'v1',
  moderation: ModerationView(state: ModerationState.clear),
  recordState: ModerationRecordState.present,
  currentSubject: StrongRef(uri: rootUri, cid: 'cid-r'),
);

void main() {
  late MockCovesApiService api;
  late FakeAuthProvider auth;
  late ViewerAuthorityProvider authority;
  late VoteProvider votes;
  late BlockProvider blocks;
  // Disposed inside the test body (see [restoreTest]), in this order.
  late List<void Function()> bodyDisposals;
  // The app-wide cache FocusedThreadScreen pins the post's provider in.
  late CommentsProviderCache cache;

  setUp(() {
    api = MockCovesApiService();
    when(api.getViewerAuthority()).thenAnswer((_) async => true);
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
    bodyDisposals = [];
    when(api.getModerationSubjectState(targetUri))
        .thenAnswer((_) async => targetRemovedState());
  });

  /// Answers every getComments call with [answer] for the request's
  /// parentRkey (null for the top-level thread).
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
    ).thenAnswer(
      (invocation) => answer(invocation.namedArguments[#parentRkey] as String?),
    );
  }

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

  CommentsResponse page(List<ThreadViewComment> comments) =>
      CommentsResponse(post: null, comments: comments);

  // Unmount and dispose inside the test body: a loaded provider's periodic
  // time-update timer must be cancelled before the binding checks for
  // pending timers, which happens before tearDowns run.
  void restoreTest(
    String description,
    Future<void> Function(WidgetTester) body,
  ) {
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        for (final dispose in bodyDisposals) {
          dispose();
        }
      }
    });
  }

  /// A provider for post P whose first page is loaded under the current
  /// session.
  Future<CommentsProvider> loadedProvider() async {
    // As in the app, the post screen acquires the post's provider from the
    // cache and hands it to the focused thread.
    final provider = cache.acquireProvider(
      postUri: removalPostUri,
      postCid: removalPostCid,
    );
    await provider.loadComments(refresh: true);
    return provider;
  }

  Future<void> pumpApp(WidgetTester tester, {required Widget home}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    bodyDisposals.add(() {
      cache.dispose();
      blocks.dispose();
      votes.dispose();
      authority.dispose();
      auth.dispose();
    });
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
        child: MaterialApp(theme: AppTheme.dark, home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  FocusedThreadScreen focusedScreen(
    CommentsProvider provider, {
    required ThreadViewComment thread,
    required List<ThreadViewComment> ancestors,
  }) {
    return FocusedThreadScreen(
      thread: thread,
      ancestors: ancestors,
      commentsProvider: provider,
      parentPost: removalPost().post,
    );
  }

  /// The screen auto-scrolls the anchor to the top on entry, which pushes
  /// ancestor rows out of the viewport. Scroll back so they are built.
  Future<void> scrollBackToTop(WidgetTester tester) async {
    await tester.drag(
      find.descendant(
        of: find.byType(FocusedThreadScreen),
        matching: find.byType(CustomScrollView),
      ),
      const Offset(0, 800),
    );
    await tester.pumpAndSettle();
  }

  /// Opens C's placeholder menu, picks "Restore comment", chooses Rule
  /// violation, confirms and lets the answer and any reload finish.
  Future<void> restoreTargetFromPlaceholder(WidgetTester tester) async {
    expect(_textOnCard(targetUri, _placeholder), findsOneWidget);
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
    await tester.tap(_confirmButton);
    await tester.pumpAndSettle();
    await scrollBackToTop(tester);
  }

  void markTargetRemoved(CommentsProvider provider) {
    final result = ModerationMutationResult.fromJson(removeContentJson());
    provider.markCommentRemoved(
      commentUri: targetUri,
      state: result.state,
      action: result.action,
    );
  }

  group('B5 restoring C from its placeholder on a focused thread', () {
    // Each row opens a focused screen whose provider tree lacks C, restores
    // C from its placeholder, and expects the content where the placeholder
    // was. [removedEarlier] confirms a local removal of C before entry;
    // [afterRestore] runs any further steps of the row.
    final rows = [
      (
        name: '(a) a fallback anchor C',
        removedEarlier: false,
        thread: serverRemovedTargetThread,
        ancestors: () => [_rootWithRemovedTarget()],
        expectedOnCards: [
          (uri: targetUri, text: targetText),
          (uri: reply1Uri, text: reply1Text),
          (uri: reply2Uri, text: reply2Text),
        ],
      ),
      (
        name: '(b) C as an ancestor row of a focused thread on C1',
        removedEarlier: false,
        thread: _reply1Thread,
        ancestors: () => [
          _rootWithRemovedTarget(),
          serverRemovedTargetThread(),
        ],
        expectedOnCards: [(uri: targetUri, text: targetText)],
      ),
      (
        name:
            '(c) C removed earlier in this session, served to the screen as '
            'the restorable placeholder ancestor row of C1',
        removedEarlier: true,
        thread: _reply1Thread,
        ancestors: () => [
          _rootWithRemovedTarget(),
          serverRemovedTargetThread(),
        ],
        expectedOnCards: [(uri: targetUri, text: targetText)],
      ),
    ];
    for (final row in rows) {
      restoreTest('B5 ${row.name}: the content returns where the placeholder '
          'was', (tester) async {
        // Flipped when the server applies the restore: from then on C's and
        // R's snapshots carry C live.
        var restored = false;
        // From the second screen of row (c) on, no fetch lands anything.
        var serveNothing = false;
        answerThreadRequests((parentRkey) async {
          if (parentRkey == null) {
            // The provider's loaded tree holds only S.
            return page([liveSibling()]);
          }
          if (serveNothing) {
            return page(const []);
          }
          return switch (parentRkey) {
            'r' => page([
              if (restored) liveRoot() else _rootWithRemovedTarget(),
            ]),
            'c' => page([
              if (restored) liveTarget() else serverRemovedTargetThread(),
            ]),
            'c1' => page([_reply1Thread()]),
            'c2' => page([_reply2Thread()]),
            _ => page(const []),
          };
        });
        answerRestore(() async {
          restored = true;
          return ModerationMutationResult.fromJson(restoreContentJson());
        });

        final provider = await loadedProvider();
        if (row.removedEarlier) {
          markTargetRemoved(provider);
        }
        await pumpApp(
          tester,
          home: focusedScreen(
            provider,
            thread: row.thread(),
            ancestors: row.ancestors(),
          ),
        );
        await scrollBackToTop(tester);

        await restoreTargetFromPlaceholder(tester);

        expect(_sheet, findsNothing);
        for (final expected in row.expectedOnCards) {
          expect(
            _textOnCard(expected.uri, expected.text),
            findsOneWidget,
            reason: expected.uri,
          );
        }
        expect(_textOnCard(targetUri, _placeholder), findsNothing);

        if (!row.removedEarlier) {
          return;
        }
        // A new focused screen on C2, handed C live as an ancestor row, with
        // nothing usable from any fetch: the restore evicted the earlier
        // removal, so C's row shows its content.
        serveNothing = true;
        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        unawaited(
          navigator.pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => focusedScreen(
                provider,
                thread: _reply2Thread(),
                ancestors: [liveRoot(), liveTarget()],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await scrollBackToTop(tester);

        expect(_textOnCard(reply2Uri, reply2Text), findsOneWidget);
        expect(_textOnCard(targetUri, targetText), findsOneWidget);
        expect(_textOnCard(targetUri, _placeholder), findsNothing);
      });
    }
  });

  group(
    'B6 a restore the server still hides keeps earlier snapshots masked',
    () {
      // Screen F, focused on C1, was handed C live as an ancestor row before
      // C was removed, and never refreshes it. The admin continues into screen
      // G and restores C there, but the server still hides C. Back on F, C's
      // row must stay on the placeholder.
      final rows = [
        (
          name: 'the author deleted it',
          restored: restoreContentJson(recordState: 'deleted'),
          message: 'Restored, but the author deleted it, so it stays hidden.',
        ),
        (
          name: 'the record is unavailable',
          restored: restoreContentJson(recordState: 'unavailable'),
          message: "Restored, but it can't be shown right now.",
        ),
      ];
      for (final row in rows) {
        restoreTest(
          'B6 ${row.name}: the unrefreshed live row of C on the screen below '
          'stays on the placeholder',
          (tester) async {
            answerThreadRequests((parentRkey) async {
              return switch (parentRkey) {
                // The provider's loaded tree holds only S.
                null => page([liveSibling()]),
                'r' => page([_rootWithRemovedTarget()]),
                'c' => page([serverRemovedTargetThread()]),
                'c1' => page([_reply1Thread()]),
                _ => page(const []),
              };
            });
            answerRestore(
              () async => ModerationMutationResult.fromJson(row.restored),
            );

            final provider = await loadedProvider();
            await pumpApp(
              tester,
              home: focusedScreen(
                provider,
                thread: _reply1Thread(),
                ancestors: [liveRoot(), liveTarget()],
              ),
            );
            markTargetRemoved(provider);
            await tester.pump();
            await scrollBackToTop(tester);
            expect(_textOnCard(targetUri, _placeholder), findsOneWidget);
            expect(find.text(targetText), findsNothing);

            final navigator = tester.state<NavigatorState>(
              find.byType(Navigator),
            );
            unawaited(
              navigator.push(
                MaterialPageRoute<void>(
                  builder: (_) => focusedScreen(
                    provider,
                    thread: _reply1Thread(),
                    ancestors: [
                      _rootWithRemovedTarget(),
                      serverRemovedTargetThread(),
                    ],
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            await scrollBackToTop(tester);

            await restoreTargetFromPlaceholder(tester);

            expect(_sheet, findsNothing);
            expect(find.text(row.message), findsOneWidget);

            navigator.pop();
            await tester.pumpAndSettle();
            await scrollBackToTop(tester);

            expect(_textOnCard(targetUri, _placeholder), findsOneWidget);
            expect(find.text(targetText), findsNothing);
          },
        );
      }
    },
  );

  group('B7 focused-thread wiring', () {
    // Guard: passes on the base this run started from. A removal confirmed
    // before the screen opened still masks the live snapshots it is handed.
    final guardRows = [
      (
        name: 'a fallback anchor C',
        thread: liveTarget,
        ancestors: () => [liveRoot()],
      ),
      (
        name: 'C as an ancestor row of a focused thread on C1',
        thread: _reply1Thread,
        ancestors: () => [liveRoot(), liveTarget()],
      ),
    ];
    for (final row in guardRows) {
      restoreTest(
        'B7 (a) guard: C removed before entry shows the placeholder for '
        '${row.name} handed live snapshots',
        (tester) async {
          answerThreadRequests(
            (parentRkey) async =>
                parentRkey == null ? page([liveSibling()]) : page(const []),
          );
          final provider = await loadedProvider();
          markTargetRemoved(provider);

          await pumpApp(
            tester,
            home: focusedScreen(
              provider,
              thread: row.thread(),
              ancestors: row.ancestors(),
            ),
          );
          await scrollBackToTop(tester);

          expect(_textOnCard(targetUri, _placeholder), findsOneWidget);
          expect(find.text(targetText), findsNothing);
        },
      );
    }

    final decisionNotFound = ApiException(
      'DecisionNotFound',
      statusCode: 404,
      errorCode: 'DecisionNotFound',
    );
    final reloadRows = [
      (
        name:
            '(b) reloads the thread and its snapshots: C and the edited R '
            'show',
        rootLands: true,
      ),
      (
        name:
            "(c) says the latest version couldn't load when R's fetch is "
            'empty',
        rootLands: false,
      ),
    ];
    for (final row in reloadRows) {
      restoreTest(
        'B7 ${row.name} after a DecisionNotFound restore of a fallback '
        'anchor C',
        (tester) async {
          // Flipped when the restore is sent: from then on the server's
          // snapshots carry C live and R edited.
          var restoreSent = false;
          answerThreadRequests((parentRkey) async {
            return switch (parentRkey) {
              // Top-level reloads keep omitting C.
              null => page([liveSibling()]),
              'c' => page([
                if (restoreSent) liveTarget() else serverRemovedTargetThread(),
              ]),
              'r' when !restoreSent => page([_rootWithRemovedTarget()]),
              'r' when row.rootLands => page([liveRoot(text: editedRootText)]),
              _ => page(const []),
            };
          });
          answerRestore(() async {
            restoreSent = true;
            throw decisionNotFound;
          });

          final provider = await loadedProvider();
          await pumpApp(
            tester,
            home: focusedScreen(
              provider,
              thread: serverRemovedTargetThread(),
              ancestors: [_rootWithRemovedTarget()],
            ),
          );
          await scrollBackToTop(tester);

          await restoreTargetFromPlaceholder(tester);

          expect(_sheet, findsNothing);
          if (row.rootLands) {
            expect(_textOnCard(targetUri, targetText), findsOneWidget);
            expect(_textOnCard(rootUri, editedRootText), findsOneWidget);
            expect(
              find.text("Couldn't load the latest version. Try again."),
              findsNothing,
            );
          } else {
            expect(
              find.text("Couldn't load the latest version. Try again."),
              findsOneWidget,
            );
          }
        },
      );
    }
  });

  group('B8 per-row snapshot provenance on a focused thread', () {
    restoreTest(
      "B8 C removed while R's snapshot is still out keeps C's ancestor row "
      'on the placeholder once R lands',
      (tester) async {
        // From the removal attempt on, R's snapshot fetch is held until the
        // test releases it; every other request answers at once.
        var holdRoot = false;
        Completer<CommentsResponse>? heldRoot;
        answerThreadRequests((parentRkey) {
          if (parentRkey == 'r' && holdRoot) {
            return (heldRoot = Completer<CommentsResponse>()).future;
          }
          return Future.value(switch (parentRkey) {
            // The provider's loaded tree holds only S.
            null => page([liveSibling()]),
            'c' => page([liveTarget()]),
            'c1' => page([_reply1Thread()]),
            'r' => page([liveRoot()]),
            _ => page(const []),
          });
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
        ).thenThrow(
          ApiException('Edited', statusCode: 400, errorCode: 'ContentChanged'),
        );

        final provider = await loadedProvider();
        await pumpApp(
          tester,
          home: focusedScreen(
            provider,
            thread: _reply1Thread(),
            ancestors: [liveRoot(), liveTarget()],
          ),
        );
        await scrollBackToTop(tester);
        expect(_textOnCard(targetUri, targetText), findsOneWidget);

        // A removal attempt the server answers with ContentChanged reloads
        // the thread and this screen's snapshots: C's lands live, R's is
        // held.
        holdRoot = true;
        await tester.tap(_optionsOf(targetUri));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Remove comment'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(of: _sheet, matching: find.text('Spam')),
        );
        await tester.pumpAndSettle();
        await tester.tap(_confirmButton);
        for (var frame = 0; frame < 10; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(heldRoot, isNotNull, reason: "R's snapshot fetch is out");

        // C is then removed in this screen, and only after that R lands.
        markTargetRemoved(provider);
        await tester.pump();
        heldRoot!.complete(page([liveRoot()]));
        await tester.pumpAndSettle();
        await scrollBackToTop(tester);

        expect(_textOnCard(targetUri, _placeholder), findsOneWidget);
        expect(_textOnCard(targetUri, targetText), findsNothing);
      },
    );

    // C was removed before the screen opened, so the live snapshots handed
    // in show the placeholder. A refresh requested after that removal
    // serves C live (the server no longer hides it), and that row is taken
    // as served: the earlier removal is not applied over it again.
    final positionRows = [
      (
        name: 'a fallback anchor C',
        thread: liveTarget,
        ancestors: () => [_removableRoot()],
      ),
      (
        name: 'C as an ancestor row of a focused thread on C1',
        thread: _reply1Thread,
        ancestors: () => [_removableRoot(), liveTarget()],
      ),
    ];
    for (final row in positionRows) {
      restoreTest(
        'B8 C removed before entry shows its content for ${row.name} once a '
        'refresh requested after the removal serves C live',
        (tester) async {
          // Flipped by the removal attempt on R: until then C's snapshot and
          // subtree fetches carry nothing, so only the refresh it triggers
          // can land C.
          var removalAttempted = false;
          answerThreadRequests((parentRkey) async {
            return switch (parentRkey) {
              // The provider's loaded tree holds only S.
              null => page([liveSibling()]),
              'r' => page([_removableRoot()]),
              'c' when removalAttempted => page([liveTarget()]),
              'c1' => page([_reply1Thread()]),
              _ => page(const []),
            };
          });
          when(api.getModerationSubjectState(rootUri))
              .thenAnswer((_) async => _rootClearState);
          when(
            api.removeContent(
              subject: anyNamed('subject'),
              expectedVersion: anyNamed('expectedVersion'),
              idempotencyKey: anyNamed('idempotencyKey'),
              reason: anyNamed('reason'),
              privateNote: anyNamed('privateNote'),
            ),
          ).thenAnswer((_) async {
            removalAttempted = true;
            throw ApiException(
              'Edited',
              statusCode: 400,
              errorCode: 'ContentChanged',
            );
          });

          final provider = await loadedProvider();
          markTargetRemoved(provider);
          await pumpApp(
            tester,
            home: focusedScreen(
              provider,
              thread: row.thread(),
              ancestors: row.ancestors(),
            ),
          );
          await scrollBackToTop(tester);
          expect(_textOnCard(targetUri, _placeholder), findsOneWidget);
          expect(_textOnCard(targetUri, targetText), findsNothing);

          // A removal attempt on R that the server answers with
          // ContentChanged reloads the thread and this screen's snapshots.
          await tester.tap(_optionsOf(rootUri));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Remove comment'));
          await tester.pumpAndSettle();
          await tester.tap(
            find.descendant(of: _sheet, matching: find.text('Spam')),
          );
          await tester.pumpAndSettle();
          await tester.tap(_confirmButton);
          await tester.pumpAndSettle();
          await scrollBackToTop(tester);

          expect(removalAttempted, isTrue);
          expect(_textOnCard(targetUri, targetText), findsOneWidget);
          expect(_textOnCard(targetUri, _placeholder), findsNothing);
        },
      );
    }
  });
}
