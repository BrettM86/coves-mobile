import 'package:coves_flutter/constants/app_colors.dart';
import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/widgets/icons/downvote_icon.dart';
import 'package:coves_flutter/widgets/icons/lucide_icon_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget harness({required bool selected, bool disableAnimations = false}) =>
    MaterialApp(
      theme: AppTheme.dark,
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Center(
          child: DownvoteIcon(
            isDownvoted: selected,
            color: selected ? AppColors.teal : Colors.grey,
          ),
        ),
      ),
    );

LucideIconPainter painter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.byType(DownvoteIcon),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter!
        as LucideIconPainter;

List<double> transformSnapshot(WidgetTester tester) => tester
    .widgetList<Transform>(
      find.descendant(
        of: find.byType(DownvoteIcon),
        matching: find.byType(Transform),
      ),
    )
    .expand((widget) => widget.transform.storage)
    .toList();

void main() {
  testWidgets('selected thumb remains outline with a stronger stroke', (
    tester,
  ) async {
    await tester.pumpWidget(harness(selected: false));
    expect(painter(tester).filled, isFalse);
    expect(painter(tester).strokeWidth, 2);
    await tester.pumpWidget(harness(selected: true));
    expect(painter(tester).filled, isFalse);
    expect(painter(tester).strokeWidth, 2.5);
    expect(painter(tester).color, AppColors.teal);
  });

  testWidgets(
    'selection animates for 240ms but initial selection and removal do not',
    (tester) async {
      await tester.pumpWidget(harness(selected: true));
      final initial = transformSnapshot(tester);
      await tester.pump(const Duration(milliseconds: 96));
      expect(transformSnapshot(tester), initial);
      await tester.pumpWidget(harness(selected: false));
      final unselected = transformSnapshot(tester);
      await tester.pump(const Duration(milliseconds: 96));
      expect(transformSnapshot(tester), unselected);
      await tester.pumpWidget(harness(selected: true));
      final rest = transformSnapshot(tester);
      await tester.pump(const Duration(milliseconds: 96));
      expect(transformSnapshot(tester), isNot(rest));
      await tester.pump(const Duration(milliseconds: 144));
      expect(transformSnapshot(tester), rest);
      // Flush the final ticker notification after the visible 240ms endpoint.
      await tester.pump(const Duration(milliseconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );

  testWidgets('reduced motion changes selection without animation', (
    tester,
  ) async {
    await tester.pumpWidget(harness(selected: false, disableAnimations: true));
    final rest = transformSnapshot(tester);
    await tester.pumpWidget(harness(selected: true, disableAnimations: true));
    final selected = transformSnapshot(tester);
    await tester.pump(const Duration(milliseconds: 96));
    expect(transformSnapshot(tester), selected);
    expect(selected, rest);
    expect(painter(tester).color, AppColors.teal);
  });
}
