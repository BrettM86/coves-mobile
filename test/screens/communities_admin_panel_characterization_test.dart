// Characterization net for CommunitiesAdminPanel, ahead of its split into a
// thin shell + admin menu + create form + avatar upload page + a shared text
// field + a pure name validator.
//
// Everything is asserted through the rendered UI, because every piece of the
// state the split will move - _currentPage, _nameError, _selectedCommunity,
// _selectedImage, _isLoadingCommunities - is private today.
//
// Two behaviours here look like bugs and are not:
//
//  * The name validator LOWERCASES before matching its regex, so an
//    uppercase name is ACCEPTED and sent lowercased, despite the error copy
//    promising "must be lowercase letters" (A3/A10).
//  * All three create-form fields share ONE listener, so typing in the
//    Description field clears an error raised against the Name field (A12).
//    Giving each extracted field its own listener destroys that.

import 'dart:async';

import 'package:coves_flutter/models/community.dart';
import 'package:coves_flutter/screens/home/communities_admin_panel.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/test_mocks.dart';

const String communityDid = 'did:plc:testcove';

CommunityView buildCommunity({
  String did = communityDid,
  String name = 'testcove',
  String displayName = 'Test Cove',
}) {
  return CommunityView(
    did: did,
    name: name,
    displayName: displayName,
    handle: '$name.coves.social',
  );
}

CreateCommunityResponse buildCreateResponse() {
  return const CreateCommunityResponse(
    uri: 'at://did:plc:new/social.coves.community/1',
    cid: 'bafycommunity',
    did: 'did:plc:new',
    handle: 'c-worldnews.coves.social',
  );
}

