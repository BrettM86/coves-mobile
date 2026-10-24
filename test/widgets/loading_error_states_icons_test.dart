import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/widgets/icons/lucide_paths.dart';
import 'package:coves_flutter/widgets/loading_error_states.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/lucide_glyph_finder.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('B6c FullScreenError shows the Lucide circle-alert at 64', (
    tester,
  ) async {
    await _pump(
      tester,
      FullScreenError(message: 'Something broke', onRetry: () {}),
    );

    expectLucideGlyph(
      tester,
      within: find.byType(FullScreenError),
      paths: LucidePaths.circleAlert,
      color: const Color(0xFFFF8040),
      size: 64,
    );
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('B6c InlineError shows the Lucide circle-alert at 32', (
    tester,
  ) async {
    await _pump(
      tester,
      InlineError(message: 'Could not load more', onRetry: () {}),
    );

    expectLucideGlyph(
      tester,
      within: find.byType(InlineError),
      paths: LucidePaths.circleAlert,
      color: const Color(0xFFFF8040),
      size: 32,
    );
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });
}
