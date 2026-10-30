import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Three lines: "aa" [0,2], "bb" [3,5], "cc" [6,8].
const threeLines = 'aa\nbb\ncc';

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

/// One edit on a block-formatted text. `setUp` applies the blocks to `text`,
/// which must produce `precondition`; then `edited` is delivered with the
/// caret at `caret`. When `composing` is set, the edit is first delivered as
/// that composing region and `expected` is checked while composing, then the
/// same text is delivered with no composing region (the commit).
typedef EditRow = ({
  String name,
  String text,
  void Function(FacetEditingController controller) setUp,
  Set<BlockRange> precondition,
  String edited,
  int caret,
  TextRange? composing,
  Set<BlockRange> expected,
});

void runEditRows(List<EditRow> rows) {
  for (final row in rows) {
    final controller = FacetEditingController(text: row.text);
    addTearDown(controller.dispose);
    row.setUp(controller);
    expect(
      controller.blockRanges.toSet(),
      row.precondition,
      reason: '${row.name}: precondition',
    );
    final composing = row.composing;
    if (composing != null) {
      deliver(controller, row.edited, row.caret, composing);
      expect(
        controller.blockRanges.toSet(),
        row.expected,
        reason: '${row.name}: while composing',
      );
    }
    deliver(controller, row.edited, row.caret);
    expect(
      controller.blockRanges.toSet(),
      row.expected,
      reason: '${row.name}: after the edit',
    );
    expect(
      (controller.text, controller.selection),
      (row.edited, TextSelection.collapsed(offset: row.caret)),
      reason: '${row.name}: text and caret stay as delivered',
    );
  }
}

/// Toggles [format] on both lines of 'aa\n' (the empty last line cannot be
/// reached by one selection, which would end at its start).
void toggleBothLines(FacetEditingController controller, BlockFormat format) {
  toggleOver(controller, 0, 0, format);
  toggleOver(controller, 3, 3, format);
}

const quote = BlockFormat.blockquote;
const heading = BlockFormat.heading;
const code = BlockFormat.codeBlock;

