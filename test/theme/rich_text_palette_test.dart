import 'dart:convert';

import 'package:coves_flutter/constants/app_colors.dart';
import 'package:coves_flutter/models/facet.dart';
import 'package:coves_flutter/widgets/rich_text_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// UTF-8 byte length, since facet indices are byte offsets.
int _byteLen(String s) => utf8.encode(s).length;

/// Builds a facet covering the first occurrence of [span] in [fullText].
///
/// Mirrors the helper in `test/widgets/rich_text_renderer_test.dart`.
RichTextFacet _facetOver({
  required String fullText,
  required String span,
  required List<FacetFeature> features,
}) {
  final charStart = fullText.indexOf(span);
  if (charStart == -1) {
    throw ArgumentError('span "$span" not found in fullText');
  }
  final charEnd = charStart + span.length;

  return RichTextFacet(
    index: ByteSlice(
      byteStart: _byteLen(fullText.substring(0, charStart)),
      byteEnd: _byteLen(fullText.substring(0, charEnd)),
    ),
    features: features,
  );
}

/// Pulls the inner content spans out of a rendered [RichText].
List<InlineSpan> _contentSpans(RichText richText) {
  final textSpan = richText.text as TextSpan;
  final children = textSpan.children;
  if (children == null || children.isEmpty) {
    return const [];
  }
  final first = children.first;
  if (first is TextSpan && (first.children?.isNotEmpty ?? false)) {
    return first.children!;
  }
  return children;
}

TextSpan _spanWithText(List<InlineSpan> spans, String text) {
  return spans.whereType<TextSpan>().firstWhere((s) => s.text == text);
}

void main() {
  // `testWidgets`, never a plain `test`: this renders a widget tree.
  testWidgets('link and mention facets take their color from the palette', (
    tester,
  ) async {
    const text = 'hey @alice.test see example.com ok';

    // Deliberately a BARE MaterialApp - Material's default *light* theme,
    // which is what most of this suite pumps and is nothing like the app's.
    // The contract is that these colors are palette-derived, so they must
    // hold even here; a harness using AppTheme.dark could not tell a
    // palette lookup apart from an inherited `colorScheme.primary`.
    late ColorScheme ambient;
    await tester.pumpWidget(
      // ignore: avoid_bare_material_app
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              ambient = Theme.of(context).colorScheme;
              return RichTextRenderer(
                text: text,
                facets: [
                  _facetOver(
                    fullText: text,
                    span: '@alice.test',
                    features: const [MentionFacetFeature(did: 'did:plc:abc')],
                  ),
                  _facetOver(
                    fullText: text,
                    span: 'example.com',
                    features: const [
                      LinkFacetFeature(uri: 'https://example.com'),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    // Guards the harness itself: if the ambient theme ever happened to carry
    // the palette's colors, the assertions below would stop discriminating.
    expect(ambient.brightness, Brightness.light);
    expect(ambient.primary, isNot(AppColors.textLink));
    expect(ambient.primary, isNot(AppColors.coral));

    final richText = tester.widget<RichText>(find.byType(RichText));
    final spans = _contentSpans(richText);

    expect(
      _spanWithText(spans, 'example.com').style?.color,
      AppColors.textLink,
      reason: 'links must render in the palette link color, not the theme',
    );
    expect(
      _spanWithText(spans, '@alice.test').style?.color,
      AppColors.coral,
      reason: 'mentions must render in the palette accent, not the theme',
    );
  });
}
