// The admin panel's create-form draft and receipt list must survive a trip
// to the menu.
//
// CreateCommunityForm is built only while the shell's current page is
// AdminPage.createCommunity, so its State is disposed on every back-tap.
// Anything the form owned outright would be thrown away the moment the admin
// glanced at the menu. Two things must not be:
//
//   * the in-progress draft (the three text controllers), and
//   * the green "Created Communities" receipts, which are the admin's only
//     record that a community was created.
//
// Both therefore live on the panel shell, which outlives the page, and are
// passed down. These tests pin that ownership split from the outside: they
// never name the shell's fields, only the behaviour a user would notice.
//
// This is the boundary a future refactor is most likely to get wrong again -
// moving either back into the form reads like tidying up and silently
// destroys work the admin has done.

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

  setUp(() {
    mockApiService = MockCovesApiService();
    when(
      mockApiService.createCommunity(
        name: anyNamed('name'),
        displayName: anyNamed('displayName'),
        description: anyNamed('description'),
        visibility: anyNamed('visibility'),
      ),
    ).thenAnswer((_) async => createdCommunity);
  });

  Finder nameField() => find.byType(TextField).at(0);
  Finder displayNameField() => find.byType(TextField).at(1);
  Finder descriptionField() => find.byType(TextField).at(2);
  Finder backArrow() => find.byTooltip('Back');
  Finder createButton() =>
      find.widgetWithText(ElevatedButton, 'Create Community');

  String textOf(WidgetTester tester, Finder field) =>
      tester.widget<TextField>(field).controller?.text ?? '';

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

  /// Create form -> menu, via the in-app back arrow.
  Future<void> tapBack(WidgetTester tester) async {
    await tester.tap(backArrow());
    await tester.pumpAndSettle();
    expect(find.text('Admin Tools'), findsOneWidget);
  }

  testWidgets('a half-typed draft survives a trip to the menu and back', (
    tester,
  ) async {
    await pumpPanel(tester);
    await openCreateForm(tester);

    await tester.enterText(nameField(), 'worldnews');
    await tester.enterText(displayNameField(), 'World News');
    await tester.enterText(descriptionField(), 'Global news');
    await tester.pumpAndSettle();

    await tapBack(tester);
    await openCreateForm(tester);

    // The user stepped out to the menu for a moment; their draft must not
    // have been thrown away.
    expect(textOf(tester, nameField()), 'worldnews');
    expect(textOf(tester, displayNameField()), 'World News');
    expect(textOf(tester, descriptionField()), 'Global news');
  });

  testWidgets('the created-communities receipt survives a trip to the menu '
      'and back', (tester) async {
    await pumpPanel(tester);
    await openCreateForm(tester);

    await tester.enterText(nameField(), 'worldnews');
    await tester.enterText(displayNameField(), 'World News');
    await tester.enterText(descriptionField(), 'Global news');
    await tester.pumpAndSettle();

    await tester.ensureVisible(createButton());
    await tester.pumpAndSettle();
    await tester.tap(createButton());
    // Let the success SnackBar come and go.
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(find.text('Created Communities'), findsOneWidget);
    expect(find.text(createdCommunity.handle), findsOneWidget);

    await tapBack(tester);
    await openCreateForm(tester);

    // The receipt is the only record the admin has that the community was
    // created; it must not vanish because they looked at the menu.
    expect(find.text('Created Communities'), findsOneWidget);
    expect(find.text(createdCommunity.handle), findsOneWidget);
  });
}
