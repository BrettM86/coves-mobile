import 'dart:ui' show PointerDeviceKind, Tristate;

import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:coves_flutter/widgets/icons/lucide_icon_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'formatting_toolbar_test_helpers.dart';

/// The eight toolbar buttons' semantic labels, in PRD order.
const buttonLabels = [
  'Bold',
  'Italic',
  'Strikethrough',
  'Spoiler',
  'Code',
  'Quote',
  'Heading',
  'Code block',
];

/// The color the button labelled [label] renders its glyph in.
Color iconColor(WidgetTester tester, String label) {
  expect(button(label), findsOneWidget, reason: 'toolbar button "$label"');
  final painters = find.descendant(
    of: button(label),
    matching: find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is LucideIconPainter,
    ),
  );
  if (painters.evaluate().isNotEmpty) {
    return (tester.widget<CustomPaint>(painters.first).painter!
            as LucideIconPainter)
        .color;
  }
  final icons = find.descendant(of: button(label), matching: find.byType(Icon));
  expect(icons, findsOneWidget, reason: 'glyph inside "$label"');
  final icon = tester.widget<Icon>(icons);
  return icon.color ?? IconTheme.of(tester.element(icons)).color!;
}

/// A host control with its own semantic label, calling [onTap] when tapped.
Widget hostControl(String label, {VoidCallback? onTap}) => GestureDetector(
  behavior: HitTestBehavior.opaque,
  onTap: onTap,
  child: Semantics(
    container: true,
    button: true,
    label: label,
    child: const SizedBox(width: 32, height: 32),
  ),
);

