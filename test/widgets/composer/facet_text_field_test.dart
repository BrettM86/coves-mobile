import 'dart:ui' as ui;

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:coves_flutter/widgets/composer/facet_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'clipboard_test_helpers.dart';

/// Widget tests run as Android by default; these pin it, so the text-editing
/// shortcuts use Control and the context menu is the Material toolbar.
final android = TargetPlatformVariant.only(TargetPlatform.android);

/// [text] with each of [ranges] toggled on through a selection.
FacetEditingController controllerWith(String text, List<InlineRange> ranges) {
  final controller = FacetEditingController(text: text);
  for (final range in ranges) {
    controller
      ..selection = TextSelection(
        baseOffset: range.start,
        extentOffset: range.end,
      )
      ..toggleInline(range.format);
  }
  return controller;
}

/// Pumps a [FacetTextField] over [controller], focuses it and gives it
/// [selection] as a user tap would.
Future<void> pumpFocusedField(
  WidgetTester tester,
  FacetEditingController controller,
  TextSelection selection, {
  int? maxLines = 1,
}) async {
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: FacetTextField(controller: controller, maxLines: maxLines),
      ),
    ),
  );
  await tester.showKeyboard(find.byType(EditableText));
  await tester.pump();
  tester
      .state<EditableTextState>(find.byType(EditableText))
      .userUpdateTextEditingValue(
        controller.value.copyWith(selection: selection),
        SelectionChangedCause.tap,
      );
  await tester.pump();
}

/// Expects the field to have scrolled and its caret to lie inside the
/// editable's visible viewport.
void expectCaretInView(WidgetTester tester, String reason) {
  final editable = tester.state<EditableTextState>(find.byType(EditableText));
  final scrollable = tester.state<ScrollableState>(
    find.descendant(
      of: find.byType(EditableText),
      matching: find.byType(Scrollable),
    ),
  );
  expect(scrollable.position.pixels, greaterThan(0), reason: reason);
  final renderEditable = editable.renderEditable;
  final caret = renderEditable.getLocalRectForCaret(
    editable.textEditingValue.selection.extent,
  );
  expect(caret.top, greaterThanOrEqualTo(-0.5), reason: reason);
  expect(
    caret.bottom,
    lessThanOrEqualTo(renderEditable.size.height + 0.5),
    reason: reason,
  );
}

/// The effective style of the character at [offset] in [root], with each
/// span's style merged over its ancestors'.
TextStyle? styleAt(InlineSpan root, int offset) {
  var position = 0;
  TextStyle? found;
  var done = false;
  void visit(InlineSpan span, TextStyle? inherited) {
    if (done) {
      return;
    }
    final style = inherited == null ? span.style : inherited.merge(span.style);
    if (span is! TextSpan) {
      position += 1;
      return;
    }
    final text = span.text ?? '';
    if (offset >= position && offset < position + text.length) {
      found = style;
      done = true;
      return;
    }
    position += text.length;
    for (final child in span.children ?? const <InlineSpan>[]) {
      visit(child, style);
    }
  }

  visit(root, null);
  return found;
}

/// Pumps a [FacetTextField] over a fresh controller, with
/// [focusNode] when given, above a plain [TextField] on [otherFocusNode].
Future<void> pumpFieldWithNeighbour(
  WidgetTester tester, {
  FocusNode? focusNode,
  FocusNode? otherFocusNode,
}) async {
  final controller = FacetEditingController(text: 'aa');
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: Column(
          children: [
            FacetTextField(controller: controller, focusNode: focusNode),
            TextField(focusNode: otherFocusNode),
          ],
        ),
      ),
    ),
  );
}

/// Whether the [FacetTextField]'s editable has focus.
bool facetFieldHasFocus(WidgetTester tester) => tester
    .state<EditableTextState>(
      find.descendant(
        of: find.byType(FacetTextField),
        matching: find.byType(EditableText),
      ),
    )
    .widget
    .focusNode
    .hasFocus;

Future<void> setBottomInset(WidgetTester tester, double bottom) async {
  tester.view.viewInsets = FakeViewPadding(bottom: bottom);
  await tester.pump();
}

