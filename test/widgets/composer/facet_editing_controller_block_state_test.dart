import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Three lines: "aa" [0,2], "bb" [3,5], "cc" [6,8].
const threeLines = 'aa\nbb\ncc';

const quote = BlockFormat.blockquote;
const heading = BlockFormat.heading;
const code = BlockFormat.codeBlock;
const bold = InlineFormat.bold;
const italic = InlineFormat.italic;

/// Selects [start]..[end] (a caret when equal) and toggles [format].
void toggleOver(
  FacetEditingController controller,
  int start,
  int end,
  BlockFormat format, {
  int level = 1,
}) {
  controller
    ..selection = TextSelection(baseOffset: start, extentOffset: end)
    ..toggleBlock(format, level: level);
}

/// Selects [start]..[end] (a caret when equal) and toggles inline [format].
void toggleInlineOver(
  FacetEditingController controller,
  int start,
  int end,
  InlineFormat format,
) {
  controller
    ..selection = TextSelection(baseOffset: start, extentOffset: end)
    ..toggleInline(format);
}

/// Selects [start]..[end] (a caret when equal).
void select(FacetEditingController controller, int start, int end) {
  controller.selection = TextSelection(baseOffset: start, extentOffset: end);
}

/// Delivers one complete editing value, the way the platform reports an IME
/// update; [composing] defaults to no composing region.
void deliver(
  FacetEditingController controller,
  String text,
  int caret, [
  TextRange composing = TextRange.empty,
]) {
  controller.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: caret),
    composing: composing,
  );
}

/// A shifting composition on 'aa\nbb' with a block on line 1: three
/// characters are composed at the start, so the caret (3) sits on line 0
/// while the held block coordinates (3,5) would put it on the block.
void composeAtStart(FacetEditingController controller) =>
    deliver(controller, 'xxxaa\nbb', 3, const TextRange(start: 0, end: 3));

/// One query of the active block state. `setUp` applies the blocks to
/// `text`; `act` sets the selection (or delivers a composing value); then the
/// block ranges must equal `precondition` before the query.
typedef StateRow = ({
  String name,
  String text,
  void Function(FacetEditingController controller) setUp,
  void Function(FacetEditingController controller) act,
  Set<BlockRange> precondition,
});

FacetEditingController prepare(StateRow row) {
  final controller = FacetEditingController(text: row.text);
  addTearDown(controller.dispose);
  row.setUp(controller);
  row.act(controller);
  expect(
    controller.blockRanges.toSet(),
    row.precondition,
    reason: '${row.name}: precondition',
  );
  return controller;
}

