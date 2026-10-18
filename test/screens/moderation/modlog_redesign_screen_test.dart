import 'dart:async';

import 'package:coves_flutter/models/community.dart';
import 'package:coves_flutter/models/moderation.dart';
import 'package:coves_flutter/models/moderation_action.dart';
import 'package:coves_flutter/providers/viewer_authority_provider.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../test_helpers/fake_providers.dart';
import '../../test_helpers/modlog_fixtures.dart';
import '../../test_helpers/pump_helpers.dart';
import '../../test_helpers/test_mocks.dart';

const gamingDid = 'did:plc:gaming';
const artDid = 'did:plc:art';
const unresolvableDid = 'did:plc:unresolvable-community';
const postUri = 'at://did:plc:author/social.coves.community.post/p1';

ModerationSubjectRef postIn(String communityDid) =>
    ModerationSubjectRef(uri: postUri, communityDid: communityDid);

ModerationScope communityScope(String communityDid) => ModerationScope(
  kind: ModerationScopeKind.community,
  communityDid: communityDid,
);

void stubCommunities(MockCovesApiService api) {
  when(api.getCommunity(community: gamingDid)).thenAnswer(
    (_) async =>
        CommunityView(did: gamingDid, name: 'gaming', origin: 'coves.social'),
  );
  when(api.getCommunity(community: artDid)).thenAnswer(
    (_) async =>
        CommunityView(did: artDid, name: 'art', origin: 'coves.social'),
  );
  when(api.getCommunity(community: unresolvableDid)).thenAnswer(
    (_) async => throw ApiException('Community not found', statusCode: 404),
  );
}

/// Whether [row] renders [text] as one run.
Finder inRow(Finder row, String text) =>
    find.descendant(of: row, matching: renderedText(text));

/// The community picker lists one community, [community], whose row reads
/// its description.
void stubCommunityPicker(MockCovesApiService api, CommunityView community) {
  when(
    api.listCommunities(
      limit: anyNamed('limit'),
      cursor: anyNamed('cursor'),
      sort: anyNamed('sort'),
      subscribed: anyNamed('subscribed'),
    ),
  ).thenAnswer((_) async => CommunitiesResponse(communities: [community]));
}

/// Opens the community picker and chooses the row reading [description].
Future<void> pickCommunity(WidgetTester tester, String description) async {
  await tester.tap(find.text('Community'));
  await pumpFrames(tester);
  await tester.tap(find.text(description));
  await pumpFrames(tester);
}

/// Signed-out viewer, so the screen reads the public log.
(FakeAuthProvider, ViewerAuthorityProvider) signedOut(MockCovesApiService api) {
  final auth = FakeAuthProvider();
  return (auth, ViewerAuthorityProvider(apiService: api, authProvider: auth));
}

