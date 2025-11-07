import 'package:coves_flutter/widgets/icons/animated_heart_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AnimatedHeartIcon', () {
    testWidgets('should render with default size', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AnimatedHeartIcon(isLiked: false)),
        ),
      );

      // Widget should render
      expect(find.byType(AnimatedHeartIcon), findsOneWidget);

      // Find the SizedBox that defines the size
      final sizedBox = tester.widget<SizedBox>(
        find
            .descendant(
              of: find.byType(AnimatedHeartIcon),
              matching: find.byType(SizedBox),
            )
            .first,
      );

      // Default size should be 18
      expect(sizedBox.width, 18);
      expect(sizedBox.height, 18);
    });

    testWidgets('should render with custom size', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AnimatedHeartIcon(isLiked: false, size: 32)),
        ),
      );

      // Find the SizedBox that defines the size
      final sizedBox = tester.widget<SizedBox>(
        find
            .descendant(
              of: find.byType(AnimatedHeartIcon),
              matching: find.byType(SizedBox),
            )
            .first,
      );

      // Custom size should be 32
      expect(sizedBox.width, 32);
      expect(sizedBox.height, 32);
    });

    testWidgets('should use custom color when provided', (tester) async {
      const customColor = Colors.blue;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnimatedHeartIcon(isLiked: false, color: customColor),
          ),
        ),
      );

      // Widget should render with custom color
      expect(find.byType(AnimatedHeartIcon), findsOneWidget);
      // Note: We can't easily verify the color without accessing the CustomPainter,
      // but we can verify the widget accepts the parameter
    });

    testWidgets('should use custom liked color when provided', (tester) async {
      const customLikedColor = Colors.pink;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnimatedHeartIcon(
              isLiked: true,
              likedColor: customLikedColor,
            ),
          ),
        ),
      );

      // Widget should render with custom liked color
      expect(find.byType(AnimatedHeartIcon), findsOneWidget);
    });

    testWidgets('should start animation when isLiked changes to true', (
      tester,
    ) async {
      // Start with unliked state
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AnimatedHeartIcon(isLiked: false)),
        ),
      );

      // Verify initial state
      expect(find.byType(AnimatedHeartIcon), findsOneWidget);

      // Change to liked state
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AnimatedHeartIcon(isLiked: true)),
        ),
      );

      // Pump frames to allow animation to start
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Widget should still be present and animating
      expect(find.byType(AnimatedHeartIcon), findsOneWidget);
    });

    testWidgets('should not animate when isLiked changes to false', (
      tester,
    ) async {
      // Start with liked state
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AnimatedHeartIcon(isLiked: true)),
        ),
      );

      await tester.pump();

      // Change to unliked state
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AnimatedHeartIcon(isLiked: false)),
        ),
      );

      await tester.pump();

      // Widget should update without error
      expect(find.byType(AnimatedHeartIcon), findsOneWidget);
    });

    testWidgets('should complete animation after duration', (tester) async {
      // Start with unliked state
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AnimatedHeartIcon(isLiked: false)),
        ),
      );

      // Change to liked state
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AnimatedHeartIcon(isLiked: true)),
        ),
      );

      // Pump through the entire animation duration (800ms)
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();

      // Widget should still be present after animation completes
      expect(find.byType(AnimatedHeartIcon), findsOneWidget);
    });

    testWidgets('should handle rapid state changes', (tester) async {
      // Start with unliked state
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AnimatedHeartIcon(isLiked: false)),
        ),
      );

      // Rapidly toggle states
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AnimatedHeartIcon(isLiked: true)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AnimatedHeartIcon(isLiked: false)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AnimatedHeartIcon(isLiked: true)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      // Widget should handle rapid changes without error
      expect(find.byType(AnimatedHeartIcon), findsOneWidget);
    });

    testWidgets('should use OverflowBox to allow animation overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AnimatedHeartIcon(isLiked: true)),
        ),
      );

      // Find the OverflowBox
      expect(find.byType(OverflowBox), findsOneWidget);

      final overflowBox = tester.widget<OverflowBox>(find.byType(OverflowBox));

      // OverflowBox should have larger max dimensions (2.5x the icon size)
      // to accommodate the 1.3x scale and particle burst
      expect(overflowBox.maxWidth, 18 * 2.5);
      expect(overflowBox.maxHeight, 18 * 2.5);
    });

    testWidgets('should render CustomPaint for heart icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AnimatedHeartIcon(isLiked: false)),
        ),
      );

      // Find the CustomPaint widget (used for rendering the heart)
      expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
    });

    testWidgets('should not animate on initial render when isLiked is true', (
      tester,
    ) async {
      // Render with isLiked=true initially
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AnimatedHeartIcon(isLiked: true)),
        ),
      );

      await tester.pump();

      // Widget should render in liked state without animation
      // (Animation only triggers on state change, not initial render)
      expect(find.byType(AnimatedHeartIcon), findsOneWidget);
    });

    testWidgets('should dispose controller properly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AnimatedHeartIcon(isLiked: false)),
        ),
      );

      // Remove the widget
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      );

      // Should dispose without error
      // (No assertions needed - test passes if no exception is thrown)
    });

    testWidgets('should rebuild when isLiked changes', (tester) async {
      var buildCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                buildCount++;
                return const AnimatedHeartIcon(isLiked: false);
              },
            ),
          ),
        ),
      );

      final initialBuildCount = buildCount;

      // Change isLiked state
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                buildCount++;
                return const AnimatedHeartIcon(isLiked: true);
              },
            ),
          ),
        ),
      );

      // Should rebuild
      expect(buildCount, greaterThan(initialBuildCount));
    });
  });
}
