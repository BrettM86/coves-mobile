import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/moderation.dart';
import 'package:coves_flutter/models/moderation_action.dart';
import 'package:coves_flutter/models/moderation_subject_state.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/post_get_result.dart';
import 'package:coves_flutter/providers/viewer_authority_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/home/post_detail_loader.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/comments_provider_cache.dart';
import 'package:coves_flutter/widgets/moderation/moderation_action_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/fake_providers.dart';
import '../../test_helpers/pump_helpers.dart';
import '../../test_helpers/test_mocks.dart';

const _postUri = 'at://did:plc:author/social.coves.community.post/p1';

const _removedModeration = ModerationView(
  state: ModerationState.removed,
  sources: [
    ModerationSource(
      authorityDid: 'did:web:coves.social',
      scope: ModerationScope(kind: ModerationScopeKind.instance),
    ),
  ],
);

const _tombstone = PostGetModerated(
  uri: _postUri,
  moderation: _removedModeration,
  viewerModeration: {ModerationCapability.restore},
);

/// The same tombstone for a viewer the server grants no restore.
const _tombstoneWithoutRestore = PostGetModerated(
  uri: _postUri,
  moderation: _removedModeration,
);

PostGetSuccess _restoredPost() => PostGetSuccess(
  PostView(
    uri: _postUri,
    cid: 'bafy-c2',
    rkey: 'p1',
    author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
    community: CommunityRef(did: 'did:plc:community', name: 'gaming'),
    createdAt: DateTime.parse('2026-01-01T12:00:00Z'),
    indexedAt: DateTime.parse('2026-01-01T12:00:00Z'),
    record: const PostRecord(content: 'Thread body', title: 'Weekly thread'),
    stats: PostStats(score: 3, upvotes: 3, downvotes: 0, commentCount: 0),
  ),
);

const _removedState = ModerationSubjectState(
  subject: _postUri,
  version: 'v7',
  moderation: ModerationView(state: ModerationState.removed),
  recordState: ModerationRecordState.present,
  currentSubject: StrongRef(uri: _postUri, cid: 'bafy-c2'),
  localRemoval: ModerationActionRef(
    serviceDid: 'did:web:coves.social',
    actionId: 'R1',
  ),
);

/// A subject the instance no longer removes: there is nothing to restore.
const _notRemovedState = ModerationSubjectState(
  subject: _postUri,
  version: 'v7',
  moderation: ModerationView(state: ModerationState.clear),
  recordState: ModerationRecordState.present,
  currentSubject: StrongRef(uri: _postUri, cid: 'bafy-c2'),
);

/// An applied restore whose resulting state is [moderation] and [record].
ModerationMutationResult _restoreAnswer({
  ModerationState moderation = ModerationState.clear,
  ModerationRecordState record = ModerationRecordState.present,
}) => ModerationMutationResult(
  outcome: ModerationMutationOutcome.applied,
  state: ModerationSubjectState(
    subject: _postUri,
    version: 'v8',
    moderation: ModerationView(state: moderation),
    recordState: record,
    currentSubject: record == ModerationRecordState.present
        ? const StrongRef(uri: _postUri, cid: 'bafy-c2')
        : null,
  ),
);

final _restoredAnswer = _restoreAnswer();

final Finder _sheet = find.byWidgetPredicate(
  (widget) => widget is ModerationActionSheet,
);

/// The sheet's confirm button, found by type because its label becomes a
/// spinner while the request is in flight. (The sheet's close IconButton is
/// also a ButtonStyleButton under Material 3, so the filled subtype is used.)
final Finder _confirmButton = find.descendant(
  of: _sheet,
  matching: find.bySubtype<FilledButton>(),
);

/// What the loader's post.get requests answer.
class _PostServer {
  _PostServer(this.post);

  /// What every request answers unless [answerOnce] is set.
  PostGetResult post;

  /// Answers only the next request (a held completer or a failure).
  Future<PostGetResult> Function()? answerOnce;

  Future<PostGetResult> fetch(String uri) {
    final once = answerOnce;
    if (once != null) {
      answerOnce = null;
      return once();
    }
    return Future.value(post);
  }
}

/// A signed-in admin's API: live authority, the removed state with local
/// removal R1, no comments, and restoreContent answering [restore].
MockCovesApiService _adminApi({
  Future<ModerationMutationResult> Function()? restore,
}) {
  final api = MockCovesApiService();
  when(api.getViewerAuthority()).thenAnswer((_) async => true);
  when(api.getModerationSubjectState(any))
      .thenAnswer((_) async => _removedState);
  _answerRestore(api, restore ?? () async => _restoredAnswer);
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
  ).thenAnswer((_) async => CommentsResponse(post: null, comments: const []));
  return api;
}

