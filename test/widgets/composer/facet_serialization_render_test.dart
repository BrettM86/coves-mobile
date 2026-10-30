import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/utils/rich_text_composer.dart';
import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:coves_flutter/widgets/composer/facet_serialization.dart';
import 'package:coves_flutter/widgets/rich_text_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void select(FacetEditingController controller, int start, int end) {
  controller.selection = TextSelection(baseOffset: start, extentOffset: end);
}

/// Every rendered character in paint order with its effective style and the
/// [RichText] that paints it.
class RenderedText {
  RenderedText(WidgetTester tester) {
    final richTexts = tester.widgetList<RichText>(
      find.descendant(
        of: find.byType(RichTextRenderer),
        matching: find.byType(RichText),
      ),
    );
    for (final richText in richTexts) {
      _walk(richText.text, const TextStyle(), richText);
    }
  }

  final _text = StringBuffer();
  final _styles = <TextStyle>[];
  final _owners = <RichText>[];

  void _walk(InlineSpan span, TextStyle inherited, RichText owner) {
    final style = inherited.merge(span.style);
    if (span is TextSpan) {
      final text = span.text;
      if (text != null) {
        _text.write(text);
        _styles.addAll(List.filled(text.length, style));
        _owners.addAll(List.filled(text.length, owner));
      }
      for (final child in span.children ?? const <InlineSpan>[]) {
        _walk(child, style, owner);
      }
    }
  }

  int _startOf(String fragment) {
    final text = _text.toString();
    final start = text.indexOf(fragment);
    expect(start, isNot(-1), reason: '"$fragment" is rendered');
    expect(
      text.indexOf(fragment, start + 1),
      -1,
      reason: '"$fragment" is rendered once',
    );
    return start;
  }

  /// The styles of the characters of [fragment], which must appear once.
  List<TextStyle> stylesOf(String fragment) {
    final start = _startOf(fragment);
    return _styles.sublist(start, start + fragment.length);
  }

  /// The [RichText]s painting the characters of [fragment].
  Set<RichText> ownersOf(String fragment) {
    final start = _startOf(fragment);
    return _owners.sublist(start, start + fragment.length).toSet();
  }
}

/// Matches the blockquote left-bar container used by the renderer
bool _hasLeftBar(Widget widget) =>
    widget is Container &&
    widget.decoration is BoxDecoration &&
    (widget.decoration! as BoxDecoration).border is Border &&
    ((widget.decoration! as BoxDecoration).border! as Border).left.width == 3;

/// Whether every character of [fragment] is painted inside a quote bar.
bool isQuoted(WidgetTester tester, RenderedText rendered, String fragment) =>
    rendered
        .ownersOf(fragment)
        .every(
          (owner) => tester.any(
            find.ancestor(
              of: find.byWidget(owner),
              matching: find.byWidgetPredicate(_hasLeftBar),
            ),
          ),
        );

bool isMonospace(TextStyle style) => style.fontFamily == 'monospace';

bool isStruck(TextStyle style) =>
    style.decoration?.contains(TextDecoration.lineThrough) ?? false;

void expectEvery(
  RenderedText rendered,
  String fragment,
  bool Function(TextStyle style) property,
  String description, {
  required bool expected,
}) {
  for (final style in rendered.stylesOf(fragment)) {
    expect(property(style), expected, reason: '"$fragment" $description');
  }
}

void main() {
  // Lines: 0 inline formats, 1 quote, 2 heading, 3-4 quote over code block,
  // 5 plain
  const text =
      'bold italic strike code plain\n'
      'quoted line\n'
      'Heading line\n'
      'quoted code one\n'
      'quoted code two\n'
      'end';

  testWidgets(
    'B5 each format covers the same text from editor to rendered output',
    (tester) async {
      final controller = FacetEditingController(text: text);
      select(controller, 0, 4);
      controller.toggleInline(InlineFormat.bold);
      select(controller, 5, 11);
      controller.toggleInline(InlineFormat.italic);
      select(controller, 12, 18);
      controller.toggleInline(InlineFormat.strikethrough);
      select(controller, 19, 23);
      controller.toggleInline(InlineFormat.code);
      select(controller, 30, 30);
      controller.toggleBlock(BlockFormat.blockquote);
      select(controller, 42, 42);
      controller.toggleBlock(BlockFormat.heading);
      select(controller, 55, 86);
      controller.toggleBlock(BlockFormat.codeBlock);
      select(controller, 55, 86);
      controller.toggleBlock(BlockFormat.blockquote);

      final serialized = serializeFormatting(
        controller.text,
        inlineRanges: controller.inlineRanges,
        blockRanges: controller.blockRanges,
      );
      final composed = composeFormattedRichText(
        serialized.content,
        formattingFacets: serialized.facets,
        excludedRanges: serialized.codeRanges,
      );
      // Bold, italic, strikethrough, code, quote, heading, and one grouped
      // quote + code block facet
      expect(composed.facets, hasLength(7));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: RichTextRenderer(
              text: composed.content,
              facets: composed.facets,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ),
      );
      final rendered = RenderedText(tester);

      bool isBold(TextStyle style) => style.fontWeight == FontWeight.w700;
      bool isItalic(TextStyle style) => style.fontStyle == FontStyle.italic;

      expectEvery(rendered, 'bold', isBold, 'is bold', expected: true);
      expectEvery(rendered, ' italic', isBold, 'is not bold', expected: false);
      expectEvery(rendered, 'italic', isItalic, 'is italic', expected: true);
      expectEvery(
        rendered,
        ' strike',
        isItalic,
        'is not italic',
        expected: false,
      );
      expectEvery(rendered, 'strike', isStruck, 'is struck', expected: true);
      expectEvery(
        rendered,
        ' code plain',
        isStruck,
        'is not struck',
        expected: false,
      );
      // "strike code plain": only "code" (7-10) is inline code
      final codeLine = rendered.stylesOf('strike code plain');
      for (var i = 0; i < codeLine.length; i++) {
        expect(
          isMonospace(codeLine[i]),
          i >= 7 && i <= 10,
          reason: 'monospace at offset $i of "strike code plain"',
        );
      }

      expect(isQuoted(tester, rendered, 'quoted line'), isTrue);
      expect(isQuoted(tester, rendered, 'bold italic'), isFalse);
      expect(isQuoted(tester, rendered, 'Heading line'), isFalse);
      expect(isQuoted(tester, rendered, 'end'), isFalse);
      expectEvery(
        rendered,
        'quoted line',
        isMonospace,
        'is prose',
        expected: false,
      );
      expectEvery(
        rendered,
        'quoted line',
        isBold,
        'is not bold',
        expected: false,
      );

      for (final style in rendered.stylesOf('Heading line')) {
        expect(style.fontSize, greaterThan(16));
        expect(style.fontWeight, FontWeight.w700);
      }

      expectEvery(
        rendered,
        'quoted code one',
        isMonospace,
        'is code',
        expected: true,
      );
      expectEvery(
        rendered,
        'quoted code two',
        isMonospace,
        'is code',
        expected: true,
      );

      expectEvery(rendered, 'end', isMonospace, 'is prose', expected: false);
      for (final style in rendered.stylesOf('end')) {
        expect(style.fontSize, 16);
        expect(style.fontWeight, isNot(FontWeight.w700));
      }
    },
  );
}
