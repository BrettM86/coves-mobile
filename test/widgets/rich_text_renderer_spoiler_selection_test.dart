import 'dart:convert';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/facet.dart';
import 'package:coves_flutter/widgets/rich_text_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

int _byteLen(String s) => utf8.encode(s).length;

RichTextFacet _facetOver({
  required String fullText,
  required String span,
  required List<FacetFeature> features,
}) {
  final charStart = fullText.indexOf(span);
  final byteStart = _byteLen(fullText.substring(0, charStart));
  final byteEnd = byteStart + _byteLen(span);
  return RichTextFacet(
    index: ByteSlice(byteStart: byteStart, byteEnd: byteEnd),
    features: features,
  );
}

void main() {
  final cases = <({String name, String text, List<RichTextFacet> facets})>[
    (
      name: 'inline spoiler',
      text: 'The ending is Rosebud',
      facets: [
        _facetOver(
          fullText: 'The ending is Rosebud',
          span: 'Rosebud',
          features: const [SpoilerFacetFeature()],
        ),
      ],
    ),
    (
      name: 'spoiler inside a code block',
      text: 'The ending is\nsled = Rosebud\nend',
      facets: [
        _facetOver(
          fullText: 'The ending is\nsled = Rosebud\nend',
          span: 'sled = Rosebud',
          features: const [CodeBlockFacetFeature()],
        ),
        _facetOver(
          fullText: 'The ending is\nsled = Rosebud\nend',
          span: 'Rosebud',
          features: const [SpoilerFacetFeature()],
        ),
      ],
    ),
  ];

  for (final c in cases) {
    testWidgets(
      'Select all + Copy does not put an unrevealed spoiler on the clipboard '
      '(${c.name})',
      (tester) async {
        final copied = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (methodCall) async {
            if (methodCall.method == 'Clipboard.setData') {
              final args = methodCall.arguments as Map<Object?, Object?>;
              copied.add(args['text']! as String);
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(
              body: SelectionArea(
                child: RichTextRenderer(text: c.text, facets: c.facets),
              ),
            ),
          ),
        );

        final visible = find.byWidgetPredicate(
          (widget) =>
              widget is RichText &&
              widget.text.toPlainText().startsWith('The ending is'),
        );
        await tester.longPressAt(
          tester.getTopLeft(visible) + const Offset(8, 8),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Select all'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Copy'));
        await tester.pumpAndSettle();

        expect(copied, hasLength(1));
        expect(copied.single, contains('The ending is'));
        expect(copied.single, isNot(contains('Rosebud')));
      },
    );
  }
}
