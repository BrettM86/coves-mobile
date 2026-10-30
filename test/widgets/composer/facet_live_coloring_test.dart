import 'package:coves_flutter/constants/app_colors.dart';
import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/theme/rich_text_palette.dart';
import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:coves_flutter/widgets/composer/facet_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'span_style_helpers.dart';

const _baseStyle = TextStyle(fontSize: 14, color: Color(0xFF000000));

const _text =
    'hi @alice.test !science !science@coves.social https://example.com/x.';

/// Line 1 holds a mention and a link outside code and `@bob.test` [15,24),
/// which gets inline code; line 2 [45,81) becomes a code block holding a
/// link [45,69) and a mention [70,81)
const _codeText =
    'hi @alice.test @bob.test https://example.com\n'
    'https://code.example.com @carol.test';

/// A controller over [_codeText] with inline code over `@bob.test` and a
/// code block on line 2
FacetEditingController _codeController() {
  final controller = FacetEditingController(text: _codeText)
    ..selection = const TextSelection(baseOffset: 15, extentOffset: 24)
    ..toggleInline(InlineFormat.code)
    ..selection = const TextSelection.collapsed(offset: 50)
    ..toggleBlock(BlockFormat.codeBlock);
  return controller;
}

/// Delivers one complete editing value, the way the platform reports an IME
/// update; [composing] defaults to no composing region
void _deliver(
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

void main() {
  testWidgets('colors the mentions and the link, and nothing else', (
    tester,
  ) async {
    final context = await buildContextFor(tester);
    final controller = FacetEditingController(text: _text);
    addTearDown(controller.dispose);

    final span = controller.buildTextSpan(
      context: context,
      style: _baseStyle,
      withComposing: false,
    );

    expect(coloredRuns(characterStylesOf(span, _text)), [
      ('mention', 3, 14),
      ('mention', 15, 23),
      ('mention', 24, 45),
      ('link', 46, 67),
    ]);
  });

  testWidgets(
    'coloring keeps bold on a mention and the composing underline on a link',
    (tester) async {
      final context = await buildContextFor(tester);
      final controller = FacetEditingController(text: _text);
      addTearDown(controller.dispose);
      controller
        ..selection = const TextSelection(baseOffset: 5, extentOffset: 10)
        ..toggleInline(InlineFormat.bold)
        ..selection = const TextSelection.collapsed(offset: 68);
      controller.value = controller.value.copyWith(
        composing: const TextRange(start: 50, end: 60),
      );

      final styles = characterStylesOf(
        controller.buildTextSpan(
          context: context,
          style: _baseStyle,
          withComposing: true,
        ),
        _text,
      );

      final boldMentionCharacters = [
        for (var index = 0; index < styles.length; index++)
          if (styles[index].fontWeight == FontWeight.w700 &&
              styles[index].color == RichTextPalette.mention)
            index,
      ];
      final underlinedLinkCharacters = [
        for (var index = 0; index < styles.length; index++)
          if ((styles[index].decoration?.contains(TextDecoration.underline) ??
                  false) &&
              styles[index].color == RichTextPalette.link)
            index,
      ];
      expect(boldMentionCharacters, [5, 6, 7, 8, 9]);
      expect(underlinedLinkCharacters, [
        50,
        51,
        52,
        53,
        54,
        55,
        56,
        57,
        58,
        59,
      ]);
    },
  );
  testWidgets('a keystroke that completes a link colors it in the field', (
    tester,
  ) async {
    final controller = FacetEditingController(text: 'see https://');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: FacetTextField(
            controller: controller,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
      ),
    );

    RenderEditable editable() =>
        tester.allRenderObjects.whereType<RenderEditable>().single;

    expect(
      coloredRuns(characterStylesOf(editable().text!, 'see https://')),
      isEmpty,
      reason: 'a bare scheme is not a link',
    );

    await tester.enterText(
      find.byType(FacetTextField),
      'see https://example.com',
    );
    await tester.pump();

    expect(
      coloredRuns(
        characterStylesOf(editable().text!, 'see https://example.com'),
      ),
      [('link', 4, 23)],
    );
  });

  testWidgets('mentions and links inside inline code or a code block '
      'stay uncolored', (tester) async {
    final context = await buildContextFor(tester);
    final controller = _codeController();
    addTearDown(controller.dispose);

    final span = controller.buildTextSpan(
      context: context,
      style: _baseStyle,
      withComposing: false,
    );

    expect(coloredRuns(characterStylesOf(span, _codeText)), [
      ('mention', 3, 14),
      ('link', 25, 44),
    ]);

    // Only code blocks exclude, and only their own lines: a heading line
    // [0,17) and a quoted line [18,34) keep their mentions, the code-block
    // line [35,51) does not, and the plain line after it [52,71) keeps its
    // link
    const blocksText =
        '@alice.test title\n'
        '@bob.test quoted\n'
        '@carol.test code\n'
        'https://example.com';
    final blocksController = FacetEditingController(text: blocksText)
      ..selection = const TextSelection.collapsed(offset: 5)
      ..toggleBlock(BlockFormat.heading)
      ..selection = const TextSelection.collapsed(offset: 20)
      ..toggleBlock(BlockFormat.blockquote)
      ..selection = const TextSelection.collapsed(offset: 40)
      ..toggleBlock(BlockFormat.codeBlock);
    addTearDown(blocksController.dispose);

    final blocksSpan = blocksController.buildTextSpan(
      context: context,
      style: _baseStyle,
      withComposing: false,
    );

    expect(coloredRuns(characterStylesOf(blocksSpan, blocksText)), [
      ('mention', 0, 11),
      ('mention', 18, 27),
      ('link', 52, 71),
    ]);
  });

  testWidgets('code exclusions follow the text while an earlier composition '
      'shifts it', (tester) async {
    final context = await buildContextFor(tester);
    final controller = _codeController();
    addTearDown(controller.dispose);
    // The IME recomposes "hi" into "hippopotamus", shifting everything
    // after it by 10: @alice.test [13,24), @bob.test [25,34) in inline
    // code, link [35,54), code block line [55,91) with a link [55,79) and
    // @carol.test [80,91).
    const composedText =
        'hippopotamus @alice.test @bob.test https://example.com\n'
        'https://code.example.com @carol.test';
    _deliver(controller, _codeText, 2);
    _deliver(controller, _codeText, 2, const TextRange(start: 0, end: 2));
    _deliver(controller, composedText, 12, const TextRange(start: 0, end: 12));

    final span = controller.buildTextSpan(
      context: context,
      style: _baseStyle,
      withComposing: true,
    );

    expect(coloredRuns(characterStylesOf(span, composedText)), [
      ('mention', 13, 24),
      ('link', 35, 54),
    ]);
  });
}
