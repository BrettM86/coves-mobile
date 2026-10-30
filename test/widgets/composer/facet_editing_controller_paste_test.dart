import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Three lines: "aa" [0,2], "bbbb" [3,7], "cc" [8,10].
const fixture = 'aa\nbbbb\ncc';

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

/// Selects [start]..[end] and toggles the inline [format] over it.
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

void main() {
  group('D8 single-line paste takes the containing line blocks', () {
    const formats = [
      (name: 'quote', format: BlockFormat.blockquote, level: 1, bold: true),
      (name: 'heading 2', format: BlockFormat.heading, level: 2, bold: true),
      (
        name: 'code block',
        format: BlockFormat.codeBlock,
        level: 1,
        bold: false,
      ),
    ];
    final placements = [
      (
        name: 'caret 5',
        selection: const TextSelection.collapsed(offset: 5),
        text: 'aa\nbbXYbb\ncc',
        blockEnd: 9,
        bold: {
          const InlineRange(InlineFormat.bold, 3, 5),
          const InlineRange(InlineFormat.bold, 7, 9),
        },
        caret: 7,
      ),
      (
        name: 'selection [4,6)',
        selection: const TextSelection(baseOffset: 4, extentOffset: 6),
        text: 'aa\nbXYb\ncc',
        blockEnd: 7,
        bold: {
          const InlineRange(InlineFormat.bold, 3, 4),
          const InlineRange(InlineFormat.bold, 6, 7),
        },
        caret: 6,
      ),
    ];

    for (final format in formats) {
      for (final placement in placements) {
        test('D8 ${format.name} line, ${placement.name}, paste XY', () {
          final controller = FacetEditingController(text: fixture);
          addTearDown(controller.dispose);
          toggleOver(controller, 3, 3, format.format, level: format.level);
          if (format.bold) {
            toggleInlineOver(controller, 3, 7, InlineFormat.bold);
          }
          expect(controller.blockRanges.toSet(), {
            BlockRange(format.format, 3, 7, level: format.level),
          });
          expect(
            controller.inlineRanges.toSet(),
            format.bold
                ? {const InlineRange(InlineFormat.bold, 3, 7)}
                : <InlineRange>{},
          );

          controller
            ..selection = placement.selection
            ..pasteUnformatted('XY');

          expect(controller.text, placement.text);
          expect(controller.blockRanges.toSet(), {
            BlockRange(
              format.format,
              3,
              placement.blockEnd,
              level: format.level,
            ),
          });
          expect(
            controller.inlineRanges.toSet(),
            format.bold ? placement.bold : <InlineRange>{},
          );
          expect(
            controller.selection,
            TextSelection.collapsed(offset: placement.caret),
          );
        });
      }
    }

    test('D8 invalid selection: paste is a no-op', () {
      final controller = FacetEditingController(text: fixture);
      addTearDown(controller.dispose);
      toggleOver(controller, 3, 3, BlockFormat.blockquote);
      toggleInlineOver(controller, 3, 7, InlineFormat.bold);
      controller.selection = const TextSelection.collapsed(offset: -1);
      expect(controller.blockRanges.toSet(), {
        const BlockRange(BlockFormat.blockquote, 3, 7),
      });
      expect(controller.inlineRanges.toSet(), {
        const InlineRange(InlineFormat.bold, 3, 7),
      });

      controller.pasteUnformatted('XY');

      expect(controller.text, fixture);
      expect(controller.blockRanges.toSet(), {
        const BlockRange(BlockFormat.blockquote, 3, 7),
      });
      expect(controller.inlineRanges.toSet(), {
        const InlineRange(InlineFormat.bold, 3, 7),
      });
      expect(controller.selection, const TextSelection.collapsed(offset: -1));
    });
  });

  group('D9 multi-line paste follows the Enter rule per newline', () {
    final rows =
        <
          ({
            String name,
            String text,
            void Function(FacetEditingController controller) setUp,
            Set<BlockRange> before,
            TextSelection selection,
            String pasted,
            String expectedText,
            Set<BlockRange> expected,
            int caret,
          })
        >[
          (
            name: 'quote line, caret 5',
            text: fixture,
            setUp: (controller) =>
                toggleOver(controller, 3, 3, BlockFormat.blockquote),
            before: {const BlockRange(BlockFormat.blockquote, 3, 7)},
            selection: const TextSelection.collapsed(offset: 5),
            pasted: 'X\nY\nZ',
            expectedText: 'aa\nbbX\nY\nZbb\ncc',
            expected: {const BlockRange(BlockFormat.blockquote, 3, 12)},
            caret: 10,
          ),
          (
            name: 'code-block line, caret 5',
            text: fixture,
            setUp: (controller) =>
                toggleOver(controller, 3, 3, BlockFormat.codeBlock),
            before: {const BlockRange(BlockFormat.codeBlock, 3, 7)},
            selection: const TextSelection.collapsed(offset: 5),
            pasted: 'X\nY\nZ',
            expectedText: 'aa\nbbX\nY\nZbb\ncc',
            expected: {const BlockRange(BlockFormat.codeBlock, 3, 12)},
            caret: 10,
          ),
          (
            name: 'heading 2 line, caret 5',
            text: fixture,
            setUp: (controller) =>
                toggleOver(controller, 3, 3, BlockFormat.heading, level: 2),
            before: {const BlockRange(BlockFormat.heading, 3, 7, level: 2)},
            selection: const TextSelection.collapsed(offset: 5),
            pasted: 'X\nY\nZ',
            expectedText: 'aa\nbbX\nY\nZbb\ncc',
            expected: {const BlockRange(BlockFormat.heading, 3, 6, level: 2)},
            caret: 10,
          ),
          (
            name: 'selection [1,5) from quote line into code line',
            text: fixture,
            setUp: (controller) {
              toggleOver(controller, 0, 0, BlockFormat.blockquote);
              toggleOver(controller, 3, 3, BlockFormat.codeBlock);
            },
            before: {
              const BlockRange(BlockFormat.blockquote, 0, 2),
              const BlockRange(BlockFormat.codeBlock, 3, 7),
            },
            selection: const TextSelection(baseOffset: 1, extentOffset: 5),
            pasted: 'X\nY\nZ',
            expectedText: 'aX\nY\nZbb\ncc',
            expected: {const BlockRange(BlockFormat.blockquote, 0, 8)},
            caret: 6,
          ),
          (
            name: 'select all over quote and code lines (selection, not diff)',
            text: 'aa\nbb',
            setUp: (controller) {
              toggleOver(controller, 0, 0, BlockFormat.blockquote);
              toggleOver(controller, 3, 3, BlockFormat.codeBlock);
            },
            before: {
              const BlockRange(BlockFormat.blockquote, 0, 2),
              const BlockRange(BlockFormat.codeBlock, 3, 5),
            },
            selection: const TextSelection(baseOffset: 0, extentOffset: 5),
            pasted: 'aa\nzz',
            expectedText: 'aa\nzz',
            expected: {const BlockRange(BlockFormat.blockquote, 0, 5)},
            caret: 5,
          ),
          (
            name: 'second newline lands on an empty quoted line and ends it',
            text: 'q',
            setUp: (controller) =>
                toggleOver(controller, 0, 0, BlockFormat.blockquote),
            before: {const BlockRange(BlockFormat.blockquote, 0, 1)},
            selection: const TextSelection.collapsed(offset: 1),
            pasted: '\n\nx',
            expectedText: 'q\n\nx',
            expected: {const BlockRange(BlockFormat.blockquote, 0, 1)},
            caret: 4,
          ),
          (
            name: 'quoted code block ends on its empty last line',
            text: 'q',
            setUp: (controller) {
              toggleOver(controller, 0, 0, BlockFormat.blockquote);
              toggleOver(controller, 0, 0, BlockFormat.codeBlock);
            },
            before: {
              const BlockRange(BlockFormat.blockquote, 0, 1),
              const BlockRange(BlockFormat.codeBlock, 0, 1),
            },
            selection: const TextSelection.collapsed(offset: 1),
            pasted: '\n\nx',
            expectedText: 'q\n\nx',
            expected: {
              const BlockRange(BlockFormat.blockquote, 0, 4),
              const BlockRange(BlockFormat.codeBlock, 0, 1),
            },
            caret: 4,
          ),
        ];

    for (final row in rows) {
      test('D9 ${row.name}', () {
        final controller = FacetEditingController(text: row.text);
        addTearDown(controller.dispose);
        row.setUp(controller);
        expect(controller.blockRanges.toSet(), row.before);

        controller
          ..selection = row.selection
          ..pasteUnformatted(row.pasted);

        expect(controller.text, row.expectedText);
        expect(controller.blockRanges.toSet(), row.expected);
        expect(
          controller.selection,
          TextSelection.collapsed(offset: row.caret),
        );
      });
    }
  });

  group('pasted line separators normalize to newlines', () {
    const separators = [
      (name: r'\r\n', pasted: 'X\r\nY'),
      (name: r'lone \r', pasted: 'X\rY'),
      (name: 'U+2028', pasted: 'X Y'),
      (name: 'U+2029', pasted: 'X Y'),
    ];

    for (final separator in separators) {
      test('${separator.name} pastes as one newline on a quote line', () {
        final controller = FacetEditingController(text: fixture);
        addTearDown(controller.dispose);
        toggleOver(controller, 3, 3, BlockFormat.blockquote);
        expect(controller.blockRanges.toSet(), {
          const BlockRange(BlockFormat.blockquote, 3, 7),
        });

        controller
          ..selection = const TextSelection.collapsed(offset: 5)
          ..pasteUnformatted(separator.pasted);

        expect(controller.text, 'aa\nbbX\nYbb\ncc');
        expect(controller.blockRanges.toSet(), {
          const BlockRange(BlockFormat.blockquote, 3, 10),
        });
        expect(controller.selection, const TextSelection.collapsed(offset: 8));
      });
    }

    test(r'\r\n then lone \r pastes as two newlines, not three', () {
      final controller = FacetEditingController(text: 'q');
      addTearDown(controller.dispose);
      toggleOver(controller, 0, 0, BlockFormat.blockquote);

      controller
        ..selection = const TextSelection.collapsed(offset: 1)
        ..pasteUnformatted('\r\n\rx');

      expect(controller.text, 'q\n\nx');
      expect(controller.blockRanges.toSet(), {
        const BlockRange(BlockFormat.blockquote, 0, 1),
      });
      expect(controller.selection, const TextSelection.collapsed(offset: 4));
    });
  });

  test('paste during an IME composition commits it once', () {
    final controller = FacetEditingController(text: '0123456789');
    addTearDown(controller.dispose);
    toggleInlineOver(controller, 0, 10, InlineFormat.bold);
    controller.selection = const TextSelection.collapsed(offset: 5);
    expect(controller.inlineRanges.toSet(), {
      const InlineRange(InlineFormat.bold, 0, 10),
    });

    controller
      ..value = const TextEditingValue(
        text: '01234ab56789',
        selection: TextSelection.collapsed(offset: 7),
        composing: TextRange(start: 5, end: 7),
      )
      ..pasteUnformatted('YZ');

    expect(controller.text, '01234abYZ56789');
    expect(controller.inlineRanges.toSet(), {
      const InlineRange(InlineFormat.bold, 0, 7),
      const InlineRange(InlineFormat.bold, 9, 14),
    });
    expect(controller.selection, const TextSelection.collapsed(offset: 9));
    expect(controller.value.composing, TextRange.empty);

    controller.value = controller.value.copyWith(composing: TextRange.empty);

    expect(controller.text, '01234abYZ56789');
    expect(controller.inlineRanges.toSet(), {
      const InlineRange(InlineFormat.bold, 0, 7),
      const InlineRange(InlineFormat.bold, 9, 14),
    });
  });
}
