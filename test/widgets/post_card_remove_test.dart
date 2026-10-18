import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/moderation.dart';
import 'package:coves_flutter/models/moderation_action.dart';
import 'package:coves_flutter/models/moderation_subject_state.dart';
import 'package:coves_flutter/models/post.dart';
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
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/test_mocks.dart';

const postUri = 'at://did:plc:author/social.coves.community.post/p1';

FeedViewPost _post({bool canRemove = true}) => FeedViewPost(
  post: PostView(
    uri: postUri,
    cid: 'cid-p1',
    rkey: 'p1',
    author: AuthorView(did: 'did:plc:author', handle: 'author.coves.test'),
    community: CommunityRef(did: 'did:plc:community', name: 'testcove'),
    createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
    indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
    record: const PostRecord(title: 'Post to moderate', content: 'Body'),
    stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
    viewer: ViewerState(
      moderation: canRemove ? {ModerationCapability.remove} : {},
    ),
  ),
);

ModerationSubjectState _subjectState({String version = 'v7'}) =>
    ModerationSubjectState(
      subject: postUri,
      version: version,
      moderation: const ModerationView(state: ModerationState.clear),
      recordState: ModerationRecordState.present,
      currentSubject: const StrongRef(uri: postUri, cid: 'cid-newer'),
    );

Finder get _removeButton => find.ancestor(
  of: find.text('Remove'),
  matching: find.bySubtype<ButtonStyleButton>(),
);
Finder get _sheetPrimaryButton => find
    .descendant(
      of: find.byType(BottomSheet),
      matching: find.bySubtype<ButtonStyleButton>(),
    )
    .last;

