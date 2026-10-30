import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/facet.dart';
import 'package:coves_flutter/widgets/rich_text_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Matches the blockquote left-bar container used by the renderer
bool _hasLeftBar(Widget w) =>
    w is Container &&
    w.decoration is BoxDecoration &&
    (w.decoration! as BoxDecoration).border is Border &&
    ((w.decoration! as BoxDecoration).border! as Border).left.width == 3;

/// Matches the code-block card: a rounded, bordered container
bool _isCodeBlockCard(Widget w) =>
    w is Container &&
    w.decoration is BoxDecoration &&
    (w.decoration! as BoxDecoration).borderRadius != null &&
    (w.decoration! as BoxDecoration).border is Border;

final _quoteBar = find.byWidgetPredicate(_hasLeftBar);
final _codeBlockCard = find.byWidgetPredicate(_isCodeBlockCard);

Finder _rich(String text) => find.textContaining(text, findRichText: true);

/// Effective style of the leaf span containing [text] in the single
/// RichText that renders it, with ancestor span styles merged in.
TextStyle _effectiveStyleOf(WidgetTester tester, String text) {
  final richText = tester.widget<RichText>(
    find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().contains(text),
    ),
  );
  TextStyle? found;
  void walk(InlineSpan span, TextStyle inherited) {
    final merged = inherited.merge(span.style);
    if (span is TextSpan) {
      if (span.text != null && span.text!.contains(text)) {
        found ??= merged;
      }
      for (final child in span.children ?? const <InlineSpan>[]) {
        walk(child, merged);
      }
    }
  }

  walk(richText.text, const TextStyle());
  expect(found, isNotNull, reason: 'no leaf span contains "$text"');
  return found!;
}

Widget _app(Widget child) => MaterialApp(
  theme: AppTheme.dark,
  home: Scaffold(body: child),
);

void main() {
  group('RichTextRenderer grouped block features', () {
    // 'Intro\nTitle\nOutro': Title is bytes [6, 11)
    const headingCases = <String, List<FacetFeature>>{
      'quote first': [BlockquoteFacetFeature(), HeadingFacetFeature(level: 2)],
      'heading first': [
        HeadingFacetFeature(level: 2),
        BlockquoteFacetFeature(),
      ],
    };

    for (final entry in headingCases.entries) {
      testWidgets(
        'one [blockquote, heading] facet renders a heading inside the quote '
        '(${entry.key})',
        (tester) async {
          await tester.pumpWidget(
            _app(
              RichTextRenderer(
                text: 'Intro\nTitle\nOutro',
                style: const TextStyle(fontSize: 16),
                facets: [
                  RichTextFacet(
                    index: const ByteSlice(byteStart: 6, byteEnd: 11),
                    features: entry.value,
                  ),
                ],
              ),
            ),
          );

          expect(_rich('Title'), findsOneWidget);
          expect(
            find.descendant(of: _quoteBar, matching: _rich('Title')),
            findsOneWidget,
          );

          final style = _effectiveStyleOf(tester, 'Title');
          expect(style.fontSize, greaterThan(16));
          expect(style.fontWeight, FontWeight.w700);

          for (final plain in ['Intro', 'Outro']) {
            expect(_rich(plain), findsOneWidget);
            expect(
              find.descendant(of: _quoteBar, matching: _rich(plain)),
              findsNothing,
            );
          }
        },
      );
    }

    // 'Before\nlet a = 1;\nlet b = 2;\nAfter': code lines are bytes [7, 28)
    const codeCases = <String, List<FacetFeature>>{
      'quote first': [BlockquoteFacetFeature(), CodeBlockFacetFeature()],
      'code block first': [CodeBlockFacetFeature(), BlockquoteFacetFeature()],
    };

    for (final entry in codeCases.entries) {
      testWidgets(
        'one [blockquote, codeBlock] facet renders a code block inside the '
        'quote (${entry.key})',
        (tester) async {
          await tester.pumpWidget(
            _app(
              RichTextRenderer(
                text: 'Before\nlet a = 1;\nlet b = 2;\nAfter',
                style: const TextStyle(fontSize: 16),
                facets: [
                  RichTextFacet(
                    index: const ByteSlice(byteStart: 7, byteEnd: 28),
                    features: entry.value,
                  ),
                ],
              ),
            ),
          );

          for (final line in ['let a = 1;', 'let b = 2;']) {
            expect(_rich(line), findsOneWidget);
            expect(
              find.descendant(of: _codeBlockCard, matching: _rich(line)),
              findsOneWidget,
            );
            expect(_effectiveStyleOf(tester, line).fontFamily, 'monospace');
          }

          expect(
            find.descendant(of: _quoteBar, matching: _codeBlockCard),
            findsOneWidget,
          );

          for (final plain in ['Before', 'After']) {
            expect(_rich(plain), findsOneWidget);
            expect(
              find.descendant(of: _quoteBar, matching: _rich(plain)),
              findsNothing,
            );
          }
        },
      );
    }

    testWidgets(
      'a facet with duplicate blockquote features renders one quote',
      (tester) async {
        await tester.pumpWidget(
          _app(
            const RichTextRenderer(
              text: 'Intro\nQuoted\nOutro',
              style: TextStyle(fontSize: 16),
              facets: [
                RichTextFacet(
                  index: ByteSlice(byteStart: 6, byteEnd: 12),
                  features: [
                    BlockquoteFacetFeature(),
                    BlockquoteFacetFeature(),
                    BlockquoteFacetFeature(),
                  ],
                ),
              ],
            ),
          ),
        );

        expect(_rich('Quoted'), findsOneWidget);
        expect(_quoteBar, findsOneWidget);
        expect(
          find.descendant(of: _quoteBar, matching: _rich('Quoted')),
          findsOneWidget,
        );
      },
    );

    testWidgets('a [heading, codeBlock] facet renders only the heading', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const RichTextRenderer(
            text: 'Intro\nTitle\nOutro',
            style: TextStyle(fontSize: 16),
            facets: [
              RichTextFacet(
                index: ByteSlice(byteStart: 6, byteEnd: 11),
                features: [
                  HeadingFacetFeature(level: 2),
                  CodeBlockFacetFeature(),
                ],
              ),
            ],
          ),
        ),
      );

      expect(_rich('Title'), findsOneWidget);
      expect(_codeBlockCard, findsNothing);
      final style = _effectiveStyleOf(tester, 'Title');
      expect(style.fontSize, greaterThan(16));
      expect(style.fontWeight, FontWeight.w700);
      expect(style.fontFamily, isNot('monospace'));
    });

    testWidgets('a [codeBlock, heading] facet renders only the code block', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const RichTextRenderer(
            text: 'Intro\nTitle\nOutro',
            style: TextStyle(fontSize: 16),
            facets: [
              RichTextFacet(
                index: ByteSlice(byteStart: 6, byteEnd: 11),
                features: [
                  CodeBlockFacetFeature(),
                  HeadingFacetFeature(level: 2),
                ],
              ),
            ],
          ),
        ),
      );

      expect(_rich('Title'), findsOneWidget);
      expect(
        find.descendant(of: _codeBlockCard, matching: _rich('Title')),
        findsOneWidget,
      );
      expect(_effectiveStyleOf(tester, 'Title').fontFamily, 'monospace');
    });
  });
}
