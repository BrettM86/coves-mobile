import 'package:coves_flutter/constants/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/font_identity.dart';
import '../test_helpers/theme_pump.dart';

void main() {
  // `testWidgets`, never a plain `test`: resolving the theme touches the
  // font loader, which only stays inert inside the fake-async zone.
  testWidgets('every text style resolves one family at every weight', (
    tester,
  ) async {
    late TextStyle base;
    late TextTheme textTheme;

    await pumpUnderAppTheme(
      tester,
      Builder(
        builder: (context) {
          base = DefaultTextStyle.of(context).style;
          textTheme = Theme.of(context).textTheme;
          return const Text('x');
        },
      ),
    );

    // The app imposes no body font - it renders in the platform's own face.
    // So the contract is "we did not override Material's choice", expressed
    // against Material's own default rather than a hardcoded name: the
    // resolved family is Roboto on Android and a San Francisco variant on
    // Apple, and pinning either would make this test lie on the other.
    final family = ThemeData.dark().textTheme.bodyMedium?.fontFamily;

    expect(
      AppTypography.fontFamily,
      isNull,
      reason:
          'the app must not name a body font; null is what hands the choice '
          'to the platform',
    );

    // Exactly the family, not a variant of it. A per-weight family name is
    // the tell for a font source that registers one family per weight and
    // only ever fetches the weights Material's own type scale asks for
    // (w400 and w500) - leaving every w600/w700/w800 site to render as
    // Regular, synthetically emboldened by the rasterizer.
    expect(
      base.fontFamily,
      family,
      reason:
          'unstyled text must render in exactly $family, not a per-weight '
          'variant of it',
    );

    // A fallback naming a family nothing registered is worse than no
    // fallback: it reads like a safety net and catches nothing.
    expect(
      base.fontFamilyFallback ?? const <String>[],
      isEmpty,
      reason: 'the platform face needs no fallback list',
    );

    // Every role, not just the one an unstyled Text happens to inherit.
    final roles = <String, TextStyle?>{
      'displayLarge': textTheme.displayLarge,
      'displayMedium': textTheme.displayMedium,
      'displaySmall': textTheme.displaySmall,
      'headlineLarge': textTheme.headlineLarge,
      'headlineMedium': textTheme.headlineMedium,
      'headlineSmall': textTheme.headlineSmall,
      'titleLarge': textTheme.titleLarge,
      'titleMedium': textTheme.titleMedium,
      'titleSmall': textTheme.titleSmall,
      'bodyLarge': textTheme.bodyLarge,
      'bodyMedium': textTheme.bodyMedium,
      'bodySmall': textTheme.bodySmall,
      'labelLarge': textTheme.labelLarge,
      'labelMedium': textTheme.labelMedium,
      'labelSmall': textTheme.labelSmall,
    };
    expect(roles, hasLength(15));

    roles.forEach((name, style) {
      expect(
        rendersInFamily(style, family),
        isTrue,
        reason: '$name must render in $family, got ${style?.fontFamily}',
      );
    });

    // The heavier weights the app actually asks for, built the way a call
    // site builds them. One family has to serve all of them; a source that
    // needs a different family name per weight fails here.
    for (final weight in [FontWeight.w600, FontWeight.w700, FontWeight.w800]) {
      final bold = textTheme.titleMedium!.copyWith(fontWeight: weight);
      expect(
        rendersInFamily(bold, family),
        isTrue,
        reason:
            'asking for $weight must not change the family, got '
            '${bold.fontFamily}',
      );
      expect(bold.fontWeight, weight);
    }
  });
}
