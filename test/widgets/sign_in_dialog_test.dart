import 'package:coves_flutter/widgets/sign_in_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SignInDialog', () {
    testWidgets('should display default title and message', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () => SignInDialog.show(context),
                  child: const Text('Show Dialog'),
                );
              },
            ),
          ),
        ),
      );

      // Tap button to show dialog
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Verify default title and message
      expect(find.text('Sign in required'), findsOneWidget);
      expect(
        find.text('You need to sign in to interact with posts.'),
        findsOneWidget,
      );
    });

    testWidgets('should display custom title and message', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () => SignInDialog.show(
                    context,
                    title: 'Custom Title',
                    message: 'Custom message here',
                  ),
                  child: const Text('Show Dialog'),
                );
              },
            ),
          ),
        ),
      );

      // Tap button to show dialog
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Verify custom title and message
      expect(find.text('Custom Title'), findsOneWidget);
      expect(find.text('Custom message here'), findsOneWidget);
    });

    testWidgets('should have Cancel and Sign In buttons', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () => SignInDialog.show(context),
                  child: const Text('Show Dialog'),
                );
              },
            ),
          ),
        ),
      );

      // Tap button to show dialog
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Verify buttons exist
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
    });

    testWidgets('should return false when Cancel is tapped', (tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await SignInDialog.show(context);
                  },
                  child: const Text('Show Dialog'),
                );
              },
            ),
          ),
        ),
      );

      // Tap button to show dialog
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Tap Cancel button
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Verify result is false
      expect(result, false);

      // Dialog should be dismissed
      expect(find.text('Sign in required'), findsNothing);
    });

    testWidgets('should return true when Sign In is tapped', (tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await SignInDialog.show(context);
                  },
                  child: const Text('Show Dialog'),
                );
              },
            ),
          ),
        ),
      );

      // Tap button to show dialog
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Tap Sign In button
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      // Verify result is true
      expect(result, true);

      // Dialog should be dismissed
      expect(find.text('Sign in required'), findsNothing);
    });

    testWidgets('should dismiss when tapped outside (barrier)', (tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await SignInDialog.show(context);
                  },
                  child: const Text('Show Dialog'),
                );
              },
            ),
          ),
        ),
      );

      // Tap button to show dialog
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Tap outside the dialog (on the barrier)
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Verify result is null (dismissed without selecting an option)
      expect(result, null);

      // Dialog should be dismissed
      expect(find.text('Sign in required'), findsNothing);
    });

    testWidgets('should use app colors for styling', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () => SignInDialog.show(context),
                  child: const Text('Show Dialog'),
                );
              },
            ),
          ),
        ),
      );

      // Tap button to show dialog
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Find the AlertDialog widget
      final alertDialog = tester.widget<AlertDialog>(
        find.byType(AlertDialog),
      );

      // Verify background color is set
      expect(alertDialog.backgroundColor, isNotNull);

      // Find the Sign In button
      final signInButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Sign In'),
      );

      // Verify button styling
      expect(signInButton.style, isNotNull);
    });
  });
}
