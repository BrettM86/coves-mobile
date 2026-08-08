// RED: the contract for a second regression the admin-panel split
// introduced, this time for an in-flight create.
//
// These tests FAIL against the code as it stands. Do not soften them.
//
// Pre-split, _createCommunity ran on the panel's own State, which survives a
// page switch, so `mounted` stayed true for the whole request and the
// success block always ran.
//
// Post-split it runs on the disposable _CreateCommunityFormState. Tap back
// to the menu while createCommunity is in flight and that State is disposed,
// so `mounted` is false and create_community_form.dart:186 skips the ENTIRE
// success block: onCommunityCreated never fires (no receipt), the fields are
// never cleared, no confirmation is shown.
//
// The server call already succeeded. Because the fields still hold the
// draft, returning to the form builds a fresh State with _isSubmitting
// false, an enabled submit button, and no memory that anything was created -
// so the admin can create a DUPLICATE community.
//
// The fix has to make the outcome of a succeeded request reach the shell
// regardless of whether the page that started it is still mounted.

import 'dart:async';

import 'package:coves_flutter/models/community.dart';
import 'package:coves_flutter/screens/home/communities_admin_panel.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/test_mocks.dart';

const CreateCommunityResponse createdCommunity = CreateCommunityResponse(
  uri: 'at://did:plc:new/social.coves.community/1',
  cid: 'bafycommunity',
  did: 'did:plc:newcommunity',
  handle: 'c-worldnews.coves.social',
);

void main() {
  late MockCovesApiService mockApiService;
  late Completer<CreateCommunityResponse> gate;

  setUp(() {
    mockApiService = MockCovesApiService();
    // NOTE: `gate` is deliberately NOT created here. setUp runs outside the
    // FakeAsync zone testWidgets wraps the test body in, so a Completer
    // built here hands back a future bound to the OUTER zone - and
    // tester.pump() never flushes that queue, so the continuation lands
    // after the assertions have already run. Each test creates its own gate
    // as its first statement, inside the zone. The stub below only captures
    // the variable, so it is safe to register early.
    when(
      mockApiService.createCommunity(
        name: anyNamed('name'),
        displayName: anyNamed('displayName'),
        description: anyNamed('description'),
        visibility: anyNamed('visibility'),
      ),
    ).thenAnswer((_) => gate.future);
  });

  Finder nameField() => find.byType(TextField).at(0);
  Finder displayNameField() => find.byType(TextField).at(1);
  Finder descriptionField() => find.byType(TextField).at(2);
  Finder backArrow() => find.byTooltip('Back');
  Finder createButton() =>
      find.widgetWithText(ElevatedButton, 'Create Community');

  String textOf(WidgetTester tester, Finder field) =>
      tester.widget<TextField>(field).controller?.text ?? '';

  VerificationResult verifyCreateCalls() => verify(
        mockApiService.createCommunity(
          name: anyNamed('name'),
          displayName: anyNamed('displayName'),
          description: anyNamed('description'),
          visibility: anyNamed('visibility'),
        ),
      );

  Future<void> pumpPanel(WidgetTester tester) async {
    await tester.pumpWidget(
      Provider<CovesApiService>.value(
        value: mockApiService,
        child: const MaterialApp(home: CommunitiesAdminPanel()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Menu -> create form.
  Future<void> openCreateForm(WidgetTester tester) async {
    await tester.tap(find.text('Create Community'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(3));
  }

  /// Fills the form and submits, leaving the request in flight.
  ///
  /// Only pumps a single frame: once submitting, the button hosts a
  /// CircularProgressIndicator whose animation never settles.
  Future<void> submitAndLeaveInFlight(WidgetTester tester) async {
    await tester.enterText(nameField(), 'worldnews');
    await tester.enterText(displayNameField(), 'World News');
    await tester.enterText(descriptionField(), 'Global news');
    await tester.pumpAndSettle();

    // The submit button sits below the fold at the test viewport size.
    await tester.ensureVisible(createButton());
    await tester.pumpAndSettle();
    await tester.tap(createButton());
    await tester.pump();
  }

  /// Back to the menu, then resolve the request that is still outstanding.
  Future<void> leaveThenCompleteRequest(WidgetTester tester) async {
    await tester.tap(backArrow());
    await tester.pump();
    expect(find.text('Admin Tools'), findsOneWidget);

    gate.complete(createdCommunity);
    // Let the awaiting continuation run against the now-disposed State.
    await tester.pump();
    await tester.pump();
  }

  testWidgets('a create that succeeds after the user returned to the menu '
      'still records its receipt and clears the draft', (tester) async {
    gate = Completer<CreateCommunityResponse>();

    await pumpPanel(tester);
    await openCreateForm(tester);
    await submitAndLeaveInFlight(tester);
    await leaveThenCompleteRequest(tester);

    await openCreateForm(tester);

    // The community exists on the server; the admin's only record of that
    // is the receipt, so it must be there.
    expect(find.text('Created Communities'), findsOneWidget);
    expect(find.text(createdCommunity.handle), findsOneWidget);

    // And the draft that produced it must not still be sitting in the form
    // inviting a re-submit.
    expect(textOf(tester, nameField()), '');
    expect(textOf(tester, displayNameField()), '');
    expect(textOf(tester, descriptionField()), '');
  });

  testWidgets('retrying after a create that succeeded off-page does not '
      'create a duplicate community', (tester) async {
    gate = Completer<CreateCommunityResponse>();

    await pumpPanel(tester);
    await openCreateForm(tester);
    await submitAndLeaveInFlight(tester);
    await leaveThenCompleteRequest(tester);

    await openCreateForm(tester);

    // The admin saw no confirmation, so they try again. Whatever the form
    // chooses to do about that - disable submit, clear the draft, dedupe -
    // exactly one community may reach the server.
    await tester.ensureVisible(createButton());
    await tester.pumpAndSettle();
    await tester.tap(createButton());
    await tester.pump();

    verifyCreateCalls().called(1);
  });
}