void _answerRestore(
  MockCovesApiService api,
  Future<ModerationMutationResult> Function() answer,
) {
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

/// The app wiring a signed-in admin's post detail loader reads.
class _Loader {
  _Loader(this.auth, this.api, this.authority, this.server);

  final FakeAuthProvider auth;
  final MockCovesApiService api;
  final ViewerAuthorityProvider authority;
  final _PostServer server;
}

/// Pumps a [PostDetailLoader] for a signed-in admin whose post.get answers
/// come from [server], and lets the first request finish unless it is held.
Future<_Loader> _pumpLoader(
  WidgetTester tester, {
  required MockCovesApiService api,
  required _PostServer server,
}) async {
  final auth = FakeAuthProvider(signedInDid: 'did:plc:admin');
  addTearDown(auth.dispose);
  final authority = ViewerAuthorityProvider(
    apiService: api,
    authProvider: auth,
  );
  addTearDown(authority.dispose);
  final commentService = MockCommentService();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ...profileScreenProviders(
          auth: auth,
          apiService: api,
          commentService: commentService,
          viewerAuthority: authority,
        ),
        Provider<CommentsProviderCache>(
          create: (context) => CommentsProviderCache(
            authProvider: auth,
            voteProvider: context.read<VoteProvider>(),
            commentService: commentService,
            apiService: api,
          ),
          dispose: (_, cache) => cache.dispose(),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: PostDetailLoader(postUri: _postUri, fetchPost: server.fetch),
      ),
    ),
  );
  await pumpFrames(tester);
  return _Loader(auth, api, authority, server);
}

/// Opens the restore sheet from the tombstone and picks [reason].
Future<void> _openRestoreSheet(
  WidgetTester tester, {
  String reason = 'Rule violation',
}) async {
  expect(find.text('Restore post'), findsOneWidget);
  await tester.tap(find.text('Restore post'));
  await pumpFrames(tester);
  expect(_sheet, findsOneWidget);
  await tester.tap(find.descendant(of: _sheet, matching: find.text(reason)));
  await pumpFrames(tester);
}

/// Opens the sheet, picks a reason, presses Restore and lets the answer and
/// any reload finish.
Future<void> _restore(WidgetTester tester) async {
  await _openRestoreSheet(tester);
  await tester.tap(_confirmButton);
  await pumpFrames(tester);
  await pumpFrames(tester);
}

/// Unmounts the tree and runs out the snackbar timer.
Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 5));
}

