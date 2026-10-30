import 'dart:math';

import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Three lines: "aa" [0,2], "bb" [3,5], "cc" [6,8].
const threeLines = 'aa\nbb\ncc';

/// Four lines: [threeLines] plus "dd" [9,11].
const fourLines = 'aa\nbb\ncc\ndd';

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

typedef ToggleRow = ({
  String name,
  void Function(FacetEditingController controller) setUp,
  Set<BlockRange> expected,
});

void runRows(List<ToggleRow> rows, {String text = threeLines}) {
  for (final row in rows) {
    test(row.name, () {
      final controller = FacetEditingController(text: text);
      addTearDown(controller.dispose);
      row.setUp(controller);
      expect(controller.blockRanges.toSet(), row.expected);
    });
  }
}

const emptyLineFormats = [
  (format: BlockFormat.blockquote, level: 1),
  (format: BlockFormat.heading, level: 2),
  (format: BlockFormat.codeBlock, level: 1),
];
const emptyLineAnchors = [
  (
    name: 'empty document',
    text: '',
    caret: 0,
    typed: [('x', 1), ('xy', 2)],
    start: 0,
    end: 2,
  ),
  (
    name: 'empty last line',
    text: 'abc\n',
    caret: 4,
    typed: [('abc\nx', 5), ('abc\nxy', 6)],
    start: 4,
    end: 6,
  ),
];

