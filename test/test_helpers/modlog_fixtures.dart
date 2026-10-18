import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/moderation.dart';
import 'package:coves_flutter/models/moderation_action.dart';
import 'package:coves_flutter/providers/viewer_authority_provider.dart';
import 'package:coves_flutter/screens/moderation/modlog_screen.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/profile_cache.dart';
import 'package:coves_flutter/widgets/moderation/modlog_entry_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'fake_providers.dart';
import 'pump_helpers.dart';
import 'test_mocks.dart';

/// A public modlog row at instance scope, as the AppView returns it.
/// [origin] is 'local' unless the row came from another moderation service.
ModerationActionView action(
  String serviceDid,
  String actionId, {
  ModerationActionKind kind = ModerationActionKind.remove,
  ModerationReason? reason,
  DateTime? createdAt,
  String? actorDid,
  ModerationActionRef? reverses,
  ModerationSubjectRef? subject,
  String origin = 'local',
  ModerationContentSnapshot? contentSnapshot,
  ModerationScope scope = const ModerationScope(
    kind: ModerationScopeKind.instance,
  ),
}) => ModerationActionView(
  ref: ModerationActionRef(serviceDid: serviceDid, actionId: actionId),
  action: kind,
  reason: reason,
  actorDid: actorDid,
  reverses: reverses,
  subject: subject,
  contentSnapshot: contentSnapshot,
  createdAt: createdAt ?? DateTime.utc(2026, 10, 1, 12),
  authorityDid: 'did:web:coves.social',
  scope: scope,
  origin: origin,
);

/// Text rendered as one run, whether by a Text, a Text.rich or a RichText.
Finder renderedText(String text) => find.byWidgetPredicate(
  (widget) => widget is RichText && widget.text.toPlainText() == text,
  description: 'rendered text "$text"',
);

/// Any rendered run of text that contains [fragment].
Finder renderedTextContaining(String fragment) => find.byWidgetPredicate(
  (widget) =>
      widget is RichText && widget.text.toPlainText().contains(fragment),
  description: 'rendered text containing "$fragment"',
);

/// Opens the action filter, which currently reads [from], and chooses the
/// [to] entry from its menu.
Future<void> chooseActionFilter(
  WidgetTester tester, {
  required String from,
  required String to,
}) async {
  final control = find.text(from);
  expect(control, findsOneWidget, reason: 'action filter reading "$from"');
  await tester.tap(control);
  await pumpFrames(tester);
  final choice = find.text(to);
  expect(choice, findsWidgets, reason: 'action filter menu entry "$to"');
  await tester.tap(choice.last);
  await pumpFrames(tester);
}

/// The modlog tile showing the row with this ref.
Finder tile(String serviceDid, String actionId) => find.byWidgetPredicate(
  (widget) =>
      widget is ModlogEntryTile &&
      widget.action.ref.serviceDid == serviceDid &&
      widget.action.ref.actionId == actionId,
);

/// Answers every public-log request with an empty page.
void stubPublicLog(MockCovesApiService api) {
  when(
    api.listModerationActions(
      cursor: anyNamed('cursor'),
      limit: anyNamed('limit'),
      action: anyNamed('action'),
      community: anyNamed('community'),
      subject: anyNamed('subject'),
    ),
  ).thenAnswer((_) async => const ModerationActionPage(actions: []));
}

/// Pumps ModlogScreen at '/' with a '/post/:postUri' destination that
/// prints its location. Returns a callback that unmounts the screen and
/// disposes the auth, authority and profile cache.
Future<(GoRouter, Future<void> Function())> pumpModlog(
  WidgetTester tester, {
  required CovesApiService api,
  required FakeAuthProvider auth,
  required ViewerAuthorityProvider authority,
  String? subject,
  DateTime Function()? clock,
}) async {
  tester.view.physicalSize = const Size(400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final cache = ProfileCache(auth);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => ModlogScreen(subject: subject, clock: clock),
      ),
      GoRoute(
        path: '/post/:postUri',
        builder: (_, state) => Scaffold(body: Text('post:${state.uri}')),
      ),
    ],
  );
  var disposed = false;
  void disposeAll() {
    if (disposed) {
      return;
    }
    disposed = true;
    router.dispose();
    authority.dispose();
    cache.dispose();
    auth.dispose();
  }

  Future<void> release() async {
    await tester.pumpWidget(const SizedBox());
    disposeAll();
  }

  addTearDown(disposeAll);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<CovesApiService>.value(value: api),
        Provider<ProfileCache>.value(value: cache),
        ChangeNotifierProvider<ViewerAuthorityProvider>.value(value: authority),
      ],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    ),
  );
  await pumpFrames(tester);
  return (router, release);
}

/// A signed-in instance admin whose authority has already loaded.
Future<(FakeAuthProvider, ViewerAuthorityProvider)> signedInAdmin(
  WidgetTester tester,
  MockCovesApiService api,
) async {
  when(api.getViewerAuthority()).thenAnswer((_) async => true);
  final auth = FakeAuthProvider(
    signedInDid: 'did:plc:admin',
    signedInHandle: 'admin.coves.social',
  );
  final authority = ViewerAuthorityProvider(
    apiService: api,
    authProvider: auth,
  );
  await tester.pump();
  expect(authority.status, ViewerAuthorityStatus.instanceAdmin);
  return (auth, authority);
}
