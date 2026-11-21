import 'dart:convert';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/facet.dart';
import 'package:coves_flutter/widgets/rich_text_renderer.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

/// Global rect covering [word] inside the paragraph starting with [prefix].
Rect _wordRect(WidgetTester tester, String prefix, String word) {
  final finder = find.byWidgetPredicate(
    (widget) =>
        widget is RichText &&
        widget.text
            .toPlainText(includeSemanticsLabels: false)
            .startsWith(prefix),
  );
  expect(finder, findsOneWidget, reason: 'paragraph starting "$prefix"');
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final plain = paragraph.text.toPlainText(includeSemanticsLabels: false);
  final start = plain.indexOf(word);
  expect(start, isNonNegative, reason: '"$word" not in "$plain"');
  final local = paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: start + word.length),
      )
      .map((box) => box.toRect())
      .reduce((a, b) => a.expandToInclude(b));
  return local.shift(paragraph.localToGlobal(Offset.zero));
}

/// Taps a toolbar button, asserting it is on screen first, then waits past
/// the double-tap timeout so a following tap is not read as a double tap.
Future<void> _tapToolbar(WidgetTester tester, String label) async {
  expect(find.text(label), findsOneWidget, reason: 'toolbar "$label"');
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
  await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 1));
}

void main() {
  final android = TargetPlatformVariant.only(TargetPlatform.android);

  final cases =
      <
        ({
          String name,
          String text,
          List<RichTextFacet> facets,
          bool revealFirst,
          String expected,
        })
      >[
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
          revealFirst: false,
          expected: 'The ending is xxxxxxx',
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
          revealFirst: false,
          expected: 'The ending is\nsled = xxxxxxx\nend',
        ),
        (
          name: 'inline spoiler revealed by a tap',
          text: 'The ending is Rosebud',
          facets: [
            _facetOver(
              fullText: 'The ending is Rosebud',
              span: 'Rosebud',
              features: const [SpoilerFacetFeature()],
            ),
          ],
          revealFirst: true,
          expected: 'The ending is Rosebud',
        ),
      ];

  for (final c in cases) {
    testWidgets('Select all + Copy puts exactly the shown text on the '
        'clipboard (${c.name})', (tester) async {
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

      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
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
      await tester.pump();

      if (c.revealFirst) {
        await tester.tapAt(
          _wordRect(tester, 'The ending is', 'xxxxxxx').center,
        );
        await tester.pumpAndSettle();
        await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 1));
      }

      await tester.longPressAt(
        _wordRect(tester, 'The ending is', 'ending').center,
      );
      await tester.pumpAndSettle();
      await _tapToolbar(tester, 'Select all');
      await _tapToolbar(tester, 'Copy');

      expect(copied, [c.expected]);
    }, variant: android);
  }
}