void main() {
  late FakeAuthProvider auth;
  late MockCovesApiService api;
  late ViewerAuthorityProvider authority;
  late PostChangeBroadcast broadcast;

  setUp(() {
    auth = FakeAuthProvider(
      signedInDid: 'did:plc:admin',
      signedInHandle: 'admin.coves.test',
    );
    api = MockCovesApiService();
    broadcast = PostChangeBroadcast();
    when(api.getViewerAuthority()).thenAnswer((_) async => true);
  });

  tearDown(() {
    authority.dispose();
    auth.dispose();
  });

  Future<void> pumpCard(
    WidgetTester tester, {
    bool canRemove = true,
    ValueNotifier<bool>? cardVisible,
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

    authority = ViewerAuthorityProvider(apiService: api, authProvider: auth);
    // The card was loaded under the session open when it is pumped.
    final sessionStamp = authority.sessionKey;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<CovesApiService>.value(value: api),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<ViewerAuthorityProvider>.value(
            value: authority,
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
            body: cardVisible == null
                ? PostCard(
                    post: _post(canRemove: canRemove),
                    sessionStamp: sessionStamp,
                  )
                : ValueListenableBuilder<bool>(
                    valueListenable: cardVisible,
                    builder: (_, visible, _) => visible
                        ? PostCard(
                            post: _post(canRemove: canRemove),
                            sessionStamp: sessionStamp,
                          )
                        : const SizedBox.shrink(),
                  ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Post options'));
    await tester.pumpAndSettle();
  }

  Future<void> openRemoveSheet(WidgetTester tester) async {
    await openMenu(tester);
    expect(find.text('Remove post'), findsOneWidget);
    await tester.tap(find.text('Remove post'));
    await tester.pumpAndSettle();
  }

  Future<void> submit(
    WidgetTester tester, {
    String reason = 'Spam',
    String? note,
  }) async {
    await openRemoveSheet(tester);
    await tester.tap(find.text(reason));
    await tester.pumpAndSettle();
    if (note != null) {
      await tester.enterText(find.byType(TextField), note);
      await tester.pumpAndSettle();
    }
    await tester.tap(_removeButton);
    await tester.pumpAndSettle();
  }

  void stubRemoval() {
    when(api.getModerationSubjectState(postUri))
        .thenAnswer((_) async => _subjectState());
    when(
      api.removeContent(
        subject: anyNamed('subject'),
        expectedVersion: anyNamed('expectedVersion'),
        idempotencyKey: anyNamed('idempotencyKey'),
        reason: anyNamed('reason'),
        privateNote: anyNamed('privateNote'),
      ),
    ).thenAnswer(
      (_) async => ModerationMutationResult(
        outcome: ModerationMutationOutcome.applied,
        state: _subjectState(),
      ),
    );
  }

  Future<void> startRemoval(WidgetTester tester) async {
    await openRemoveSheet(tester);
    await tester.tap(find.text('Spam'));
    await tester.pumpAndSettle();
    await tester.tap(_removeButton);
    await tester.pump();
  }

  void expectInputsEnabled(WidgetTester tester, {required bool enabled}) {
    final radios = tester.widgetList<RadioListTile<ModerationReason>>(
      find.byType(RadioListTile<ModerationReason>),
    );
    expect(radios, hasLength(6));
    for (final radio in radios) {
      expect(radio.enabled ?? true, enabled);
    }
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, enabled);
  }

  testWidgets('B1 no remove token hides Remove post', (tester) async {
    await pumpCard(tester, canRemove: false);
    await openMenu(tester);
    expect(find.text('Remove post'), findsNothing);
  });

  testWidgets('B1 remove token and instance admin show Remove post', (
    tester,
  ) async {
    await pumpCard(tester);
    expect(authority.status, ViewerAuthorityStatus.instanceAdmin);
    await openMenu(tester);
    expect(find.text('Remove post'), findsOneWidget);
  });

  testWidgets(
    'B1 remove token remains available when authority is unavailable',
    (tester) async {
      when(api.getViewerAuthority()).thenThrow(ApiException('Unavailable'));
      await pumpCard(tester);
      expect(authority.status, ViewerAuthorityStatus.unavailable);
      await openMenu(tester);
      expect(find.text('Remove post'), findsOneWidget);
    },
  );

  testWidgets('B1 revocation hides Remove post on a mounted card', (
    tester,
  ) async {
    await pumpCard(tester);
    await openMenu(tester);
    expect(find.text('Remove post'), findsOneWidget);
    await tester.tap(find.byTooltip('Post options'));
    await tester.pumpAndSettle();
    authority.markRevoked();
    await tester.pump();
    await openMenu(tester);
    expect(find.text('Remove post'), findsNothing);
  });

  testWidgets('B2 menu sheet lists six reasons and requires a selection', (
    tester,
  ) async {
    await pumpCard(tester);
    await openRemoveSheet(tester);
    for (final label in [
      'Spam',
      'Harassment',
      'Doxing',
      'Illegal content',
      'Rule violation',
      'Moderator discretion',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(_removeButton, findsOneWidget);
    expect(tester.widget<ButtonStyleButton>(_removeButton).onPressed, isNull);
    await tester.tap(find.text('Spam'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ButtonStyleButton>(_removeButton).onPressed,
      isNotNull,
    );
  });

  for (final (note, expectedNote, description) in [
    ('   ', null, 'whitespace-only note is null'),
    ('  n 👍🏽 ', '  n 👍🏽 ', 'nonblank note is sent exactly as typed'),
  ]) {
    testWidgets('B5 $description', (tester) async {
      stubRemoval();
      await pumpCard(tester);
      await submit(tester, note: note);
      final captured = verify(
        api.removeContent(
          subject: anyNamed('subject'),
          expectedVersion: anyNamed('expectedVersion'),
          idempotencyKey: anyNamed('idempotencyKey'),
          reason: anyNamed('reason'),
          privateNote: captureAnyNamed('privateNote'),
        ),
      ).captured;
      expect(captured.single, expectedNote);
    });
  }

  testWidgets('B6 fetches state first and removes the card CID with v7', (
    tester,
  ) async {
    final order = <String>[];
    when(api.getModerationSubjectState(postUri)).thenAnswer((_) async {
      order.add('getModerationSubjectState');
      return _subjectState();
    });
    when(
      api.removeContent(
        subject: anyNamed('subject'),
        expectedVersion: anyNamed('expectedVersion'),
        idempotencyKey: anyNamed('idempotencyKey'),
        reason: anyNamed('reason'),
        privateNote: anyNamed('privateNote'),
      ),
    ).thenAnswer((_) async {
      order.add('removeContent');
      return ModerationMutationResult(
        outcome: ModerationMutationOutcome.applied,
        state: _subjectState(),
      );
    });
    await pumpCard(tester);
    await submit(tester, note: 'n 👍🏽');
    expect(order, ['getModerationSubjectState', 'removeContent']);
    final captured = verify(
      api.removeContent(
        subject: captureAnyNamed('subject'),
        expectedVersion: captureAnyNamed('expectedVersion'),
        idempotencyKey: captureAnyNamed('idempotencyKey'),
        reason: captureAnyNamed('reason'),
        privateNote: captureAnyNamed('privateNote'),
      ),
    ).captured;
    final subject = captured[0] as StrongRef;
    expect(subject.uri, postUri);
    expect(subject.cid, 'cid-p1');
    expect(captured[1], 'v7');
    expect(
      captured[2],
      isA<String>().having((key) => key.isNotEmpty, 'non-empty key', true),
    );
    expect(captured[3], ModerationReason.spam);
    expect(captured[4], 'n 👍🏽');
  });

  testWidgets('B6 Harassment without a note sends null', (tester) async {
    stubRemoval();
    await pumpCard(tester);
    await submit(tester, reason: 'Harassment');
    final captured = verify(
      api.removeContent(
        subject: anyNamed('subject'),
        expectedVersion: anyNamed('expectedVersion'),
        idempotencyKey: anyNamed('idempotencyKey'),
        reason: captureAnyNamed('reason'),
        privateNote: captureAnyNamed('privateNote'),
      ),
    ).captured;
    expect(captured[0], ModerationReason.harassment);
    expect(captured[1], isNull);
  });

  for (final pendingStep in ['getModerationSubjectState', 'removeContent']) {
    testWidgets(
      'B7 $pendingStep in flight disables Remove and ignores repeat taps',
      (tester) async {
        final state = Completer<ModerationSubjectState>();
        final removal = Completer<ModerationMutationResult>();
        final changes = <PostChange>[];
        broadcast.addPostChangeListener(changes.add);
        when(api.getModerationSubjectState(postUri)).thenAnswer(
          (_) => pendingStep == 'getModerationSubjectState'
              ? state.future
              : Future.value(_subjectState()),
        );
        when(
          api.removeContent(
            subject: anyNamed('subject'),
            expectedVersion: anyNamed('expectedVersion'),
            idempotencyKey: anyNamed('idempotencyKey'),
            reason: anyNamed('reason'),
            privateNote: anyNamed('privateNote'),
          ),
        ).thenAnswer((_) => removal.future);

        try {
          await pumpCard(tester);
          await openRemoveSheet(tester);
          await tester.tap(find.text('Spam'));
          await tester.pumpAndSettle();
          await tester.tap(_removeButton);
          await tester.tap(_sheetPrimaryButton); // Before the next frame.
          await tester.pump();
          await tester.tap(_sheetPrimaryButton);
          await tester.pump(const Duration(milliseconds: 100));

          expect(
            tester.widget<ButtonStyleButton>(_sheetPrimaryButton).onPressed,
            isNull,
          );
          expect(
            find.descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(CircularProgressIndicator),
            ),
            findsOneWidget,
          );
          await tester.binding.handlePopRoute();
          // Start, finish, and settle any sheet dismissal animation.
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          await tester.pump();
          expect(find.byType(BottomSheet), findsOneWidget);
          expect(
            tester
                .widget<IconButton>(
                  find.descendant(
                    of: find.byType(BottomSheet),
                    matching: find.widgetWithIcon(IconButton, Icons.close),
                  ),
                )
                .onPressed,
            isNull,
          );
          verify(api.getModerationSubjectState(postUri)).called(1);
          if (pendingStep == 'getModerationSubjectState') {
            verifyNever(
              api.removeContent(
                subject: anyNamed('subject'),
                expectedVersion: anyNamed('expectedVersion'),
                idempotencyKey: anyNamed('idempotencyKey'),
                reason: anyNamed('reason'),
                privateNote: anyNamed('privateNote'),
              ),
            );
          } else {
            verify(
              api.removeContent(
                subject: anyNamed('subject'),
                expectedVersion: anyNamed('expectedVersion'),
                idempotencyKey: anyNamed('idempotencyKey'),
                reason: anyNamed('reason'),
                privateNote: anyNamed('privateNote'),
              ),
            ).called(1);
          }
          expect(changes.whereType<PostRemoved>(), isEmpty);
        } finally {
          if (!state.isCompleted) {
            state.complete(_subjectState());
          }
          if (!removal.isCompleted) {
            removal.complete(
              ModerationMutationResult(
                outcome: ModerationMutationOutcome.applied,
                state: _subjectState(),
              ),
            );
          }
          await tester.pump();
        }
      },
    );
  }

  testWidgets('B8u unchanged publishes removal and shows already removed', (
    tester,
  ) async {
    final changes = <PostChange>[];
    broadcast.addPostChangeListener(changes.add);
    when(api.getModerationSubjectState(postUri))
        .thenAnswer((_) async => _subjectState());
    when(
      api.removeContent(
        subject: anyNamed('subject'),
        expectedVersion: anyNamed('expectedVersion'),
        idempotencyKey: anyNamed('idempotencyKey'),
        reason: anyNamed('reason'),
        privateNote: anyNamed('privateNote'),
      ),
    ).thenAnswer(
      (_) async => ModerationMutationResult(
        outcome: ModerationMutationOutcome.unchanged,
        state: _subjectState(),
      ),
    );
    await pumpCard(tester);
    await submit(tester);
    expect(changes.whereType<PostRemoved>().map((change) => change.uri), [
      postUri,
    ]);
    expect(find.text('Post was already removed'), findsOneWidget);
  });

  testWidgets(
    'W1 failed preflight keeps inputs editable and retries the read',
    (tester) async {
      var reads = 0;
      stubRemoval();
      when(api.getModerationSubjectState(postUri)).thenAnswer((_) async {
        reads++;
        if (reads == 1) {
          throw ServerException(
            'Unavailable',
            statusCode: 503,
            errorCode: 'ModerationUnavailable',
          );
        }
        return _subjectState();
      });
      await pumpCard(tester);
      await submit(tester, note: 'review note');
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(
        find.text("Couldn't load the current moderation state. Try again."),
        findsOneWidget,
      );
      expectInputsEnabled(tester, enabled: true);
      expect(_removeButton, findsOneWidget);
      verifyNever(
        api.removeContent(
          subject: anyNamed('subject'),
          expectedVersion: anyNamed('expectedVersion'),
          idempotencyKey: anyNamed('idempotencyKey'),
          reason: anyNamed('reason'),
          privateNote: anyNamed('privateNote'),
        ),
      );
      await tester.tap(_removeButton);
      await tester.pumpAndSettle();
      verify(api.getModerationSubjectState(postUri)).called(2);
      verify(
        api.removeContent(
          subject: anyNamed('subject'),
          expectedVersion: anyNamed('expectedVersion'),
          idempotencyKey: anyNamed('idempotencyKey'),
          reason: anyNamed('reason'),
          privateNote: anyNamed('privateNote'),
        ),
      ).called(1);
    },
  );

  testWidgets(
    'W2 lost response locks inputs and Try again replays the same key',
    (tester) async {
      final changes = <PostChange>[];
      broadcast.addPostChangeListener(changes.add);
      var removals = 0;
      when(api.getModerationSubjectState(postUri))
          .thenAnswer((_) async => _subjectState());
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
          throw NetworkException('Response lost');
        }
        return ModerationMutationResult(
          outcome: ModerationMutationOutcome.applied,
          state: _subjectState(),
        );
      });
      await pumpCard(tester);
      await submit(tester, note: 'review note');
      expect(find.byType(BottomSheet), findsOneWidget);
      expectInputsEnabled(tester, enabled: false);
      expect(find.text('Try again'), findsOneWidget);
      expect(
        find.text('Moderation is temporarily unavailable. Try again.'),
        findsOneWidget,
      );
      expect(changes.whereType<PostRemoved>(), isEmpty);
      await tester.tap(
        find.ancestor(
          of: find.text('Try again'),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      await tester.pumpAndSettle();
      verify(api.getModerationSubjectState(postUri)).called(1);
      final keys = verify(
        api.removeContent(
          subject: anyNamed('subject'),
          expectedVersion: anyNamed('expectedVersion'),
          idempotencyKey: captureAnyNamed('idempotencyKey'),
          reason: anyNamed('reason'),
          privateNote: anyNamed('privateNote'),
        ),
      ).captured;
      expect(keys, hasLength(2));
      expect(
        keys.first,
        isA<String>().having((key) => key.isNotEmpty, 'non-empty key', true),
      );
      expect(keys[1], keys[0]);
      expect(find.byType(BottomSheet), findsNothing);
      expect(changes.whereType<PostRemoved>().map((change) => change.uri), [
        postUri,
      ]);
    },
  );

  testWidgets('W2 closing a locked retry discards it on reopening', (
    tester,
  ) async {
    var removals = 0;
    when(api.getModerationSubjectState(postUri))
        .thenAnswer((_) async => _subjectState());
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
        throw NetworkException('Response lost');
      }
      return ModerationMutationResult(
        outcome: ModerationMutationOutcome.applied,
        state: _subjectState(),
      );
    });
    await pumpCard(tester);
    await submit(tester, note: 'first note');
    expect(find.text('Try again'), findsOneWidget);
    expectInputsEnabled(tester, enabled: false);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await openRemoveSheet(tester);
    expectInputsEnabled(tester, enabled: true);
    expect(_removeButton, findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(
      find.text('Moderation is temporarily unavailable. Try again.'),
      findsNothing,
    );

    await tester.tap(find.text('Harassment'));
    await tester.pumpAndSettle();
    await tester.tap(_removeButton);
    await tester.pumpAndSettle();
    verify(api.getModerationSubjectState(postUri)).called(2);
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
      isA<String>().having((key) => key.isNotEmpty, 'non-empty key', true),
    );
    expect(sent[1], ModerationReason.spam);
    expect(sent[2], 'first note');
    expect(sent[3], isNot(sent[0]));
    expect(sent[4], ModerationReason.harassment);
    expect(sent[5], isNull);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets(
    'S7 sign-out closes a Try again sheet silently and hides Remove post',
    (tester) async {
      when(api.getModerationSubjectState(postUri))
          .thenAnswer((_) async => _subjectState());
      when(
        api.removeContent(
          subject: anyNamed('subject'),
          expectedVersion: anyNamed('expectedVersion'),
          idempotencyKey: anyNamed('idempotencyKey'),
          reason: anyNamed('reason'),
          privateNote: anyNamed('privateNote'),
        ),
      ).thenThrow(NetworkException('Response lost'));
      await pumpCard(tester);
      await submit(tester, note: 'review note');
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      auth.notifyWithoutChange();
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      auth.setSignedInDid(null);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      verify(
        api.removeContent(
          subject: anyNamed('subject'),
          expectedVersion: anyNamed('expectedVersion'),
          idempotencyKey: anyNamed('idempotencyKey'),
          reason: anyNamed('reason'),
          privateNote: anyNamed('privateNote'),
        ),
      ).called(1);
      await openMenu(tester);
      expect(find.text('Remove post'), findsNothing);
    },
  );

  testWidgets('W3 StateConflict already removed closes and publishes removal', (
    tester,
  ) async {
    final changes = <PostChange>[];
    broadcast.addPostChangeListener(changes.add);
    var reads = 0;
    when(api.getModerationSubjectState(postUri)).thenAnswer((_) async {
      if (++reads == 1) {
        return _subjectState();
      }
      return const ModerationSubjectState(
        subject: postUri,
        version: 'v8',
        moderation: ModerationView(state: ModerationState.removed),
        recordState: ModerationRecordState.present,
      );
    });
    when(
      api.removeContent(
        subject: anyNamed('subject'),
        expectedVersion: anyNamed('expectedVersion'),
        idempotencyKey: anyNamed('idempotencyKey'),
        reason: anyNamed('reason'),
        privateNote: anyNamed('privateNote'),
      ),
    ).thenThrow(
      ApiException('Conflict', statusCode: 400, errorCode: 'StateConflict'),
    );
    await pumpCard(tester);
    await submit(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(
      find.text('Someone else already removed this post.'),
      findsOneWidget,
    );
    expect(changes.whereType<PostRemoved>().map((change) => change.uri), [
      postUri,
    ]);
    verify(api.getModerationSubjectState(postUri)).called(2);
  });

  testWidgets('W3 StateConflict with clear v8 requires editable confirmation', (
    tester,
  ) async {
    var reads = 0;
    var removals = 0;
    when(api.getModerationSubjectState(postUri)).thenAnswer(
      (_) async => _subjectState(version: ++reads == 1 ? 'v7' : 'v8'),
    );
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
        throw ApiException(
          'Conflict',
          statusCode: 400,
          errorCode: 'StateConflict',
        );
      }
      return ModerationMutationResult(
        outcome: ModerationMutationOutcome.applied,
        state: _subjectState(version: 'v8'),
      );
    });
    await pumpCard(tester);
    await submit(tester);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      find.text('Someone else acted on this first. Confirm again.'),
      findsOneWidget,
    );
    expectInputsEnabled(tester, enabled: true);
    expect(_removeButton, findsOneWidget);
    await tester.tap(_removeButton);
    await tester.pumpAndSettle();
    final versions = verify(
      api.removeContent(
        subject: anyNamed('subject'),
        expectedVersion: captureAnyNamed('expectedVersion'),
        idempotencyKey: anyNamed('idempotencyKey'),
        reason: anyNamed('reason'),
        privateNote: anyNamed('privateNote'),
      ),
    ).captured;
    expect(versions, ['v7', 'v8']);
  });

  testWidgets(
    'W3 IdempotencyConflict unlocks and next Remove reads fresh state',
    (tester) async {
      var reads = 0;
      var removals = 0;
      when(api.getModerationSubjectState(postUri)).thenAnswer(
        (_) async => _subjectState(version: ++reads == 1 ? 'v7' : 'v8'),
      );
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
          throw NetworkException('Response lost');
        }
        if (removals == 2) {
          throw ApiException(
            'Conflict',
            statusCode: 400,
            errorCode: 'IdempotencyConflict',
          );
        }
        return ModerationMutationResult(
          outcome: ModerationMutationOutcome.applied,
          state: _subjectState(version: 'v8'),
        );
      });
      await pumpCard(tester);
      await submit(tester);
      expectInputsEnabled(tester, enabled: false);
      await tester.tap(
        find.ancestor(
          of: find.text('Try again'),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Something went wrong. Confirm again.'), findsOneWidget);
      expectInputsEnabled(tester, enabled: true);
      expect(_removeButton, findsOneWidget);
      expect(reads, 1);
      await tester.tap(_removeButton);
      await tester.pumpAndSettle();
      expect(reads, 2);
      verify(
        api.removeContent(
          subject: anyNamed('subject'),
          expectedVersion: anyNamed('expectedVersion'),
          idempotencyKey: anyNamed('idempotencyKey'),
          reason: anyNamed('reason'),
          privateNote: anyNamed('privateNote'),
        ),
      ).called(3);
    },
  );

  testWidgets('W5c UnsupportedReason closes with client error but keeps post', (
    tester,
  ) async {
    final changes = <PostChange>[];
    broadcast.addPostChangeListener(changes.add);
    when(api.getModerationSubjectState(postUri))
        .thenAnswer((_) async => _subjectState());
    when(
      api.removeContent(
        subject: anyNamed('subject'),
        expectedVersion: anyNamed('expectedVersion'),
        idempotencyKey: anyNamed('idempotencyKey'),
        reason: anyNamed('reason'),
        privateNote: anyNamed('privateNote'),
      ),
    ).thenThrow(
      ApiException(
        'Unsupported',
        statusCode: 400,
        errorCode: 'UnsupportedReason',
      ),
    );
    await pumpCard(tester);
    await submit(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text("Couldn't complete this action."), findsOneWidget);
    expect(changes.whereType<PostRemoved>(), isEmpty);
    expect(find.byType(PostCard), findsOneWidget);
  });

  testWidgets('W5d a non-API error from removal is reported without the note', (
    tester,
  ) async {
    const noteMarker = 'secret-note-marker';
    final thrown = StateError('client bug');
    when(api.getModerationSubjectState(postUri))
        .thenAnswer((_) async => _subjectState());
    when(
      api.removeContent(
        subject: anyNamed('subject'),
        expectedVersion: anyNamed('expectedVersion'),
        idempotencyKey: anyNamed('idempotencyKey'),
        reason: anyNamed('reason'),
        privateNote: anyNamed('privateNote'),
      ),
    ).thenThrow(thrown);
    await pumpCard(tester);
    final reports = <FlutterErrorDetails>[];
    final originalOnError = FlutterError.onError;
    FlutterError.onError = reports.add;
    try {
      await submit(tester, note: noteMarker);
    } finally {
      FlutterError.onError = originalOnError;
    }
    expect(reports, hasLength(1));
    final report = reports.single;
    expect(report.exception, same(thrown));
    expect(report.toString(), isNot(contains(noteMarker)));
    expect(report.exception.toString(), isNot(contains(noteMarker)));
    expect(report.context.toString(), isNot(contains(noteMarker)));
    expect(find.text("Couldn't remove this post. Try again."), findsOneWidget);
  });

  for (final interruption in ['modal barrier', 'card removed from tree']) {
    testWidgets('B10 success publishes removal after $interruption', (
      tester,
    ) async {
      final removal = Completer<ModerationMutationResult>();
      final changes = <PostChange>[];
      broadcast.addPostChangeListener(changes.add);
      final cardVisible = ValueNotifier<bool>(true);
      addTearDown(cardVisible.dispose);
      when(api.getModerationSubjectState(postUri))
          .thenAnswer((_) async => _subjectState());
      when(
        api.removeContent(
          subject: anyNamed('subject'),
          expectedVersion: anyNamed('expectedVersion'),
          idempotencyKey: anyNamed('idempotencyKey'),
          reason: anyNamed('reason'),
          privateNote: anyNamed('privateNote'),
        ),
      ).thenAnswer((_) => removal.future);
      try {
        await pumpCard(tester, cardVisible: cardVisible);
        await startRemoval(tester);
        if (interruption == 'modal barrier') {
          final sheetTop = tester.getTopLeft(find.byType(BottomSheet)).dy;
          await tester.tapAt(Offset(10, sheetTop / 2));
        } else {
          cardVisible.value = false;
        }
        await tester.pump();
        if (interruption == 'modal barrier') {
          // Finish and settle any sheet dismissal animation.
          await tester.pump(const Duration(seconds: 1));
          await tester.pump();
          expect(find.byType(BottomSheet), findsOneWidget);
        }
        if (interruption == 'card removed from tree') {
          expect(find.byType(PostCard), findsNothing);
        }
        expect(changes.whereType<PostRemoved>(), isEmpty);
        removal.complete(
          ModerationMutationResult(
            outcome: ModerationMutationOutcome.applied,
            state: _subjectState(),
          ),
        );
        await tester.pumpAndSettle();
        expect(changes.whereType<PostRemoved>().map((change) => change.uri), [
          postUri,
        ]);
      } finally {
        if (!removal.isCompleted) {
          removal.complete(
            ModerationMutationResult(
              outcome: ModerationMutationOutcome.applied,
              state: _subjectState(),
            ),
          );
          await tester.pump();
        }
      }
    });
  }
}
