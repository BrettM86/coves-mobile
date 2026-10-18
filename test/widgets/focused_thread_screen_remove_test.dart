import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/moderation_subject_state.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/comments_provider.dart';
import 'package:coves_flutter/providers/viewer_authority_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/home/focused_thread_screen.dart';
import 'package:coves_flutter/screens/home/post_detail_screen.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/comments_provider_cache.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/post_change_broadcast.dart';
import 'package:coves_flutter/services/streamable_service.dart';
import 'package:coves_flutter/widgets/comment_card.dart';
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

Finder get _removeButton => find.ancestor(
  of: find.text('Remove'),
  matching: find.bySubtype<ButtonStyleButton>(),
);

const _placeholder = '[Removed by server admin]';

/// The route the focused screen is pushed above.
const _baseRouteText = 'Base route';

void main() {
  late MockCovesApiService api;
  late FakeAuthProvider auth;
  late ViewerAuthorityProvider authority;
  late VoteProvider votes;
  late BlockProvider blocks;
  late List<String?> threadRequests;
  // Disposed inside the test body (see [removalTest]), in this order.
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
    threadRequests = [];
    bodyDisposals = [];
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

  CommentsResponse page(List<ThreadViewComment> comments) =>
      CommentsResponse(post: null, comments: comments);

  // Unmount and dispose inside the test body: a loaded provider's periodic
  // time-update timer must be cancelled before the binding checks for
  // pending timers, which happens before tearDowns run.
  void removalTest(
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

  /// Opens C's menu, picks "Remove comment", chooses Spam and taps Remove.
  /// Leaves the answer unsettled for the caller.
  Future<void> submitRemovalOfTarget(WidgetTester tester) async {
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
    await tester.tap(_removeButton);
  }

  void markTargetRemoved(CommentsProvider provider) {
    final result = ModerationMutationResult.fromJson(removeContentJson());
    provider.markCommentRemoved(
      commentUri: targetUri,
      state: result.state,
      action: result.action,
    );
  }

  removalTest(
    'B5 (a) after C is removed in post detail, a focused thread on C from '
    'the same cached provider shows the placeholder',
    (tester) async {
      // The focused screen's entry hydration finds nothing more to load.
      answerThreadRequests(
        (parentRkey) async =>
            parentRkey == null ? page(liveThreads()) : page(const []),
      );
      await pumpApp(
        tester,
        home: PostDetailScreen(sessionStamp: null, post: removalPost()),
      );

      await submitRemovalOfTarget(tester);
      await tester.pumpAndSettle();

      final postDetail = tester.element(_cardOf(rootUri));
      unawaited(
        Navigator.of(postDetail).push(
          MaterialPageRoute<void>(
            builder: (_) => FocusedThreadScreen(
              // The snapshot the caller held from before the removal.
              thread: liveTarget(),
              ancestors: [liveRoot()],
              commentsProvider: postDetail.read<CommentsProvider>(),
              parentPost: removalPost().post,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FocusedThreadScreen), findsOneWidget);
      expect(_textOnCard(targetUri, _placeholder), findsOneWidget);
      expect(find.text(targetText), findsNothing);
    },
  );

  final snapshotRows = [
    (
      name: 'B5 (b) a fallback anchor C outside the provider tree',
      thread: liveTarget,
      ancestors: () => [liveRoot()],
    ),
    (
      name: 'B5 (c) C as an ancestor row of a focused thread on C1',
      thread: () => liveTarget().replies!.first,
      ancestors: () => [liveRoot(), liveTarget()],
    ),
    (
      name: 'B5 (d) C as a reply under a focused anchor R',
      thread: liveRoot,
      ancestors: () => <ThreadViewComment>[],
    ),
  ];
  for (final row in snapshotRows) {
    removalTest('${row.name} shows the placeholder once C is removed', (
      tester,
    ) async {
      // The provider's loaded tree holds only S.
      answerThreadRequests(
        (parentRkey) async =>
            parentRkey == null ? page([liveSibling()]) : page(const []),
      );
      final provider = await loadedProvider();
      await pumpApp(
        tester,
        home: FocusedThreadScreen(
          thread: row.thread(),
          ancestors: row.ancestors(),
          commentsProvider: provider,
          parentPost: removalPost().post,
        ),
      );
      await scrollBackToTop(tester);
      expect(_textOnCard(targetUri, targetText), findsOneWidget);
      // C's row carries this screen's session stamp: admin tools show.
      final targetOptions = find.descendant(
        of: _cardOf(targetUri),
        matching: find.byTooltip('Comment options'),
      );
      await tester.tap(targetOptions);
      await tester.pumpAndSettle();
      expect(find.text('Remove comment'), findsOneWidget);
      await tester.tap(targetOptions);
      await tester.pumpAndSettle();
      expect(find.text('Remove comment'), findsNothing);

      markTargetRemoved(provider);
      await tester.pumpAndSettle();

      expect(_textOnCard(targetUri, _placeholder), findsOneWidget);
      expect(find.text(targetText), findsNothing);
    });
  }

  final readBackRows = [
    (
      name: 'R8 (a) C as the fallback anchor',
      thread: liveTarget,
      ancestors: () => [liveRoot()],
    ),
    (
      name: 'R8 (b) C as an ancestor row of a focused thread on C1',
      thread: () => liveTarget().replies!.first,
      ancestors: () => [liveRoot(), liveTarget()],
    ),
  ];
  for (final row in readBackRows) {
    removalTest(
      '${row.name}: removing C from the focused screen reads C back and its '
      'row offers Restore comment without leaving the screen',
      (tester) async {
        // The provider's loaded tree holds only S. Until the removal, every
        // other read answers at once with nothing more to load; from the
        // submission on, reads of C ('c') are held.
        var holdTargetReads = false;
        final readBack = Completer<CommentsResponse>();
        answerThreadRequests((parentRkey) {
          if (parentRkey == null) {
            return Future.value(page([liveSibling()]));
          }
          if (parentRkey == 'c' && holdTargetReads) {
            return readBack.future;
          }
          return Future.value(page(const []));
        });
        final provider = await loadedProvider();
        await pumpApp(
          tester,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => FocusedThreadScreen(
                        thread: row.thread(),
                        ancestors: row.ancestors(),
                        commentsProvider: provider,
                        parentPost: removalPost().post,
                      ),
                    ),
                  ),
                  child: const Text(_baseRouteText),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text(_baseRouteText));
        await tester.pumpAndSettle();
        await scrollBackToTop(tester);
        expect(_textOnCard(targetUri, targetText), findsOneWidget);
        final targetOptions = find.descendant(
          of: _cardOf(targetUri),
          matching: find.byTooltip('Comment options'),
        );

        holdTargetReads = true;
        await submitRemovalOfTarget(tester);
        await tester.pumpAndSettle();
        await scrollBackToTop(tester);

        expect(find.byType(BottomSheet), findsNothing);
        expect(_textOnCard(targetUri, _placeholder), findsOneWidget);
        expect(targetOptions, findsNothing);

        readBack.complete(page([serverRemovedTargetThread()]));
        await tester.pumpAndSettle();
        await scrollBackToTop(tester);

        expect(find.byType(FocusedThreadScreen), findsOneWidget);
        expect(find.text(_baseRouteText), findsNothing);
        expect(_textOnCard(targetUri, _placeholder), findsOneWidget);
        expect(targetOptions, findsOneWidget);
        await tester.tap(targetOptions);
        await tester.pumpAndSettle();
        expect(find.text('Restore comment'), findsOneWidget);
      },
    );
  }

  removalTest(
    'an ancestor row whose remove token was loaded for admin A offers no '
    'Remove comment once the session switches to account B and the new '
    "provider's first page lands",
    (tester) async {
      const otherDid = 'did:plc:notadmin';
      // Only A is an instance admin; B's responses carry no tokens.
      when(api.getViewerAuthority())
          .thenAnswer((_) async => auth.did == adminDid);
      answerThreadRequests(
        (parentRkey) async =>
            parentRkey == null ? page([liveSibling()]) : page(const []),
      );
      final provider = await loadedProvider();
      await pumpApp(
        tester,
        home: FocusedThreadScreen(
          // C is an ancestor row of a focused thread on C1; its snapshot
          // carries the remove token served to A.
          thread: liveTarget().replies!.first,
          ancestors: [liveRoot(), liveTarget()],
          commentsProvider: provider,
          parentPost: removalPost().post,
        ),
      );
      await scrollBackToTop(tester);
      final targetOptions = find.descendant(
        of: _cardOf(targetUri),
        matching: find.byTooltip('Comment options'),
      );
      // Control: under A the ancestor row offers the admin tool.
      await tester.tap(targetOptions);
      await tester.pumpAndSettle();
      expect(find.text('Remove comment'), findsOneWidget);
      await tester.tap(targetOptions);
      await tester.pumpAndSettle();
      expect(find.text('Remove comment'), findsNothing);

      auth.setSignedInDid(otherDid);
      await tester.pumpAndSettle();
      final newProvider = cache.peekProvider(removalPostUri)!;
      expect(
        newProvider,
        isNot(same(provider)),
        reason: 'control: the account change replaced the provider',
      );
      // The new session's first page lands, as the post screen underneath
      // loads it.
      await newProvider.loadComments(refresh: true);
      await tester.pumpAndSettle();
      expect(
        newProvider.sessionStamp,
        authority.sessionKey,
        reason: "control: the new provider is stamped with B's session",
      );
      expect(authority.isRevoked, isFalse);
      await scrollBackToTop(tester);

      expect(_textOnCard(targetUri, targetText), findsOneWidget);
      await tester.tap(targetOptions);
      await tester.pumpAndSettle();
      expect(
        find.text('Remove comment'),
        findsNothing,
        reason:
            "the ancestor's remove token was served to account A, so "
            'account B must not be offered Remove comment',
      );
    },
  );

  const failedReloadCopy = "Couldn't load the latest version. Try again.";
  const contentChangedCopy =
      'The author edited this comment. Review the new version before acting.';
  const subjectChangedCopy = 'This item changed. Showing the latest version.';
  final contentChanged = ApiException(
    'Edited',
    statusCode: 400,
    errorCode: 'ContentChanged',
  );
  final subjectNotFound = ApiException(
    'Gone',
    statusCode: 404,
    errorCode: 'SubjectNotFound',
  );
  // ancestorAnswer / subtreeAnswer: how A's fetch (parentRkey 'r') and C's
  // subtree fetch (parentRkey 'c') answer: 'edited' lands the server's copy,
  // 'edited-no-replies' lands it with no replies (subtree only), 'empty'
  // lands a page without the comment, 'fails' throws.
  final reloadRows = [
    (
      name: 'B7 ContentChanged',
      error: contentChanged,
      ancestorAnswer: 'edited',
      subtreeAnswer: 'edited',
      expectedRootText: editedRootText,
      expectedTargetText: serverTargetText,
      expectedSnackbar: contentChangedCopy,
      absentSnackbar: failedReloadCopy,
    ),
    (
      name: 'B7 SubjectNotFound',
      error: subjectNotFound,
      ancestorAnswer: 'edited',
      subtreeAnswer: 'edited',
      expectedRootText: editedRootText,
      expectedTargetText: serverTargetText,
      expectedSnackbar: subjectChangedCopy,
      absentSnackbar: failedReloadCopy,
    ),
    (
      name: "B7 SubjectNotFound with C's subtree landing without replies",
      error: subjectNotFound,
      ancestorAnswer: 'edited',
      subtreeAnswer: 'edited-no-replies',
      expectedRootText: editedRootText,
      expectedTargetText: serverTargetText,
      expectedSnackbar: subjectChangedCopy,
      absentSnackbar: failedReloadCopy,
    ),
    (
      name: "B7 ContentChanged with A's fetch failing",
      error: contentChanged,
      ancestorAnswer: 'fails',
      subtreeAnswer: 'edited',
      expectedRootText: rootText,
      expectedTargetText: serverTargetText,
      expectedSnackbar: failedReloadCopy,
      absentSnackbar: contentChangedCopy,
    ),
    (
      name: "B7 ContentChanged with A's fetch empty",
      error: contentChanged,
      ancestorAnswer: 'empty',
      subtreeAnswer: 'edited',
      expectedRootText: rootText,
      expectedTargetText: serverTargetText,
      expectedSnackbar: failedReloadCopy,
      absentSnackbar: contentChangedCopy,
    ),
    (
      name: "B7 SubjectNotFound with C's subtree empty",
      error: subjectNotFound,
      ancestorAnswer: 'edited',
      subtreeAnswer: 'empty',
      expectedRootText: editedRootText,
      expectedTargetText: targetText,
      expectedSnackbar: failedReloadCopy,
      absentSnackbar: subjectChangedCopy,
    ),
    (
      name: "B7 SubjectNotFound with C's subtree failing",
      error: subjectNotFound,
      ancestorAnswer: 'edited',
      subtreeAnswer: 'fails',
      expectedRootText: editedRootText,
      expectedTargetText: targetText,
      expectedSnackbar: failedReloadCopy,
      absentSnackbar: subjectChangedCopy,
    ),
  ];
  for (final row in reloadRows) {
    removalTest(
      '${row.name}: removing a fallback anchor C from the focused screen '
      'closes the sheet and reloads the thread, C and its ancestor quietly',
      (tester) async {
        // Before the removal every request answers at once; from the
        // submission on, each is held until the test resolves it.
        var holdRequests = false;
        final held = <(String?, Completer<CommentsResponse>)>[];
        answerThreadRequests((parentRkey) {
          if (holdRequests) {
            final response = Completer<CommentsResponse>();
            held.add((parentRkey, response));
            return response.future;
          }
          return Future.value(switch (parentRkey) {
            null => page([liveSibling()]),
            'c' => page([liveTarget()]),
            _ => page([liveRoot()]),
          });
        });
        when(
          api.removeContent(
            subject: anyNamed('subject'),
            expectedVersion: anyNamed('expectedVersion'),
            idempotencyKey: anyNamed('idempotencyKey'),
            reason: anyNamed('reason'),
            privateNote: anyNamed('privateNote'),
          ),
        ).thenThrow(row.error);

        final provider = await loadedProvider();
        await pumpApp(
          tester,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => FocusedThreadScreen(
                        thread: liveTarget(),
                        ancestors: [liveRoot()],
                        commentsProvider: provider,
                        parentPost: removalPost().post,
                      ),
                    ),
                  ),
                  child: const Text(_baseRouteText),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text(_baseRouteText));
        await tester.pumpAndSettle();
        await scrollBackToTop(tester);
        expect(_textOnCard(targetUri, targetText), findsOneWidget);
        expect(_textOnCard(rootUri, rootText), findsOneWidget);

        holdRequests = true;
        threadRequests.clear();
        await submitRemovalOfTarget(tester);
        for (var frame = 0; frame < 10; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        // While the reload is out, the focused screen keeps its content.
        expect(held, isNotEmpty, reason: 'the reload is still out');
        expect(find.byType(FocusedThreadScreen), findsOneWidget);
        expect(_textOnCard(targetUri, targetText), findsOneWidget);
        expect(provider.isLoading, isFalse);
        // The thread reloads first; the screen's own snapshots wait for it.
        expect(held.map((request) => request.$1), [null]);

        // Resolve the held requests, the top-level thread last in each
        // round, until no new request goes out.
        while (held.isNotEmpty) {
          final round = [...held]
            ..sort((a, b) => (a.$1 == null ? 1 : 0) - (b.$1 == null ? 1 : 0));
          held.clear();
          for (final (parentRkey, response) in round) {
            switch (parentRkey) {
              case null:
                response.complete(page([liveSibling()]));
              case 'c' when row.subtreeAnswer == 'fails':
                response.completeError(
                  ServerException('Unavailable', statusCode: 503),
                );
              case 'c' when row.subtreeAnswer == 'empty':
                response.complete(page(const []));
              case 'c' when row.subtreeAnswer == 'edited-no-replies':
                response.complete(
                  page([
                    liveTarget(text: serverTargetText, withReplies: false),
                  ]),
                );
              case 'c':
                response.complete(page([liveTarget(text: serverTargetText)]));
              case 'r' when row.ancestorAnswer == 'fails':
                response.completeError(
                  ServerException('Unavailable', statusCode: 503),
                );
              case 'r' when row.ancestorAnswer == 'empty':
                response.complete(page(const []));
              default:
                response.complete(
                  page([
                    liveRoot(
                      text: editedRootText,
                      targetBody: serverTargetText,
                    ),
                  ]),
                );
            }
            await tester.pump();
          }
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.text(row.expectedSnackbar),
          ),
          findsOneWidget,
        );
        expect(find.text(row.absentSnackbar), findsNothing);
        expect(find.byType(BottomSheet), findsNothing);
        expect(threadRequests.toSet(), {null, 'c', 'r'});
        expect(find.byType(FocusedThreadScreen), findsOneWidget);
        expect(find.text(_baseRouteText), findsNothing);
        await scrollBackToTop(tester);
        expect(_textOnCard(targetUri, row.expectedTargetText), findsOneWidget);
        expect(_textOnCard(rootUri, row.expectedRootText), findsOneWidget);
      },
    );
  }
}