void main() {
  testWidgets('D5 context-menu paste inside bold is unformatted', (
    tester,
  ) async {
    installClipboard(tester, text: 'XY');
    final controller = controllerWith('abcdefghij', const [
      InlineRange(InlineFormat.bold, 0, 10),
    ]);
    expect(controller.inlineRanges.toSet(), {
      const InlineRange(InlineFormat.bold, 0, 10),
    });

    await pumpFocusedField(
      tester,
      controller,
      const TextSelection.collapsed(offset: 5),
    );
    expect(controller.selection, const TextSelection.collapsed(offset: 5));
    tester.state<EditableTextState>(find.byType(EditableText)).showToolbar();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();

    expect(controller.text, 'abcdeXYfghij');
    expect(controller.inlineRanges.toSet(), {
      const InlineRange(InlineFormat.bold, 0, 5),
      const InlineRange(InlineFormat.bold, 7, 12),
    });
  }, variant: android);

  testWidgets('D6 keyboard paste at the armed end of bold is unformatted', (
    tester,
  ) async {
    installClipboard(tester, text: 'XY');
    final controller = controllerWith('abcdefghij', const [
      InlineRange(InlineFormat.bold, 0, 10),
    ]);

    await pumpFocusedField(
      tester,
      controller,
      const TextSelection.collapsed(offset: 10),
    );
    expect(controller.selection, const TextSelection.collapsed(offset: 10));
    expect(controller.activeInlineFormats(), {InlineFormat.bold});

    await pressWithControl(tester, LogicalKeyboardKey.keyV);

    expect(controller.text, 'abcdefghijXY');
    expect(controller.inlineRanges.toSet(), {
      const InlineRange(InlineFormat.bold, 0, 10),
    });
  }, variant: android);

  testWidgets('D7 copy and cut put only the plain substring on the clipboard', (
    tester,
  ) async {
    const rows = [
      (name: 'copy', key: LogicalKeyboardKey.keyC, text: 'abcdefghij'),
      (name: 'cut', key: LogicalKeyboardKey.keyX, text: 'abchij'),
    ];
    for (final row in rows) {
      final clipboard = installClipboard(tester);
      final controller = controllerWith('abcdefghij', const [
        InlineRange(InlineFormat.bold, 2, 6),
        InlineRange(InlineFormat.italic, 4, 8),
      ]);
      expect(controller.inlineRanges.toSet(), {
        const InlineRange(InlineFormat.bold, 2, 6),
        const InlineRange(InlineFormat.italic, 4, 8),
      });

      await pumpFocusedField(
        tester,
        controller,
        const TextSelection(baseOffset: 3, extentOffset: 7),
      );
      expect(
        controller.selection,
        const TextSelection(baseOffset: 3, extentOffset: 7),
        reason: row.name,
      );

      await pressWithControl(tester, row.key);

      expect(clipboard.text, 'defg', reason: row.name);
      expect(controller.text, row.text, reason: row.name);
    }
  }, variant: android);

  testWidgets(
    'D1 heading lines render at the heading scale, weight and height',
    (tester) async {
      final controller = FacetEditingController(text: 'aa\nbb\ncc\ndd');
      addTearDown(controller.dispose);
      for (final (start, level) in const [(0, 1), (3, 2), (6, 3)]) {
        controller
          ..selection = TextSelection.collapsed(offset: start)
          ..toggleBlock(BlockFormat.heading, level: level);
      }
      expect(controller.blockRanges.toSet(), {
        const BlockRange(BlockFormat.heading, 0, 2),
        const BlockRange(BlockFormat.heading, 3, 5, level: 2),
        const BlockRange(BlockFormat.heading, 6, 8, level: 3),
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: FacetTextField(
              controller: controller,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w400),
            ),
          ),
        ),
      );
      final span = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable
          .text!;

      const rows = [
        (name: 'H1', offsets: [0, 1], size: 31.0, weight: FontWeight.w700),
        (name: 'H2', offsets: [3, 4], size: 28.0, weight: FontWeight.w700),
        (name: 'H3', offsets: [6, 7], size: 25.0, weight: FontWeight.w600),
      ];
      for (final row in rows) {
        for (final offset in row.offsets) {
          final style = styleAt(span, offset);
          final reason = '${row.name} offset $offset';
          expect(style?.fontSize, closeTo(row.size, 0.01), reason: reason);
          expect(style?.fontWeight, row.weight, reason: reason);
          expect(style?.height, closeTo(1.3, 0.001), reason: reason);
        }
      }
      for (final offset in const [9, 10]) {
        final style = styleAt(span, offset);
        expect(style?.fontSize, closeTo(20.0, 0.01), reason: 'plain $offset');
        expect(style?.fontWeight, FontWeight.w400, reason: 'plain $offset');
      }
    },
  );

  testWidgets('a prefix, prefixText or prefixIcon is rejected in debug', (
    tester,
  ) async {
    final controller = FacetEditingController(text: 'plain');
    addTearDown(controller.dispose);
    for (final (name, decoration) in const [
      ('prefixIcon', InputDecoration(prefixIcon: Icon(Icons.search))),
      ('prefix', InputDecoration(prefix: Text('@'))),
      ('prefixText', InputDecoration(prefixText: '@')),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: FacetTextField(
              controller: controller,
              decoration: decoration,
            ),
          ),
        ),
      );
      expect(
        tester.takeException(),
        isA<AssertionError>().having(
          (error) => error.message,
          'message',
          contains('prefix'),
        ),
        reason: name,
      );
    }
  });

  testWidgets('D10 semantics value is plain text; text options pass through', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = controllerWith('Title\nsome bold', const [
      InlineRange(InlineFormat.bold, 11, 15),
    ]);
    addTearDown(controller.dispose);
    controller
      ..selection = const TextSelection.collapsed(offset: 0)
      ..toggleBlock(BlockFormat.heading);
    expect(controller.blockRanges.toSet(), {
      const BlockRange(BlockFormat.heading, 0, 5),
    });
    expect(controller.inlineRanges.toSet(), {
      const InlineRange(InlineFormat.bold, 11, 15),
    });
    const spellCheck = SpellCheckConfiguration.disabled();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: FacetTextField(
            controller: controller,
            autocorrect: false,
            spellCheckConfiguration: spellCheck,
            textCapitalization: TextCapitalization.sentences,
          ),
        ),
      ),
    );

    expect(
      tester.getSemantics(find.byType(EditableText)).value,
      'Title\nsome bold',
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.autocorrect, isFalse);
    expect(field.spellCheckConfiguration, spellCheck);
    expect(field.textCapitalization, TextCapitalization.sentences);
    semantics.dispose();
  });

  testWidgets('D5b toolbar and keyboard paste keep the caret in view', (
    tester,
  ) async {
    const pasted = 'one\ntwo\nthree\nfour\nfive\nsix\nseven';
    for (final viaToolbar in [true, false]) {
      final reason = viaToolbar ? 'toolbar' : 'keyboard';
      installClipboard(tester, text: pasted);
      final controller = FacetEditingController(text: 'start');
      await pumpFocusedField(
        tester,
        controller,
        const TextSelection.collapsed(offset: 5),
        maxLines: 3,
      );
      if (viaToolbar) {
        tester
            .state<EditableTextState>(find.byType(EditableText))
            .showToolbar();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Paste'));
      } else {
        await pressWithControl(tester, LogicalKeyboardKey.keyV);
      }
      await tester.pumpAndSettle();

      expect(controller.text, 'start$pasted', reason: reason);
      expect(
        controller.selection,
        const TextSelection.collapsed(offset: 5 + pasted.length),
        reason: reason,
      );
      expectCaretInView(tester, reason);
      // Unmount before the next row so its controller can be disposed.
      await tester.pumpWidget(const SizedBox.shrink());
    }
  }, variant: android);

  testWidgets('D5c accessibility paste inside bold is unformatted, once', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    installClipboard(tester, text: 'XY');
    final controller = controllerWith('abcdefghij', const [
      InlineRange(InlineFormat.bold, 0, 10),
    ]);

    await pumpFocusedField(
      tester,
      controller,
      const TextSelection.collapsed(offset: 5),
    );
    await tester.pumpAndSettle();
    final node = tester.getSemantics(find.byType(EditableText));
    expect(node.getSemanticsData().hasAction(SemanticsAction.paste), isTrue);

    tester.binding.performSemanticsAction(
      SemanticsActionEvent(
        type: SemanticsAction.paste,
        viewId: tester.view.viewId,
        nodeId: node.id,
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.text, 'abcdeXYfghij');
    expect(controller.inlineRanges.toSet(), {
      const InlineRange(InlineFormat.bold, 0, 5),
      const InlineRange(InlineFormat.bold, 7, 12),
    });
    semantics.dispose();
  }, variant: android);

  testWidgets('paste over a selection in a full field fills only the room '
      'the selection frees', (tester) async {
    installClipboard(tester, text: 'VWXYZ');
    final controller = FacetEditingController(text: 'abcdefghij');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: FacetTextField(controller: controller, maxLength: 10),
        ),
      ),
    );
    await tester.showKeyboard(find.byType(EditableText));
    await tester.pump();
    tester
        .state<EditableTextState>(find.byType(EditableText))
        .userUpdateTextEditingValue(
          controller.value.copyWith(
            selection: const TextSelection(baseOffset: 4, extentOffset: 7),
          ),
          SelectionChangedCause.tap,
        );
    await tester.pump();
    expect(controller.text.length, 10);

    await pressWithControl(tester, LogicalKeyboardKey.keyV);
    await tester.pumpAndSettle();

    expect(controller.text, 'abcdVWXhij');
    expect(controller.selection, const TextSelection.collapsed(offset: 7));
  }, variant: android);

  testWidgets('D11 closing the soft keyboard unfocuses the field', (
    tester,
  ) async {
    addTearDown(tester.view.resetViewInsets);

    // A supplied focus node.
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await pumpFieldWithNeighbour(tester, focusNode: focusNode);
    focusNode.requestFocus();
    await setBottomInset(tester, 300);
    expect(focusNode.hasFocus, isTrue, reason: 'keyboard opened');
    await setBottomInset(tester, 120);
    expect(focusNode.hasFocus, isTrue, reason: 'keyboard still open');
    await setBottomInset(tester, 0);
    expect(focusNode.hasFocus, isFalse, reason: 'supplied focus node');

    // No focus node supplied.
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpFieldWithNeighbour(tester);
    await tester.showKeyboard(find.byType(FacetTextField));
    await setBottomInset(tester, 300);
    expect(facetFieldHasFocus(tester), isTrue, reason: 'own node, open');
    await setBottomInset(tester, 0);
    expect(facetFieldHasFocus(tester), isFalse, reason: 'own focus node');

    // Mounted while the keyboard is already open.
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await pumpFieldWithNeighbour(tester);
    await tester.showKeyboard(find.byType(FacetTextField));
    await tester.pump();
    expect(facetFieldHasFocus(tester), isTrue, reason: 'mounted open');
    await setBottomInset(tester, 0);
    expect(facetFieldHasFocus(tester), isFalse, reason: 'mounted open');

    // Unmounted: later inset changes do not throw.
    await tester.pumpWidget(const SizedBox.shrink());
    await setBottomInset(tester, 300);
    await setBottomInset(tester, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('D11b a hardware keyboard (no inset) keeps the field focused', (
    tester,
  ) async {
    addTearDown(tester.view.resetViewInsets);
    addTearDown(tester.view.resetPhysicalSize);
    await pumpFieldWithNeighbour(tester);
    await tester.showKeyboard(find.byType(FacetTextField));
    await tester.pump();
    tester.view.viewInsets = FakeViewPadding.zero;
    tester.view.physicalSize = const Size(1000, 1800);
    await tester.pump();
    expect(facetFieldHasFocus(tester), isTrue);
  });

  testWidgets('D11c closing the keyboard leaves another field focused', (
    tester,
  ) async {
    addTearDown(tester.view.resetViewInsets);
    final otherFocusNode = FocusNode();
    addTearDown(otherFocusNode.dispose);
    await pumpFieldWithNeighbour(tester, otherFocusNode: otherFocusNode);
    otherFocusNode.requestFocus();
    await setBottomInset(tester, 300);
    await setBottomInset(tester, 0);
    expect(otherFocusNode.hasFocus, isTrue);
  });

  testWidgets(
    'D11d an inset drop while the app is in the background keeps the field '
    'focused',
    (tester) async {
      addTearDown(tester.view.resetViewInsets);
      final binding = tester.binding;
      void resume() {
        for (final state in [
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          if (binding.lifecycleState != AppLifecycleState.resumed) {
            binding.handleAppLifecycleStateChanged(state);
          }
        }
      }

      addTearDown(resume);
      await pumpFieldWithNeighbour(tester);
      await tester.showKeyboard(find.byType(FacetTextField));
      await setBottomInset(tester, 300);
      [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ].forEach(binding.handleAppLifecycleStateChanged);
      await setBottomInset(tester, 0);
      expect(facetFieldHasFocus(tester), isTrue, reason: 'backgrounded');

      resume();
      await tester.pump();
      await setBottomInset(tester, 300);
      await setBottomInset(tester, 0);
      expect(facetFieldHasFocus(tester), isFalse, reason: 'after resume');
    },
  );

  testWidgets('D12 the selection highlight is tight to each line', (
    tester,
  ) async {
    await pumpFieldWithNeighbour(tester);
    final editable = tester.state<EditableTextState>(
      find.descendant(
        of: find.byType(FacetTextField),
        matching: find.byType(EditableText),
      ),
    );
    expect(editable.renderEditable.selectionWidthStyle, ui.BoxWidthStyle.tight);
  }, variant: android);
}
