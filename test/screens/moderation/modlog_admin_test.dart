import 'dart:async';

import 'package:coves_flutter/models/community.dart';
import 'package:coves_flutter/models/moderation_action.dart';
import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/providers/viewer_authority_provider.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/widgets/loading_error_states.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../test_helpers/fake_providers.dart';
import '../../test_helpers/modlog_fixtures.dart';
import '../../test_helpers/pump_helpers.dart';
import '../../test_helpers/test_mocks.dart';

const postSubject = 'at://did:plc:a/social.coves.community.postv2/3kabc';

Finder appBarTitle(String title) =>
    find.descendant(of: find.byType(AppBar), matching: renderedText(title));

/// The admin log's app bar reads "Moderation log" with a separate "Admin
/// view" pill; the public log's has the same title and no pill.
void expectLogAppBar({required bool admin, String? reason}) {
  expect(appBarTitle('Moderation log'), findsOneWidget, reason: reason);
  expect(
    admin ? appBarTitle('Admin view') : renderedTextContaining('Admin view'),
    admin ? findsOneWidget : findsNothing,
    reason: reason,
  );
}

void main() {
  late MockCovesApiService api;

  setUp(() => api = MockCovesApiService());

  void stubAdminLog(List<AdminModerationActionView> rows) {
    when(
      api.listAdminModerationActions(
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
        action: anyNamed('action'),
        community: anyNamed('community'),
        subject: anyNamed('subject'),
      ),
    ).thenAnswer((_) async => AdminModerationActionPage(actions: rows));
  }

  /// Holds every admin-log request on the returned Completer.
  Completer<AdminModerationActionPage> holdAdminLog() {
    final page = Completer<AdminModerationActionPage>();
    when(
      api.listAdminModerationActions(
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
        action: anyNamed('action'),
        community: anyNamed('community'),
        subject: anyNamed('subject'),
      ),
    ).thenAnswer((_) => page.future);
    return page;
  }

  testWidgets('B2 only an instance admin loads the admin log', (tester) async {
    final neverAnswers = Completer<bool>();
    final rows =
        <
          ({
            String name,
            String? did,
            void Function() stubAuthority,
            bool revoke,
            ViewerAuthorityStatus status,
            bool admin,
          })
        >[
          (
            name: 'instanceAdmin',
            did: 'did:plc:admin',
            stubAuthority: () =>
                when(api.getViewerAuthority()).thenAnswer((_) async => true),
            revoke: false,
            status: ViewerAuthorityStatus.instanceAdmin,
            admin: true,
          ),
          (
            name: 'signedOut',
            did: null,
            stubAuthority: () {},
            revoke: false,
            status: ViewerAuthorityStatus.signedOut,
            admin: false,
          ),
          (
            name: 'loading',
            did: 'did:plc:admin',
            stubAuthority: () =>
                when(api.getViewerAuthority())
                    .thenAnswer((_) => neverAnswers.future),
            revoke: false,
            status: ViewerAuthorityStatus.loading,
            admin: false,
          ),
          (
            name: 'notAdmin',
            did: 'did:plc:admin',
            stubAuthority: () =>
                when(api.getViewerAuthority()).thenAnswer((_) async => false),
            revoke: false,
            status: ViewerAuthorityStatus.notAdmin,
            admin: false,
          ),
          (
            name: 'unavailable',
            did: 'did:plc:admin',
            stubAuthority: () => when(api.getViewerAuthority()).thenAnswer(
              (_) async => throw ApiException('Unavailable', statusCode: 503),
            ),
            revoke: false,
            status: ViewerAuthorityStatus.unavailable,
            admin: false,
          ),
          (
            name: 'revoked',
            did: 'did:plc:admin',
            stubAuthority: () =>
                when(api.getViewerAuthority()).thenAnswer((_) async => true),
            revoke: true,
            status: ViewerAuthorityStatus.revoked,
            admin: false,
          ),
        ];

    for (final row in rows) {
      api = MockCovesApiService();
      stubPublicLog(api);
      stubAdminLog([
        AdminModerationActionView(
          action: action('did:web:coves.social', 'private-row'),
          privateNote: 'Spam ring.',
          privateSubject: const ModerationSubjectRef(uri: postSubject),
        ),
      ]);
      row.stubAuthority();
      final auth = FakeAuthProvider(signedInDid: row.did);
      final authority = ViewerAuthorityProvider(
        apiService: api,
        authProvider: auth,
      );
      await tester.pump();
      if (row.revoke) {
        authority.markRevoked();
      }
      expect(authority.status, row.status, reason: row.name);

      final (_, release) = await pumpModlog(
        tester,
        api: api,
        auth: auth,
        authority: authority,
        subject: postSubject,
      );

      if (row.admin) {
        verify(
          api.listAdminModerationActions(
            cursor: anyNamed('cursor'),
            limit: anyNamed('limit'),
            action: anyNamed('action'),
            community: anyNamed('community'),
            subject: postSubject,
          ),
        );
        verifyNever(
          api.listModerationActions(
            cursor: anyNamed('cursor'),
            limit: anyNamed('limit'),
            action: anyNamed('action'),
            community: anyNamed('community'),
            subject: anyNamed('subject'),
          ),
        );
        expectLogAppBar(admin: true, reason: row.name);
      } else {
        verify(
          api.listModerationActions(
            cursor: anyNamed('cursor'),
            limit: anyNamed('limit'),
            action: anyNamed('action'),
            community: anyNamed('community'),
            subject: postSubject,
          ),
        );
        verifyNever(
          api.listAdminModerationActions(
            cursor: anyNamed('cursor'),
            limit: anyNamed('limit'),
            action: anyNamed('action'),
            community: anyNamed('community'),
            subject: anyNamed('subject'),
          ),
        );
        expectLogAppBar(admin: false, reason: row.name);
        expect(find.text('Private note'), findsNothing, reason: row.name);
        expect(
          find.textContaining('Spam ring.'),
          findsNothing,
          reason: row.name,
        );
        expect(
          find.text('Hidden from public log'),
          findsNothing,
          reason: row.name,
        );
      }
      await release();
    }
  });

  testWidgets('B3 an admin row shows its private note between the subject '
      'box and the reason', (tester) async {
    stubPublicLog(api);
    stubAdminLog([
      AdminModerationActionView(
        action: action(
          'did:web:coves.social',
          'noted',
          reason: ModerationReason.spam,
        ),
        privateNote: 'Spam ring.\nSee ticket 42 for the linked accounts.',
      ),
    ]);
    final (auth, authority) = await signedInAdmin(tester, api);

    await pumpModlog(tester, api: api, auth: auth, authority: authority);
    final row = tile('did:web:coves.social', 'noted');
    final label = find.descendant(of: row, matching: find.text('Private note'));
    final note = find.descendant(
      of: row,
      matching: find.text('Spam ring.\nSee ticket 42 for the linked accounts.'),
    );
    expect(label, findsOneWidget);
    expect(note, findsOneWidget);
    // The note sits below the subject box's text and above the footer's
    // reason.
    final subjectText = find.descendant(
      of: row,
      matching: find.text('Content not shown'),
    );
    final reasonText = find.descendant(of: row, matching: find.text('Spam'));
    expect(subjectText, findsOneWidget);
    expect(reasonText, findsOneWidget);
    final subjectBottom = tester.getBottomLeft(subjectText).dy;
    final reasonTop = tester.getTopLeft(reasonText).dy;
    expect(tester.getTopLeft(label).dy, greaterThanOrEqualTo(subjectBottom));
    expect(tester.getTopLeft(note).dy, greaterThanOrEqualTo(subjectBottom));
    expect(tester.getBottomLeft(note).dy, lessThanOrEqualTo(reasonTop));
  });

  testWidgets('B4 admin rows link the private subject and name the admin '
      'actor', (tester) async {
    when(api.getProfile(actor: 'did:plc:top')).thenAnswer(
      (_) async => UserProfile(did: 'did:plc:top', handle: 'top.coves.social'),
    );
    when(api.getProfile(actor: 'did:plc:pub')).thenAnswer(
      (_) async => UserProfile(did: 'did:plc:pub', handle: 'pub.coves.social'),
    );
    stubPublicLog(api);
    stubAdminLog([
      AdminModerationActionView(
        action: action(
          'did:web:coves.social',
          'hidden',
          actorDid: 'did:plc:pub',
        ),
        actorDid: 'did:plc:top',
        privateSubject: const ModerationSubjectRef(uri: postSubject),
      ),
      AdminModerationActionView(
        action: action(
          'did:web:coves.social',
          'fallback',
          actorDid: 'did:plc:pub',
        ),
      ),
      AdminModerationActionView(
        action: action(
          'did:web:coves.social',
          'public',
          actorDid: 'did:plc:pub',
          subject: const ModerationSubjectRef(
            uri: 'at://did:plc:pub/social.coves.community.post/p1',
          ),
        ),
        actorDid: 'did:plc:pub',
        privateSubject: const ModerationSubjectRef(uri: postSubject),
      ),
      // The realistic admin row: the public log withholds the actor and only
      // the private admin DID is set.
      AdminModerationActionView(
        action: action('did:web:coves.social', 'private-actor'),
        actorDid: 'did:plc:top',
      ),
      AdminModerationActionView(
        action: action('did:web:coves.social', 'unresolved-actor'),
        actorDid: 'did:plc:raw',
      ),
    ]);
    when(api.getProfile(actor: 'did:plc:raw')).thenAnswer(
      (_) async => throw ApiException('Unavailable', statusCode: 503),
    );
    final (auth, authority) = await signedInAdmin(tester, api);

    final (router, _) = await pumpModlog(
      tester,
      api: api,
      auth: auth,
      authority: authority,
    );
    final hidden = tile('did:web:coves.social', 'hidden');
    final fallback = tile('did:web:coves.social', 'fallback');
    final public = tile('did:web:coves.social', 'public');
    final privateActor = tile('did:web:coves.social', 'private-actor');
    final unresolvedActor = tile('did:web:coves.social', 'unresolved-actor');

    // (a) The private subject is linked and tagged; the admin actor is named
    // in the headline, which takes its noun from the private subject.
    expect(
      find.descendant(
        of: hidden,
        matching: renderedText('@top.coves.social removed a post'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: hidden,
        matching: renderedTextContaining('@pub.coves.social'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: hidden,
        matching: find.text('Hidden from public log'),
      ),
      findsOneWidget,
    );
    // (b) Without an admin actor the public actor is named.
    expect(
      find.descendant(
        of: fallback,
        matching: renderedText('@pub.coves.social removed content'),
      ),
      findsOneWidget,
    );
    // (b2) Without a public actor the private admin is named: by handle, or
    // as "A moderator" when the handle does not resolve, never by the DID.
    expect(
      find.descendant(
        of: privateActor,
        matching: renderedText('@top.coves.social removed content'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: unresolvedActor,
        matching: renderedText('A moderator removed content'),
      ),
      findsOneWidget,
    );
    expect(renderedTextContaining('did:plc:raw'), findsNothing);
    for (final row in [privateActor, unresolvedActor]) {
      expect(
        find.descendant(
          of: row,
          matching: renderedTextContaining('Server admin'),
        ),
        findsNothing,
      );
    }
    // (c) A public subject wins over the private one and is not tagged.
    expect(
      find.descendant(
        of: public,
        matching: find.text('Hidden from public log'),
      ),
      findsNothing,
    );

    await tester.tap(find.descendant(of: hidden, matching: find.text('Post')));
    await pumpFrames(tester);
    expect(
      find.text(
        'post:/post/at%3A%2F%2Fdid%3Aplc%3Aa%2Fsocial.coves.community.postv2%2F3kabc',
      ),
      findsOneWidget,
    );

    router.pop();
    await pumpFrames(tester);
    await tester.tap(find.descendant(of: public, matching: find.text('Post')));
    await pumpFrames(tester);
    expect(
      find.text(
        'post:/post/at%3A%2F%2Fdid%3Aplc%3Apub%2Fsocial.coves.community.post%2Fp1',
      ),
      findsOneWidget,
    );
  });

  testWidgets('B5 the admin log names NSFW label rows and filters removals '
      'and by community', (tester) async {
    when(
      api.listCommunities(
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
        sort: anyNamed('sort'),
        subscribed: anyNamed('subscribed'),
      ),
    ).thenAnswer(
      (_) async => CommunitiesResponse(
        communities: [CommunityView(did: 'did:plc:c', name: 'gardening')],
      ),
    );
    stubPublicLog(api);
    stubAdminLog([
      AdminModerationActionView(
        action: action(
          'did:web:coves.social',
          'marked',
          kind: ModerationActionKind.label,
          subject: const ModerationSubjectRef(uri: postSubject),
        ),
      ),
      AdminModerationActionView(
        action: action(
          'did:web:coves.social',
          'unmarked',
          kind: ModerationActionKind.retractLabel,
          subject: const ModerationSubjectRef(uri: postSubject),
        ),
      ),
    ]);
    final (auth, authority) = await signedInAdmin(tester, api);

    await pumpModlog(tester, api: api, auth: auth, authority: authority);

    expect(renderedText('Server admin marked a post NSFW'), findsOneWidget);
    expect(
      renderedText('Server admin removed the NSFW label from a post'),
      findsOneWidget,
    );
    await tester.tap(find.text('All actions'));
    await pumpFrames(tester);
    expect(find.text('Removals'), findsOneWidget);
    expect(find.text('Restores'), findsOneWidget);

    await tester.tap(find.text('Removals'));
    await pumpFrames(tester);
    verify(
      api.listAdminModerationActions(
        // ignore: avoid_redundant_argument_values
        cursor: null,
        limit: anyNamed('limit'),
        action: 'remove',
        community: anyNamed('community'),
        subject: anyNamed('subject'),
      ),
    );

    await tester.tap(find.text('Community'));
    await pumpFrames(tester);
    await tester.tap(find.text('gardening'));
    await pumpFrames(tester);
    verify(
      api.listAdminModerationActions(
        // ignore: avoid_redundant_argument_values
        cursor: null,
        limit: anyNamed('limit'),
        action: 'remove',
        community: 'did:plc:c',
        subject: anyNamed('subject'),
      ),
    ).called(1);
  });

  testWidgets('B5 the admin log follows its cursor to the next page', (
    tester,
  ) async {
    stubPublicLog(api);
    when(
      api.listAdminModerationActions(
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
        action: anyNamed('action'),
        community: anyNamed('community'),
        subject: anyNamed('subject'),
      ),
    ).thenAnswer(
      (invocation) async => switch (invocation.namedArguments[#cursor]) {
        null => AdminModerationActionPage(
          actions: [
            AdminModerationActionView(
              action: action('did:web:coves.social', 'page-1'),
            ),
          ],
          cursor: 'c2',
        ),
        'c2' => AdminModerationActionPage(
          actions: [
            AdminModerationActionView(
              action: action('did:web:coves.social', 'page-2'),
            ),
          ],
        ),
        _ => throw StateError('Unexpected admin modlog cursor'),
      },
    );
    final (auth, authority) = await signedInAdmin(tester, api);

    await pumpModlog(tester, api: api, auth: auth, authority: authority);

    verify(
      api.listAdminModerationActions(
        cursor: 'c2',
        limit: anyNamed('limit'),
        action: anyNamed('action'),
        community: anyNamed('community'),
        subject: anyNamed('subject'),
      ),
    ).called(1);
    expect(tile('did:web:coves.social', 'page-1'), findsOneWidget);
    expect(tile('did:web:coves.social', 'page-2'), findsOneWidget);
  });

  testWidgets('B6 leaving instance admin clears private rows in the same '
      'frame and reloads the public log', (tester) async {
    const note = 'Spam ring.\nSee ticket 42 for the linked accounts.';
    final cases =
        <
          ({
            String name,
            String? subject,
            void Function(FakeAuthProvider, ViewerAuthorityProvider) leave,
          })
        >[
          (
            name: 'sign out',
            subject: postSubject,
            leave: (auth, _) => auth.setSignedInDid(null),
          ),
          (
            name: 'account switch',
            subject: null,
            leave: (auth, _) {
              when(api.getViewerAuthority()).thenAnswer((_) async => false);
              auth.setSignedInDid('did:plc:other');
            },
          ),
          (
            name: 'revoked',
            subject: null,
            leave: (_, authority) => authority.markRevoked(),
          ),
        ];

    for (final row in cases) {
      api = MockCovesApiService();
      final publicPage = Completer<ModerationActionPage>();
      when(
        api.listModerationActions(
          cursor: anyNamed('cursor'),
          limit: anyNamed('limit'),
          action: anyNamed('action'),
          community: anyNamed('community'),
          subject: anyNamed('subject'),
        ),
      ).thenAnswer((_) => publicPage.future);
      stubAdminLog([
        AdminModerationActionView(
          action: action('did:web:coves.social', 'noted'),
          privateNote: note,
        ),
        AdminModerationActionView(
          action: action('did:web:coves.social', 'hidden'),
          privateSubject: const ModerationSubjectRef(uri: postSubject),
        ),
      ]);
      final (auth, authority) = await signedInAdmin(tester, api);
      final (_, release) = await pumpModlog(
        tester,
        api: api,
        auth: auth,
        authority: authority,
        subject: row.subject,
      );
      final hidden = tile('did:web:coves.social', 'hidden');
      expect(find.text(note), findsOneWidget, reason: row.name);
      expect(
        find.text('Hidden from public log'),
        findsOneWidget,
        reason: row.name,
      );
      expect(
        find.descendant(of: hidden, matching: find.text('Post')),
        findsOneWidget,
        reason: row.name,
      );

      row.leave(auth, authority);
      await tester.pump();

      expect(find.textContaining('Spam ring.'), findsNothing, reason: row.name);
      expect(find.text('Private note'), findsNothing, reason: row.name);
      expect(
        find.text('Hidden from public log'),
        findsNothing,
        reason: row.name,
      );
      expect(find.text('Post'), findsNothing, reason: row.name);

      await pumpFrames(tester);
      verify(
        api.listModerationActions(
          // ignore: avoid_redundant_argument_values
          cursor: null,
          limit: anyNamed('limit'),
          action: anyNamed('action'),
          community: anyNamed('community'),
          subject: row.subject,
        ),
      );

      publicPage.complete(const ModerationActionPage(actions: []));
      await pumpFrames(tester);
      await release();
    }
  });

  testWidgets('B7 an in-flight admin page never lands after authority '
      'changes', (tester) async {
    const note = 'Spam ring.\nSee ticket 42 for the linked accounts.';
    final cases =
        <
          ({
            String name,
            void Function(FakeAuthProvider, ViewerAuthorityProvider) leave,
            bool adminResolvesFirst,
          })
        >[
          (
            name: 'revoked, public page first',
            leave: (_, authority) => authority.markRevoked(),
            adminResolvesFirst: false,
          ),
          (
            name: 'sign out, public page first',
            leave: (auth, _) => auth.setSignedInDid(null),
            adminResolvesFirst: false,
          ),
          (
            name: 'revoked, admin page first',
            leave: (_, authority) => authority.markRevoked(),
            adminResolvesFirst: true,
          ),
        ];

    void expectNoPrivateRows(String reason) {
      expect(find.textContaining('Spam ring.'), findsNothing, reason: reason);
      expect(find.text('Private note'), findsNothing, reason: reason);
      expect(find.text('Hidden from public log'), findsNothing, reason: reason);
      expect(
        tile('did:web:coves.social', 'noted'),
        findsNothing,
        reason: reason,
      );
      expect(
        tile('did:web:coves.social', 'hidden'),
        findsNothing,
        reason: reason,
      );
      expect(find.text('Post'), findsNothing, reason: reason);
    }

    for (final row in cases) {
      api = MockCovesApiService();
      final publicPage = Completer<ModerationActionPage>();
      when(
        api.listModerationActions(
          cursor: anyNamed('cursor'),
          limit: anyNamed('limit'),
          action: anyNamed('action'),
          community: anyNamed('community'),
          subject: anyNamed('subject'),
        ),
      ).thenAnswer((_) => publicPage.future);
      final adminPage = holdAdminLog();
      final (auth, authority) = await signedInAdmin(tester, api);
      final (_, release) = await pumpModlog(
        tester,
        api: api,
        auth: auth,
        authority: authority,
      );
      verify(
        api.listAdminModerationActions(
          cursor: anyNamed('cursor'),
          limit: anyNamed('limit'),
          action: anyNamed('action'),
          community: anyNamed('community'),
          subject: anyNamed('subject'),
        ),
      );
      expectLogAppBar(admin: true, reason: row.name);

      row.leave(auth, authority);
      await pumpFrames(tester);
      expect(authority.isInstanceAdmin, isFalse, reason: row.name);

      void completeAdminPage() => adminPage.complete(
        AdminModerationActionPage(
          actions: [
            AdminModerationActionView(
              action: action('did:web:coves.social', 'noted'),
              privateNote: note,
            ),
            AdminModerationActionView(
              action: action('did:web:coves.social', 'hidden'),
              privateSubject: const ModerationSubjectRef(uri: postSubject),
            ),
          ],
        ),
      );
      void completePublicPage() => publicPage.complete(
        ModerationActionPage(
          actions: [action('did:web:coves.social', 'public-row')],
        ),
      );

      if (row.adminResolvesFirst) {
        completeAdminPage();
        await pumpFrames(tester);
        expectNoPrivateRows(row.name);
        completePublicPage();
      } else {
        completePublicPage();
        await pumpFrames(tester);
        expect(
          tile('did:web:coves.social', 'public-row'),
          findsOneWidget,
          reason: row.name,
        );
        completeAdminPage();
      }
      await pumpFrames(tester);

      expectNoPrivateRows(row.name);
      expect(
        tile('did:web:coves.social', 'public-row'),
        findsOneWidget,
        reason: row.name,
      );
      expectLogAppBar(admin: false, reason: row.name);
      await release();
    }
  });

  testWidgets('B8 a Forbidden admin log revokes authority and reloads the '
      'public log', (tester) async {
    stubPublicLog(api);
    when(
      api.listAdminModerationActions(
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
        action: anyNamed('action'),
        community: anyNamed('community'),
        subject: anyNamed('subject'),
      ),
    ).thenAnswer(
      (_) async => throw ApiException(
        'Forbidden',
        statusCode: 403,
        errorCode: 'Forbidden',
      ),
    );
    final (auth, authority) = await signedInAdmin(tester, api);

    await pumpModlog(tester, api: api, auth: auth, authority: authority);
    await pumpFrames(tester);

    expect(authority.status, ViewerAuthorityStatus.revoked);
    verify(
      api.listModerationActions(
        // ignore: avoid_redundant_argument_values
        cursor: null,
        limit: anyNamed('limit'),
        action: anyNamed('action'),
        community: anyNamed('community'),
        subject: anyNamed('subject'),
      ),
    );
    expectLogAppBar(admin: false);
  });

  testWidgets('B8 a failing admin log keeps authority and shows the error', (
    tester,
  ) async {
    stubPublicLog(api);
    when(
      api.listAdminModerationActions(
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
        action: anyNamed('action'),
        community: anyNamed('community'),
        subject: anyNamed('subject'),
      ),
    ).thenAnswer(
      (_) async =>
          throw ServerException('Service unavailable', statusCode: 503),
    );
    final (auth, authority) = await signedInAdmin(tester, api);

    await pumpModlog(tester, api: api, auth: auth, authority: authority);
    await pumpFrames(tester);

    expect(authority.status, ViewerAuthorityStatus.instanceAdmin);
    verifyNever(
      api.listModerationActions(
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
        action: anyNamed('action'),
        community: anyNamed('community'),
        subject: anyNamed('subject'),
      ),
    );
    expect(find.byType(FullScreenError), findsOneWidget);
    expect(find.text('Server error. Please try again later.'), findsOneWidget);
  });

  ApiException forbidden() =>
      ApiException('Forbidden', statusCode: 403, errorCode: 'Forbidden');

  testWidgets('B8b a Forbidden answer for a previous account revokes '
      'nothing', (tester) async {
    stubPublicLog(api);
    final accountARequest = Completer<AdminModerationActionPage>();
    final adminAnswers = <Future<AdminModerationActionPage>>[
      accountARequest.future,
      Future.value(
        AdminModerationActionPage(
          actions: [
            AdminModerationActionView(
              action: action('did:web:coves.social', 'account-b-row'),
            ),
          ],
        ),
      ),
    ];
    when(
      api.listAdminModerationActions(
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
        action: anyNamed('action'),
        community: anyNamed('community'),
        subject: anyNamed('subject'),
      ),
    ).thenAnswer((_) => adminAnswers.removeAt(0));
    final (auth, authority) = await signedInAdmin(tester, api);
    await pumpModlog(tester, api: api, auth: auth, authority: authority);
    expectLogAppBar(admin: true);

    auth.setSignedInDid('did:plc:account-b');
    await pumpFrames(tester);
    expect(authority.status, ViewerAuthorityStatus.instanceAdmin);
    expect(tile('did:web:coves.social', 'account-b-row'), findsOneWidget);

    accountARequest.completeError(forbidden());
    await pumpFrames(tester);

    expect(authority.status, ViewerAuthorityStatus.instanceAdmin);
    expectLogAppBar(admin: true);
    expect(tile('did:web:coves.social', 'account-b-row'), findsOneWidget);
  });

  testWidgets('B8b a Forbidden answer superseded by a newer filter run '
      'revokes nothing', (tester) async {
    stubPublicLog(api);
    final allRequest = Completer<AdminModerationActionPage>();
    when(
      api.listAdminModerationActions(
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
        // ignore: avoid_redundant_argument_values
        action: null,
        community: anyNamed('community'),
        subject: anyNamed('subject'),
      ),
    ).thenAnswer((_) => allRequest.future);
    when(
      api.listAdminModerationActions(
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
        action: 'remove',
        community: anyNamed('community'),
        subject: anyNamed('subject'),
      ),
    ).thenAnswer(
      (_) async => AdminModerationActionPage(
        actions: [
          AdminModerationActionView(
            action: action('did:web:coves.social', 'removal-row'),
          ),
        ],
      ),
    );
    final (auth, authority) = await signedInAdmin(tester, api);
    await pumpModlog(tester, api: api, auth: auth, authority: authority);

    await chooseActionFilter(tester, from: 'All actions', to: 'Removals');
    expect(tile('did:web:coves.social', 'removal-row'), findsOneWidget);

    allRequest.completeError(forbidden());
    await pumpFrames(tester);

    expect(authority.status, ViewerAuthorityStatus.instanceAdmin);
    expectLogAppBar(admin: true);
    expect(tile('did:web:coves.social', 'removal-row'), findsOneWidget);
    verifyNever(
      api.listModerationActions(
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
        action: anyNamed('action'),
        community: anyNamed('community'),
        subject: anyNamed('subject'),
      ),
    );
  });

  testWidgets('B13 opening with unavailable authority asks again and loads '
      'the admin log', (tester) async {
    var authorityRequests = 0;
    when(api.getViewerAuthority()).thenAnswer((_) async {
      authorityRequests++;
      if (authorityRequests == 1) {
        throw ApiException('Unavailable', statusCode: 503);
      }
      return true;
    });
    stubPublicLog(api);
    stubAdminLog([]);
    final auth = FakeAuthProvider(signedInDid: 'did:plc:admin');
    final authority = ViewerAuthorityProvider(
      apiService: api,
      authProvider: auth,
    );
    await tester.pump();
    expect(authority.status, ViewerAuthorityStatus.unavailable);

    await pumpModlog(tester, api: api, auth: auth, authority: authority);
    await pumpFrames(tester);

    verify(
      api.listAdminModerationActions(
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
        action: anyNamed('action'),
        community: anyNamed('community'),
        subject: anyNamed('subject'),
      ),
    );
    expectLogAppBar(admin: true);
  });

  testWidgets('B13 pull-to-refresh with unavailable authority asks again and '
      'loads the admin log', (tester) async {
    when(api.getViewerAuthority()).thenAnswer(
      (_) async => throw ApiException('Unavailable', statusCode: 503),
    );
    stubPublicLog(api);
    stubAdminLog([]);
    final auth = FakeAuthProvider(signedInDid: 'did:plc:admin');
    final authority = ViewerAuthorityProvider(
      apiService: api,
      authProvider: auth,
    );
    await tester.pump();

    await pumpModlog(tester, api: api, auth: auth, authority: authority);
    await pumpFrames(tester);
    expect(authority.status, ViewerAuthorityStatus.unavailable);
    expect(find.text('No moderation actions yet.'), findsOneWidget);
    verifyNever(
      api.listAdminModerationActions(
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
        action: anyNamed('action'),
        community: anyNamed('community'),
        subject: anyNamed('subject'),
      ),
    );

    when(api.getViewerAuthority()).thenAnswer((_) async => true);
    await tester.fling(
      find.text('No moderation actions yet.'),
      const Offset(0, 400),
      1000,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await pumpFrames(tester);
    await pumpFrames(tester);

    verify(
      api.listAdminModerationActions(
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
        action: anyNamed('action'),
        community: anyNamed('community'),
        subject: anyNamed('subject'),
      ),
    );
    expectLogAppBar(admin: true);
  });

  testWidgets('Modlog redesign B8 the admin log titles itself Moderation log '
      'with an Admin view pill; the public log has no pill', (tester) async {
    stubPublicLog(api);
    stubAdminLog([]);
    final (auth, authority) = await signedInAdmin(tester, api);

    final (_, release) = await pumpModlog(
      tester,
      api: api,
      auth: auth,
      authority: authority,
    );
    expect(appBarTitle('Moderation log'), findsOneWidget);
    expect(appBarTitle('Admin view'), findsOneWidget);
    expect(renderedTextContaining('(admin)'), findsNothing);
    await release();

    api = MockCovesApiService();
    stubPublicLog(api);
    final publicAuth = FakeAuthProvider();
    await pumpModlog(
      tester,
      api: api,
      auth: publicAuth,
      authority: ViewerAuthorityProvider(
        apiService: api,
        authProvider: publicAuth,
      ),
    );
    expect(appBarTitle('Moderation log'), findsOneWidget);
    expect(renderedTextContaining('Admin view'), findsNothing);
  });

  testWidgets('Modlog redesign B9 an admin restore row previews the admin '
      "log's snapshot when the public row has none", (tester) async {
    stubPublicLog(api);
    stubAdminLog([
      AdminModerationActionView(
        action: action(
          'did:web:coves.social',
          'restore',
          kind: ModerationActionKind.restore,
          reverses: const ModerationActionRef(
            serviceDid: 'did:web:coves.social',
            actionId: 'removal-not-loaded',
          ),
          subject: const ModerationSubjectRef(
            uri: 'at://did:plc:a/social.coves.community.comment/c1',
            rootUri: postSubject,
          ),
        ),
        contentSnapshot: const ModerationContentSnapshot(
          text: 'Honestly the remaster fixed the pacing',
          capturedCid: 'bafy-comment',
        ),
      ),
    ]);
    final (auth, authority) = await signedInAdmin(tester, api);

    await pumpModlog(tester, api: api, auth: auth, authority: authority);
    expect(
      find.descendant(
        of: tile('did:web:coves.social', 'restore'),
        matching: renderedText('Honestly the remaster fixed the pacing'),
      ),
      findsOneWidget,
    );
  });
}
