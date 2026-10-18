// Mark NSFW and Remove NSFW label from a post card's menu: which admin items
// the menu offers, the NSFW sheets, and how the card's blur and menu follow
// the server's answers.
import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/moderation.dart';
import 'package:coves_flutter/models/moderation_action.dart';
import 'package:coves_flutter/models/moderation_subject_state.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/post_get_result.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/community_subscription_provider.dart';
import 'package:coves_flutter/providers/viewer_authority_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/post_change_broadcast.dart';
import 'package:coves_flutter/services/streamable_service.dart';
import 'package:coves_flutter/widgets/post_card.dart';
import 'package:coves_flutter/widgets/sensitive_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/pump_helpers.dart';
import '../test_helpers/test_mocks.dart';

const _postUri = 'at://did:plc:author/social.coves.community.post/p1';
const _postBody = 'Body of the post under review';

const _markNsfw = 'Mark NSFW';
const _removeNsfwLabel = 'Remove NSFW label';
const _removePost = 'Remove post';

const _clearModeration = ModerationView(state: ModerationState.clear);
const _nsfwModeration = ModerationView(
  state: ModerationState.clear,
  contentLabels: [ContentLabelView(value: 'nsfw')],
);

const _nsfwLocalLabel = LocalLabel(
  value: 'nsfw',
  action: ModerationActionRef(
    serviceDid: 'did:web:s1.coves.social',
    actionId: 'A1',
  ),
);

PostView _postView({
  Set<ModerationCapability> capabilities = const {},
  ModerationView? moderation,
  bool authorSelfLabel = false,
  String cid = 'cid-p1',
  String title = 'Post under review',
}) => PostView(
  uri: _postUri,
  cid: cid,
  rkey: 'p1',
  author: AuthorView(did: 'did:plc:author', handle: 'author.coves.test'),
  community: CommunityRef(did: 'did:plc:community', name: 'testcove'),
  createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
  indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
  record: PostRecord(
    title: title,
    content: _postBody,
    labels: authorSelfLabel ? const ['nsfw'] : const [],
  ),
  stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
  viewer: ViewerState(moderation: capabilities),
  moderation: moderation,
);

ModerationSubjectState _subjectState({
  String version = 'v7',
  ModerationView moderation = _clearModeration,
  List<LocalLabel> localLabels = const [],
  String currentCid = 'cid-p1',
}) => ModerationSubjectState(
  subject: _postUri,
  version: version,
  moderation: moderation,
  recordState: ModerationRecordState.present,
  currentSubject: StrongRef(uri: _postUri, cid: currentCid),
  localLabels: localLabels,
);

ModerationMutationResult _applied(ModerationView moderation) =>
    ModerationMutationResult(
      outcome: ModerationMutationOutcome.applied,
      state: _subjectState(version: 'v8', moderation: moderation),
    );

typedef _GateRow = ({
  String name,
  Set<ModerationCapability> capabilities,
  bool revoked,
  bool staleStamp,
  bool markNsfwShown,
  bool removeNsfwLabelShown,
});

/// A captured StrongRef as a record, so a mismatch prints its uri and cid.
Object? _readableStrongRef(Object? ref) =>
    ref is StrongRef ? (uri: ref.uri, cid: ref.cid) : ref;

Finder _confirmButton(String label) => find.ancestor(
  of: find.text(label),
  matching: find.bySubtype<ButtonStyleButton>(),
);

Finder get _concealedBanner => find.byWidgetPredicate(
  (widget) => widget is SensitiveContentBanner && widget.concealed,
);

void _expectConcealed({String? reason}) {
  expect(_concealedBanner, findsOneWidget, reason: reason);
  expect(find.text(_postBody), findsNothing, reason: reason);
}

void _expectUnconcealed({String? reason}) {
  expect(find.byType(SensitiveContentBanner), findsNothing, reason: reason);
  expect(find.text(_postBody), findsOneWidget, reason: reason);
}

/// A surface showing one post card, as a feed does: it applies a published
/// replacement of its post in place, drops the card when the post is
/// published as removed, and keeps its own session stamp.
///
/// With [stampFollowsSession] the surface re-stamps its card with the
/// current session key, as a surface reloaded under a new session would, so
/// any post it is handed after a session change would show that post's
/// admin items.
class _PostSurface extends StatefulWidget {
  const _PostSurface({
    required this.initialPost,
    required this.broadcast,
    required this.sessionStamp,
    this.stampFollowsSession = false,
    super.key,
  });