void main() {
  late MockCovesApiService mockApiService;

  setUp(() {
    mockApiService = MockCovesApiService();
  });

  Future<void> pumpPanel(WidgetTester tester) async {
    await tester.pumpWidget(
      Provider<CovesApiService>.value(
        value: mockApiService,
        child: const MaterialApp(home: CommunitiesAdminPanel()),
      ),
    );
    await tester.pumpAndSettle();
  }

  void stubListCommunities(List<CommunityView> communities) {
    when(
      mockApiService.listCommunities(
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
        sort: anyNamed('sort'),
        subscribed: anyNamed('subscribed'),
      ),
    ).thenAnswer((_) async => CommunitiesResponse(communities: communities));
  }

  void stubCreateCommunity() {
    when(
      mockApiService.createCommunity(
        name: anyNamed('name'),
        displayName: anyNamed('displayName'),
        description: anyNamed('description'),
        visibility: anyNamed('visibility'),
      ),
    ).thenAnswer((_) async => buildCreateResponse());
  }

  // The create form's three fields, in render order: name, display name,
  // description. Asserted to be exactly three wherever it matters.
  Finder nameField() => find.byType(TextField).at(0);
  Finder displayNameField() => find.byType(TextField).at(1);
  Finder descriptionField() => find.byType(TextField).at(2);

  Finder createButton() =>
      find.widgetWithText(ElevatedButton, 'Create Community');

  Finder backArrow() => find.byTooltip('Back');

  bool createEnabled(WidgetTester tester) =>
      tester.widget<ElevatedButton>(createButton()).onPressed != null;

  /// Opens the create form from the menu.
  Future<void> openCreateForm(WidgetTester tester) async {
    await pumpPanel(tester);
    await tester.tap(find.text('Create Community'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(3));
  }

  /// Taps submit, scrolling it into view first: the form is a
  /// SingleChildScrollView and the button sits below the fold at the test
  /// viewport size, where a tap would silently miss.
  Future<void> tapCreate(WidgetTester tester) async {
    await tester.ensureVisible(createButton());
    await tester.pumpAndSettle();
    await tester.tap(createButton());
    await tester.pumpAndSettle();
  }

  /// Fills all three fields, which is what enables the submit button.
  Future<void> fillForm(
    WidgetTester tester, {
    required String name,
    String displayName = 'World News',
    String description = 'Global news',
  }) async {
    await tester.enterText(nameField(), name);
    await tester.enterText(displayNameField(), displayName);
    await tester.enterText(descriptionField(), description);
    await tester.pumpAndSettle();
  }

  group('name validation, driven through the submit button', () {
    testWidgets('A1 the "Name is required" branch is unreachable: a blank '
        'name disables submit before the validator can run', (tester) async {
      // The submit guard requires all three fields non-empty AFTER
      // trimming, and toLowerCase() cannot empty a non-empty string, so the
      // validator's empty-name branch is dead through this widget. What is
      // observable is the guard that makes it dead. Once the validator is
      // extracted as a pure function the branch becomes directly testable;
      // it is not today.
      await openCreateForm(tester);
      await tester.enterText(displayNameField(), 'World News');
      await tester.enterText(descriptionField(), 'Global news');
      await tester.enterText(nameField(), '   ');
      await tester.pumpAndSettle();

      expect(createEnabled(tester), isFalse);
      expect(find.text('Name is required'), findsNothing);
    });

    testWidgets('A2 a name longer than 63 characters is rejected', (
      tester,
    ) async {
      await openCreateForm(tester);
      await fillForm(tester, name: 'a' * 64);

      await tapCreate(tester);

      expect(
        find.text('Name must be 63 characters or less'),
        findsOneWidget,
      );
      verifyNever(
        mockApiService.createCommunity(
          name: anyNamed('name'),
          displayName: anyNamed('displayName'),
          description: anyNamed('description'),
          visibility: anyNamed('visibility'),
        ),
      );
    });

    testWidgets('A3 an uppercase name is ACCEPTED and sent lowercased', (
      tester,
    ) async {
      // The validator lowercases before matching, so the error copy's
      // "must be lowercase letters" is a promise the code does not keep.
      stubCreateCommunity();
      await openCreateForm(tester);
      await fillForm(tester, name: 'MyCommunity');

      await tapCreate(tester);

      expect(
        find.text('Name must be lowercase letters, numbers, and hyphens only'),
        findsNothing,
      );
      verify(
        mockApiService.createCommunity(
          name: 'mycommunity',
          displayName: 'World News',
          description: 'Global news',
          visibility: anyNamed('visibility'),
        ),
      ).called(1);

      // Let the success SnackBar time out so no timer outlives the test.
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('A4 hyphens at the edges, underscores, spaces and dots are '
        'rejected', (tester) async {
      const rejected = <String>[
        '-worldnews',
        'worldnews-',
        'world_news',
        'world news',
        'world.news',
      ];

      await openCreateForm(tester);

      for (final name in rejected) {
        // Retyping clears the previous error (the shared listener), so each
        // iteration genuinely re-raises it rather than reading a stale one.
        await fillForm(tester, name: name);
        expect(
          find.text(
            'Name must be lowercase letters, numbers, and hyphens only',
          ),
          findsNothing,
          reason: 'typing should have cleared the previous error',
        );

        await tapCreate(tester);

        expect(
          find.text(
            'Name must be lowercase letters, numbers, and hyphens only',
          ),
          findsOneWidget,
          reason: '"$name" should be rejected by the charset rule',
        );
      }

      verifyNever(
        mockApiService.createCommunity(
          name: anyNamed('name'),
          displayName: anyNamed('displayName'),
          description: anyNamed('description'),
          visibility: anyNamed('visibility'),
        ),
      );
    });

    testWidgets('A5 a valid name passes and reaches the API', (tester) async {
      stubCreateCommunity();
      await openCreateForm(tester);
      // Interior hyphens and digits are fine.
      await fillForm(tester, name: 'world-news-2');

      await tapCreate(tester);

      expect(find.textContaining('Name must be'), findsNothing);
      verify(
        mockApiService.createCommunity(
          name: 'world-news-2',
          displayName: anyNamed('displayName'),
          description: anyNamed('description'),
          visibility: anyNamed('visibility'),
        ),
      ).called(1);

      await tester.pumpAndSettle(const Duration(seconds: 5));
    });
  });

  group('page routing', () {
    testWidgets('A6 the menu renders by default, with no back arrow', (
      tester,
    ) async {
      await pumpPanel(tester);

      expect(find.text('Admin Tools'), findsOneWidget);
      expect(find.text('Create Community'), findsOneWidget);
      expect(find.text('Change Profile Pic'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      // The menu is the root page: leaving is the shell's business.
      expect(backArrow(), findsNothing);
    });

    testWidgets('A7 tapping Create Community shows the form, and the in-app '
        'back arrow returns to the menu', (tester) async {
      await pumpPanel(tester);

      await tester.tap(find.text('Create Community'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNWidgets(3));
      expect(find.text('Admin Tools'), findsNothing);
      expect(backArrow(), findsOneWidget);

      await tester.tap(backArrow());
      await tester.pumpAndSettle();

      expect(find.text('Admin Tools'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(backArrow(), findsNothing);
    });

    testWidgets('A8 navigating to Change Profile Pic loads communities, and '
        're-entering while that load is in flight does not refetch', (
      tester,
    ) async {
      final inFlight = Completer<CommunitiesResponse>();
      when(
        mockApiService.listCommunities(
          limit: anyNamed('limit'),
          cursor: anyNamed('cursor'),
          sort: anyNamed('sort'),
          subscribed: anyNamed('subscribed'),
        ),
      ).thenAnswer((_) => inFlight.future);

      await pumpPanel(tester);
      await tester.tap(find.text('Change Profile Pic'));
      // pump, not pumpAndSettle: the loading spinner never stops animating.
      await tester.pump();

      expect(find.text('Change Profile Picture'), findsOneWidget);
      expect(backArrow(), findsOneWidget);
      verify(
        mockApiService.listCommunities(
          limit: anyNamed('limit'),
          cursor: anyNamed('cursor'),
          sort: anyNamed('sort'),
          subscribed: anyNamed('subscribed'),
        ),
      ).called(1);

      // Bounce back to the menu and re-enter while the first load is still
      // outstanding: the in-flight guard must swallow the second attempt.
      await tester.tap(backArrow());
      await tester.pump();
      await tester.tap(find.text('Change Profile Pic'));
      await tester.pump();

      verifyNever(
        mockApiService.listCommunities(
          limit: anyNamed('limit'),
          cursor: anyNamed('cursor'),
          sort: anyNamed('sort'),
          subscribed: anyNamed('subscribed'),
        ),
      );

      inFlight.complete(CommunitiesResponse(communities: [buildCommunity()]));
      await tester.pumpAndSettle();
      expect(find.text('Test Cove'), findsOneWidget);
    });
  });

  group('create form state', () {
    testWidgets('A9 submit stays disabled until all three fields are '
        'non-empty', (tester) async {
      await openCreateForm(tester);
      expect(createEnabled(tester), isFalse);

      await tester.enterText(nameField(), 'worldnews');
      await tester.pumpAndSettle();
      expect(createEnabled(tester), isFalse);

      await tester.enterText(displayNameField(), 'World News');
      await tester.pumpAndSettle();
      expect(createEnabled(tester), isFalse);

      await tester.enterText(descriptionField(), 'Global news');
      await tester.pumpAndSettle();
      expect(createEnabled(tester), isTrue);

      // Whitespace does not count as filled: the form trims first.
      await tester.enterText(descriptionField(), '   ');
      await tester.pumpAndSettle();
      expect(createEnabled(tester), isFalse);
    });

    testWidgets('A10 the handle preview tracks the name field and lowercases '
        'it', (tester) async {
      await openCreateForm(tester);
      expect(find.text('@c-{name}.coves.social'), findsOneWidget);

      await tester.enterText(nameField(), 'worldnews');
      await tester.pumpAndSettle();
      expect(find.text('@c-worldnews.coves.social'), findsOneWidget);

      // Same lowercasing the validator and the create call apply.
      await tester.enterText(nameField(), 'MyCove');
      await tester.pumpAndSettle();
      expect(find.text('@c-mycove.coves.social'), findsOneWidget);

      await tester.enterText(nameField(), '');
      await tester.pumpAndSettle();
      expect(find.text('@c-{name}.coves.social'), findsOneWidget);
    });

    testWidgets('A12 the three fields share one listener: typing in '
        'Description clears an error raised against Name', (tester) async {
      await openCreateForm(tester);
      await fillForm(tester, name: 'bad name');

      await tapCreate(tester);
      expect(
        find.text('Name must be lowercase letters, numbers, and hyphens only'),
        findsOneWidget,
      );

      // Type into a DIFFERENT field. One shared listener means the name
      // error clears; per-field listeners would leave it on screen.
      await tester.enterText(descriptionField(), 'Global news updated');
      await tester.pumpAndSettle();

      expect(
        find.text('Name must be lowercase letters, numbers, and hyphens only'),
        findsNothing,
      );
      // The name itself is untouched - only the error was cleared.
      expect(
        tester.widget<TextField>(nameField()).controller?.text,
        'bad name',
      );
    });
  });

  group('avatar upload page state', () {
    testWidgets('A11 going back to the menu clears the selected community', (
      tester,
    ) async {
      stubListCommunities([buildCommunity()]);
      await pumpPanel(tester);

      await tester.tap(find.text('Change Profile Pic'));
      await tester.pumpAndSettle();
      expect(find.text('Test Cove'), findsOneWidget);
      expect(find.text('Current Profile Picture'), findsNothing);

      // Selecting a community reveals its current picture section. No image
      // picker is involved, so the platform statics are never reached.
      await tester.tap(find.text('Test Cove'));
      await tester.pumpAndSettle();
      expect(find.text('Current Profile Picture'), findsOneWidget);

      await tester.tap(backArrow());
      await tester.pumpAndSettle();
      expect(find.text('Admin Tools'), findsOneWidget);

      // Re-entering starts from a clean slate.
      await tester.tap(find.text('Change Profile Pic'));
      await tester.pumpAndSettle();
      expect(find.text('Test Cove'), findsOneWidget);
      expect(find.text('Current Profile Picture'), findsNothing);
    });

    testWidgets('an empty community list renders the empty state', (
      tester,
    ) async {
      stubListCommunities(const []);
      await pumpPanel(tester);

      await tester.tap(find.text('Change Profile Pic'));
      await tester.pumpAndSettle();

      expect(find.text('No communities found'), findsOneWidget);
      expect(find.text('Current Profile Picture'), findsNothing);
    });
  });

  group('teardown', () {
    testWidgets('unmounting from any page tears down cleanly', (tester) async {
      // A controller whose dispose() is dropped by the split, or a listener
      // left attached to a disposed State, surfaces here as a thrown
      // FlutterError during finalization. Per-controller disposal is not
      // otherwise observable: all four controllers are private, and the
      // fourth (_communityHandleController) is never attached to any field.
      stubListCommunities([buildCommunity()]);

      await pumpPanel(tester);
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      expect(tester.takeException(), isNull);

      await pumpPanel(tester);
      await tester.tap(find.text('Create Community'));
      await tester.pumpAndSettle();
      await tester.enterText(nameField(), 'worldnews');
      await tester.pumpAndSettle();
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      expect(tester.takeException(), isNull);

      await pumpPanel(tester);
      await tester.tap(find.text('Change Profile Pic'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      expect(tester.takeException(), isNull);

      await tester.pumpAndSettle();
    });
  });
}
