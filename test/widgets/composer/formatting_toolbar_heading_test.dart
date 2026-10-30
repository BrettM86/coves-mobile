import 'dart:ui' show PointerDeviceKind, Tristate;

import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'formatting_toolbar_test_helpers.dart';

/// Opens the picker and picks [entry].
Future<void> pickHeading(WidgetTester tester, String entry) async {
  await openPicker(tester);
  await pickEntry(tester, entry);
}

/// A controller over [text] whose lines in [start]..[end] are headings at
/// [level], with that range selected.
FacetEditingController headed(String text, int start, int end, int level) =>
    selected(text, start, end)..toggleBlock(BlockFormat.heading, level: level);

void main() {
  group('Heading button inside a code block', () {
    toolbarTest('Heading stays enabled with the caret in a code block', (
      tester,
    ) async {
      final controller = FacetEditingController(text: 'bold\ncode')
        ..selection = const TextSelection.collapsed(offset: 7)
        ..toggleBlock(BlockFormat.codeBlock);
      await pumpToolbar(tester, controller);
      expect(controller.isSelectionInCodeBlock(), isTrue);

      expect(enabledState(tester, 'Heading'), Tristate.isTrue);
    });
  });

  group('Heading picker', () {
    toolbarTest('Heading opens four entries, each a button with a selected '
        'state', (tester) async {
      await pumpToolbar(tester, selected('one\ntwo', 0, 7));

      await openPicker(tester);

      for (final label in pickerLabels) {
        expect(button(label), findsOneWidget, reason: label);
        final node = tester.getSemantics(button(label));
        expect(node.label, label);
        expect(node.flagsCollection.isButton, isTrue, reason: label);
        expect(
          node.flagsCollection.isSelected,
          isNot(Tristate.none),
          reason: '$label exposes a selected state',
        );
      }
    });

    final rows =
        <
          ({
            String name,
            FacetEditingController Function() controller,
            List<BlockRange> before,
            String entry,
            List<BlockRange> after,
          })
        >[
          (
            name: 'Heading 2 over two plain lines heads both at level 2',
            controller: () => selected('one\ntwo', 0, 7),
            before: [],
            entry: 'Heading 2',
            after: [
              const BlockRange(BlockFormat.heading, 0, 3, level: 2),
              const BlockRange(BlockFormat.heading, 4, 7, level: 2),
            ],
          ),
          (
            name: 'Heading 3 over two H2 lines changes both to level 3',
            controller: () => headed('one\ntwo', 0, 7, 2),
            before: [
              const BlockRange(BlockFormat.heading, 0, 3, level: 2),
              const BlockRange(BlockFormat.heading, 4, 7, level: 2),
            ],
            entry: 'Heading 3',
            after: [
              const BlockRange(BlockFormat.heading, 0, 3, level: 3),
              const BlockRange(BlockFormat.heading, 4, 7, level: 3),
            ],
          ),
        ];
    for (final row in rows) {
      toolbarTest('${row.name} and closes the picker', (tester) async {
        final controller = row.controller();
        expect(controller.blockRanges, row.before, reason: 'before');
        await pumpToolbar(tester, controller);

        await pickHeading(tester, row.entry);

        expect(controller.blockRanges, row.after);
        for (final label in pickerLabels) {
          expect(button(label), findsNothing, reason: '$label after picking');
        }
      });
    }
  });

  group('Heading active state', () {
    toolbarTest('over H2 lines Heading and the Heading 2 entry are selected', (
      tester,
    ) async {
      final controller = headed('one\ntwo', 0, 7, 2);
      expect(controller.activeHeadingLevel(), 2);
      await pumpToolbar(tester, controller);

      expect(selectedState(tester, 'Heading'), Tristate.isTrue);
      await openPicker(tester);
      final want = {
        'Heading 1': Tristate.isFalse,
        'Heading 2': Tristate.isTrue,
        'Heading 3': Tristate.isFalse,
      };
      for (final entry in want.entries) {
        expect(
          selectedState(tester, entry.key),
          entry.value,
          reason: entry.key,
        );
      }
    });

    toolbarTest('on a plain line Heading is not selected', (tester) async {
      final controller = selected('one', 0, 3);
      expect(controller.activeHeadingLevel(), isNull);
      await pumpToolbar(tester, controller);

      expect(selectedState(tester, 'Heading'), Tristate.isFalse);
    });
  });

  group('Heading picker in an empty composer', () {
    final rows = <({List<String> entries, List<BlockRange> want})>[
      (
        entries: ['Heading 2'],
        want: [const BlockRange(BlockFormat.heading, 0, 5, level: 2)],
      ),
      (entries: ['Heading 2', 'Normal text'], want: []),
      (entries: ['Heading 2', 'Heading 2'], want: []),
    ];
    for (final row in rows) {
      toolbarTest('${row.entries.join(' then ')} then typing "Title"', (
        tester,
      ) async {
        final controller = FacetEditingController();
        await pumpToolbar(tester, controller, withField: true);
        await focusField(tester, const TextSelection.collapsed(offset: 0));

        for (final entry in row.entries) {
          await pickHeading(tester, entry);
        }
        await typeAs(tester, 'Title', 5);

        expect(controller.text, 'Title');
        expect(controller.blockRanges, row.want);
      });
    }
  });

  group('Heading removal', () {
    final rows =
        <
          ({
            String name,
            FacetEditingController Function() controller,
            List<BlockRange> before,
            String entry,
          })
        >[
          (
            name: 'Normal text on an H2 line removes the heading',
            controller: () => headed('title', 2, 2, 2),
            before: [const BlockRange(BlockFormat.heading, 0, 5, level: 2)],
            entry: 'Normal text',
          ),
          (
            name: 'Heading 2 on an H2 line removes the heading',
            controller: () => headed('title', 2, 2, 2),
            before: [const BlockRange(BlockFormat.heading, 0, 5, level: 2)],
            entry: 'Heading 2',
          ),
          (
            name:
                'Normal text over H1, H2 and plain lines removes every '
                'heading and adds none',
            controller: () => headed('one\ntwo\nthree', 0, 3, 1)
              ..selection = const TextSelection.collapsed(offset: 5)
              ..toggleBlock(BlockFormat.heading, level: 2)
              ..selection = const TextSelection(
                baseOffset: 0,
                extentOffset: 13,
              ),
            before: [
              const BlockRange(BlockFormat.heading, 0, 3),
              const BlockRange(BlockFormat.heading, 4, 7, level: 2),
            ],
            entry: 'Normal text',
          ),
        ];
    for (final row in rows) {
      toolbarTest(row.name, (tester) async {
        final controller = row.controller();
        expect(controller.blockRanges, row.before, reason: 'before');
        await pumpToolbar(tester, controller);

        await pickHeading(tester, row.entry);

        expect(controller.blockRanges, isEmpty);
      });
    }
  });

  group('Heading picker keeps the field focused', () {
    toolbarTest('mouse taps on Heading and Heading 1 keep focus and '
        'selection', (tester) async {
      final controller = FacetEditingController(text: 'hello world');
      await pumpToolbar(tester, controller, withField: true);
      const selection = TextSelection(baseOffset: 2, extentOffset: 5);
      await focusField(tester, selection);
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.focusNode.hasFocus, isTrue, reason: 'focused before');
      expect(controller.selection, selection, reason: 'selection before');

      await openPicker(tester, kind: PointerDeviceKind.mouse);
      expect(field.focusNode.hasFocus, isTrue, reason: 'focused, picker open');
      expect(controller.selection, selection, reason: 'selection, picker open');

      await pickEntry(tester, 'Heading 1', kind: PointerDeviceKind.mouse);
      expect(field.focusNode.hasFocus, isTrue, reason: 'focused after');
      expect(controller.selection, selection, reason: 'selection after');
      expect(controller.blockRanges, [
        const BlockRange(BlockFormat.heading, 0, 11),
      ]);
    });
  });
}