void main() {
  test('D8 active block formats and heading level follow the touched '
      'lines', () {
    final rows = <(StateRow, Set<BlockFormat> formats, int? headingLevel)>[
      (
        (
          name: 'caret on a quoted line',
          text: threeLines,
          setUp: (controller) => toggleOver(controller, 3, 3, quote),
          act: (controller) => select(controller, 4, 4),
          precondition: {const BlockRange(quote, 3, 5)},
        ),
        {quote},
        null,
      ),
      (
        (
          name: 'selection over lines 0–1 inside a quote on lines 0–2',
          text: threeLines,
          setUp: (controller) => toggleOver(controller, 0, 8, quote),
          act: (controller) => select(controller, 0, 5),
          precondition: {const BlockRange(quote, 0, 8)},
        ),
        {quote},
        null,
      ),
      (
        (
          name: 'selection over lines 0–1 with a quote on line 0 only',
          text: threeLines,
          setUp: (controller) => toggleOver(controller, 0, 0, quote),
          act: (controller) => select(controller, 0, 5),
          precondition: {const BlockRange(quote, 0, 2)},
        ),
        <BlockFormat>{},
        null,
      ),
      (
        (
          name: 'selection ending at the start of line 1, quote on line 0',
          text: threeLines,
          setUp: (controller) => toggleOver(controller, 0, 0, quote),
          act: (controller) => select(controller, 0, 3),
          precondition: {const BlockRange(quote, 0, 2)},
        ),
        {quote},
        null,
      ),
      (
        (
          name: 'empty document with an activated quote',
          text: '',
          setUp: (controller) => toggleOver(controller, 0, 0, quote),
          act: (controller) => select(controller, 0, 0),
          precondition: {const BlockRange(quote, 0, 0)},
        ),
        {quote},
        null,
      ),
      (
        (
          name: 'quote and code block on the same line',
          text: 'aaaa',
          setUp: (controller) {
            toggleOver(controller, 0, 0, quote);
            toggleOver(controller, 0, 0, code);
          },
          act: (controller) => select(controller, 2, 2),
          precondition: {
            const BlockRange(quote, 0, 4),
            const BlockRange(code, 0, 4),
          },
        ),
        {quote, code},
        null,
      ),
      (
        (
          name: 'H2 on both selected lines',
          text: threeLines,
          setUp: (controller) {
            toggleOver(controller, 0, 0, heading, level: 2);
            toggleOver(controller, 3, 3, heading, level: 2);
          },
          act: (controller) => select(controller, 0, 5),
          precondition: {
            const BlockRange(heading, 0, 2, level: 2),
            const BlockRange(heading, 3, 5, level: 2),
          },
        ),
        {heading},
        2,
      ),
      (
        (
          name: 'H1 on line 0 and H2 on line 1, both selected',
          text: threeLines,
          setUp: (controller) {
            toggleOver(controller, 0, 0, heading);
            toggleOver(controller, 3, 3, heading, level: 2);
          },
          act: (controller) => select(controller, 0, 5),
          precondition: {
            const BlockRange(heading, 0, 2),
            const BlockRange(heading, 3, 5, level: 2),
          },
        ),
        {heading},
        null,
      ),
      (
        (
          name: 'heading on line 0 only, lines 0–1 selected',
          text: threeLines,
          setUp: (controller) => toggleOver(controller, 0, 0, heading),
          act: (controller) => select(controller, 0, 5),
          precondition: {const BlockRange(heading, 0, 2)},
        ),
        <BlockFormat>{},
        null,
      ),
      (
        (
          name: 'composition that shifted a quote off the caret line',
          text: 'aa\nbb',
          setUp: (controller) => toggleOver(controller, 3, 3, quote),
          act: composeAtStart,
          precondition: {const BlockRange(quote, 6, 8)},
        ),
        <BlockFormat>{},
        null,
      ),
    ];

    for (final (row, formats, headingLevel) in rows) {
      final controller = prepare(row);
      expect(
        controller.activeBlockFormats(),
        formats,
        reason: '${row.name}: active block formats',
      );
      expect(
        controller.activeHeadingLevel(),
        headingLevel,
        reason: '${row.name}: active heading level',
      );
    }
  });

  test('D9 isSelectionInCodeBlock is true when any touched line is in a '
      'code block', () {
    final rows = <(StateRow, bool inCodeBlock)>[
      (
        (
          name: 'selection inside a code-block line',
          text: 'aaaa',
          setUp: (controller) => toggleOver(controller, 0, 0, code),
          act: (controller) => select(controller, 1, 3),
          precondition: {const BlockRange(code, 0, 4)},
        ),
        true,
      ),
      (
        (
          name: 'caret on a code-block line',
          text: 'aaaa',
          setUp: (controller) => toggleOver(controller, 0, 0, code),
          act: (controller) => select(controller, 2, 2),
          precondition: {const BlockRange(code, 0, 4)},
        ),
        true,
      ),
      (
        (
          name: 'selection over a plain line and a code-block line',
          text: 'aa\nbb',
          setUp: (controller) => toggleOver(controller, 3, 3, code),
          act: (controller) => select(controller, 0, 5),
          precondition: {const BlockRange(code, 3, 5)},
        ),
        true,
      ),
      (
        (
          name: 'caret on a plain line',
          text: 'aa\nbb',
          setUp: (controller) => toggleOver(controller, 3, 3, code),
          act: (controller) => select(controller, 1, 1),
          precondition: {const BlockRange(code, 3, 5)},
        ),
        false,
      ),
      (
        (
          name: 'selection ending at the code-block line start',
          text: 'aa\nbb',
          setUp: (controller) => toggleOver(controller, 3, 3, code),
          act: (controller) => select(controller, 0, 3),
          precondition: {const BlockRange(code, 3, 5)},
        ),
        false,
      ),
      (
        (
          name: 'composition that shifted a code block off the caret line',
          text: 'aa\nbb',
          setUp: (controller) => toggleOver(controller, 3, 3, code),
          act: composeAtStart,
          precondition: {const BlockRange(code, 6, 8)},
        ),
        false,
      ),
    ];

    for (final (row, inCodeBlock) in rows) {
      final controller = prepare(row);
      expect(
        controller.isSelectionInCodeBlock(),
        inCodeBlock,
        reason: '${row.name}: in code block',
      );
    }
  });

  test('D9 an inline toggle over a code-block selection changes nothing', () {
    for (final (name, text, codeLineStart, start, end) in [
      ('selection inside a code-block line', 'aaaa', 0, 1, 3),
      ('selection over a plain line and a code-block line', 'aa\nbb', 3, 0, 5),
    ]) {
      final controller = FacetEditingController(text: text);
      addTearDown(controller.dispose);
      toggleOver(controller, codeLineStart, codeLineStart, code);
      expect(controller.blockRanges.toSet(), {
        BlockRange(code, codeLineStart, text.length),
      }, reason: '$name: precondition');

      toggleInlineOver(controller, start, end, bold);

      expect(controller.inlineRanges, isEmpty, reason: name);
    }
  });

  test('D9 an inline toggle at a caret in a code block arms nothing', () {
    final controller = FacetEditingController(text: 'aaaa');
    addTearDown(controller.dispose);
    toggleOver(controller, 0, 0, code);
    expect(controller.blockRanges.toSet(), {const BlockRange(code, 0, 4)});

    toggleInlineOver(controller, 2, 2, bold);
    expect(
      controller.activeInlineFormats(),
      isEmpty,
      reason: 'armed formats after the toggle',
    );
    deliver(controller, 'aaxaa', 3);

    expect(controller.inlineRanges, isEmpty, reason: 'typed text');
    expect(
      controller.activeInlineFormats(),
      isEmpty,
      reason: 'armed formats after typing',
    );
  });

  test('D10 applying a code block removes inline ranges from its lines', () {
    final rows =
        <
          (
            String name,
            String text,
            void Function(FacetEditingController controller) setUp,
            Set<InlineRange> inlinePrecondition,
            Set<InlineRange> expected,
          )
        >[
          (
            'bold on line 0 and italic on line 1',
            'aa bb\ncc',
            (controller) {
              toggleInlineOver(controller, 0, 2, bold);
              toggleInlineOver(controller, 6, 8, italic);
            },
            {const InlineRange(bold, 0, 2), const InlineRange(italic, 6, 8)},
            {const InlineRange(italic, 6, 8)},
          ),
          (
            'bold crossing from line 0 into line 1',
            'aa bb\ncc',
            (controller) => toggleInlineOver(controller, 1, 7, bold),
            {const InlineRange(bold, 1, 7)},
            {const InlineRange(bold, 6, 7)},
          ),
        ];

    for (final (name, text, setUp, inlinePrecondition, expected) in rows) {
      final controller = FacetEditingController(text: text);
      addTearDown(controller.dispose);
      setUp(controller);
      expect(
        controller.inlineRanges.toSet(),
        inlinePrecondition,
        reason: '$name: inline precondition',
      );

      toggleOver(controller, 0, 0, code);
      expect(controller.blockRanges.toSet(), {
        const BlockRange(code, 0, 5),
      }, reason: '$name: code block applied');

      expect(controller.inlineRanges.toSet(), expected, reason: name);
    }
  });

  test('D10 applying a code block at a caret clears formats armed there', () {
    final controller = FacetEditingController(text: 'aaaa');
    addTearDown(controller.dispose);
    toggleInlineOver(controller, 2, 2, bold);
    expect(controller.activeInlineFormats(), {bold}, reason: 'armed bold');

    controller.toggleBlock(code);
    expect(controller.blockRanges.toSet(), {const BlockRange(code, 0, 4)});
    expect(
      controller.activeInlineFormats(),
      isEmpty,
      reason: 'armed formats after the code block',
    );
    deliver(controller, 'aaxaa', 3);

    expect(controller.inlineRanges, isEmpty, reason: 'typed text');
    expect(
      controller.activeInlineFormats(),
      isEmpty,
      reason: 'armed formats after typing',
    );
  });

  test('D10 a widened code block removes inline ranges from all its '
      'lines', () {
    final controller = FacetEditingController(text: threeLines);
    addTearDown(controller.dispose);
    toggleOver(controller, 3, 8, quote);
    toggleInlineOver(controller, 6, 8, bold);
    expect(controller.blockRanges.toSet(), {const BlockRange(quote, 3, 8)});
    expect(controller.inlineRanges.toSet(), {const InlineRange(bold, 6, 8)});

    toggleOver(controller, 0, 4, code);
    expect(controller.blockRanges.toSet(), {
      const BlockRange(code, 0, 8),
      const BlockRange(quote, 0, 8),
    }, reason: 'code block and quote widened over all three lines');

    expect(controller.inlineRanges, isEmpty);
  });

  test('D10 a join into a code-block line drops inline ranges from it', () {
    // Each row joins 'bb' onto the code-block line 'aa' (Backspace at the
    // start of line 1). `composing` is the composing region the join arrives
    // with; a non-empty region is committed afterwards with the same text.
    final rows = <(String name, TextRange composing)>[
      ('committed join', TextRange.empty),
      ('join while composing', const TextRange(start: 2, end: 4)),
    ];

    for (final (name, composing) in rows) {
      final controller = FacetEditingController(text: 'aa\nbb');
      addTearDown(controller.dispose);
      toggleOver(controller, 0, 0, code);
      toggleInlineOver(controller, 3, 5, bold);
      expect(controller.blockRanges.toSet(), {
        const BlockRange(code, 0, 2),
      }, reason: '$name: block precondition');
      expect(controller.inlineRanges.toSet(), {
        const InlineRange(bold, 3, 5),
      }, reason: '$name: inline precondition');

      select(controller, 3, 3);
      deliver(controller, 'aabb', 2, composing);
      if (!composing.isCollapsed) {
        expect(
          controller.inlineRanges,
          isEmpty,
          reason: '$name: inline ranges while composing',
        );
        deliver(controller, 'aabb', 2);
      }

      expect(controller.blockRanges.toSet(), {
        const BlockRange(code, 0, 4),
      }, reason: '$name: joined line is in the code block');
      expect(
        controller.inlineRanges,
        isEmpty,
        reason: '$name: inline ranges after the join',
      );

      deliver(controller, 'aabbx', 5);
      expect(
        controller.inlineRanges,
        isEmpty,
        reason: '$name: inline ranges after typing at the end',
      );
    }
  });
}
