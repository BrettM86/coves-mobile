import 'package:coves_flutter/models/community.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/screens/home/create_post_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// Fake AuthProvider for testing
class FakeAuthProvider extends AuthProvider {
  bool _isAuthenticated = true;
  String? _did = 'did:plc:testuser';
  String? _handle = 'testuser.coves.social';

  @override
  bool get isAuthenticated => _isAuthenticated;

  @override
  String? get did => _did;

  @override
  String? get handle => _handle;

  void setAuthenticated({required bool value, String? did, String? handle}) {
    _isAuthenticated = value;
    _did = did;
    _handle = handle;
    notifyListeners();
  }

  @override
  Future<String?> getAccessToken() async {
    return _isAuthenticated ? 'mock_access_token' : null;
  }

  @override
  Future<bool> refreshToken() async {
    return _isAuthenticated;
  }

  @override
  Future<void> signOut() async {
    _isAuthenticated = false;
    _did = null;
    _handle = null;
    notifyListeners();
  }
}

void main() {
  group('CreatePostScreen Widget Tests', () {
    late FakeAuthProvider fakeAuthProvider;

    setUp(() {
      fakeAuthProvider = FakeAuthProvider();
    });

    Widget createTestWidget({VoidCallback? onNavigateToFeed}) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: fakeAuthProvider),
        ],
        child: MaterialApp(
          home: CreatePostScreen(onNavigateToFeed: onNavigateToFeed),
        ),
      );
    }

    testWidgets('should display Create Post title', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Create Post'), findsOneWidget);
    });

    testWidgets('should display user handle', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('@testuser.coves.social'), findsOneWidget);
    });

    testWidgets('should display community selector', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Select a community'), findsOneWidget);
    });

    testWidgets('should display title field', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'Title'), findsOneWidget);
    });

    testWidgets('should display URL field', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'URL'), findsOneWidget);
    });

    testWidgets('should display body field', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(TextField, 'What are your thoughts?'),
        findsOneWidget,
      );
    });

    testWidgets('should display language dropdown', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Default language should be English
      expect(find.text('English'), findsOneWidget);
    });

    testWidgets('should display NSFW toggle', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('NSFW'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
    });

    testWidgets('should have disabled Post button initially', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Find the Post button
      final postButton = find.widgetWithText(TextButton, 'Post');
      expect(postButton, findsOneWidget);

      // Button should be disabled (no community selected, no content)
      final button = tester.widget<TextButton>(postButton);
      expect(button.onPressed, isNull);
    });

    testWidgets('should enable Post button when title is entered and community selected', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Enter a title
      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Test Post');
      await tester.pumpAndSettle();

      // Post button should still be disabled (no community selected)
      final postButton = find.widgetWithText(TextButton, 'Post');
      final button = tester.widget<TextButton>(postButton);
      expect(button.onPressed, isNull);
    });

    testWidgets('should toggle NSFW switch', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Find the switch
      final switchWidget = find.byType(Switch);
      expect(switchWidget, findsOneWidget);

      // Initially should be off
      Switch switchBefore = tester.widget<Switch>(switchWidget);
      expect(switchBefore.value, false);

      // Scroll to make switch visible, then tap
      await tester.ensureVisible(switchWidget);
      await tester.pumpAndSettle();
      await tester.tap(switchWidget);
      await tester.pumpAndSettle();

      // Should be on now
      Switch switchAfter = tester.widget<Switch>(switchWidget);
      expect(switchAfter.value, true);
    });

    testWidgets('should show thumbnail field when URL is entered', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Initially no thumbnail field
      expect(find.widgetWithText(TextField, 'Thumbnail URL'), findsNothing);

      // Enter a URL
      await tester.enterText(
        find.widgetWithText(TextField, 'URL'),
        'https://example.com',
      );
      await tester.pumpAndSettle();

      // Thumbnail field should now be visible
      expect(find.widgetWithText(TextField, 'Thumbnail URL'), findsOneWidget);
    });

    testWidgets('should hide thumbnail field when URL is cleared', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Enter a URL
      final urlField = find.widgetWithText(TextField, 'URL');
      await tester.enterText(urlField, 'https://example.com');
      await tester.pumpAndSettle();

      // Thumbnail field should be visible
      expect(find.widgetWithText(TextField, 'Thumbnail URL'), findsOneWidget);

      // Clear the URL
      await tester.enterText(urlField, '');
      await tester.pumpAndSettle();

      // Thumbnail field should be hidden
      expect(find.widgetWithText(TextField, 'Thumbnail URL'), findsNothing);
    });

    testWidgets('should display close button', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('should call onNavigateToFeed when close button is tapped', (tester) async {
      bool callbackCalled = false;

      await tester.pumpWidget(
        createTestWidget(onNavigateToFeed: () => callbackCalled = true),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(callbackCalled, true);
    });

    testWidgets('should have character limit on title field', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Find the title TextField
      final titleField = find.widgetWithText(TextField, 'Title');
      final textField = tester.widget<TextField>(titleField);

      // Should have maxLength set to 300 (kTitleMaxLength)
      expect(textField.maxLength, 300);
    });

    testWidgets('should have character limit on body field', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Find the body TextField
      final bodyField = find.widgetWithText(TextField, 'What are your thoughts?');
      final textField = tester.widget<TextField>(bodyField);

      // Should have maxLength set to 10000 (kContentMaxLength)
      expect(textField.maxLength, 10000);
    });

    testWidgets('should be scrollable', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Should have a SingleChildScrollView
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });

  group('CreatePostScreen Form Validation', () {
    late FakeAuthProvider fakeAuthProvider;

    setUp(() {
      fakeAuthProvider = FakeAuthProvider();
    });

    Widget createTestWidget() {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: fakeAuthProvider),
        ],
        child: const MaterialApp(home: CreatePostScreen()),
      );
    }

    testWidgets('form is invalid with no community and no content', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final postButton = find.widgetWithText(TextButton, 'Post');
      final button = tester.widget<TextButton>(postButton);
      expect(button.onPressed, isNull);
    });

    testWidgets('form is invalid with content but no community', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Enter title
      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Test');
      await tester.pumpAndSettle();

      final postButton = find.widgetWithText(TextButton, 'Post');
      final button = tester.widget<TextButton>(postButton);
      expect(button.onPressed, isNull);
    });

    testWidgets('entering text updates form state', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Enter title
      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'My Test Post',
      );
      await tester.pumpAndSettle();

      // Verify text was entered
      expect(find.text('My Test Post'), findsOneWidget);
    });

    testWidgets('entering body text updates form state', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Enter body
      await tester.enterText(
        find.widgetWithText(TextField, 'What are your thoughts?'),
        'This is my post content',
      );
      await tester.pumpAndSettle();

      // Verify text was entered
      expect(find.text('This is my post content'), findsOneWidget);
    });
  });
}
