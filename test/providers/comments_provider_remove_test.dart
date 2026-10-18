import 'dart:async';

import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/moderation.dart';
import 'package:coves_flutter/models/moderation_subject_state.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/comments_provider.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/utils/removal_copy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/comment_removal_fixtures.dart';
import '../test_helpers/test_mocks.dart';

typedef _CommentsCall = ({
  String? parentRkey,
  String? cursor,
  Completer<CommentsResponse> response,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAuthProvider auth;
  late MockCovesApiService api;
  late List<_CommentsCall> calls;
  late List<CommentsProvider> providers;

  setUp(() {
    auth = MockAuthProvider();
    api = MockCovesApiService();
    calls = [];
    providers = [];
    when(auth.isAuthenticated).thenReturn(true);
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
      final call = (
        parentRkey: invocation.namedArguments[#parentRkey] as String?,
        cursor: invocation.namedArguments[#cursor] as String?,
        response: Completer<CommentsResponse>(),
      );
      calls.add(call);
      return call.response.future;
    });
  });

  tearDown(() {
    for (final provider in providers) {
      provider.dispose();
    }
  });

  CommentsProvider buildProvider({Object? Function()? sessionKeyOf}) {
    final provider = CommentsProvider(
      auth,
      postUri: removalPostUri,
      postCid: removalPostCid,
      apiService: api,
      sessionKeyOf: sessionKeyOf,
    );
    providers.add(provider);
    return provider;
  }

  CommentsResponse page(List<ThreadViewComment> threads, {String? cursor}) =>
      CommentsResponse(post: null, comments: threads, cursor: cursor);

  /// Starts [request], waits until its getComments call is in flight, and
  /// returns the pending future with that call.
  Future<(Future<Object?>, _CommentsCall)> start(
    Future<Object?> Function() request,
  ) async {
    final before = calls.length;
    final pending = request();
    await pumpEventQueue();
    expect(calls, hasLength(before + 1), reason: 'the request is in flight');
    return (pending, calls.last);
  }

  Future<void> loadFirstPage(
    CommentsProvider provider,
    List<ThreadViewComment> threads, {
    String? cursor,
  }) async {
    final (pending, call) = await start(
      () => provider.loadComments(refresh: true),
    );
    call.response.complete(page(threads, cursor: cursor));
    await pending;
  }

  ThreadViewComment? targetIn(List<ThreadViewComment> threads) =>
      threads.map((thread) => thread.findByUri(targetUri)).nonNulls.firstOrNull;

  String placeholderCopy(CommentView comment) => RemovalCopy.forComment(
    deletionReason: comment.deletionReason,
    moderation: comment.moderation,
  );

  void markRemoved(
    CommentsProvider provider, [
    Map<String, dynamic>? responseJson,
  ]) {
    final result = ModerationMutationResult.fromJson(
      responseJson ?? removeContentJson(),
    );
    provider.markCommentRemoved(
      commentUri: targetUri,
      state: result.state,
      action: result.action,
    );
  }

  group('B2 placeholder built from the confirmed removal', () {
    for (final row in [
      (
        name: 'applied with localRemoval and action',
        json: removeContentJson(),
        authorityDid: 'did:web:coves.test',
      ),
      (
        name: 'unchanged with localRemoval and no action',
        json: removeContentJson(outcome: 'unchanged', withAction: false),
        authorityDid: 'did:web:coves.test',
      ),
      (
        name: 'applied with action and no localRemoval',
        json: removeContentJson(withLocalRemoval: false),
        authorityDid: 'did:plc:actionauthority',
      ),
    ]) {
      test('B2 ${row.name}', () async {
        final provider = buildProvider();
        await loadFirstPage(provider, liveThreads());

        markRemoved(provider, row.json);

        final surfaces = [
          ('provider tree', targetIn(provider.comments)),
          (
            'overlaid live snapshot of R',
            provider.applyRemovalOverlay(liveRoot()).findByUri(targetUri),
          ),
        ];
        for (final (surface, node) in surfaces) {
          expect(node, isNotNull, reason: surface);
          final comment = node!.comment;
          expect(
            placeholderCopy(comment),
            '[Removed by server admin]',
            reason: surface,
          );
          expect(comment.isDeleted, isTrue, reason: surface);
          expect(comment.deletionReason, 'moderator', reason: surface);
          expect(comment.record, isNull, reason: surface);
          expect(comment.author?.did, 'did:plc:commenter', reason: surface);
          expect(
            comment.viewer?.moderation ?? const <ModerationCapability>{},
            isEmpty,
            reason: surface,
          );
          expect(
            comment.moderation?.state,
            ModerationState.removed,
            reason: surface,
          );
          expect(
            comment.moderation?.contentLabels.map((label) => label.value),
            ['graphic-media'],
            reason: surface,
          );
          expect(
            comment.moderation?.sources.map(
              (source) => (source.scope.kind, source.authorityDid),
            ),
            [(ModerationScopeKind.instance, row.authorityDid)],
            reason: surface,
          );
          expect(node.replies?.map((reply) => reply.comment.uri), [
            'at://did:plc:replier/social.coves.community.comment/c1',
            'at://did:plc:replier/social.coves.community.comment/c2',
          ], reason: surface);
          expect(node.hasMore, isTrue, reason: surface);
          expect(node.repliesCursor, 'c-replies-cursor', reason: surface);
        }
      });
    }
  });

  group('B4 a response requested before the removal cannot bring C back', () {
    for (final row in [
      (
        name: 'loadMoreReplies(R) subtree with C live',
        firstPage: liveThreads(),
        request: (CommentsProvider provider) =>
            provider.loadMoreReplies(rootUri),
        response: page([liveRoot()]),
      ),
      (
        name: 'next page holding unloaded root R whose replies include C live',
        firstPage: [liveSibling()],
        request: (CommentsProvider provider) => provider.loadMoreComments(),
        response: page([liveRoot()]),
      ),
      (
        name: 'refresh first page with C live',
        firstPage: liveThreads(),
        request: (CommentsProvider provider) =>
            provider.loadComments(refresh: true),
        response: page(liveThreads()),
      ),
    ]) {
      test('B4 ${row.name}', () async {
        final provider = buildProvider();
        await loadFirstPage(provider, row.firstPage, cursor: 'page-2');

        final (pending, call) = await start(() => row.request(provider));
        markRemoved(provider);
        call.response.complete(row.response);
        await pending;

        final target = targetIn(provider.comments);
        expect(target, isNotNull);
        expect(placeholderCopy(target!.comment), '[Removed by server admin]');
        expect(target.comment.isDeleted, isTrue);
        expect(target.comment.record, isNull);
      });
    }
  });

  group('B4 a response requested after the removal is taken as served', () {
    for (final row in [
      (
        name: 'refresh first page with C live',
        request: (CommentsProvider provider) =>
            provider.loadComments(refresh: true),
        response: page(liveThreads()),
        targetAfter: (CommentsProvider provider, Object? result) =>
            targetIn(provider.comments),
      ),
      (
        name: 'loadMoreReplies(R) subtree with C live',
        request: (CommentsProvider provider) =>
            provider.loadMoreReplies(rootUri),
        response: page([liveRoot()]),
        targetAfter: (CommentsProvider provider, Object? result) =>
            targetIn(provider.comments),
      ),
      (
        name: 'fetchCommentSnapshot(R) with C live',
        request: (CommentsProvider provider) =>
            provider.fetchCommentSnapshot(rootUri),
        response: page([liveRoot()]),
        targetAfter: (CommentsProvider provider, Object? result) =>
            (result as ThreadViewComment?)?.findByUri(targetUri),
      ),
    ]) {
      test('B4 ${row.name}', () async {
        final provider = buildProvider();
        await loadFirstPage(provider, liveThreads());
        markRemoved(provider);
        expect(targetIn(provider.comments)!.comment.isDeleted, isTrue);

        final (pending, call) = await start(() => row.request(provider));
        call.response.complete(row.response);
        final result = await pending;

        final target = row.targetAfter(provider, result);
        expect(target, isNotNull);
        expect(target!.comment.isDeleted, isFalse);
        expect(target.comment.record?.content, targetText);
      });
    }
  });

  /// The removal as the server serves it on C, told apart from the
  /// locally built one by its content label and source.
  const servedRemoval = ModerationView(
    state: ModerationState.removed,
    contentLabels: [ContentLabelView(value: 'served-label')],
    sources: [
      ModerationSource(
        authorityDid: 'did:web:served.coves.test',
        scope: ModerationScope(kind: ModerationScopeKind.instance),
      ),
    ],
  );

  /// C's subtree as the parentRkey 'c' read serves it while C is removed:
  /// the placeholder with [servedRemoval] and one reply the loaded tree
  /// does not hold.
  ThreadViewComment servedRemovedTarget({bool restoreToken = true}) {
    return ThreadViewComment(
      comment: serverRemovedTarget(
        restoreToken: restoreToken,
        moderation: servedRemoval,
      ),
      replies: [
        ThreadViewComment(
          comment: fixtureComment(
            uri: 'at://did:plc:replier/social.coves.community.comment/c9',
            authorDid: 'did:plc:replier',
            text: 'Reply C9',
            parentUri: targetUri,
          ),
        ),
      ],
    );
  }

  /// Calls readBackRemovedComment for C, answers every getComments read of
  /// C ('c') it sent with [answer] (a CommentsResponse, or an error to
  /// throw), and expects the call to complete normally.
  Future<void> readBackTarget(CommentsProvider provider, Object answer) async {
    final before = calls.length;
    final pending = provider.readBackRemovedComment(targetUri);
    await pumpEventQueue();
    for (final call
        in calls.skip(before).where((call) => call.parentRkey == 'c')) {
      if (answer is CommentsResponse) {
        call.response.complete(answer);
      } else {
        call.response.completeError(answer);
      }
    }
    await expectLater(pending, completes);
    await pumpEventQueue();
  }

  List<(ModerationScopeKind, String)>? sourcesOf(CommentView comment) => comment
      .moderation
      ?.sources
      .map((source) => (source.scope.kind, source.authorityDid))
      .toList();

  List<String>? contentLabelsOf(CommentView comment) =>
      comment.moderation?.contentLabels.map((label) => label.value).toList();

  group('R1 the read-back adopts the served restore-carrying placeholder', () {
    test('R1 the loaded tree shows C as served and keeps its replies and '
        'every other node', () async {
      final provider = buildProvider();
      await loadFirstPage(provider, liveThreads());
      markRemoved(provider);
      expect(provider.removalSequence, 1);
      final rootCommentBefore = provider.comments[0].comment;
      final siblingBefore = provider.comments[1];
      final targetBefore = targetIn(provider.comments)!;
      final reply1Before = targetBefore.replies![0];
      final reply2Before = targetBefore.replies![1];

      await readBackTarget(provider, page([servedRemovedTarget()]));

      final target = targetIn(provider.comments)!;
      expect(target.comment.viewer?.moderation, {ModerationCapability.restore});
      expect(target.comment.isDeleted, isTrue);
      expect(target.comment.moderation?.state, ModerationState.removed);
      expect(contentLabelsOf(target.comment), ['served-label']);
      expect(sourcesOf(target.comment), [
        (ModerationScopeKind.instance, 'did:web:served.coves.test'),
      ]);
      expect(target.replies, hasLength(2));
      expect(identical(target.replies![0], reply1Before), isTrue);
      expect(identical(target.replies![1], reply2Before), isTrue);
      expect(target.hasMore, isTrue);
      expect(target.repliesCursor, 'c-replies-cursor');
      expect(
        identical(provider.comments[0].comment, rootCommentBefore),
        isTrue,
      );
      expect(identical(provider.comments[1], siblingBefore), isTrue);
      expect(provider.removalSequence, 1);
    });

    test('R1 a snapshot taken before the read lands shows C as served once '
        'overlaid', () async {
      final provider = buildProvider();
      await loadFirstPage(provider, liveThreads());
      markRemoved(provider);
      final snapshot = provider.comments[0];
      expect(snapshot.findByUri(targetUri)!.comment.isDeleted, isTrue);

      await readBackTarget(provider, page([servedRemovedTarget()]));

      final target = provider
          .applyRemovalOverlay(snapshot)
          .findByUri(targetUri)!;
      expect(target.comment.viewer?.moderation, {ModerationCapability.restore});
      expect(sourcesOf(target.comment), [
        (ModerationScopeKind.instance, 'did:web:served.coves.test'),
      ]);
    });
  });

  group('R2 an answer the read-back cannot adopt leaves the local '
      'placeholder', () {
    for (final row in [
      (name: 'the read throws', answer: ApiException('Server unavailable')),
      (name: 'the answer has no entry for C', answer: page([])),
      (name: 'the answer serves C live', answer: page([liveTarget()])),
      (
        name: 'the answer serves C removed without restore',
        answer: page([servedRemovedTarget(restoreToken: false)]),
      ),
      (
        name: 'the answer serves another comment removed with restore',
        answer: page([
          ThreadViewComment(
            comment: CommentView(
              uri: 'at://did:plc:replier/social.coves.community.comment/d',
              cid: 'cid-d',
              isDeleted: true,
              deletionReason: 'moderator',
              createdAt: DateTime.utc(2025),
              indexedAt: DateTime.utc(2025),
              author: AuthorView(
                did: 'did:plc:replier',
                handle: 'handle.invalid',
              ),
              post: CommentRef(uri: removalPostUri, cid: removalPostCid),
              parent: CommentRef(uri: targetUri, cid: targetCid),
              stats: const CommentStats(),
              viewer: CommentViewerState(
                moderation: const {ModerationCapability.restore},
              ),
              moderation: servedRemoval,
            ),
          ),
        ]),
      ),
    ]) {
      test('R2 ${row.name}', () async {
        final provider = buildProvider();
        await loadFirstPage(provider, liveThreads());
        markRemoved(provider);
        final requestsBefore = calls.length;

        await readBackTarget(provider, row.answer);

        expect(
          provider.comments[0].replies?.first.comment.uri,
          targetUri,
          reason: "C's slot under R still holds C",
        );
        final target = targetIn(provider.comments)!;
        expect(target.comment.isDeleted, isTrue);
        expect(
          target.comment.viewer?.moderation ?? const <ModerationCapability>{},
          isEmpty,
        );
        expect(contentLabelsOf(target.comment), ['graphic-media']);
        expect(sourcesOf(target.comment), [
          (ModerationScopeKind.instance, 'did:web:coves.test'),
        ]);
        expect(
          calls
              .skip(requestsBefore)
              .map((call) => (call.parentRkey, call.cursor))
              .toList(),
          [('c', null)],
          reason: 'one read of C, never retried, no whole-thread request',
        );
      });
    }
  });

  test('R3 a replies page of R requested before the removal shows C as the '
      'served placeholder once the read-back applied', () async {
    final provider = buildProvider();
    await loadFirstPage(provider, liveThreads());
    final (pending, repliesCall) = await start(
      () => provider.loadMoreReplies(rootUri),
    );
    markRemoved(provider);
    await readBackTarget(provider, page([servedRemovedTarget()]));

    repliesCall.response.complete(page([liveRoot()]));
    await pending;

    final target = targetIn(provider.comments)!;
    expect(target.comment.viewer?.moderation, {ModerationCapability.restore});
    expect(target.comment.isDeleted, isTrue);
    expect(sourcesOf(target.comment), [
      (ModerationScopeKind.instance, 'did:web:served.coves.test'),
    ]);
  });

  group('R4 a read-back answer landing after C changed under it changes '
      'nothing', () {
    /// How [comment] shows: deletion, text, moderation and capabilities.
    Map<String, Object?> shownAs(CommentView comment) => {
      'deleted': comment.isDeleted,
      'text': comment.record?.content,
      'labels': contentLabelsOf(comment),
      'sources': sourcesOf(comment),
      'capabilities': comment.viewer?.moderation.toList(),
    };

    const localPlaceholder = {
      'deleted': true,
      'text': null,
      'labels': ['graphic-media'],
      'sources': [(ModerationScopeKind.instance, 'did:web:coves.test')],
      'capabilities': <ModerationCapability>[],
    };

    /// Loads [R(C(C1, C2)), S], removes C, takes the snapshot of R a screen
    /// would hold, and starts the read-back of C with its answer held. Runs
    /// [during] while the read is out and checks every surface [shown]
    /// lists against [expected]; then answers the read with the
    /// restore-carrying served placeholder, expects the read to complete
    /// normally, and checks the surfaces against [expected] again.
    Future<void> answerReadBackLate({
      required Future<void> Function(CommentsProvider provider) during,
      required Map<String, CommentView?> Function(
        CommentsProvider provider,
        ThreadViewComment snapshot,
      )
      shown,
      required Map<String, Map<String, Object?>> expected,
    }) async {
      final provider = buildProvider();
      await loadFirstPage(provider, liveThreads());
      markRemoved(provider);
      final snapshot = provider.comments[0];
      final (pending, readCall) = await start(
        () => provider.readBackRemovedComment(targetUri),
      );
      expect(readCall.parentRkey, 'c');
      var readLanded = false;
      unawaited(pending.then((_) => readLanded = true));

      await during(provider);
      await pumpEventQueue();

      Map<String, Map<String, Object?>?> surfaces() => {
        for (final MapEntry(:key, :value) in shown(provider, snapshot).entries)
          key: value == null ? null : shownAs(value),
      };
      expect(readLanded, isFalse, reason: 'the read is still out');
      expect(surfaces(), expected, reason: 'before the read lands');

      readCall.response.complete(page([servedRemovedTarget()]));
      await expectLater(pending, completes);
      await pumpEventQueue();

      expect(surfaces(), expected, reason: 'after the read landed');
    }

    Future<void> refreshWith(
      CommentsProvider provider,
      List<ThreadViewComment> threads,
    ) async {
      final (pending, call) = await start(
        () => provider.loadComments(refresh: true),
      );
      call.response.complete(page(threads));
      await pending;
    }

    /// C removed as a refresh serves it: no restore token, and a removal
    /// told apart from the local one by its content label and source.
    final removedWithoutRestore = [
      ThreadViewComment(
        comment: liveRoot().comment,
        replies: [
          ThreadViewComment(
            comment: serverRemovedTarget(
              restoreToken: false,
              moderation: const ModerationView(
                state: ModerationState.removed,
                contentLabels: [ContentLabelView(value: 'refresh-label')],
                sources: [
                  ModerationSource(
                    authorityDid: 'did:web:refresh.coves.test',
                    scope: ModerationScope(kind: ModerationScopeKind.instance),
                  ),
                ],
              ),
            ),
            replies: liveTarget().replies,
          ),
        ],
      ),
      liveSibling(),
    ];

    CommentView? inTree(CommentsProvider provider) =>
        targetIn(provider.comments)?.comment;

    for (final row in [
      (
        name: '(a) the removal was cleared while the read was out',
        during: (CommentsProvider provider) async =>
            provider.clearCommentRemoval(targetUri),
        shown: (CommentsProvider provider, ThreadViewComment snapshot) => {
          'tree': inTree(provider),
          'overlaid pre-read snapshot': provider
              .applyRemovalOverlay(snapshot)
              .findByUri(targetUri)
              ?.comment,
        },
        expected: {
          'tree': localPlaceholder,
          'overlaid pre-read snapshot': localPlaceholder,
        },
      ),
      (
        name: '(b) C was removed again while the read was out',
        during: (CommentsProvider provider) async =>
            markRemoved(provider, removeContentJson(withLocalRemoval: false)),
        // The tree keeps the first placeholder; a live snapshot gets the
        // newer removal's local placeholder.
        shown: (CommentsProvider provider, ThreadViewComment snapshot) => {
          'tree': inTree(provider),
          'overlaid live snapshot': provider
              .applyRemovalOverlay(liveRoot())
              .findByUri(targetUri)
              ?.comment,
        },
        expected: {
          'tree': localPlaceholder,
          'overlaid live snapshot': {
            'deleted': true,
            'text': null,
            'labels': ['graphic-media'],
            'sources': [
              (ModerationScopeKind.instance, 'did:plc:actionauthority'),
            ],
            'capabilities': <ModerationCapability>[],
          },
        },
      ),
      (
        name:
            '(c) a refresh requested after the removal landed with C live '
            'while the read was out',
        during: (CommentsProvider provider) =>
            refreshWith(provider, liveThreads()),
        shown: (CommentsProvider provider, ThreadViewComment snapshot) => {
          'tree': inTree(provider),
        },
        expected: {
          'tree': {
            'deleted': false,
            'text': 'Comment C to remove',
            'labels': null,
            'sources': null,
            'capabilities': [ModerationCapability.remove],
          },
        },
      ),
      (
        name:
            '(e) a refresh requested after the removal landed with C '
            'removed without restore while the read was out',
        during: (CommentsProvider provider) =>
            refreshWith(provider, removedWithoutRestore),
        shown: (CommentsProvider provider, ThreadViewComment snapshot) => {
          'tree': inTree(provider),
        },
        expected: {
          'tree': {
            'deleted': true,
            'text': null,
            'labels': ['refresh-label'],
            'sources': [
              (ModerationScopeKind.instance, 'did:web:refresh.coves.test'),
            ],
            'capabilities': <ModerationCapability>[],
          },
        },
      ),
    ]) {
      test('R4 ${row.name}', () async {
        await answerReadBackLate(
          during: row.during,
          shown: row.shown,
          expected: row.expected,
        );
      });
    }

    test('R4 (d) the provider was disposed while the read was out', () async {
      var notifiedAfterDispose = 0;
      await answerReadBackLate(
        during: (provider) async {
          provider
            ..addListener(() => notifiedAfterDispose++)
            ..dispose();
          providers.remove(provider);
        },
        shown: (provider, snapshot) => {'tree': inTree(provider)},
        expected: {'tree': localPlaceholder},
      );
      expect(notifiedAfterDispose, 0);
    });
  });

  test(
    'B9 session stamp is the key read when the first page was requested',
    () async {
      final observed = <String, Object?>{};

      // The key changes while the first page is in flight.
      var key = 'session-A';
      var provider = buildProvider(sessionKeyOf: () => key);
      var (pending, call) = await start(
        () => provider.loadComments(refresh: true),
      );
      key = 'session-B';
      call.response.complete(page(liveThreads()));
      await pending;
      observed['key changed while the first page was in flight'] =
          provider.sessionStamp;

      // A refresh requested under a new key fails.
      key = 'session-A';
      provider = buildProvider(sessionKeyOf: () => key);
      await loadFirstPage(provider, liveThreads());
      key = 'session-B';
      (pending, call) = await start(() => provider.loadComments(refresh: true));
      call.response.completeError(NetworkException('offline'));
      await pending;
      observed['refresh under a new key failed'] = provider.sessionStamp;

      // A refresh requested under a new key succeeds.
      key = 'session-A';
      provider = buildProvider(sessionKeyOf: () => key);
      await loadFirstPage(provider, liveThreads());
      key = 'session-B';
      (pending, call) = await start(() => provider.loadComments(refresh: true));
      call.response.complete(page(liveThreads()));
      await pending;
      observed['refresh under a new key succeeded'] = provider.sessionStamp;

      // No sessionKeyOf.
      provider = buildProvider();
      await loadFirstPage(provider, liveThreads());
      observed['no sessionKeyOf'] = provider.sessionStamp;

      expect(observed, {
        'key changed while the first page was in flight': 'session-A',
        'refresh under a new key failed': 'session-A',
        'refresh under a new key succeeded': 'session-B',
        'no sessionKeyOf': null,
      });
    },
  );
}
