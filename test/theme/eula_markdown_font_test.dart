import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/screens/eula_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/font_identity.dart';

/// The family Material resolves for this platform when no font is bundled.
///
/// The app names no body font, so the correct expectation is "whatever the
/// platform provides" - Roboto on Android, a San Francisco variant on Apple.
/// Comparing against Material's own default keeps this honest on both rather
/// than hardcoding one and lying on the other.
String? get _platformFamily =>
    ThemeData.dark().textTheme.bodyMedium?.fontFamily;

void main() {
  // `testWidgets`, never a plain `test`: this pumps a screen and resolves
  // fonts, which google_fonts only tolerates inside the fake-async zone.
  testWidgets('the EULA renders its legal text in the app font', (
    tester,
  ) async {
    // The real screen, the real asset, the real Markdown widget. `viewOnly`
    // skips the accept flow, which is the only part that needs a provider.
    // EulaScreen brings its own Scaffold, so this pumps the app theme
    // directly rather than through `pumpUnderAppTheme`.
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark, home: const EulaScreen(viewOnly: true)),
    );
    await tester.pumpAndSettle();

    final markdown = find.byType(Markdown);
    expect(
      markdown,
      findsOneWidget,
      reason: 'assets/legal/eula.md did not load - the screen is showing its '
          'error or loading state, so nothing below is being measured',
    );

    final spans = renderedSpans(tester, markdown);
    // Cheap insurance against a green that means "nothing rendered".
    expect(spans.length, greaterThan(5), reason: 'legal text looks empty');

    // Markdown is the one place the "anonymous styles inherit the family"
    // assumption is worth checking rather than assuming: MarkdownStyleSheet
    // hands its styles straight to the spans, so a family named there wins
    // over the theme, and a family *missing* there has to fall through to
    // the ambient DefaultTextStyle to come out right. Asserting on what the
    // spans actually resolved covers both.
    for (final span in spans) {
      expect(
        rendersInFamily(span.style, _platformFamily),
        isTrue,
        reason:
            'legal text must render in $_platformFamily, but '
            '$span resolved fontFamily=${span.style?.fontFamily} '
            'fallback=${span.style?.fontFamilyFallback}',
      );
    }
  });
}