void main() {
  group('D1 quote covers every touched line', () {
    runRows([
      (
        name: 'D1 selection touching parts of lines 1-3 quotes all three',
        setUp: (controller) =>
            toggleOver(controller, 1, 7, BlockFormat.blockquote),
        expected: {const BlockRange(BlockFormat.blockquote, 0, 8)},
      ),
      (
        name: 'D1 selection ending at a line start does not touch that line',
        setUp: (controller) =>
            toggleOver(controller, 1, 6, BlockFormat.blockquote),
        expected: {const BlockRange(BlockFormat.blockquote, 0, 5)},
      ),
    ]);

    test('D1 toggle during a composition applies to the composed text', () {
      final controller = FacetEditingController(text: threeLines);
      addTearDown(controller.dispose);
      deliver(controller, 'aa\nbbx\ncc', 6, const TextRange(start: 3, end: 6));
      controller.toggleBlock(BlockFormat.blockquote);

      expect(controller.blockRanges.toSet(), {
        const BlockRange(BlockFormat.blockquote, 3, 6),
      });

      deliver(controller, 'aa\nbbx\ncc', 6);

      expect(controller.blockRanges.toSet(), {
        const BlockRange(BlockFormat.blockquote, 3, 6),
      });
    });
  });

  test('D2 toggling quote over fully quoted lines removes it', () {
    final controller = FacetEditingController(text: threeLines);
    addTearDown(controller.dispose);
    toggleOver(controller, 0, 8, BlockFormat.blockquote);
    expect(controller.blockRanges.toSet(), {
      const BlockRange(BlockFormat.blockquote, 0, 8),
    }, reason: 'precondition: the quote exists before toggling it off');

    toggleOver(controller, 1, 7, BlockFormat.blockquote);

    expect(controller.blockRanges, isEmpty);
  });

  test('D3 caret on the middle line splits the quote', () {
    final controller = FacetEditingController(text: threeLines);
    addTearDown(controller.dispose);
    toggleOver(controller, 0, 8, BlockFormat.blockquote);

    toggleOver(controller, 4, 4, BlockFormat.blockquote);

    expect(controller.blockRanges.toSet(), {
      const BlockRange(BlockFormat.blockquote, 0, 2),
      const BlockRange(BlockFormat.blockquote, 6, 8),
    });
  });

  group('D4 heading levels', () {
    runRows([
      (
        name: 'D4 heading gives each touched line its own range',
        setUp: (controller) =>
            toggleOver(controller, 1, 4, BlockFormat.heading, level: 2),
        expected: {
          const BlockRange(BlockFormat.heading, 0, 2, level: 2),
          const BlockRange(BlockFormat.heading, 3, 5, level: 2),
        },
      ),
      (
        name: 'D4 picking H2 on H1 lines replaces the level',
        setUp: (controller) {
          toggleOver(controller, 1, 4, BlockFormat.heading);
          toggleOver(controller, 1, 4, BlockFormat.heading, level: 2);
        },
        expected: {
          const BlockRange(BlockFormat.heading, 0, 2, level: 2),
          const BlockRange(BlockFormat.heading, 3, 5, level: 2),
        },
      ),
      (
        name: 'D4 heading on line 3 preserves the heading on line 1',
        setUp: (controller) {
          toggleOver(controller, 1, 1, BlockFormat.heading);
          toggleOver(controller, 7, 7, BlockFormat.heading, level: 2);
        },
        expected: {
          const BlockRange(BlockFormat.heading, 0, 2),
          const BlockRange(BlockFormat.heading, 6, 8, level: 2),
        },
      ),
    ]);

    test('D4 toggling H2 on H2 lines removes the headings', () {
      final controller = FacetEditingController(text: threeLines);
      addTearDown(controller.dispose);
      toggleOver(controller, 1, 4, BlockFormat.heading, level: 2);
      expect(controller.blockRanges.toSet(), {
        const BlockRange(BlockFormat.heading, 0, 2, level: 2),
        const BlockRange(BlockFormat.heading, 3, 5, level: 2),
      }, reason: 'precondition: both lines are H2 before toggling H2 off');

      toggleOver(controller, 1, 4, BlockFormat.heading, level: 2);

      expect(controller.blockRanges, isEmpty);
    });
  });

  group('D5 heading and code block are exclusive per line', () {
    runRows([
      (
        name: 'D5 code block replaces the heading on its line',
        setUp: (controller) {
          toggleOver(controller, 4, 4, BlockFormat.heading);
          toggleOver(controller, 4, 4, BlockFormat.codeBlock);
        },
        expected: {const BlockRange(BlockFormat.codeBlock, 3, 5)},
      ),
      (
        name: 'D5 heading splits the code block around its line',
        setUp: (controller) {
          toggleOver(controller, 0, 8, BlockFormat.codeBlock);
          toggleOver(controller, 4, 4, BlockFormat.heading, level: 2);
        },
        expected: {
          const BlockRange(BlockFormat.codeBlock, 0, 2),
          const BlockRange(BlockFormat.codeBlock, 6, 8),
          const BlockRange(BlockFormat.heading, 3, 5, level: 2),
        },
      ),
      (
        name: 'D5 heading inside a quoted code block keeps the quote whole',
        setUp: (controller) {
          toggleOver(controller, 0, 8, BlockFormat.blockquote);
          toggleOver(controller, 0, 8, BlockFormat.codeBlock);
          toggleOver(controller, 4, 4, BlockFormat.heading, level: 2);
        },
        expected: {
          const BlockRange(BlockFormat.blockquote, 0, 8),
          const BlockRange(BlockFormat.codeBlock, 0, 2),
          const BlockRange(BlockFormat.heading, 3, 5, level: 2),
          const BlockRange(BlockFormat.codeBlock, 6, 8),
        },
      ),
    ]);
  });

  group('D6 toggle order does not change the result', () {
    runRows([
      (
        name: 'D6 quote then code block over all lines',
        setUp: (controller) {
          toggleOver(controller, 0, 8, BlockFormat.blockquote);
          toggleOver(controller, 0, 8, BlockFormat.codeBlock);
        },
        expected: {
          const BlockRange(BlockFormat.blockquote, 0, 8),
          const BlockRange(BlockFormat.codeBlock, 0, 8),
        },
      ),
      (
        name: 'D6 code block then quote over all lines',
        setUp: (controller) {
          toggleOver(controller, 0, 8, BlockFormat.codeBlock);
          toggleOver(controller, 0, 8, BlockFormat.blockquote);
        },
        expected: {
          const BlockRange(BlockFormat.blockquote, 0, 8),
          const BlockRange(BlockFormat.codeBlock, 0, 8),
        },
      ),
      (
        name: 'D6 quote then heading on line 2',
        setUp: (controller) {
          toggleOver(controller, 4, 4, BlockFormat.blockquote);
          toggleOver(controller, 4, 4, BlockFormat.heading);
        },
        expected: {
          const BlockRange(BlockFormat.blockquote, 3, 5),
          const BlockRange(BlockFormat.heading, 3, 5),
        },
      ),
      (
        name: 'D6 heading then quote on line 2',
        setUp: (controller) {
          toggleOver(controller, 4, 4, BlockFormat.heading);
          toggleOver(controller, 4, 4, BlockFormat.blockquote);
        },
        expected: {
          const BlockRange(BlockFormat.blockquote, 3, 5),
          const BlockRange(BlockFormat.heading, 3, 5),
        },
      ),
    ]);
  });

  group('D7 conflicting blocks expand to the existing edges', () {
    runRows([
      (
        name: 'D7 quote inside part of a code block widens to the code block',
        setUp: (controller) {
          toggleOver(controller, 0, 8, BlockFormat.codeBlock);
          toggleOver(controller, 4, 4, BlockFormat.blockquote);
        },
        expected: {
          const BlockRange(BlockFormat.codeBlock, 0, 8),
          const BlockRange(BlockFormat.blockquote, 0, 8),
        },
      ),
      (
        name: 'D7 code block on a line inside a quote does not widen',
        setUp: (controller) {
          toggleOver(controller, 0, 8, BlockFormat.blockquote);
          toggleOver(controller, 4, 4, BlockFormat.codeBlock);
        },
        expected: {
          const BlockRange(BlockFormat.blockquote, 0, 8),
          const BlockRange(BlockFormat.codeBlock, 3, 5),
        },
      ),
    ]);

    runRows(text: fourLines, [
      (
        name: 'D7 quote crossing the code block edge widens to its start',
        setUp: (controller) {
          toggleOver(controller, 0, 8, BlockFormat.codeBlock);
          toggleOver(controller, 4, 10, BlockFormat.blockquote);
        },
        expected: {
          const BlockRange(BlockFormat.codeBlock, 0, 8),
          const BlockRange(BlockFormat.blockquote, 0, 11),
        },
      ),
      (
        name:
            'D7 code block crossing the quote edge widens to its start '
            'and the quote widens to the code block',
        setUp: (controller) {
          toggleOver(controller, 0, 8, BlockFormat.blockquote);
          toggleOver(controller, 4, 10, BlockFormat.codeBlock);
        },
        expected: {
          const BlockRange(BlockFormat.blockquote, 0, 11),
          const BlockRange(BlockFormat.codeBlock, 0, 11),
        },
      ),
      (
        name: 'D7 widened code block removes the heading on an untouched line',
        setUp: (controller) {
          toggleOver(controller, 0, 8, BlockFormat.blockquote);
          toggleOver(controller, 1, 1, BlockFormat.heading);
          toggleOver(controller, 4, 10, BlockFormat.codeBlock);
        },
        expected: {
          const BlockRange(BlockFormat.blockquote, 0, 11),
          const BlockRange(BlockFormat.codeBlock, 0, 11),
        },
      ),
      (
        name: 'D7 code block over the lines around a quote widens the quote',
        setUp: (controller) {
          toggleOver(controller, 4, 7, BlockFormat.blockquote);
          toggleOver(controller, 0, 11, BlockFormat.codeBlock);
        },
        expected: {
          const BlockRange(BlockFormat.blockquote, 0, 11),
          const BlockRange(BlockFormat.codeBlock, 0, 11),
        },
      ),
      (
        name:
            'D7 code block next to a code block inside a quote stays '
            'separate',
        setUp: (controller) {
          toggleOver(controller, 0, 8, BlockFormat.blockquote);
          toggleOver(controller, 4, 7, BlockFormat.codeBlock);
          toggleOver(controller, 10, 10, BlockFormat.codeBlock);
        },
        expected: {
          const BlockRange(BlockFormat.blockquote, 0, 8),
          const BlockRange(BlockFormat.codeBlock, 3, 8),
          const BlockRange(BlockFormat.codeBlock, 9, 11),
        },
      ),
      (
        name:
            'D7 code block next to a code block matching a quote stays '
            'separate',
        setUp: (controller) {
          toggleOver(controller, 4, 4, BlockFormat.blockquote);
          toggleOver(controller, 4, 4, BlockFormat.codeBlock);
          toggleOver(controller, 7, 7, BlockFormat.codeBlock);
        },
        expected: {
          const BlockRange(BlockFormat.blockquote, 3, 5),
          const BlockRange(BlockFormat.codeBlock, 3, 5),
          const BlockRange(BlockFormat.codeBlock, 6, 8),
        },
      ),
      (
        name: 'D7 quote next to a quote matching a code block merges with it',
        setUp: (controller) {
          toggleOver(controller, 4, 4, BlockFormat.blockquote);
          toggleOver(controller, 4, 4, BlockFormat.codeBlock);
          toggleOver(controller, 7, 7, BlockFormat.blockquote);
        },
        expected: {
          const BlockRange(BlockFormat.blockquote, 3, 8),
          const BlockRange(BlockFormat.codeBlock, 3, 5),
        },
      ),
      (
        name: 'D7 removing the quote merges the code blocks it kept apart',
        setUp: (controller) {
          toggleOver(controller, 0, 8, BlockFormat.blockquote);
          toggleOver(controller, 4, 7, BlockFormat.codeBlock);
          toggleOver(controller, 10, 10, BlockFormat.codeBlock);
          toggleOver(controller, 0, 8, BlockFormat.blockquote);
        },
        expected: {const BlockRange(BlockFormat.codeBlock, 3, 11)},
      ),
      (
        name:
            'D7 quote removal from a quote matching a code block removes '
            'it from the whole code block',
        setUp: (controller) {
          toggleOver(controller, 0, 8, BlockFormat.blockquote);
          toggleOver(controller, 0, 8, BlockFormat.codeBlock);
          toggleOver(controller, 4, 4, BlockFormat.blockquote);
        },
        expected: {const BlockRange(BlockFormat.codeBlock, 0, 8)},
      ),
      (
        name: 'D7 quote removal widens over the code block it would cross',
        setUp: (controller) {
          toggleOver(controller, 0, 11, BlockFormat.blockquote);
          toggleOver(controller, 3, 8, BlockFormat.codeBlock);
          toggleOver(controller, 4, 4, BlockFormat.blockquote);
        },
        expected: {
          const BlockRange(BlockFormat.blockquote, 0, 2),
          const BlockRange(BlockFormat.blockquote, 9, 11),
          const BlockRange(BlockFormat.codeBlock, 3, 8),
        },
      ),
    ]);

    test('D7 heading inside a code block that widened a quote keeps the quote '
        'whole', () {
      final controller = FacetEditingController(text: fourLines);
      addTearDown(controller.dispose);
      toggleOver(controller, 3, 8, BlockFormat.blockquote);
      toggleOver(controller, 0, 11, BlockFormat.codeBlock);
      expect(controller.blockRanges.toSet(), {
        const BlockRange(BlockFormat.blockquote, 0, 11),
        const BlockRange(BlockFormat.codeBlock, 0, 11),
      }, reason: 'precondition: the code block widened the quote');

      toggleOver(controller, 4, 4, BlockFormat.heading, level: 2);

      expect(controller.blockRanges.toSet(), {
        const BlockRange(BlockFormat.codeBlock, 0, 2),
        const BlockRange(BlockFormat.codeBlock, 6, 11),
        const BlockRange(BlockFormat.blockquote, 0, 11),
        const BlockRange(BlockFormat.heading, 3, 5, level: 2),
      });
    });
  });

  test('D8 random toggle sequences keep block ranges well formed', () {
    const text = 'aa\nbb\n\ncc\ndd\n\nee';
    final lines = linesOf(text);
    final lineStarts = {for (final line in lines) line.start};
    final lineEnds = {for (final line in lines) line.end};
    var keptSeparateAdjacencies = 0;

    for (var seed = 0; seed < 20; seed++) {
      final random = Random(seed);
      final controller = FacetEditingController(text: text);
      addTearDown(controller.dispose);

      for (var step = 0; step < 30; step++) {
        final format = BlockFormat.values[random.nextInt(3)];
        final level = format == BlockFormat.heading ? 1 + random.nextInt(3) : 1;
        final existing = controller.blockRanges;
        final TextSelection selection;
        if (existing.isNotEmpty && random.nextInt(3) == 0) {
          // A caret on the line just before or after an existing block.
          final neighbour = existing[random.nextInt(existing.length)];
          final caret = random.nextBool()
              ? neighbour.start - 1
              : neighbour.end + 1;
          final clamped = caret.clamp(0, text.length);
          selection = TextSelection.collapsed(offset: clamped);
        } else {
          final base = random.nextInt(text.length + 1);
          final extent = random.nextBool()
              ? base
              : random.nextInt(text.length + 1);
          selection = TextSelection(baseOffset: base, extentOffset: extent);
        }
        final touched = touchedLines(lines, selection.start, selection.end);
        final removing = touched.every(
          (line) => covers(controller.blockRanges, line, format, level),
        );
        final where =
            'seed $seed step $step: ${removing ? 'removing' : 'adding'} '
            '$format level $level over ${selection.start}..${selection.end}';

        controller
          ..selection = selection
          ..toggleBlock(format, level: level);
        final ranges = controller.blockRanges;

        for (final range in ranges) {
          expect(
            lineStarts.contains(range.start) &&
                lineEnds.contains(range.end) &&
                range.start <= range.end,
            isTrue,
            reason: '$where: $range must span whole lines',
          );
        }
        for (var first = 0; first < ranges.length; first++) {
          for (var second = first + 1; second < ranges.length; second++) {
            final a = ranges[first];
            final b = ranges[second];
            final disjoint = a.end < b.start || b.end < a.start;
            final nested =
                (a.start <= b.start && b.end <= a.end) ||
                (b.start <= a.start && a.end <= b.end);
            expect(
              disjoint || nested,
              isTrue,
              reason: '$where: $a and $b cross',
            );
            final quoteAndCode = {
              a.format,
              b.format,
            }.containsAll({BlockFormat.blockquote, BlockFormat.codeBlock});
            if (quoteAndCode) {
              final quote = a.format == BlockFormat.blockquote ? a : b;
              final code = a.format == BlockFormat.codeBlock ? a : b;
              final codeStrictlyContainsQuote =
                  code.start <= quote.start &&
                  quote.end <= code.end &&
                  (code.start != quote.start || code.end != quote.end);
              expect(
                codeStrictlyContainsQuote,
                isFalse,
                reason: '$where: code block $code strictly contains $quote',
              );
            }
            if (a.format != b.format) {
              continue;
            }
            expect(
              disjoint,
              isTrue,
              reason: '$where: same-format $a and $b overlap',
            );
            // Lines are separated by one newline, so ranges on adjacent
            // lines are one offset apart.
            final adjacent = a.end + 1 == b.start || b.end + 1 == a.start;
            if (a.format == BlockFormat.heading || !adjacent) {
              continue;
            }
            // Adjacent quotes or code blocks stay separate only when their
            // merged span would cross another block's edge or put a quote
            // strictly inside a code block.
            final merged = (
              start: min(a.start, b.start),
              end: max(a.end, b.end),
            );
            final mergeBlocked = ranges.any((other) {
              if (other.format == a.format ||
                  other.format == BlockFormat.heading) {
                return false;
              }
              final overlaps =
                  other.start <= merged.end && merged.start <= other.end;
              final mergedContainsOther =
                  merged.start <= other.start && other.end <= merged.end;
              final otherContainsMerged =
                  other.start <= merged.start && merged.end <= other.end;
              final crosses =
                  overlaps && !mergedContainsOther && !otherContainsMerged;
              final quoteInsideCode =
                  a.format == BlockFormat.codeBlock &&
                  mergedContainsOther &&
                  !otherContainsMerged;
              return crosses || quoteInsideCode;
            });
            expect(
              mergeBlocked,
              isTrue,
              reason: '$where: adjacent $a and $b should have merged',
            );
            keptSeparateAdjacencies++;
          }
        }
        for (final line in lines) {
          final hasHeading = ranges.any(
            (range) =>
                range.format == BlockFormat.heading &&
                range.start <= line.start &&
                line.end <= range.end,
          );
          final hasCodeBlock = covers(ranges, line, BlockFormat.codeBlock, 1);
          expect(
            hasHeading && hasCodeBlock,
            isFalse,
            reason: '$where: line $line has both a heading and a code block',
          );
        }
        for (final line in touched) {
          expect(
            covers(ranges, line, format, level),
            removing ? isFalse : isTrue,
            reason: '$where: touched line $line in $ranges',
          );
        }
      }
    }
    expect(
      keptSeparateAdjacencies,
      greaterThan(0),
      reason: 'the sequences must reach adjacent blocks kept separate',
    );
  });

  group('D9 a block activated on an empty line covers the typed text', () {
    for (final block in emptyLineFormats) {
      for (final anchor in emptyLineAnchors) {
        test('D9 ${block.format} on the ${anchor.name} then typing', () {
          final controller = FacetEditingController(text: anchor.text);
          addTearDown(controller.dispose);
          toggleOver(
            controller,
            anchor.caret,
            anchor.caret,
            block.format,
            level: block.level,
          );
          for (final (text, caret) in anchor.typed) {
            deliver(controller, text, caret);
          }

          expect(controller.blockRanges.toSet(), {
            BlockRange(
              block.format,
              anchor.start,
              anchor.end,
              level: block.level,
            ),
          });
        });
      }
    }

    for (final anchor in emptyLineAnchors) {
      test('D9 quote on the ${anchor.name} then composing and committing', () {
        final controller = FacetEditingController(text: anchor.text);
        addTearDown(controller.dispose);
        toggleOver(
          controller,
          anchor.caret,
          anchor.caret,
          BlockFormat.blockquote,
        );
        for (final (text, caret) in anchor.typed) {
          deliver(
            controller,
            text,
            caret,
            TextRange(start: anchor.start, end: caret),
          );
        }
        final (committed, caret) = anchor.typed.last;
        deliver(controller, committed, caret);

        expect(controller.blockRanges.toSet(), {
          BlockRange(BlockFormat.blockquote, anchor.start, anchor.end),
        });
      });
    }

    test('D9 activation under a quote extends that quote', () {
      final controller = FacetEditingController(text: 'abc\n');
      addTearDown(controller.dispose);
      toggleOver(controller, 0, 3, BlockFormat.blockquote);
      toggleOver(controller, 4, 4, BlockFormat.blockquote);
      deliver(controller, 'abc\nx', 5);
      deliver(controller, 'abc\nxy', 6);

      expect(controller.blockRanges.toSet(), {
        const BlockRange(BlockFormat.blockquote, 0, 6),
      });
    });
  });

  group('D10 a block toggled off before typing stays off', () {
    for (final block in emptyLineFormats) {
      for (final anchor in emptyLineAnchors) {
        test('D10 ${block.format} on the ${anchor.name} toggled off', () {
          final controller = FacetEditingController(text: anchor.text);
          addTearDown(controller.dispose);
          toggleOver(
            controller,
            anchor.caret,
            anchor.caret,
            block.format,
            level: block.level,
          );
          expect(controller.blockRanges.toSet(), {
            BlockRange(
              block.format,
              anchor.caret,
              anchor.caret,
              level: block.level,
            ),
          }, reason: 'precondition: activation creates a zero-length range');

          toggleOver(
            controller,
            anchor.caret,
            anchor.caret,
            block.format,
            level: block.level,
          );
          expect(controller.blockRanges, isEmpty);

          for (final (text, caret) in anchor.typed) {
            deliver(controller, text, caret);
          }
          expect(controller.blockRanges, isEmpty);
        });
      }
    }

    test('D10 clear drops an activated quote on the empty document', () {
      final controller = FacetEditingController();
      addTearDown(controller.dispose);
      toggleOver(controller, 0, 0, BlockFormat.blockquote);
      expect(controller.blockRanges.toSet(), {
        const BlockRange(BlockFormat.blockquote, 0, 0),
      }, reason: 'precondition: activation creates a zero-length range');

      final seenByListener = <List<BlockRange>>[];
      controller
        ..addListener(() => seenByListener.add(controller.blockRanges))
        ..clear();
      expect(controller.blockRanges, isEmpty);
      expect(seenByListener, [
        isEmpty,
      ], reason: 'one notification, after the range is gone');

      deliver(controller, 'x', 1);
      deliver(controller, 'xy', 2);
      expect(controller.blockRanges, isEmpty);
    });

    for (final row in [
      (
        name: 'a quote on line 1 of "abc"',
        text: 'abc',
        precondition: const BlockRange(BlockFormat.blockquote, 0, 3),
      ),
      (
        name: 'an activated quote on the empty document',
        text: '',
        precondition: const BlockRange(BlockFormat.blockquote, 0, 0),
      ),
    ]) {
      test('D10 text = \'\' drops block ranges: ${row.name}', () {
        final controller = FacetEditingController(text: row.text);
        addTearDown(controller.dispose);
        toggleOver(controller, 0, 0, BlockFormat.blockquote);
        expect(controller.blockRanges.toSet(), {
          row.precondition,
        }, reason: 'precondition: the quote exists before the reset');
        if (row.text.isEmpty) {
          // `text =` leaves the selection at offset -1. Parking it there
          // first means the reset changes nothing but the block ranges.
          controller.selection = const TextSelection.collapsed(offset: -1);
          expect(controller.blockRanges.toSet(), {
            row.precondition,
          }, reason: 'precondition: moving the caret keeps the quote');
        }
        final valueBefore = controller.value;

        final seenByListener = <List<BlockRange>>[];
        controller
          ..addListener(() => seenByListener.add(controller.blockRanges))
          ..text = '';
        expect(controller.blockRanges, isEmpty);
        expect(seenByListener, [
          isEmpty,
        ], reason: 'one notification, after the ranges are gone');
        if (row.text.isEmpty) {
          expect(
            controller.value,
            valueBefore,
            reason: 'precondition: the reset left the value unchanged',
          );
        }

        deliver(controller, 'x', 1);
        deliver(controller, 'xy', 2);
        expect(controller.blockRanges, isEmpty);
      });
    }
  });

  test('D1 a composition before a quote moves the quote provisionally', () {
    final controller = FacetEditingController(text: threeLines);
    addTearDown(controller.dispose);
    toggleOver(controller, 4, 4, BlockFormat.blockquote);
    expect(controller.blockRanges.toSet(), {
      const BlockRange(BlockFormat.blockquote, 3, 5),
    }, reason: 'precondition: line 2 is quoted');

    deliver(controller, threeLines, 2, const TextRange(start: 2, end: 2));
    deliver(controller, 'aaxyz\nbb\ncc', 5, const TextRange(start: 2, end: 5));
    expect(controller.blockRanges.toSet(), {
      const BlockRange(BlockFormat.blockquote, 6, 8),
    }, reason: 'while composing, the quote is shown on the composed text');

    controller.toggleBlock(BlockFormat.heading, level: 2);
    deliver(controller, 'aaxyz\nbb\ncc', 5);
    expect(controller.blockRanges.toSet(), {
      const BlockRange(BlockFormat.heading, 0, 5, level: 2),
      const BlockRange(BlockFormat.blockquote, 6, 8),
    });
  });

  test('D1 a cancelled composition restores the block ranges', () {
    final controller = FacetEditingController(text: threeLines);
    addTearDown(controller.dispose);
    toggleOver(controller, 1, 1, BlockFormat.blockquote);
    expect(controller.blockRanges.toSet(), {
      const BlockRange(BlockFormat.blockquote, 0, 2),
    }, reason: 'precondition: line 1 is quoted before the composition');
    deliver(controller, threeLines, 5);
    deliver(controller, threeLines, 5, const TextRange(start: 3, end: 5));
    deliver(controller, 'aa\nb\ncc', 4, const TextRange(start: 3, end: 4));
    // A toggle during the composition rebases it onto the composed text.
    controller.toggleBlock(BlockFormat.blockquote);
    expect(controller.blockRanges.toSet(), {
      const BlockRange(BlockFormat.blockquote, 0, 4),
    }, reason: 'precondition: the toggle quoted the composed line 2');

    deliver(controller, threeLines, 5);

    expect(controller.blockRanges.toSet(), {
      const BlockRange(BlockFormat.blockquote, 0, 2),
    });
  });
}

/// The lines of [text] as [start, end] ranges, excluding the newline.
List<TextRange> linesOf(String text) {
  final lines = <TextRange>[];
  var start = 0;
  for (var index = 0; index <= text.length; index++) {
    if (index == text.length || text[index] == '\n') {
      lines.add(TextRange(start: start, end: index));
      start = index + 1;
    }
  }
  return lines;
}

/// Lines holding a position in [start]..[end]; a non-collapsed selection
/// ending at a line start does not touch that line.
List<TextRange> touchedLines(List<TextRange> lines, int start, int end) {
  final last = end > start && lines.any((line) => line.start == end)
      ? end - 1
      : end;
  return [
    for (final line in lines)
      if (line.start <= last && line.end >= start) line,
  ];
}

/// Whether [line] lies inside a [format] range (a heading at [level]).
bool covers(
  List<BlockRange> ranges,
  TextRange line,
  BlockFormat format,
  int level,
) => ranges.any(
  (range) =>
      range.format == format &&
      (format != BlockFormat.heading || range.level == level) &&
      range.start <= line.start &&
      line.end <= range.end,
);
