import 'dart:ui' show Tristate;

import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'formatting_toolbar_test_helpers.dart';

/// A controller over [lead] and, on the line after it, [boldWords] single
/// bold words, with [start]..[end] selected. [format] runs first, while the
/// count is still low; each bold word then adds one facet.
FacetEditingController budgetFixture(
  String lead, {
  required int boldWords,
  required int start,
  required int end,
  void Function(FacetEditingController controller)? format,
}) {
  final controller = FacetEditingController(
    text: '$lead\n${List.filled(boldWords, 'w').join(' ')}',
  );
  format?.call(controller);
  final fillerStart = lead.length + 1;
  for (var i = 0; i < boldWords; i++) {
    final word = fillerStart + 2 * i;
    controller
      ..selection = TextSelection(baseOffset: word, extentOffset: word + 1)
      ..toggleInline(InlineFormat.bold);
  }
  return controller
    ..selection = TextSelection(baseOffset: start, extentOffset: end);
}

/// Selects [start]..[end] on [controller] and applies [format] at [level].
void blockOver(
  FacetEditingController controller,
  BlockFormat format,
  int start,
  int end, {
  int level = 1,
}) {
  controller
    ..selection = TextSelection(baseOffset: start, extentOffset: end)
    ..toggleBlock(format, level: level);
}

/// Expects [controller]'s budget to be [used] with [remaining] left.
void expectBudget(
  FacetEditingController controller, {
  required int used,
  required int remaining,
}) {
  expect(controller.formattingBudget.used, used, reason: 'budget used');
  expect(
    controller.formattingBudget.remaining,
    remaining,
    reason: 'budget remaining',
  );
}

/// Expects each label in [want] to expose its enabled state.
void expectEnabled(WidgetTester tester, Map<String, Tristate> want) {
  for (final entry in want.entries) {
    expect(enabledState(tester, entry.key), entry.value, reason: entry.key);
  }
}

void main() {
  group('Exhausted budget (200 used)', () {
    toolbarTest('a plain-word selection disables all eight buttons', (
      tester,
    ) async {
      final controller = budgetFixture(
        'plain',
        boldWords: 200,
        start: 0,
        end: 5,
      );
      expectBudget(controller, used: 200, remaining: 0);
      await pumpToolbar(tester, controller);

      for (final label in const [
        'Bold',
        'Italic',
        'Strikethrough',
        'Spoiler',
        'Code',
        'Quote',
        'Heading',
        'Code block',
      ]) {
        expect(enabledState(tester, label), Tristate.isFalse, reason: label);
      }
    });

    toolbarTest('a selection exactly over a bold word keeps Bold enabled and '
        'selected, and the other inline buttons enabled', (tester) async {
      final controller = budgetFixture(
        'bold',
        boldWords: 199,
        start: 0,
        end: 4,
        format: (controller) => controller
          ..selection = const TextSelection(baseOffset: 0, extentOffset: 4)
          ..toggleInline(InlineFormat.bold),
      );
      expectBudget(controller, used: 200, remaining: 0);
      await pumpToolbar(tester, controller);

      expect(selectedState(tester, 'Bold'), Tristate.isTrue);
      for (final label in const [
        'Bold',
        'Italic',
        'Strikethrough',
        'Spoiler',
        'Code',
      ]) {
        expect(enabledState(tester, label), Tristate.isTrue, reason: label);
      }
    });

    toolbarTest('the caret on an H2 line keeps Heading, Heading 2 and Normal '
        'text enabled', (tester) async {
      final controller = budgetFixture(
        'title',
        boldWords: 199,
        start: 2,
        end: 2,
        format: (controller) =>
            blockOver(controller, BlockFormat.heading, 0, 5, level: 2),
      );
      expectBudget(controller, used: 200, remaining: 0);
      await pumpToolbar(tester, controller);

      expect(enabledState(tester, 'Heading'), Tristate.isTrue);
      await openPicker(tester);
      expectEnabled(tester, {
        'Heading 2': Tristate.isTrue,
        'Normal text': Tristate.isTrue,
      });
    });

    toolbarTest('the caret on the middle line of a three-line quote keeps '
        'Quote enabled', (tester) async {
      final controller = budgetFixture(
        'one\ntwo\nthree',
        boldWords: 199,
        start: 5,
        end: 5,
        format: (controller) =>
            blockOver(controller, BlockFormat.blockquote, 0, 13),
      );
      expectBudget(controller, used: 200, remaining: 0);
      await pumpToolbar(tester, controller);

      expect(enabledState(tester, 'Quote'), Tristate.isTrue);
    });
  });

  group('One facet left (199 used)', () {
    toolbarTest('two plain lines selected disable Heading and keep Quote '
        'enabled', (tester) async {
      final controller = budgetFixture(
        'one\ntwo',
        boldWords: 199,
        start: 0,
        end: 7,
      );
      expectBudget(controller, used: 199, remaining: 1);
      await pumpToolbar(tester, controller);

      expectEnabled(tester, {
        'Heading': Tristate.isFalse,
        'Quote': Tristate.isTrue,
      });
    });

    toolbarTest('one plain line keeps Heading and Heading 1 enabled', (
      tester,
    ) async {
      final controller = budgetFixture(
        'one\ntwo',
        boldWords: 199,
        start: 1,
        end: 1,
      );
      expectBudget(controller, used: 199, remaining: 1);
      await pumpToolbar(tester, controller);

      expect(enabledState(tester, 'Heading'), Tristate.isTrue);
      await openPicker(tester);
      expect(enabledState(tester, 'Heading 1'), Tristate.isTrue);
    });

    toolbarTest('an H1 line and two plain lines selected disable the level '
        'entries, and Normal text removes the H1 without adding a heading', (
      tester,
    ) async {
      final controller = budgetFixture(
        'one\ntwo\nthree',
        boldWords: 198,
        start: 0,
        end: 13,
        format: (controller) =>
            blockOver(controller, BlockFormat.heading, 0, 3),
      );
      expectBudget(controller, used: 199, remaining: 1);
      expect(controller.blockRanges, [
        const BlockRange(BlockFormat.heading, 0, 3),
      ], reason: 'before');
      await pumpToolbar(tester, controller);

      expect(enabledState(tester, 'Heading'), Tristate.isTrue);
      await openPicker(tester);
      expectEnabled(tester, {
        'Heading 1': Tristate.isFalse,
        'Heading 2': Tristate.isFalse,
        'Heading 3': Tristate.isFalse,
        'Normal text': Tristate.isTrue,
      });

      await pickEntry(tester, 'Normal text');

      expect(controller.blockRanges, isEmpty);
    });
  });
}