  final PostView initialPost;
  final PostChangeBroadcast broadcast;
  final Object? sessionStamp;
  final bool stampFollowsSession;

  @override
  State<_PostSurface> createState() => _PostSurfaceState();
}

class _PostSurfaceState extends State<_PostSurface> {
  late FeedViewPost _post = FeedViewPost(post: widget.initialPost);
  bool _removed = false;

  @override
  void initState() {
    super.initState();
    widget.broadcast.addPostChangeListener(_onPostChanged);
  }

  @override
  void dispose() {
    widget.broadcast.removePostChangeListener(_onPostChanged);
    super.dispose();
  }

  void _onPostChanged(PostChange change) {
    if (change is PostReplaced && change.post.uri == _post.post.uri) {
      setState(() => _post = _post.copyWith(post: change.post));
    } else if (change is PostRemoved && change.uri == _post.post.uri) {
      setState(() => _removed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_removed) {
      return const SizedBox.shrink();
    }
    final stamp = widget.stampFollowsSession
        ? context.watch<ViewerAuthorityProvider>().sessionKey
        : widget.sessionStamp;
    return PostCard(post: _post, sessionStamp: stamp);
  }
}

void main() {
  late FakeAuthProvider auth;
  late MockCovesApiService api;
  late ViewerAuthorityProvider authority;
  late PostChangeBroadcast broadcast;

  setUp(() {
    provideDummy<PostGetResult>(const PostGetNotFound(_postUri));
    auth = FakeAuthProvider(
      signedInDid: 'did:plc:admin',
      signedInHandle: 'admin.coves.test',
    );
    api = MockCovesApiService();
    broadcast = PostChangeBroadcast();
    when(api.getViewerAuthority()).thenAnswer((_) async => true);
  });

  tearDown(() => auth.dispose());

  Future<void> pumpCard(
    WidgetTester tester,
    PostView post, {
    bool staleStamp = false,
    bool stampFollowsSession = false,
    Key? key,
  }) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final cardAuthority = ViewerAuthorityProvider(
      apiService: api,
      authProvider: auth,
    );
    authority = cardAuthority;
    addTearDown(cardAuthority.dispose);
    // The card was loaded under the session open when it is pumped, unless
    // the row needs a stamp from some other session.
    final sessionStamp = staleStamp
        ? 'stamp-from-an-earlier-session'
        : cardAuthority.sessionKey;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<CovesApiService>.value(value: api),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<ViewerAuthorityProvider>.value(
            value: cardAuthority,
          ),
          ChangeNotifierProvider<VoteProvider>(
            create: (_) => FakeVoteProvider(auth),
          ),
          ChangeNotifierProvider<CommunitySubscriptionProvider>(
            create: (_) =>
                FakeSubscriptionProvider(authProvider: auth, apiService: api),
          ),
          ChangeNotifierProvider<BlockProvider>(
            create: (_) => BlockProvider(apiService: api, authProvider: auth),
          ),
          Provider<StreamableService>.value(value: StreamableService()),
          Provider<PostChangeBroadcast>.value(value: broadcast),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: _PostSurface(
              key: key,
              initialPost: post,
              broadcast: broadcast,
              sessionStamp: sessionStamp,
              stampFollowsSession: stampFollowsSession,
            ),
          ),
        ),
      ),
    );
    await pumpFrames(tester);
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Post options'));
    await pumpFrames(tester);
    // The menu really is open, so a missing admin item is not a closed menu.
    expect(find.text('Subscribe to !testcove'), findsOneWidget);
  }

  Future<void> closeMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Post options'));
    await pumpFrames(tester);
  }

  void expectNoAdminItems() {
    expect(find.text(_markNsfw), findsNothing);
    expect(find.text(_removeNsfwLabel), findsNothing);
    expect(find.text(_removePost), findsNothing);
  }

  Future<void> openSheet(WidgetTester tester, String item) async {
    await openMenu(tester);
    expect(find.text(item), findsOneWidget);
    await tester.tap(find.text(item));
    await pumpFrames(tester);
    expect(find.byType(BottomSheet), findsOneWidget);
  }

  /// Opens [item]'s sheet and confirms it with the preselected "No reason".
  Future<void> confirmWithoutReason(WidgetTester tester, String item) async {
    await openSheet(tester, item);
    await tester.tap(_confirmButton(item));
    await pumpFrames(tester);
  }

  void stubLabel(ModerationMutationResult result) {
    when(
      api.labelContent(
        subject: anyNamed('subject'),
        expectedVersion: anyNamed('expectedVersion'),
        idempotencyKey: anyNamed('idempotencyKey'),
        reason: anyNamed('reason'),
        privateNote: anyNamed('privateNote'),
      ),
    ).thenAnswer((_) async => result);
  }

  void stubRetract(ModerationMutationResult result) {
    when(
      api.retractContentLabel(
        actionId: anyNamed('actionId'),
        expectedVersion: anyNamed('expectedVersion'),
        idempotencyKey: anyNamed('idempotencyKey'),
        reason: anyNamed('reason'),
        reviewedSubject: anyNamed('reviewedSubject'),
        privateNote: anyNamed('privateNote'),
      ),
    ).thenAnswer((_) async => result);
  }

  // ---------------------------------------------------------------------------
  // B4 menu gating
  // ---------------------------------------------------------------------------

  Future<void> expectGateRows(WidgetTester tester, List<_GateRow> rows) async {
    for (final row in rows) {
      await pumpCard(
        tester,
        _postView(capabilities: row.capabilities),
        staleStamp: row.staleStamp,
        key: ValueKey(row.name),
      );
      if (row.revoked) {
        authority.markRevoked();
        await pumpFrames(tester);
      }
      await openMenu(tester);
      expect(
        find.text(_markNsfw),
        row.markNsfwShown ? findsOneWidget : findsNothing,
        reason: row.name,
      );
      expect(
        find.text(_removeNsfwLabel),
        row.removeNsfwLabelShown ? findsOneWidget : findsNothing,
        reason: row.name,
      );
    }
  }

  testWidgets('B4 Mark NSFW follows the label token and the admin gate', (
    tester,
  ) async {
    await expectGateRows(tester, [
      (
        name: 'label',
        capabilities: {ModerationCapability.label},
        revoked: false,
        staleStamp: false,
        markNsfwShown: true,
        removeNsfwLabelShown: false,
      ),
      (
        name: 'remove and label',
        capabilities: {ModerationCapability.remove, ModerationCapability.label},
        revoked: false,
        staleStamp: false,
        markNsfwShown: true,
        removeNsfwLabelShown: false,
      ),
      (
        name: 'label with authority revoked',
        capabilities: {ModerationCapability.label},
        revoked: true,
        staleStamp: false,
        markNsfwShown: false,
        removeNsfwLabelShown: false,
      ),
      (
        name: 'label with a stale session stamp',
        capabilities: {ModerationCapability.label},
        revoked: false,
        staleStamp: true,
        markNsfwShown: false,
        removeNsfwLabelShown: false,
      ),
    ]);
  });

  testWidgets(
    'B4 Remove NSFW label follows the retract-label token and the admin gate',
    (tester) async {
      await expectGateRows(tester, [
        (
          name: 'retract-label',
          capabilities: {ModerationCapability.retractLabel},
          revoked: false,
          staleStamp: false,
          markNsfwShown: false,
          removeNsfwLabelShown: true,
        ),
        (
          name: 'remove only',
          capabilities: {ModerationCapability.remove},
          revoked: false,
          staleStamp: false,
          markNsfwShown: false,
          removeNsfwLabelShown: false,
        ),
        (
          name: 'retract-label with authority revoked',
          capabilities: {ModerationCapability.retractLabel},
          revoked: true,
          staleStamp: false,
          markNsfwShown: false,
          removeNsfwLabelShown: false,
        ),
        (
          name: 'retract-label with a stale session stamp',
          capabilities: {ModerationCapability.retractLabel},
          revoked: false,
          staleStamp: true,
          markNsfwShown: false,
          removeNsfwLabelShown: false,
        ),
      ]);
    },
  );

  // ---------------------------------------------------------------------------
  // B5 NSFW sheets
  // ---------------------------------------------------------------------------

  for (final row in [
    (
      item: _markNsfw,
      post: _postView(capabilities: {ModerationCapability.label}),
      state: _subjectState(),
      stubMutation: () => stubLabel(_applied(_nsfwModeration)),
      sentReasons: () => verify(
        api.labelContent(
          subject: anyNamed('subject'),
          expectedVersion: anyNamed('expectedVersion'),
          idempotencyKey: anyNamed('idempotencyKey'),
          reason: captureAnyNamed('reason'),
          privateNote: anyNamed('privateNote'),
        ),
      ).captured,
    ),
    (
      item: _removeNsfwLabel,
      post: _postView(
        capabilities: {ModerationCapability.retractLabel},
        moderation: _nsfwModeration,
      ),
      state: _subjectState(
        moderation: _nsfwModeration,
        localLabels: [_nsfwLocalLabel],
      ),
      stubMutation: () => stubRetract(_applied(_clearModeration)),
      sentReasons: () => verify(
        api.retractContentLabel(
          actionId: anyNamed('actionId'),
          expectedVersion: anyNamed('expectedVersion'),
          idempotencyKey: anyNamed('idempotencyKey'),
          reason: captureAnyNamed('reason'),
          reviewedSubject: anyNamed('reviewedSubject'),
          privateNote: anyNamed('privateNote'),
        ),
      ).captured,
    ),
  ]) {
    testWidgets('B5 the ${row.item} sheet offers an optional reason and sends '
        'no reason when No reason is chosen', (tester) async {
      when(api.getModerationSubjectState(_postUri))
          .thenAnswer((_) async => row.state);
      row.stubMutation();
      when(api.getPost(_postUri)).thenAnswer(
        (_) => Future.error(
          ApiException('Down', statusCode: 503, errorCode: 'Unavailable'),
        ),
      );
      final semantics = tester.ensureSemantics();
      try {
        await pumpCard(tester, row.post);
        await openSheet(tester, row.item);

        // Titled and confirmed with the same words.
        expect(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text(row.item),
          ),
          findsNWidgets(2),
        );
        expect(_confirmButton(row.item), findsOneWidget);
        expect(
          tester.getSemantics(find.text('No reason')),
          isSemantics(isChecked: true),
        );
        for (final offered in [
          'Spam',
          'Harassment',
          'Rule violation',
          'Moderator discretion',
        ]) {
          expect(find.text(offered), findsOneWidget, reason: offered);
        }
        expect(find.text('Doxing'), findsNothing);
        expect(find.text('Illegal content'), findsNothing);
        expect(
          tester.widget<ButtonStyleButton>(_confirmButton(row.item)).onPressed,
          isNotNull,
        );

        await tester.tap(find.text('Spam'));
        await tester.pump();
        expect(
          tester.getSemantics(find.text('Spam')),
          isSemantics(isChecked: true),
        );
        await tester.tap(find.text('No reason'));
        await tester.pump();
        expect(
          tester.getSemantics(find.text('No reason')),
          isSemantics(isChecked: true),
        );
        await tester.tap(_confirmButton(row.item));
        await pumpFrames(tester);

        expect(row.sentReasons(), [null]);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('B5 the ${row.item} sheet sends the reason chosen', (
      tester,
    ) async {
      when(api.getModerationSubjectState(_postUri))
          .thenAnswer((_) async => row.state);
      row.stubMutation();
      when(api.getPost(_postUri)).thenAnswer(
        (_) => Future.error(
          ApiException('Down', statusCode: 503, errorCode: 'Unavailable'),
        ),
      );

      await pumpCard(tester, row.post);
      await openSheet(tester, row.item);
      await tester.tap(find.text('Spam'));
      await tester.pump();
      await tester.tap(_confirmButton(row.item));
      await pumpFrames(tester);

      expect(row.sentReasons(), [ModerationReason.spam]);
    });
  }

  // ---------------------------------------------------------------------------
  // B7 follow-up post.get after Mark NSFW
  // ---------------------------------------------------------------------------

  for (final row in [
    'the server read offers retract-label',
    'the server read fails',
    'the session changes before the server read answers',
  ]) {
    testWidgets('B7 Mark NSFW blurs at once with no admin items, then $row', (
      tester,
    ) async {
      final serverRead = Completer<PostGetResult>();
      when(api.getModerationSubjectState(_postUri))
          .thenAnswer((_) async => _subjectState());
      stubLabel(_applied(_nsfwModeration));
      when(api.getPost(_postUri)).thenAnswer((_) => serverRead.future);
      final sessionChanges = row.startsWith('the session changes');

      await pumpCard(
        tester,
        _postView(
          capabilities: {
            ModerationCapability.remove,
            ModerationCapability.label,
          },
        ),
        stampFollowsSession: sessionChanges,
      );
      _expectUnconcealed();

      await confirmWithoutReason(tester, _markNsfw);

      // Interim: blurred from the mutation's state, no capabilities until
      // the server's post.get answers.
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Marked NSFW'), findsOneWidget);
      _expectConcealed();
      await openMenu(tester);
      expectNoAdminItems();
      await closeMenu(tester);

      if (sessionChanges) {
        auth.setSignedInDid('did:plc:other-admin');
        await pumpFrames(tester);
      }

      if (row == 'the server read fails') {
        serverRead.completeError(
          ApiException('Down', statusCode: 503, errorCode: 'Unavailable'),
        );
      } else {
        serverRead.complete(
          PostGetSuccess(
            _postView(
              capabilities: {
                ModerationCapability.remove,
                ModerationCapability.retractLabel,
              },
              moderation: _nsfwModeration,
            ),
          ),
        );
      }
      await pumpFrames(tester);

      _expectConcealed();
      await openMenu(tester);
      if (row == 'the server read offers retract-label') {
        expect(find.text(_removeNsfwLabel), findsOneWidget);
        expect(find.text(_markNsfw), findsNothing);
      } else {
        expectNoAdminItems();
      }
    });
  }

  // ---------------------------------------------------------------------------
  // B8 Remove NSFW label
  // ---------------------------------------------------------------------------

  for (final row in [
    (name: 'a post without an author self-label', authorSelfLabel: false),
    (name: 'a post the author labeled nsfw', authorSelfLabel: true),
  ]) {
    testWidgets(
      'B8 Remove NSFW label on ${row.name} updates the card in place',
      (tester) async {
        when(api.getModerationSubjectState(_postUri)).thenAnswer(
          (_) async => _subjectState(
            moderation: _nsfwModeration,
            localLabels: [_nsfwLocalLabel],
          ),
        );
        stubRetract(_applied(_clearModeration));
        // The server's read never answers, so the card shows what the
        // retraction's own answer established.
        when(api.getPost(_postUri))
            .thenAnswer((_) => Completer<PostGetResult>().future);

        await pumpCard(
          tester,
          _postView(
            capabilities: {ModerationCapability.retractLabel},
            moderation: _nsfwModeration,
            authorSelfLabel: row.authorSelfLabel,
          ),
        );
        _expectConcealed();

        await confirmWithoutReason(tester, _removeNsfwLabel);

        expect(find.byType(BottomSheet), findsNothing);
        expect(find.text('NSFW label removed'), findsOneWidget);
        if (row.authorSelfLabel) {
          _expectConcealed();
        } else {
          _expectUnconcealed();
        }
        await openMenu(tester);
        expectNoAdminItems();
      },
    );
  }

  // ---------------------------------------------------------------------------
  // NSFW success on a post the server reports removed
  // ---------------------------------------------------------------------------

  for (final row in [
    (
      item: _markNsfw,
      post: _postView(capabilities: {ModerationCapability.label}),
      state: _subjectState(
        moderation: const ModerationView(state: ModerationState.removed),
      ),
      stubMutation: () => stubLabel(
        _applied(
          const ModerationView(
            state: ModerationState.removed,
            contentLabels: [ContentLabelView(value: 'nsfw')],
          ),
        ),
      ),
    ),
    (
      item: _removeNsfwLabel,
      post: _postView(
        capabilities: {ModerationCapability.retractLabel},
        moderation: _nsfwModeration,
      ),
      state: _subjectState(
        moderation: const ModerationView(
          state: ModerationState.removed,
          contentLabels: [ContentLabelView(value: 'nsfw')],
        ),
        localLabels: [_nsfwLocalLabel],
      ),
      stubMutation: () => stubRetract(
        _applied(const ModerationView(state: ModerationState.removed)),
      ),
    ),
  ]) {
    testWidgets('${row.item} succeeding on a removed post takes the post off '
        'every surface', (tester) async {
      when(api.getModerationSubjectState(_postUri))
          .thenAnswer((_) async => row.state);
      row.stubMutation();
      when(api.getPost(_postUri))
          .thenAnswer((_) => Completer<PostGetResult>().future);
      final changes = <PostChange>[];
      broadcast.addPostChangeListener(changes.add);
      addTearDown(() => broadcast.removePostChangeListener(changes.add));

      await pumpCard(tester, row.post);
      await confirmWithoutReason(tester, row.item);

      expect(find.byType(BottomSheet), findsNothing);
      expect(
        changes.map(
          (change) => switch (change) {
            PostRemoved(:final uri) => 'removed $uri',
            PostReplaced(:final post) => 'replaced ${post.uri}',
          },
        ),
        ['removed $_postUri'],
      );
      expect(find.byType(PostCard), findsNothing);
      expect(
        find.text('Someone else already removed this post.'),
        findsOneWidget,
      );
      verifyNever(api.getPost(_postUri));
    });
  }

  // ---------------------------------------------------------------------------
  // Remove NSFW label reviews the version the card shows
  // ---------------------------------------------------------------------------

  testWidgets('Remove NSFW label reviews the version the card shows and, '
      'when the author edited it, shows the new version still labeled', (
    tester,
  ) async {
    const retractCapabilities = {
      ModerationCapability.remove,
      ModerationCapability.retractLabel,
    };
    when(api.getModerationSubjectState(_postUri)).thenAnswer(
      (_) async => _subjectState(
        moderation: _nsfwModeration,
        localLabels: [_nsfwLocalLabel],
        currentCid: 'cid-p2',
      ),
    );
    when(
      api.retractContentLabel(
        actionId: anyNamed('actionId'),
        expectedVersion: anyNamed('expectedVersion'),
        idempotencyKey: anyNamed('idempotencyKey'),
        reason: anyNamed('reason'),
        reviewedSubject: anyNamed('reviewedSubject'),
        privateNote: anyNamed('privateNote'),
      ),
    ).thenAnswer(
      (_) => Future.error(
        ApiException('Edited', statusCode: 400, errorCode: 'ContentChanged'),
      ),
    );
    when(api.getPost(_postUri)).thenAnswer(
      (_) async => PostGetSuccess(
        _postView(
          capabilities: retractCapabilities,
          moderation: _nsfwModeration,
          cid: 'cid-p2',
          title: 'After',
        ),
      ),
    );

    await pumpCard(
      tester,
      _postView(
        capabilities: retractCapabilities,
        moderation: _nsfwModeration,
        title: 'Before',
      ),
    );
    expect(find.text('Before'), findsOneWidget);

    await confirmWithoutReason(tester, _removeNsfwLabel);

    expect(
      verify(
        api.retractContentLabel(
          actionId: anyNamed('actionId'),
          expectedVersion: anyNamed('expectedVersion'),
          idempotencyKey: anyNamed('idempotencyKey'),
          reason: anyNamed('reason'),
          reviewedSubject: captureAnyNamed('reviewedSubject'),
          privateNote: anyNamed('privateNote'),
        ),
      ).captured.map(_readableStrongRef),
      [(uri: _postUri, cid: 'cid-p1')],
      reason: 'reviewedSubject',
    );
    expect(find.byType(BottomSheet), findsNothing);
    expect(
      find.text(
        'The author edited this post. Review the new version before acting.',
      ),
      findsOneWidget,
    );
    expect(find.text('After'), findsOneWidget);
    expect(find.text('Before'), findsNothing);
    _expectConcealed();
    await openMenu(tester);
    expect(find.text(_removeNsfwLabel), findsOneWidget);
  });

  testWidgets('B8 Remove NSFW label with no server NSFW label sends nothing, '
      'says so and reloads the post', (tester) async {
    when(api.getModerationSubjectState(_postUri))
        .thenAnswer((_) async => _subjectState());
    stubRetract(_applied(_clearModeration));
    when(api.getPost(_postUri)).thenAnswer(
      (_) async =>
          PostGetSuccess(_postView(capabilities: {ModerationCapability.label})),
    );

    await pumpCard(
      tester,
      _postView(
        capabilities: {ModerationCapability.retractLabel},
        moderation: _nsfwModeration,
      ),
    );
    await confirmWithoutReason(tester, _removeNsfwLabel);

    verifyNever(
      api.retractContentLabel(
        actionId: anyNamed('actionId'),
        expectedVersion: anyNamed('expectedVersion'),
        idempotencyKey: anyNamed('idempotencyKey'),
        reason: anyNamed('reason'),
        reviewedSubject: anyNamed('reviewedSubject'),
        privateNote: anyNamed('privateNote'),
      ),
    );
    expect(
      find.text('This post no longer has a server NSFW label.'),
      findsOneWidget,
    );
    verify(api.getPost(_postUri));
  });
}