void main() {
  late MockCovesApiService api;

  setUp(() => api = MockCovesApiService());

  testWidgets('Modlog redesign B5 rows name their community once per DID, '
      'subject first, then scope, and an unresolvable community shows '
      'nothing', (tester) async {
    stubCommunities(api);
    when(
      api.listModerationActions(
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
        action: anyNamed('action'),
        community: anyNamed('community'),
        subject: anyNamed('subject'),
      ),
    ).thenAnswer(
      (invocation) async => switch (invocation.namedArguments[#cursor]) {
        null => ModerationActionPage(
          actions: [
            action(
              'did:web:coves.social',
              'gaming-1',
              subject: postIn(gamingDid),
            ),
            action(
              'did:web:coves.social',
              'gaming-2',
              subject: postIn(gamingDid),
            ),
            action(
              'did:web:coves.social',
              'subject-over-scope',
              subject: postIn(gamingDid),
              scope: communityScope(artDid),
            ),
            action(
              'did:web:coves.social',
              'scope-only',
              scope: communityScope(artDid),
            ),
            action(
              'did:web:coves.social',
              'unresolvable',
              subject: postIn(unresolvableDid),
            ),
          ],
          cursor: 'c2',
        ),
        'c2' => ModerationActionPage(
          actions: [
            action(
              'did:web:coves.social',
              'gaming-3',
              subject: postIn(gamingDid),
            ),
          ],
        ),
        _ => throw StateError('Unexpected moderation cursor'),
      },
    );
    final (auth, authority) = signedOut(api);

    await pumpModlog(tester, api: api, auth: auth, authority: authority);
    final scrollView = find.byType(CustomScrollView);
    for (final actionId in ['gaming-1', 'gaming-2', 'subject-over-scope']) {
      final row = tile('did:web:coves.social', actionId);
      expect(
        inRow(row, '!gaming@coves.social'),
        findsOneWidget,
        reason: actionId,
      );
      expect(inRow(row, '!art@coves.social'), findsNothing, reason: actionId);
    }
    expect(
      inRow(tile('did:web:coves.social', 'scope-only'), '!art@coves.social'),
      findsOneWidget,
    );
    final unresolvable = tile('did:web:coves.social', 'unresolvable');
    expect(unresolvable, findsOneWidget);
    expect(
      find.descendant(of: unresolvable, matching: renderedTextContaining('!')),
      findsNothing,
    );
    expect(renderedTextContaining(unresolvableDid), findsNothing);

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.drag(scrollView, const Offset(0, -4000));
    await pumpFrames(tester);
    verify(
      api.listModerationActions(
        cursor: 'c2',
        limit: anyNamed('limit'),
        action: anyNamed('action'),
        community: anyNamed('community'),
        subject: anyNamed('subject'),
      ),
    ).called(1);
    expect(
      inRow(tile('did:web:coves.social', 'gaming-3'), '!gaming@coves.social'),
      findsOneWidget,
    );
    expect(renderedTextContaining(unresolvableDid), findsNothing);
    // One lookup per distinct community DID for the whole screen.
    verify(api.getCommunity(community: gamingDid)).called(1);
  });

  testWidgets('Modlog redesign B5 an admin row names the community of its '
      'private subject when the public subject is withheld, and the public '
      'subject still wins', (tester) async {
    stubCommunities(api);
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
      (_) async => AdminModerationActionPage(
        actions: [
          AdminModerationActionView(
            action: action(
              'did:web:coves.social',
              'private-over-scope',
              scope: communityScope(gamingDid),
            ),
            privateSubject: postIn(artDid),
          ),
          AdminModerationActionView(
            action: action(
              'did:web:coves.social',
              'public-over-private',
              subject: postIn(gamingDid),
            ),
            privateSubject: postIn(artDid),
          ),
        ],
      ),
    );
    final (auth, authority) = await signedInAdmin(tester, api);

    await pumpModlog(tester, api: api, auth: auth, authority: authority);
    final privateOverScope = tile('did:web:coves.social', 'private-over-scope');
    expect(inRow(privateOverScope, '!art@coves.social'), findsOneWidget);
    expect(inRow(privateOverScope, '!gaming@coves.social'), findsNothing);
    final publicOverPrivate = tile(
      'did:web:coves.social',
      'public-over-private',
    );
    expect(inRow(publicOverPrivate, '!gaming@coves.social'), findsOneWidget);
    expect(inRow(publicOverPrivate, '!art@coves.social'), findsNothing);
  });

  testWidgets('Modlog redesign B6 rows sit under local day headers from the '
      'injected clock, continued across a later page', (tester) async {
    // A year away from the host clock, so a header computed from the real
    // time can never pass by coincidence.
    final now = DateTime(2025, 10, 15, 12);
    final secondPage = Completer<ModerationActionPage>();
    addTearDown(() {
      if (!secondPage.isCompleted) {
        secondPage.complete(const ModerationActionPage(actions: []));
      }
    });
    when(
      api.listModerationActions(
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
        action: anyNamed('action'),
        community: anyNamed('community'),
        subject: anyNamed('subject'),
      ),
    ).thenAnswer(
      (invocation) => switch (invocation.namedArguments[#cursor]) {
        null => Future.value(
          ModerationActionPage(
            actions: [
              action(
                'did:web:coves.social',
                'today-9',
                createdAt: DateTime(2025, 10, 15, 9),
              ),
              action(
                'did:web:coves.social',
                'today-8',
                createdAt: DateTime(2025, 10, 15, 8),
              ),
              action(
                'did:web:coves.social',
                'oct12-9',
                createdAt: DateTime(2025, 10, 12, 9),
              ),
            ],
            cursor: 'c2',
          ),
        ),
        'c2' => secondPage.future,
        _ => throw StateError('Unexpected moderation cursor'),
      },
    );
    final (auth, authority) = signedOut(api);

    await pumpModlog(
      tester,
      api: api,
      auth: auth,
      authority: authority,
      clock: () => now,
    );
    final today9 = tile('did:web:coves.social', 'today-9');
    final today8 = tile('did:web:coves.social', 'today-8');
    final oct12at9 = tile('did:web:coves.social', 'oct12-9');
    final todayHeader = renderedText('Today');
    final oct12Header = renderedText('Oct 12');
    double top(Finder finder) => tester.getTopLeft(finder).dy;
    double bottom(Finder finder) => tester.getBottomLeft(finder).dy;

    expect(todayHeader, findsOneWidget);
    expect(oct12Header, findsOneWidget);
    expect(bottom(todayHeader), lessThanOrEqualTo(top(today9)));
    expect(bottom(today9), lessThanOrEqualTo(top(today8)));
    expect(bottom(today8), lessThanOrEqualTo(top(oct12Header)));
    expect(bottom(oct12Header), lessThanOrEqualTo(top(oct12at9)));

    // The short first page asked for the next one, which is still held.
    verify(
      api.listModerationActions(
        cursor: 'c2',
        limit: anyNamed('limit'),
        action: anyNamed('action'),
        community: anyNamed('community'),
        subject: anyNamed('subject'),
      ),
    ).called(1);
    secondPage.complete(
      ModerationActionPage(
        actions: [
          action(
            'did:web:coves.social',
            'oct12-8',
            createdAt: DateTime(2025, 10, 12, 8),
          ),
          action(
            'did:web:coves.social',
            'oct11-9',
            createdAt: DateTime(2025, 10, 11, 9),
          ),
        ],
      ),
    );
    await pumpFrames(tester);
    final oct12at8 = tile('did:web:coves.social', 'oct12-8');
    final oct11at9 = tile('did:web:coves.social', 'oct11-9');
    final oct11Header = renderedText('Oct 11');
    expect(oct12at9, findsOneWidget);
    expect(oct12at8, findsOneWidget);
    // The page boundary falls inside Oct 12: no second header between them.
    expect(oct12Header, findsOneWidget);
    expect(bottom(oct12at9), lessThanOrEqualTo(top(oct12at8)));
    expect(oct11Header, findsOneWidget);
    expect(bottom(oct12at8), lessThanOrEqualTo(top(oct11Header)));
    expect(bottom(oct11Header), lessThanOrEqualTo(top(oct11at9)));
  });

  testWidgets('Modlog redesign B7 the action filter is a menu of All actions, '
      'Removals and Restores that reloads the log', (tester) async {
    final calls = <Map<Symbol, dynamic>>[];
    when(
      api.listModerationActions(
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
        action: anyNamed('action'),
        community: anyNamed('community'),
        subject: anyNamed('subject'),
      ),
    ).thenAnswer((invocation) async {
      calls.add(invocation.namedArguments);
      return ModerationActionPage(
        actions: [action('did:web:coves.social', 'row-${calls.length}')],
      );
    });
    final (auth, authority) = signedOut(api);

    await pumpModlog(tester, api: api, auth: auth, authority: authority);
    expect(calls, hasLength(1));
    expect(find.text('All actions'), findsOneWidget);
    expect(find.text('Removals'), findsNothing);
    expect(find.text('Restores'), findsNothing);

    await tester.tap(find.text('All actions'));
    await pumpFrames(tester);
    expect(find.text('All actions'), findsWidgets);
    expect(find.text('Removals'), findsOneWidget);
    expect(find.text('Restores'), findsOneWidget);
    expect(calls, hasLength(1));

    await tester.tap(find.text('Removals'));
    await pumpFrames(tester);
    expect(calls, hasLength(2));
    expect((calls.last[#cursor], calls.last[#action]), (null, 'remove'));
    expect(find.text('Removals'), findsOneWidget);
    expect(find.text('All actions'), findsNothing);
    expect(find.text('Restores'), findsNothing);
    expect(tile('did:web:coves.social', 'row-2'), findsOneWidget);

    await chooseActionFilter(tester, from: 'Removals', to: 'All actions');
    expect(calls, hasLength(3));
    expect((calls.last[#cursor], calls.last[#action]), (null, null));
    expect(find.text('All actions'), findsOneWidget);
    expect(find.text('Removals'), findsNothing);
    expect(tile('did:web:coves.social', 'row-3'), findsOneWidget);
  });

  testWidgets('Modlog review R2 the filter row fits a 320px window at 2x '
      'text with a long community handle and Removals chosen', (tester) async {
    stubCommunityPicker(
      api,
      CommunityView(
        did: 'did:plc:long',
        name: 'averyveryverylongcommunityname',
        origin: 'coves.social',
        description: 'long row',
      ),
    );
    stubPublicLog(api);
    final (auth, authority) = signedOut(api);

    await pumpModlog(tester, api: api, auth: auth, authority: authority);
    tester.view.physicalSize = const Size(320, 700);
    await pumpFrames(tester);
    await chooseActionFilter(tester, from: 'All actions', to: 'Removals');
    await pickCommunity(tester, 'long row');
    expect(
      find.text('!averyveryverylongcommunityname@coves.social'),
      findsOneWidget,
    );

    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpFrames(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Removals').hitTestable(), findsOneWidget);
    expect(
      find.byTooltip('Clear community filter').hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('Modlog review R3 pull-to-refresh retries a failed community '
      'lookup and does not refetch a successful one', (tester) async {
    var gamingLookups = 0;
    when(api.getCommunity(community: gamingDid)).thenAnswer((_) async {
      gamingLookups++;
      if (gamingLookups == 1) {
        throw ApiException('Service unavailable', statusCode: 503);
      }
      return CommunityView(
        did: gamingDid,
        name: 'gaming',
        origin: 'coves.social',
      );
    });
    when(api.getCommunity(community: artDid)).thenAnswer(
      (_) async =>
          CommunityView(did: artDid, name: 'art', origin: 'coves.social'),
    );
    when(
      api.listModerationActions(
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
        action: anyNamed('action'),
        community: anyNamed('community'),
        subject: anyNamed('subject'),
      ),
    ).thenAnswer(
      (_) async => ModerationActionPage(
        actions: [
          action('did:web:coves.social', 'gaming', subject: postIn(gamingDid)),
          action('did:web:coves.social', 'art', subject: postIn(artDid)),
        ],
      ),
    );
    final (auth, authority) = signedOut(api);

    await pumpModlog(tester, api: api, auth: auth, authority: authority);
    final gamingRow = tile('did:web:coves.social', 'gaming');
    final artRow = tile('did:web:coves.social', 'art');
    expect(gamingRow, findsOneWidget);
    expect(
      find.descendant(of: gamingRow, matching: renderedTextContaining('!')),
      findsNothing,
    );
    expect(inRow(artRow, '!art@coves.social'), findsOneWidget);

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 400),
      1000,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await pumpFrames(tester);
    await pumpFrames(tester);
    verify(
      api.listModerationActions(
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
        action: anyNamed('action'),
        community: anyNamed('community'),
        subject: anyNamed('subject'),
      ),
    ).called(2);

    expect(inRow(gamingRow, '!gaming@coves.social'), findsOneWidget);
    expect(inRow(artRow, '!art@coves.social'), findsOneWidget);
    // One successful lookup per community DID for the whole screen.
    verify(api.getCommunity(community: artDid)).called(1);
  });

  testWidgets('Modlog review R5 the clear community filter button has a '
      '48x48 hit area', (tester) async {
    stubCommunityPicker(
      api,
      CommunityView(
        did: gamingDid,
        name: 'gaming',
        origin: 'coves.social',
        description: 'gaming row',
      ),
    );
    stubPublicLog(api);
    final (auth, authority) = signedOut(api);

    await pumpModlog(tester, api: api, auth: auth, authority: authority);
    await pickCommunity(tester, 'gaming row');
    final clear = find.byTooltip('Clear community filter');
    expect(clear, findsOneWidget);
    final hitArea = tester.getSize(clear);
    expect(hitArea.width, greaterThanOrEqualTo(48));
    expect(hitArea.height, greaterThanOrEqualTo(48));
  });

  testWidgets('Modlog review R6 the action filter, the Community filter and '
      'the active community label each have a 48px-tall hit area', (
    tester,
  ) async {
    stubCommunityPicker(
      api,
      CommunityView(
        did: gamingDid,
        name: 'gaming',
        origin: 'coves.social',
        description: 'gaming row',
      ),
    );
    stubPublicLog(api);
    final (auth, authority) = signedOut(api);

    await pumpModlog(tester, api: api, auth: auth, authority: authority);
    // The semantics rects of these controls take in surrounding padding, so
    // measure the ink well that receives the tap.
    void expectTallHitArea(String label) {
      final text = find.text(label);
      expect(text, findsOneWidget, reason: label);
      final inkWell = find
          .ancestor(of: text, matching: find.byType(InkWell))
          .first;
      expect(
        tester.getSize(inkWell).height,
        greaterThanOrEqualTo(48),
        reason: '$label hit area',
      );
    }

    expectTallHitArea('All actions');
    expectTallHitArea('Community');
    await pickCommunity(tester, 'gaming row');
    expectTallHitArea('!gaming@coves.social');
  });

  testWidgets('Modlog review R7 the active community label reads as the '
      'community filter', (tester) async {
    stubCommunityPicker(
      api,
      CommunityView(
        did: gamingDid,
        name: 'gaming',
        origin: 'coves.social',
        description: 'gaming row',
      ),
    );
    stubPublicLog(api);
    final (auth, authority) = signedOut(api);
    final handle = tester.ensureSemantics();

    await pumpModlog(tester, api: api, auth: auth, authority: authority);
    await pickCommunity(tester, 'gaming row');
    final filter = find.bySemanticsLabel(RegExp('Community filter'));
    expect(filter, findsOneWidget);
    final data = tester.getSemantics(filter).getSemanticsData();
    expect('${data.label} ${data.value}', contains('!gaming@coves.social'));
    handle.dispose();
  });
}