void main() {
  testWidgets('B7 an admin restores a removed post from its tombstone '
      'and sees the post', (tester) async {
    final restoreAnswer = Completer<ModerationMutationResult>();
    final server = _PostServer(_tombstone);
    await _pumpLoader(
      tester,
      api: _adminApi(restore: () => restoreAnswer.future),
      server: server,
    );

    expect(find.text('View moderation log'), findsOneWidget);
    expect(find.text('Restore post'), findsOneWidget);

    await tester.tap(find.text('Restore post'));
    await pumpFrames(tester);

    expect(_sheet, findsOneWidget);
    expect(
      find.descendant(of: _sheet, matching: find.text('Restore post')),
      findsOneWidget,
    );
    for (final reason in [
      'Spam',
      'Harassment',
      'Rule violation',
      'Moderator discretion',
    ]) {
      expect(
        find.descendant(of: _sheet, matching: find.text(reason)),
        findsOneWidget,
        reason: '$reason is a restore reason',
      );
    }
    expect(find.text('Doxing'), findsNothing);
    expect(find.text('Illegal content'), findsNothing);
    expect(
      find.descendant(of: _confirmButton, matching: find.text('Restore')),
      findsOneWidget,
    );
    expect(tester.widget<ButtonStyleButton>(_confirmButton).onPressed, isNull);

    await tester.tap(find.text('Rule violation'));
    await pumpFrames(tester);
    expect(
      tester.widget<ButtonStyleButton>(_confirmButton).onPressed,
      isNotNull,
    );

    await tester.tap(_confirmButton);
    await tester.pump();
    await tester.pump();

    expect(find.text('Post Removed'), findsWidgets);
    expect(tester.widget<ButtonStyleButton>(_confirmButton).onPressed, isNull);

    server.post = _restoredPost();
    restoreAnswer.complete(_restoredAnswer);
    await pumpFrames(tester);
    await pumpFrames(tester);

    expect(_sheet, findsNothing);
    expect(find.text('Post Removed'), findsNothing);
    expect(find.text('Weekly thread'), findsOneWidget);
    expect(find.text('Post restored'), findsOneWidget);

    await _finish(tester);
  });

  testWidgets('a restore answered with a present record that still reads '
      'removed says Post restored and shows the reloaded post', (tester) async {
    final server = _PostServer(_tombstone);
    await _pumpLoader(
      tester,
      api: _adminApi(
        restore: () async =>
            _restoreAnswer(moderation: ModerationState.removed),
      ),
      server: server,
    );

    expect(find.text('Restore post'), findsOneWidget);
    server.post = _restoredPost();
    await _restore(tester);

    expect(_sheet, findsNothing);
    expect(find.text('Post Removed'), findsNothing);
    expect(find.text('Weekly thread'), findsOneWidget);
    expect(find.text('Post restored'), findsOneWidget);
    await _finish(tester);
  });

  group('B5 Restore post on a loaded tombstone', () {
    // A row with a change first shows Restore post, so the change is what
    // hides it.
    for (final (
          name,
          PostGetModerated tombstone,
          void Function(_Loader loader)? change,
          bool shows,
        )
        in [
          (
            'a restore token, live authority and the same session show it',
            _tombstone,
            null,
            true,
          ),
          ('no restore token hides it', _tombstoneWithoutRestore, null, false),
          (
            'revoked authority hides it',
            _tombstone,
            (_Loader loader) => loader.authority.markRevoked(),
            false,
          ),
          (
            'a new session after the tombstone loaded hides it',
            _tombstone,
            (_Loader loader) {
              loader.auth.setSignedInDid(null);
              loader.auth.setSignedInDid('did:plc:admin');
            },
            false,
          ),
        ]) {
      testWidgets(name, (tester) async {
        final loader = await _pumpLoader(
          tester,
          api: _adminApi(),
          server: _PostServer(tombstone),
        );
        expect(find.text('View moderation log'), findsOneWidget);

        if (change != null) {
          expect(find.text('Restore post'), findsOneWidget);
          change(loader);
          await pumpFrames(tester);
          expect(find.text('Post Removed'), findsWidgets);
        }

        expect(
          find.text('Restore post'),
          shows ? findsOneWidget : findsNothing,
        );
        await _finish(tester);
      });
    }

    testWidgets('a tombstone requested under session A and answered under '
        'session B hides it', (tester) async {
      final held = Completer<PostGetResult>();
      final server = _PostServer(_tombstone)..answerOnce = () => held.future;
      final loader = await _pumpLoader(
        tester,
        api: _adminApi(),
        server: server,
      );

      loader.auth.setSignedInDid('did:plc:admin-b');
      await pumpFrames(tester);
      held.complete(_tombstone);
      await pumpFrames(tester);

      expect(find.text('View moderation log'), findsOneWidget);
      expect(find.text('Restore post'), findsNothing);
      await _finish(tester);
    });

    testWidgets('Retry after the session changed requests under the new '
        'session and shows it', (tester) async {
      final server = _PostServer(_tombstone)
        ..answerOnce = () async => throw NetworkException('Offline');
      final loader = await _pumpLoader(
        tester,
        api: _adminApi(),
        server: server,
      );
      expect(find.text('Failed to load post'), findsOneWidget);

      loader.auth.setSignedInDid('did:plc:admin-b');
      await pumpFrames(tester);
      await tester.tap(find.text('Retry'));
      await pumpFrames(tester);

      expect(find.text('View moderation log'), findsOneWidget);
      expect(find.text('Restore post'), findsOneWidget);
      await _finish(tester);
    });
  });

  group('B8 a restore the reload still hides', () {
    for (final (name, ModerationMutationResult answer, String message) in [
      (
        'the author deleted it',
        _restoreAnswer(record: ModerationRecordState.deleted),
        'Restored, but the author deleted it, so it stays hidden.',
      ),
      (
        'the record is unavailable',
        _restoreAnswer(record: ModerationRecordState.unavailable),
        "Restored, but it can't be shown right now.",
      ),
    ]) {
      testWidgets('$name keeps the tombstone and says so', (tester) async {
        await _pumpLoader(
          tester,
          api: _adminApi(restore: () async => answer),
          server: _PostServer(_tombstone),
        );

        await _restore(tester);

        expect(_sheet, findsNothing);
        expect(find.text('Post Removed'), findsWidgets);
        expect(find.text(message), findsOneWidget);
        await _finish(tester);
      });
    }

    testWidgets('a post no longer removed says so and reloads', (tester) async {
      final api = _adminApi();
      when(api.getModerationSubjectState(any))
          .thenAnswer((_) async => _notRemovedState);
      final server = _PostServer(_tombstone);
      await _pumpLoader(tester, api: api, server: server);

      expect(find.text('Restore post'), findsOneWidget);
      server.post = _tombstoneWithoutRestore;
      await _restore(tester);

      expect(_sheet, findsNothing);
      expect(find.text('This is no longer removed.'), findsOneWidget);
      expect(find.text('View moderation log'), findsOneWidget);
      expect(find.text('Restore post'), findsNothing);
      await _finish(tester);
    });
  });

  group('B9 a restore the server rejects as stale reloads the post', () {
    for (final (code, int status, message) in [
      (
        'DecisionNotFound',
        404,
        'This item changed. Showing the latest version.',
      ),
      (
        'InvalidDecision',
        400,
        'This item changed. Showing the latest version.',
      ),
      ('StateConflict', 400, 'This item changed. Showing the latest version.'),
      (
        'ContentChanged',
        400,
        'The author edited this post. Try restoring again.',
      ),
    ]) {
      testWidgets(code, (tester) async {
        final server = _PostServer(_tombstone);
        await _pumpLoader(
          tester,
          api: _adminApi(
            restore: () async =>
                throw ApiException(code, statusCode: status, errorCode: code),
          ),
          server: server,
        );

        expect(find.text('Restore post'), findsOneWidget);
        server.post = _restoredPost();
        await _restore(tester);

        expect(_sheet, findsNothing);
        expect(find.text('Post Removed'), findsNothing);
        expect(find.text('Weekly thread'), findsOneWidget);
        expect(find.text(message), findsOneWidget);
        await _finish(tester);
      });
    }
  });

  group('B10 restore recovery', () {
    testWidgets('Forbidden closes the sheet, revokes authority and hides '
        'Restore post', (tester) async {
      final loader = await _pumpLoader(
        tester,
        api: _adminApi(
          restore: () async => throw ApiException(
            'Forbidden',
            statusCode: 403,
            errorCode: 'Forbidden',
          ),
        ),
        server: _PostServer(_tombstone),
      );

      await _restore(tester);

      expect(_sheet, findsNothing);
      expect(loader.authority.status, ViewerAuthorityStatus.revoked);
      expect(find.text('Post Removed'), findsWidgets);
      expect(find.text('Restore post'), findsNothing);
      await _finish(tester);
    });

    testWidgets('an unavailable answer locks the sheet and Try again '
        'replays the restore without a fresh state read', (tester) async {
      final server = _PostServer(_tombstone);
      final loader = await _pumpLoader(
        tester,
        api: _adminApi(
          restore: () async => throw ApiException(
            'Down',
            statusCode: 503,
            errorCode: 'ModerationUnavailable',
          ),
        ),
        server: server,
      );

      await _restore(tester);

      expect(_sheet, findsOneWidget);
      expect(
        find.descendant(of: _confirmButton, matching: find.text('Try again')),
        findsOneWidget,
      );
      final reasons = tester.widgetList<RadioListTile<ModerationReason>>(
        find.descendant(
          of: _sheet,
          matching: find.byType(RadioListTile<ModerationReason>),
        ),
      );
      expect(reasons, hasLength(4));
      for (final reason in reasons) {
        expect(reason.enabled, isFalse);
      }
      expect(
        tester
            .widget<TextField>(
              find.descendant(of: _sheet, matching: find.byType(TextField)),
            )
            .enabled,
        isFalse,
      );

      when(loader.api.getModerationSubjectState(any))
          .thenAnswer((_) async => throw NetworkException('Offline'));
      _answerRestore(loader.api, () async => _restoredAnswer);
      server.post = _restoredPost();
      await tester.tap(_confirmButton);
      await pumpFrames(tester);
      await pumpFrames(tester);

      expect(_sheet, findsNothing);
      expect(find.text('Post Removed'), findsNothing);
      expect(find.text('Weekly thread'), findsOneWidget);
      expect(find.text('Post restored'), findsOneWidget);
      await _finish(tester);
    });
  });
}