void main() {
  test('D1 non-newline inserts and deletes keep blocks on their lines', () {
    void quoteLineOneHeadingLineZero(FacetEditingController controller) {
      toggleOver(controller, 3, 5, quote);
      toggleOver(controller, 0, 0, heading, level: 2);
    }

    final precondition = {
      const BlockRange(quote, 3, 5),
      const BlockRange(heading, 0, 2, level: 2),
    };
    runEditRows([
      (
        name: 'insert at the quoted line start',
        text: threeLines,
        setUp: quoteLineOneHeadingLineZero,
        precondition: precondition,
        edited: 'aa\nxbb\ncc',
        caret: 4,
        composing: null,
        expected: {
          const BlockRange(quote, 3, 6),
          const BlockRange(heading, 0, 2, level: 2),
        },
      ),
      (
        name: 'insert at the quoted line end',
        text: threeLines,
        setUp: quoteLineOneHeadingLineZero,
        precondition: precondition,
        edited: 'aa\nbbx\ncc',
        caret: 6,
        composing: null,
        expected: {
          const BlockRange(quote, 3, 6),
          const BlockRange(heading, 0, 2, level: 2),
        },
      ),
      (
        name: 'insert at the end of the line above the quote',
        text: threeLines,
        setUp: quoteLineOneHeadingLineZero,
        precondition: precondition,
        edited: 'aax\nbb\ncc',
        caret: 3,
        composing: null,
        expected: {
          const BlockRange(quote, 4, 6),
          const BlockRange(heading, 0, 3, level: 2),
        },
      ),
      (
        name: 'delete inside the quoted line',
        text: threeLines,
        setUp: quoteLineOneHeadingLineZero,
        precondition: precondition,
        edited: 'aa\nb\ncc',
        caret: 3,
        composing: null,
        expected: {
          const BlockRange(quote, 3, 4),
          const BlockRange(heading, 0, 2, level: 2),
        },
      ),
      (
        name: 'delete all of the quoted line text',
        text: threeLines,
        setUp: quoteLineOneHeadingLineZero,
        precondition: precondition,
        edited: 'aa\n\ncc',
        caret: 3,
        composing: null,
        expected: {
          const BlockRange(quote, 3, 3),
          const BlockRange(heading, 0, 2, level: 2),
        },
      ),
    ]);
  });

  test('D2 Enter on a non-empty line continues quote and code block, '
      'not heading', () {
    runEditRows([
      (
        name: 'quote, caret mid-line',
        text: 'aaaa',
        setUp: (controller) => toggleOver(controller, 0, 0, quote),
        precondition: {const BlockRange(quote, 0, 4)},
        edited: 'aa\naa',
        caret: 3,
        composing: null,
        expected: {const BlockRange(quote, 0, 5)},
      ),
      (
        name: 'code block, caret mid-line',
        text: 'aaaa',
        setUp: (controller) => toggleOver(controller, 0, 0, code),
        precondition: {const BlockRange(code, 0, 4)},
        edited: 'aa\naa',
        caret: 3,
        composing: null,
        expected: {const BlockRange(code, 0, 5)},
      ),
      (
        name: 'three-line quote, caret mid-line on the first line',
        text: threeLines,
        setUp: (controller) => toggleOver(controller, 0, 8, quote),
        precondition: {const BlockRange(quote, 0, 8)},
        edited: 'a\na\nbb\ncc',
        caret: 2,
        composing: null,
        expected: {const BlockRange(quote, 0, 9)},
      ),
      (
        name: 'three-line code block, caret mid-line on the first line',
        text: threeLines,
        setUp: (controller) => toggleOver(controller, 0, 8, code),
        precondition: {const BlockRange(code, 0, 8)},
        edited: 'a\na\nbb\ncc',
        caret: 2,
        composing: null,
        expected: {const BlockRange(code, 0, 9)},
      ),
      (
        name: 'H2, caret mid-line',
        text: 'aaaa',
        setUp: (controller) => toggleOver(controller, 0, 0, heading, level: 2),
        precondition: {const BlockRange(heading, 0, 4, level: 2)},
        edited: 'aa\naa',
        caret: 3,
        composing: null,
        expected: {const BlockRange(heading, 0, 2, level: 2)},
      ),
      (
        name: 'H1, caret at line end',
        text: 'aaaa',
        setUp: (controller) => toggleOver(controller, 4, 4, heading),
        precondition: {const BlockRange(heading, 0, 4)},
        edited: 'aaaa\n',
        caret: 5,
        composing: null,
        expected: {const BlockRange(heading, 0, 4)},
      ),
      (
        name: 'quote and H1, caret at line end',
        text: 'aaaa',
        setUp: (controller) {
          toggleOver(controller, 4, 4, quote);
          toggleOver(controller, 4, 4, heading);
        },
        precondition: {
          const BlockRange(quote, 0, 4),
          const BlockRange(heading, 0, 4),
        },
        edited: 'aaaa\n',
        caret: 5,
        composing: null,
        expected: {
          const BlockRange(quote, 0, 5),
          const BlockRange(heading, 0, 4),
        },
      ),
    ]);
  });

  test('D3 Enter on an empty line ends a quote or heading, ends a code '
      'block on its last line and continues it elsewhere', () {
    runEditRows([
      (
        name: 'empty last quoted line',
        text: 'aa\n',
        setUp: (controller) => toggleBothLines(controller, quote),
        precondition: {const BlockRange(quote, 0, 3)},
        edited: 'aa\n\n',
        caret: 4,
        composing: null,
        expected: {const BlockRange(quote, 0, 2)},
      ),
      (
        name: 'empty middle quoted line splits the quote',
        text: 'aa\n\nbb',
        setUp: (controller) => toggleOver(controller, 0, 6, quote),
        precondition: {const BlockRange(quote, 0, 6)},
        edited: 'aa\n\n\nbb',
        caret: 4,
        composing: null,
        expected: {
          const BlockRange(quote, 0, 2),
          const BlockRange(quote, 5, 7),
        },
      ),
      (
        name: 'empty H2 line',
        text: 'aa\n',
        setUp: (controller) => toggleOver(controller, 3, 3, heading, level: 2),
        precondition: {const BlockRange(heading, 3, 3, level: 2)},
        edited: 'aa\n\n',
        caret: 4,
        composing: null,
        expected: {},
      ),
      (
        name: 'empty document with an activated quote',
        text: '',
        setUp: (controller) => toggleOver(controller, 0, 0, quote),
        precondition: {const BlockRange(quote, 0, 0)},
        edited: '\n',
        caret: 1,
        composing: null,
        expected: {},
      ),
      (
        name: 'empty last code-block line ends the code block',
        text: 'aa\n',
        setUp: (controller) => toggleBothLines(controller, code),
        precondition: {const BlockRange(code, 0, 3)},
        edited: 'aa\n\n',
        caret: 4,
        composing: null,
        expected: {const BlockRange(code, 0, 2)},
      ),
      (
        name: 'empty last code-block line above more text ends the code block',
        text: 'aa\n\nq',
        setUp: (controller) {
          toggleBothLines(controller, code);
          controller.selection = const TextSelection.collapsed(offset: 3);
        },
        precondition: {const BlockRange(code, 0, 3)},
        edited: 'aa\n\n\nq',
        caret: 4,
        composing: null,
        expected: {const BlockRange(code, 0, 2)},
      ),
      (
        name: 'empty document with an activated code block',
        text: '',
        setUp: (controller) => toggleOver(controller, 0, 0, code),
        precondition: {const BlockRange(code, 0, 0)},
        edited: '\n',
        caret: 1,
        composing: null,
        expected: {},
      ),
      (
        name: 'empty last line of a quoted code block ends only the code block',
        text: 'aa\n',
        setUp: (controller) {
          toggleBothLines(controller, quote);
          toggleBothLines(controller, code);
        },
        precondition: {
          const BlockRange(code, 0, 3),
          const BlockRange(quote, 0, 3),
        },
        edited: 'aa\n\n',
        caret: 4,
        composing: null,
        expected: {const BlockRange(code, 0, 2), const BlockRange(quote, 0, 4)},
      ),
      (
        name: 'empty code-block line in a quote extending below the code block',
        text: 'p\n\nc\nq',
        setUp: (controller) {
          toggleOver(controller, 2, 6, quote);
          toggleOver(controller, 2, 4, code);
        },
        precondition: {
          const BlockRange(quote, 2, 6),
          const BlockRange(code, 2, 4),
        },
        edited: 'p\n\n\nc\nq',
        caret: 3,
        composing: const TextRange(start: 2, end: 3),
        expected: {const BlockRange(quote, 2, 7), const BlockRange(code, 2, 5)},
      ),
      (
        name: 'empty code-block line in a quote extending above the code block',
        text: 'p\n\nc',
        setUp: (controller) {
          toggleOver(controller, 0, 4, quote);
          toggleOver(controller, 2, 4, code);
        },
        precondition: {
          const BlockRange(quote, 0, 4),
          const BlockRange(code, 2, 4),
        },
        edited: 'p\n\n\nc',
        caret: 3,
        composing: const TextRange(start: 2, end: 3),
        expected: {const BlockRange(quote, 0, 5), const BlockRange(code, 2, 5)},
      ),
      (
        name: 'empty code-block line in a quote extending above and below',
        text: 'p\n\nq',
        setUp: (controller) {
          toggleOver(controller, 0, 4, quote);
          toggleOver(controller, 2, 2, code);
        },
        precondition: {
          const BlockRange(quote, 0, 4),
          const BlockRange(code, 2, 2),
        },
        edited: 'p\n\n\nq',
        caret: 3,
        composing: const TextRange(start: 2, end: 3),
        expected: {const BlockRange(quote, 0, 5)},
      ),
      (
        name: 'empty document with an activated quote and code block',
        text: '',
        setUp: (controller) {
          toggleOver(controller, 0, 0, quote);
          toggleOver(controller, 0, 0, code);
        },
        precondition: {
          const BlockRange(quote, 0, 0),
          const BlockRange(code, 0, 0),
        },
        edited: '\n',
        caret: 1,
        composing: const TextRange(start: 0, end: 1),
        expected: {const BlockRange(quote, 0, 1)},
      ),
    ]);
  });

  test('D3b after a quoted code block ends, a second Enter ends the quote', () {
    final controller = FacetEditingController(text: 'aa\n');
    addTearDown(controller.dispose);
    toggleBothLines(controller, quote);
    toggleBothLines(controller, code);
    deliver(controller, 'aa\n\n', 4);
    expect(controller.blockRanges.toSet(), {
      const BlockRange(code, 0, 2),
      const BlockRange(quote, 0, 4),
    });
    deliver(controller, 'aa\n\n\n', 5);
    expect(controller.blockRanges.toSet(), {
      const BlockRange(code, 0, 2),
      const BlockRange(quote, 0, 3),
    });
    expect(controller.text, 'aa\n\n\n');
    expect(controller.selection, const TextSelection.collapsed(offset: 5));
  });

  test('D3c Enter at the start of a non-empty heading line inserts a plain '
      'line above', () {
    runEditRows([
      (
        name: 'H2 on the only line',
        text: 'aa',
        setUp: (controller) => toggleOver(controller, 0, 0, heading, level: 2),
        precondition: {const BlockRange(heading, 0, 2, level: 2)},
        edited: '\naa',
        caret: 1,
        composing: null,
        expected: {const BlockRange(heading, 1, 3, level: 2)},
      ),
      (
        name: 'H1 on the second line',
        text: 'p\naa',
        setUp: (controller) => toggleOver(controller, 2, 2, heading),
        precondition: {const BlockRange(heading, 2, 4)},
        edited: 'p\n\naa',
        caret: 3,
        composing: null,
        expected: {const BlockRange(heading, 3, 5)},
      ),
      (
        name: 'quoted H1: the quote covers both lines',
        text: 'aa',
        setUp: (controller) {
          toggleOver(controller, 0, 0, quote);
          toggleOver(controller, 0, 0, heading);
        },
        precondition: {
          const BlockRange(quote, 0, 2),
          const BlockRange(heading, 0, 2),
        },
        edited: '\naa',
        caret: 1,
        composing: null,
        expected: {
          const BlockRange(quote, 0, 3),
          const BlockRange(heading, 1, 3),
        },
      ),
    ]);

    final controller = FacetEditingController(text: 'aa');
    addTearDown(controller.dispose);
    toggleOver(controller, 0, 0, heading, level: 2);
    deliver(controller, '\naa', 1);
    deliver(controller, '\nxaa', 2);
    expect(controller.blockRanges.toSet(), {
      const BlockRange(heading, 1, 4, level: 2),
    });
  });

  test('D4 a join takes the upper line formats', () {
    EditRow joinOf(
      String name,
      void Function(FacetEditingController controller) setUp,
      Set<BlockRange> precondition,
      Set<BlockRange> expected,
    ) => (
      name: name,
      text: 'aa\nbb',
      setUp: setUp,
      precondition: precondition,
      edited: 'aabb',
      caret: 2,
      composing: null,
      expected: expected,
    );

    runEditRows([
      joinOf(
        'quote over plain',
        (controller) => toggleOver(controller, 0, 0, quote),
        {const BlockRange(quote, 0, 2)},
        {const BlockRange(quote, 0, 4)},
      ),
      joinOf(
        'plain over quote',
        (controller) => toggleOver(controller, 3, 3, quote),
        {const BlockRange(quote, 3, 5)},
        {},
      ),
      joinOf(
        'H1 over plain',
        (controller) => toggleOver(controller, 0, 0, heading),
        {const BlockRange(heading, 0, 2)},
        {const BlockRange(heading, 0, 4)},
      ),
      joinOf(
        'plain over H2',
        (controller) => toggleOver(controller, 3, 3, heading, level: 2),
        {const BlockRange(heading, 3, 5, level: 2)},
        {},
      ),
      joinOf(
        'code block over plain',
        (controller) => toggleOver(controller, 0, 0, code),
        {const BlockRange(code, 0, 2)},
        {const BlockRange(code, 0, 4)},
      ),
      joinOf(
        'plain over code block',
        (controller) => toggleOver(controller, 3, 3, code),
        {const BlockRange(code, 3, 5)},
        {},
      ),
      (
        name: 'plain over a two-line quote',
        text: threeLines,
        setUp: (controller) => toggleOver(controller, 3, 8, quote),
        precondition: {const BlockRange(quote, 3, 8)},
        edited: 'aabb\ncc',
        caret: 2,
        composing: null,
        expected: {const BlockRange(quote, 5, 7)},
      ),
      (
        name: 'join inside a three-line quote',
        text: threeLines,
        setUp: (controller) => toggleOver(controller, 0, 8, quote),
        precondition: {const BlockRange(quote, 0, 8)},
        edited: 'aabb\ncc',
        caret: 2,
        composing: null,
        expected: {const BlockRange(quote, 0, 7)},
      ),
    ]);
  });

  test('D5 a join of differently formatted lines keeps the upper formats', () {
    void headingOverCode(FacetEditingController controller) {
      toggleOver(controller, 0, 0, heading);
      toggleOver(controller, 3, 3, code);
    }

    void quoteOverCode(FacetEditingController controller) {
      toggleOver(controller, 0, 5, quote);
      toggleOver(controller, 6, 11, code);
    }

    runEditRows([
      (
        name: 'H1 over code block',
        text: threeLines,
        setUp: headingOverCode,
        precondition: {
          const BlockRange(heading, 0, 2),
          const BlockRange(code, 3, 5),
        },
        edited: 'aabb\ncc',
        caret: 2,
        composing: null,
        expected: {const BlockRange(heading, 0, 4)},
      ),
      (
        name: 'H1 over code block, as a composition',
        text: threeLines,
        setUp: headingOverCode,
        precondition: {
          const BlockRange(heading, 0, 2),
          const BlockRange(code, 3, 5),
        },
        edited: 'aabb\ncc',
        caret: 2,
        composing: const TextRange(start: 0, end: 4),
        expected: {const BlockRange(heading, 0, 4)},
      ),
      (
        name: 'code block over H2',
        text: 'aa\nbb',
        setUp: (controller) {
          toggleOver(controller, 0, 0, code);
          toggleOver(controller, 3, 3, heading, level: 2);
        },
        precondition: {
          const BlockRange(code, 0, 2),
          const BlockRange(heading, 3, 5, level: 2),
        },
        edited: 'aabb',
        caret: 2,
        composing: null,
        expected: {const BlockRange(code, 0, 4)},
      ),
      (
        name: 'quoted H1 over quoted code block',
        text: 'aa\nbb',
        setUp: (controller) {
          toggleOver(controller, 0, 5, quote);
          toggleOver(controller, 0, 0, heading);
          toggleOver(controller, 3, 3, code);
        },
        precondition: {
          const BlockRange(quote, 0, 5),
          const BlockRange(heading, 0, 2),
          const BlockRange(code, 3, 5),
        },
        edited: 'aabb',
        caret: 2,
        composing: null,
        expected: {
          const BlockRange(quote, 0, 4),
          const BlockRange(heading, 0, 4),
        },
      ),
      (
        name: 'quote over unquoted H2',
        text: 'aa\nbb',
        setUp: (controller) {
          toggleOver(controller, 0, 0, quote);
          toggleOver(controller, 3, 3, heading, level: 2);
        },
        precondition: {
          const BlockRange(quote, 0, 2),
          const BlockRange(heading, 3, 5, level: 2),
        },
        edited: 'aabb',
        caret: 2,
        composing: null,
        expected: {const BlockRange(quote, 0, 4)},
      ),
      (
        name: 'H1 over a two-line quoted code block',
        text: threeLines,
        setUp: (controller) {
          toggleOver(controller, 0, 0, heading);
          toggleOver(controller, 3, 8, quote);
          toggleOver(controller, 3, 8, code);
        },
        precondition: {
          const BlockRange(heading, 0, 2),
          const BlockRange(quote, 3, 8),
          const BlockRange(code, 3, 8),
        },
        edited: 'aabb\ncc',
        caret: 2,
        composing: null,
        expected: {
          const BlockRange(heading, 0, 4),
          const BlockRange(quote, 5, 7),
          const BlockRange(code, 5, 7),
        },
      ),
      (
        name: 'last quoted line over the first code-block line',
        text: 'aa\nbb\ncc\ndd',
        setUp: quoteOverCode,
        precondition: {
          const BlockRange(quote, 0, 5),
          const BlockRange(code, 6, 11),
        },
        edited: 'aa\nbbcc\ndd',
        caret: 5,
        composing: null,
        expected: {
          const BlockRange(quote, 0, 7),
          const BlockRange(code, 8, 10),
        },
      ),
      (
        name:
            'last quoted line over the first code-block line, '
            'as a composition',
        text: 'aa\nbb\ncc\ndd',
        setUp: quoteOverCode,
        precondition: {
          const BlockRange(quote, 0, 5),
          const BlockRange(code, 6, 11),
        },
        edited: 'aa\nbbcc\ndd',
        caret: 5,
        composing: const TextRange(start: 3, end: 7),
        expected: {
          const BlockRange(quote, 0, 7),
          const BlockRange(code, 8, 10),
        },
      ),
    ]);
  });

  /// Five lines: "aaaa" [0,4], "bbbb" [5,9], "cccc" [10,14], "dddd" [15,19],
  /// "eeee" [20,24].
  const fiveLines = 'aaaa\nbbbb\ncccc\ndddd\neeee';

  void quoteHeadingCode(FacetEditingController controller) {
    toggleOver(controller, 0, 9, quote);
    toggleOver(controller, 10, 10, heading, level: 2);
    toggleOver(controller, 15, 24, code);
  }

  final fiveLinesPrecondition = {
    const BlockRange(quote, 0, 9),
    const BlockRange(heading, 10, 14, level: 2),
    const BlockRange(code, 15, 24),
  };

  test('D6 deleting across several formatted lines keeps the first line '
      'formats and the surviving lines below', () {
    runEditRows([
      (
        name: 'delete [2,17)',
        text: fiveLines,
        setUp: quoteHeadingCode,
        precondition: fiveLinesPrecondition,
        edited: 'aadd\neeee',
        caret: 2,
        composing: null,
        expected: {const BlockRange(quote, 0, 4), const BlockRange(code, 5, 9)},
      ),
    ]);
  });

  test('D7 replacing across several formatted lines keeps the first line '
      'formats and the surviving lines below', () {
    runEditRows([
      (
        name: 'replace [2,17) with XY',
        text: fiveLines,
        setUp: quoteHeadingCode,
        precondition: fiveLinesPrecondition,
        edited: 'aaXYdd\neeee',
        caret: 4,
        composing: null,
        expected: {
          const BlockRange(quote, 0, 6),
          const BlockRange(code, 7, 11),
        },
      ),
    ]);
  });
}