void main() {
  group('FormattingToolbar acceptance (empty composer)', () {
    toolbarTest('Quote then typing quotes the typed line', (tester) async {
      final controller = FacetEditingController();
      await pumpToolbar(tester, controller, withField: true);
      await focusField(tester, const TextSelection.collapsed(offset: 0));

      await tapButton(tester, 'Quote');
      await typeAs(tester, 'hi', 2);

      expect(controller.blockRanges, [
        const BlockRange(BlockFormat.blockquote, 0, 2),
      ]);
      expect(selectedState(tester, 'Quote'), Tristate.isTrue);
    });

    toolbarTest('Code block toggles on and off and typing stays plain', (
      tester,
    ) async {
      final controller = FacetEditingController();
      await pumpToolbar(tester, controller, withField: true);
      await focusField(tester, const TextSelection.collapsed(offset: 0));

      await tapButton(tester, 'Code block');
      expect(controller.blockRanges, [
        const BlockRange(BlockFormat.codeBlock, 0, 0),
      ]);
      expect(selectedState(tester, 'Code block'), Tristate.isTrue);

      await tapButton(tester, 'Code block');
      expect(controller.blockRanges, isEmpty);
      expect(selectedState(tester, 'Code block'), Tristate.isFalse);

      await typeAs(tester, 'x', 1);
      expect(controller.blockRanges, isEmpty);
    });
  });

  group('FormattingToolbar contents', () {
    toolbarTest('eight buttons in PRD order between the host controls', (
      tester,
    ) async {
      await pumpToolbar(
        tester,
        FacetEditingController(),
        leading: [hostControl('Host leading')],
        trailing: [hostControl('Host trailing')],
      );

      final order = ['Host leading', ...buttonLabels, 'Host trailing'];
      for (final label in order) {
        expect(button(label), findsOneWidget, reason: label);
      }
      for (var i = 1; i < order.length; i++) {
        expect(
          tester.getCenter(button(order[i])).dx,
          greaterThan(tester.getCenter(button(order[i - 1])).dx),
          reason: '${order[i]} sits right of ${order[i - 1]}',
        );
      }
    });

    toolbarTest('with no host controls only the eight buttons', (tester) async {
      await pumpToolbar(tester, FacetEditingController());

      final labels = find.semantics
          .byPredicate((node) => node.flagsCollection.isButton)
          .evaluate()
          .map((node) => node.label)
          .toList();
      expect(labels, unorderedEquals(buttonLabels));
    });
  });

  group('FormattingToolbar applies formats to the selection', () {
    final rows =
        <({String label, List<InlineRange> inline, List<BlockRange> block})>[
          (
            label: 'Bold',
            inline: [const InlineRange(InlineFormat.bold, 0, 5)],
            block: [],
          ),
          (
            label: 'Italic',
            inline: [const InlineRange(InlineFormat.italic, 0, 5)],
            block: [],
          ),
          (
            label: 'Strikethrough',
            inline: [const InlineRange(InlineFormat.strikethrough, 0, 5)],
            block: [],
          ),
          (
            label: 'Spoiler',
            inline: [const InlineRange(InlineFormat.spoiler, 0, 5)],
            block: [],
          ),
          (
            label: 'Code',
            inline: [const InlineRange(InlineFormat.code, 0, 5)],
            block: [],
          ),
          (
            label: 'Quote',
            inline: [],
            block: [const BlockRange(BlockFormat.blockquote, 0, 11)],
          ),
          (
            label: 'Code block',
            inline: [],
            block: [const BlockRange(BlockFormat.codeBlock, 0, 11)],
          ),
        ];
    for (final row in rows) {
      toolbarTest('${row.label} over "hello" in "hello world"', (tester) async {
        final controller = selected('hello world', 0, 5);
        await pumpToolbar(tester, controller);

        await tapButton(tester, row.label);

        expect(controller.inlineRanges, row.inline);
        expect(controller.blockRanges, row.block);
      });
    }
  });

  group('FormattingToolbar at a collapsed caret', () {
    toolbarTest('Bold arms the caret so typed text is bold', (tester) async {
      final controller = FacetEditingController(text: 'ab');
      await pumpToolbar(tester, controller, withField: true);
      await focusField(tester, const TextSelection.collapsed(offset: 1));

      await tapButton(tester, 'Bold');
      await typeAs(tester, 'aXYb', 3);

      expect(controller.inlineRanges, [
        const InlineRange(InlineFormat.bold, 1, 3),
      ]);
    });
  });

  group('FormattingToolbar active state', () {
    toolbarTest('Bold follows the selection on one mounted toolbar', (
      tester,
    ) async {
      final controller = selected('hello world', 0, 5)
        ..toggleInline(InlineFormat.bold);
      await pumpToolbar(tester, controller);

      final steps = <({String name, TextSelection selection, Tristate want})>[
        (
          name: 'fully bold',
          selection: const TextSelection(baseOffset: 0, extentOffset: 5),
          want: Tristate.isTrue,
        ),
        (
          name: 'partly bold',
          selection: const TextSelection(baseOffset: 3, extentOffset: 8),
          want: Tristate.isFalse,
        ),
        (
          name: 'plain',
          selection: const TextSelection(baseOffset: 6, extentOffset: 11),
          want: Tristate.isFalse,
        ),
      ];
      for (final step in steps) {
        controller.selection = step.selection;
        await tester.pump();
        expect(selectedState(tester, 'Bold'), step.want, reason: step.name);
      }

      controller.selection = const TextSelection.collapsed(offset: 8);
      await tester.pump();
      await tapButton(tester, 'Bold');
      expect(
        selectedState(tester, 'Bold'),
        Tristate.isTrue,
        reason: 'armed at the caret',
      );
    });

    toolbarTest('the active button renders in a different color', (
      tester,
    ) async {
      final controller = selected('hello world', 0, 5)
        ..toggleInline(InlineFormat.bold);
      await pumpToolbar(tester, controller);

      final active = iconColor(tester, 'Bold');
      controller.selection = const TextSelection(
        baseOffset: 6,
        extentOffset: 11,
      );
      await tester.pump();
      final inactive = iconColor(tester, 'Bold');

      expect(active, isNot(inactive));
    });
  });

  group('FormattingToolbar toggles formats off', () {
    toolbarTest('active Bold over a bold selection removes the bold', (
      tester,
    ) async {
      final controller = selected('hello world', 0, 5)
        ..toggleInline(InlineFormat.bold);
      await pumpToolbar(tester, controller);

      await tapButton(tester, 'Bold');

      expect(controller.inlineRanges, isEmpty);
    });

    toolbarTest('Bold tapped twice at the caret leaves typed text plain', (
      tester,
    ) async {
      final controller = FacetEditingController(text: 'ab');
      await pumpToolbar(tester, controller, withField: true);
      await focusField(tester, const TextSelection.collapsed(offset: 1));

      await tapButton(tester, 'Bold');
      await tapButton(tester, 'Bold');
      await typeAs(tester, 'aXYb', 3);

      expect(controller.text, 'aXYb');
      expect(controller.inlineRanges, isEmpty);
    });

    toolbarTest('active Quote removes the quote', (tester) async {
      final controller = selected('hello world', 0, 5)
        ..toggleBlock(BlockFormat.blockquote);
      await pumpToolbar(tester, controller);

      await tapButton(tester, 'Quote');

      expect(controller.blockRanges, isEmpty);
    });
  });

  group('FormattingToolbar at a narrow width', () {
    toolbarTest('the button row scrolls and the host controls stay usable', (
      tester,
    ) async {
      final taps = <String>[];
      final controller = selected('hello world', 0, 5);
      await pumpToolbar(
        tester,
        controller,
        width: 200,
        leading: [
          hostControl('Host leading', onTap: () => taps.add('leading')),
        ],
        trailing: [
          hostControl('Host trailing', onTap: () => taps.add('trailing')),
        ],
      );
      expect(tester.takeException(), isNull);

      for (final label in ['Host leading', 'Host trailing']) {
        expect(button(label), findsOneWidget, reason: label);
        final rect = tester.getRect(button(label));
        expect(rect.left, greaterThanOrEqualTo(0), reason: label);
        expect(rect.right, lessThanOrEqualTo(200), reason: label);
      }
      await tester.tap(button('Host leading'));
      await tester.tap(button('Host trailing'));
      await tester.pump();
      expect(taps, ['leading', 'trailing']);

      expect(button('Code block'), findsOneWidget, reason: 'Code block');
      final before = tester.getCenter(button('Code block')).dx;
      await tester.drag(button('Bold'), const Offset(-1000, 0));
      await tester.pumpAndSettle();
      final after = tester.getCenter(button('Code block')).dx;
      expect(after, lessThan(before));
      expect(after, lessThan(200));

      for (final label in ['Host leading', 'Host trailing']) {
        final rect = tester.getRect(button(label));
        expect(rect.left, greaterThanOrEqualTo(0), reason: '$label after');
        expect(rect.right, lessThanOrEqualTo(200), reason: '$label after');
      }
      await tester.tap(button('Host leading'));
      await tester.tap(button('Host trailing'));
      await tester.pump();
      expect(taps, ['leading', 'trailing', 'leading', 'trailing']);

      await tapButton(tester, 'Code block');
      expect(controller.blockRanges, [
        const BlockRange(BlockFormat.codeBlock, 0, 11),
      ]);
      expect(tester.takeException(), isNull);
    });
  });

  group('FormattingToolbar inside a code block', () {
    const inlineLabels = ['Bold', 'Italic', 'Strikethrough', 'Spoiler', 'Code'];

    toolbarTest('inline buttons disable inside and re-enable outside', (
      tester,
    ) async {
      final controller = selected('bold\ncode', 0, 4)
        ..toggleInline(InlineFormat.bold)
        ..selection = const TextSelection.collapsed(offset: 7)
        ..toggleBlock(BlockFormat.codeBlock);
      await pumpToolbar(tester, controller);

      void expectInlineEnabled(Tristate want, String where) {
        for (final label in inlineLabels) {
          expect(button(label), findsOneWidget, reason: label);
          expect(
            tester.getSemantics(button(label)).flagsCollection.isEnabled,
            want,
            reason: '$label $where',
          );
        }
      }

      expectInlineEnabled(Tristate.isFalse, 'inside the code block');
      await tapButton(tester, 'Italic');
      expect(controller.inlineRanges, [
        const InlineRange(InlineFormat.bold, 0, 4),
      ]);

      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 4,
      );
      await tester.pump();
      expectInlineEnabled(Tristate.isTrue, 'outside the code block');

      controller.selection = const TextSelection.collapsed(offset: 7);
      await tester.pump();
      expectInlineEnabled(Tristate.isFalse, 'back inside');
    });

    toolbarTest('Quote and Code block still work inside the code block', (
      tester,
    ) async {
      final controller = FacetEditingController(text: 'bold\ncode')
        ..selection = const TextSelection.collapsed(offset: 7)
        ..toggleBlock(BlockFormat.codeBlock);
      await pumpToolbar(tester, controller);

      await tapButton(tester, 'Quote');
      expect(
        controller.blockRanges,
        unorderedEquals([
          const BlockRange(BlockFormat.codeBlock, 5, 9),
          const BlockRange(BlockFormat.blockquote, 5, 9),
        ]),
      );

      await tapButton(tester, 'Code block');
      expect(controller.blockRanges, [
        const BlockRange(BlockFormat.blockquote, 5, 9),
      ]);
    });
  });

  group('FormattingToolbar semantics', () {
    toolbarTest('each button is a labelled button with a selected state', (
      tester,
    ) async {
      await pumpToolbar(tester, FacetEditingController());

      for (final label in buttonLabels) {
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

    toolbarTest('with no selection every button is disabled and unselected', (
      tester,
    ) async {
      final controller = FacetEditingController(text: 'hello world');
      await pumpToolbar(tester, controller);
      expect(controller.selection.isValid, isFalse, reason: 'never focused');

      for (final label in buttonLabels) {
        expect(button(label), findsOneWidget, reason: label);
        final flags = tester.getSemantics(button(label)).flagsCollection;
        expect(flags.isEnabled, Tristate.isFalse, reason: '$label enabled');
        expect(flags.isSelected, Tristate.isFalse, reason: '$label selected');
      }
    });
  });

  group('FormattingToolbar keeps the field focused', () {
    toolbarTest('a mouse tap on Bold keeps focus and selection', (
      tester,
    ) async {
      final controller = FacetEditingController(text: 'hello world');
      await pumpToolbar(tester, controller, withField: true);
      await focusField(
        tester,
        const TextSelection(baseOffset: 2, extentOffset: 5),
      );
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.focusNode.hasFocus, isTrue, reason: 'focused before');
      expect(
        controller.selection,
        const TextSelection(baseOffset: 2, extentOffset: 5),
        reason: 'selection before',
      );

      expect(button('Bold'), findsOneWidget, reason: 'toolbar button "Bold"');
      await tester.tap(button('Bold'), kind: PointerDeviceKind.mouse);
      await tester.pump();

      expect(field.focusNode.hasFocus, isTrue, reason: 'focused after');
      expect(
        controller.selection,
        const TextSelection(baseOffset: 2, extentOffset: 5),
        reason: 'selection after',
      );
      expect(controller.inlineRanges, [
        const InlineRange(InlineFormat.bold, 2, 5),
      ]);
    });
  });
}
