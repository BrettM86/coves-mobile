import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Creates a controller over [text] with each of [ranges] toggled on.
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

TextRange region(int start, int end) => TextRange(start: start, end: end);

/// Row (a): "abcd" with bold [1,2), recomposed to "abxd" and committed.
FacetEditingController recomposeRowA() {
  final controller = controllerWith('abcd', const [
    InlineRange(InlineFormat.bold, 1, 2),
  ]);
  deliver(controller, 'abcd', 3, region(1, 3));
  deliver(controller, 'axd', 2, region(1, 2));
  deliver(controller, 'abxd', 3);
  return controller;
}

void main() {
  test('B1 ranges are held while composing', () {
    final controller = controllerWith('abcd efg', const [
      InlineRange(InlineFormat.bold, 0, 4),
    ]);
    deliver(controller, 'abcd efg', 4);
    const held = [InlineRange(InlineFormat.bold, 0, 4)];

    deliver(controller, 'abcd efg', 4, region(0, 4));
    expect(controller.heldInlineRanges, held, reason: 'composing set');
    deliver(controller, 'ab efg', 2, region(0, 2));
    expect(controller.heldInlineRanges, held, reason: 'after "ab efg"');
    deliver(controller, 'abx efg', 3, region(0, 3));
    expect(controller.heldInlineRanges, held, reason: 'after "abx efg"');
  });

  test('B1 inlineRanges are in the current text while composing', () {
    final controller = controllerWith('abcd efg', const [
      InlineRange(InlineFormat.bold, 0, 4),
    ]);
    deliver(controller, 'abcd efg', 4);
    deliver(controller, 'abcd efg', 4, region(0, 4));
    deliver(controller, 'ab efg', 2, region(0, 2));
    expect(controller.inlineRanges, const [
      InlineRange(InlineFormat.bold, 0, 2),
    ]);
  });

  group('B2 commit remaps once from the pre-composition value', () {
    test('a recompose', () {
      expect(recomposeRowA().inlineRanges, const [
        InlineRange(InlineFormat.bold, 1, 2),
      ]);
    });

    test('b armed formats apply to the composed text', () {
      final controller = FacetEditingController(text: 'ab');
      deliver(controller, 'ab', 2);
      controller.toggleInline(InlineFormat.bold);
      deliver(controller, 'abc', 3, region(2, 3));
      deliver(controller, 'abcd', 4, region(2, 4));
      deliver(controller, 'abcd', 4);
      expect(controller.inlineRanges, const [
        InlineRange(InlineFormat.bold, 2, 4),
      ]);
    });

    test('c commit by moving the caret', () {
      final controller = controllerWith('hello world', const [
        InlineRange(InlineFormat.bold, 0, 5),
      ]);
      deliver(controller, 'hello world', 5);
      deliver(controller, 'hello world', 5, region(0, 5));
      deliver(controller, 'help world', 4, region(0, 4));
      controller.selection = const TextSelection.collapsed(offset: 10);
      expect(controller.inlineRanges, const [
        InlineRange(InlineFormat.bold, 0, 4),
      ]);
    });

    test('d commit by a valid collapsed composing range', () {
      final controller = controllerWith('abcd', const [
        InlineRange(InlineFormat.bold, 2, 4),
      ]);
      deliver(controller, 'abcd', 0);
      deliver(controller, 'xabcd', 1, region(0, 1));
      deliver(controller, 'xabcd', 1, const TextRange.collapsed(1));
      expect(controller.inlineRanges, const [
        InlineRange(InlineFormat.bold, 3, 5),
      ]);
    });

    test('e a second composition takes a fresh snapshot', () {
      final controller = controllerWith('abcd', const [
        InlineRange(InlineFormat.bold, 2, 4),
      ]);
      deliver(controller, 'abcd', 0);
      deliver(controller, 'xabcd', 1, region(0, 1));
      deliver(controller, 'xabcd', 1);
      deliver(controller, 'xabcd', 4);
      deliver(controller, 'xabcyd', 5, region(4, 5));
      deliver(controller, 'xabcyd', 5);
      expect(controller.inlineRanges, const [
        InlineRange(InlineFormat.bold, 3, 6),
      ]);
    });
  });

  test('B3 cancelling a composition restores the ranges', () {
    final controller = controllerWith('hello world', const [
      InlineRange(InlineFormat.bold, 0, 5),
      InlineRange(InlineFormat.italic, 6, 8),
    ]);
    deliver(controller, 'hello world', 11, region(6, 11));
    deliver(controller, 'hello w', 7, region(6, 7));
    deliver(controller, 'hello world', 11);
    expect(controller.inlineRanges, const [
      InlineRange(InlineFormat.bold, 0, 5),
      InlineRange(InlineFormat.italic, 6, 8),
    ]);
  });

  test('B6 a toggle during a composition applies in the current text', () {
    final controller = controllerWith('ab cd ef', const []);
    deliver(controller, 'ab cd ef', 2);
    deliver(controller, 'ab cd ef', 2, region(0, 2));
    deliver(controller, 'abxyz cd ef', 5, region(0, 5));
    controller
      ..value = TextEditingValue(
        text: 'abxyz cd ef',
        selection: const TextSelection(baseOffset: 6, extentOffset: 8),
        composing: region(0, 5),
      )
      ..toggleInline(InlineFormat.bold);
    deliver(controller, 'abxyz cd ef', 5);
    expect(controller.inlineRanges, const [
      InlineRange(InlineFormat.bold, 6, 8),
    ]);
  });

  group('B7 a format toggled at the caret during a composition', () {
    test('applies to the whole composition on a pure-insertion commit', () {
      final controller = FacetEditingController(text: 'ab');
      deliver(controller, 'ab', 2);
      deliver(controller, 'abc', 3, region(2, 3));
      controller.toggleInline(InlineFormat.bold);
      deliver(controller, 'abcd', 4, region(2, 4));
      deliver(controller, 'abcd', 4);
      expect(controller.inlineRanges, const [
        InlineRange(InlineFormat.bold, 2, 4),
      ]);
    });

    test('applies when the commit repeats the composing text', () {
      final controller = FacetEditingController();
      deliver(controller, '', 0);
      deliver(controller, 'h', 1, region(0, 1));
      deliver(controller, 'hel', 3, region(0, 3));
      controller.toggleInline(InlineFormat.bold);
      deliver(controller, 'hel', 3);
      expect(controller.inlineRanges, const [
        InlineRange(InlineFormat.bold, 0, 3),
      ]);
      expect(controller.activeInlineFormats(), {InlineFormat.bold});
      deliver(controller, 'helo', 4);
      expect(controller.inlineRanges, const [
        InlineRange(InlineFormat.bold, 0, 4),
      ]);
    });

    test('stays armed when existing text is composed and committed as-is', () {
      final controller = FacetEditingController(text: 'hel');
      deliver(controller, 'hel', 3);
      deliver(controller, 'hel', 3, region(0, 3));
      controller.toggleInline(InlineFormat.bold);
      deliver(controller, 'hel', 3);
      expect(controller.activeInlineFormats(), {InlineFormat.bold});
      deliver(controller, 'helo', 4);
      expect(controller.inlineRanges, const [
        InlineRange(InlineFormat.bold, 3, 4),
      ]);
    });

    test('applies to a conversion that replaces the composing text', () {
      final controller = FacetEditingController(text: 'say ');
      deliver(controller, 'say ', 4);
      deliver(controller, 'say n', 5, region(4, 5));
      deliver(controller, 'say nihao', 9, region(4, 9));
      controller.toggleInline(InlineFormat.bold);
      deliver(controller, 'say 你好', 6);
      expect(controller.inlineRanges, const [
        InlineRange(InlineFormat.bold, 4, 6),
      ]);
      expect(controller.activeInlineFormats(), {InlineFormat.bold});
    });

    test('applies to an autocorrected word and stays armed', () {
      final controller = FacetEditingController();
      deliver(controller, '', 0);
      deliver(controller, 'h', 1, region(0, 1));
      deliver(controller, 'helo', 4, region(0, 4));
      controller.toggleInline(InlineFormat.bold);
      deliver(controller, 'hello ', 6);
      expect(controller.inlineRanges, const [
        InlineRange(InlineFormat.bold, 0, 6),
      ]);
      expect(controller.activeInlineFormats(), {InlineFormat.bold});
    });

    test('applies to a re-composed existing word that is autocorrected', () {
      final controller = FacetEditingController(text: 'helo');
      deliver(controller, 'helo', 4);
      deliver(controller, 'helo', 4, region(0, 4));
      controller.toggleInline(InlineFormat.bold);
      deliver(controller, 'hello ', 6);
      expect(controller.inlineRanges, const [
        InlineRange(InlineFormat.bold, 0, 6),
      ]);
      expect(controller.activeInlineFormats(), {InlineFormat.bold});
    });

    test('toggled off removes it from a re-composed existing word', () {
      final controller = controllerWith('helo', const [
        InlineRange(InlineFormat.bold, 0, 4),
      ]);
      deliver(controller, 'helo', 4);
      deliver(controller, 'helo', 4, region(0, 4));
      controller.toggleInline(InlineFormat.bold);
      deliver(controller, 'hello ', 6);
      expect(controller.inlineRanges, isEmpty);
    });

    test('shows in inlineRanges as soon as it is toggled', () {
      final controller = FacetEditingController();
      deliver(controller, '', 0);
      deliver(controller, 'hel', 3, region(0, 3));
      expect(controller.inlineRanges, isEmpty);
      controller.toggleInline(InlineFormat.bold);
      expect(controller.inlineRanges, const [
        InlineRange(InlineFormat.bold, 0, 3),
      ]);
    });

    test('is discarded by a cancel, which restores the ranges', () {
      final controller = controllerWith('abcd', const [
        InlineRange(InlineFormat.bold, 1, 2),
      ]);
      deliver(controller, 'abcd', 3);
      deliver(controller, 'abcd', 3, region(1, 3));
      deliver(controller, 'axd', 2, region(1, 2));
      controller.toggleInline(InlineFormat.italic);
      deliver(controller, 'abcd', 3);
      expect(controller.inlineRanges, const [
        InlineRange(InlineFormat.bold, 1, 2),
      ]);
    });
  });

  group('B10 a composed replacement without a toggle', () {
    test('takes the first replaced character formats, not the caret', () {
      final controller = controllerWith('wrold', const [
        InlineRange(InlineFormat.bold, 3, 5),
      ]);
      deliver(controller, 'wrold', 5);
      deliver(controller, 'wrold', 5, region(0, 5));
      deliver(controller, 'world ', 6);
      expect(controller.inlineRanges, isEmpty);
    });

    test('keeps formats armed before the composition began', () {
      final controller = FacetEditingController();
      deliver(controller, '', 0);
      controller.toggleInline(InlineFormat.bold);
      deliver(controller, 'h', 1, region(0, 1));
      deliver(controller, 'helo', 4, region(0, 4));
      deliver(controller, 'hello ', 6);
      expect(controller.inlineRanges, const [
        InlineRange(InlineFormat.bold, 0, 6),
      ]);
    });
  });

  group('B11 a toggle during a composition', () {
    test('covers from the diff start when it is before the composition', () {
      final controller = FacetEditingController(text: 'teh');
      deliver(controller, 'teh', 3);
      deliver(controller, 'teh', 3, region(2, 3));
      controller.toggleInline(InlineFormat.bold);
      deliver(controller, 'the ', 4);
      expect(controller.inlineRanges, const [
        InlineRange(InlineFormat.bold, 1, 4),
      ]);
    });

    test('applies when the selection before it was not collapsed', () {
      final controller = FacetEditingController(text: 'xy')
        ..selection = const TextSelection(baseOffset: 0, extentOffset: 2);
      deliver(controller, 'q', 1, region(0, 1));
      controller.toggleInline(InlineFormat.bold);
      deliver(controller, 'qr', 2);
      expect(controller.inlineRanges, const [
        InlineRange(InlineFormat.bold, 0, 2),
      ]);
    });
  });

  test('B8 a cancel after a selection toggle restores the ranges', () {
    final controller = controllerWith('abcd', const [
      InlineRange(InlineFormat.bold, 1, 2),
    ]);
    deliver(controller, 'abcd', 3);
    deliver(controller, 'abcd', 3, region(1, 3));
    deliver(controller, 'axd', 2, region(1, 2));
    controller
      ..value = TextEditingValue(
        text: 'axd',
        selection: const TextSelection(baseOffset: 1, extentOffset: 2),
        composing: region(1, 2),
      )
      ..toggleInline(InlineFormat.italic);
    deliver(controller, 'abcd', 3);
    expect(controller.inlineRanges, const [
      InlineRange(InlineFormat.bold, 1, 2),
    ]);
  });

  test('B8 committing unchanged text after a selection toggle keeps it', () {
    final controller = FacetEditingController(text: 'abcd');
    deliver(controller, 'abcd', 3);
    deliver(controller, 'abcd', 3, region(1, 3));
    controller
      ..value = TextEditingValue(
        text: 'abcd',
        selection: const TextSelection(baseOffset: 1, extentOffset: 2),
        composing: region(1, 3),
      )
      ..toggleInline(InlineFormat.italic)
      ..clearComposing();
    expect(controller.inlineRanges, const [
      InlineRange(InlineFormat.italic, 1, 2),
    ]);
  });

  test('B9 moving the caret during a composition re-arms its formats', () {
    final controller = controllerWith('abc wxyz', const [
      InlineRange(InlineFormat.bold, 0, 3),
    ]);
    deliver(controller, 'abc wxyz', 2);
    deliver(controller, 'abc wxyz', 2, region(0, 3));
    expect(controller.activeInlineFormats(), {InlineFormat.bold});
    deliver(controller, 'abc wxyz', 8, region(0, 3));
    expect(controller.activeInlineFormats(), isEmpty);
    deliver(controller, 'abc wxyz', 8);
    deliver(controller, 'abc wxyzq', 9);
    expect(controller.inlineRanges, const [
      InlineRange(InlineFormat.bold, 0, 3),
    ]);
  });

  group('B12 a keyboard update that rewrites text before the caret and '
      'inserts at it', () {
    // Key-event keyboards send no composing region; the emulator's Gboard
    // capitalises a line's first word in the same update as the next
    // character, which lands at the caret.
    test('keeps a format toggled off at the caret off', () {
      final controller = FacetEditingController(text: 'a\n');
      deliver(controller, 'a\n', 2);
      controller.toggleInline(InlineFormat.italic);
      deliver(controller, 'a\ns', 3);
      deliver(controller, 'a\nslow', 6);
      controller.toggleInline(InlineFormat.italic);
      deliver(controller, 'a\nSlow ', 7);
      expect(controller.inlineRanges, const [
        InlineRange(InlineFormat.italic, 2, 6),
      ]);
      expect(controller.activeInlineFormats(), isEmpty);
      deliver(controller, 'a\nSlow e', 8);
      expect(controller.inlineRanges, const [
        InlineRange(InlineFormat.italic, 2, 6),
      ]);
    });

    test('keeps a format toggled on at the caret on', () {
      final controller = FacetEditingController(text: 'a\n');
      deliver(controller, 'a\n', 2);
      deliver(controller, 'a\nslow', 6);
      controller.toggleInline(InlineFormat.italic);
      deliver(controller, 'a\nSlow ', 7);
      expect(controller.inlineRanges, const [
        InlineRange(InlineFormat.italic, 6, 7),
      ]);
      expect(controller.activeInlineFormats(), {InlineFormat.italic});
    });

    test('an autocorrection that changes more than letter case stays one '
        'replacement', () {
      final controller = FacetEditingController(text: 'a\n');
      deliver(controller, 'a\n', 2);
      controller.toggleInline(InlineFormat.italic);
      deliver(controller, 'a\nhelo', 6);
      controller.toggleInline(InlineFormat.italic);
      deliver(controller, 'a\nhello ', 8);
      expect(controller.inlineRanges, const [
        InlineRange(InlineFormat.italic, 2, 8),
      ]);
    });

    test('an insertion before the caret is not read as a rewrite', () {
      final controller = FacetEditingController(text: 'ab')
        ..selection = const TextSelection(baseOffset: 0, extentOffset: 2)
        ..toggleInline(InlineFormat.bold);
      deliver(controller, 'ab', 2);
      controller.toggleInline(InlineFormat.bold);
      deliver(controller, 'Xab ', 4);
      // 'ab', now at 1..3, keeps its bold
      expect(
        controller.inlineRanges.any(
          (range) =>
              range.format == InlineFormat.bold &&
              range.start <= 1 &&
              range.end >= 3,
        ),
        isTrue,
      );
    });

    test('without a toggle, the rewrite and insertion take the formats '
        'they did before', () {
      final controller = FacetEditingController(text: 'a\n');
      deliver(controller, 'a\n', 2);
      controller.toggleInline(InlineFormat.italic);
      deliver(controller, 'a\nslow', 6);
      deliver(controller, 'a\nSlow ', 7);
      expect(controller.inlineRanges, const [
        InlineRange(InlineFormat.italic, 2, 7),
      ]);
    });
  });

  group('B13 a keyboard that recomposes by selecting, deleting and '
      'reinserting', () {
    // The iOS Korean keyboard sends no composing region: each new jamo
    // selects the syllable being built, deletes it, then inserts the
    // recomposed syllable. Every value arrives twice.
    void select(FacetEditingController controller, int start, int end) {
      controller.value = controller.value.copyWith(
        selection: TextSelection(baseOffset: start, extentOffset: end),
      );
    }

    void recompose(
      FacetEditingController controller,
      String before,
      int start,
      String after,
    ) {
      select(controller, start, before.length);
      deliver(controller, before.substring(0, start), start);
      deliver(controller, before.substring(0, start), start);
      deliver(controller, after, after.length);
      deliver(controller, after, after.length);
    }

    test('keeps a format toggled on at an empty line on', () {
      final controller = FacetEditingController();
      deliver(controller, '', 0);
      controller.toggleInline(InlineFormat.bold);
      deliver(controller, 'ㄱ', 1);
      deliver(controller, 'ㄱ', 1);
      recompose(controller, 'ㄱ', 0, '가');
      expect(controller.inlineRanges, const [
        InlineRange(InlineFormat.bold, 0, 1),
      ]);
      expect(controller.activeInlineFormats(), {InlineFormat.bold});
    });

    test('keeps a format toggled off after formatted text off', () {
      final controller = controllerWith('ab', const [
        InlineRange(InlineFormat.bold, 0, 2),
      ]);
      deliver(controller, 'ab', 2);
      controller.toggleInline(InlineFormat.bold);
      deliver(controller, 'abㅇ', 3);
      deliver(controller, 'abㅇ', 3);
      recompose(controller, 'abㅇ', 2, 'ab아');
      recompose(controller, 'ab아', 2, 'ab안');
      deliver(controller, 'ab안 ', 4);
      deliver(controller, 'ab안 ㅎ', 5);
      recompose(controller, 'ab안 ㅎ', 3, 'ab안 하');
      expect(controller.inlineRanges, const [
        InlineRange(InlineFormat.bold, 0, 2),
      ]);
      expect(controller.activeInlineFormats(), isEmpty);
    });

    test('a recomposition that splits a formatted syllable keeps the format '
        'on its first character only', () {
      final controller = FacetEditingController();
      deliver(controller, '', 0);
      controller.toggleInline(InlineFormat.bold);
      deliver(controller, 'ㄱ', 1);
      recompose(controller, 'ㄱ', 0, '가');
      controller.toggleInline(InlineFormat.bold);
      recompose(controller, '가', 0, '강');
      recompose(controller, '강', 0, '가아');
      recompose(controller, '가아', 0, '가안');
      expect(controller.inlineRanges, const [
        InlineRange(InlineFormat.bold, 0, 1),
      ]);
      expect(controller.activeInlineFormats(), isEmpty);
    });

    test('a replacement put back over several updates keeps the replaced '
        'formats', () {
      final controller = controllerWith('x 하', const [
        InlineRange(InlineFormat.bold, 0, 3),
      ]);
      deliver(controller, 'x 하', 3);
      controller.toggleInline(InlineFormat.bold);
      select(controller, 1, 3);
      deliver(controller, 'x', 1);
      deliver(controller, 'x', 1);
      deliver(controller, 'x ', 2);
      deliver(controller, 'x ', 2);
      deliver(controller, 'x 항', 3);
      deliver(controller, 'x 항', 3);
      recompose(controller, 'x 항', 2, 'x 하아');
      expect(controller.inlineRanges, const [
        InlineRange(InlineFormat.bold, 0, 3),
      ]);
      expect(controller.activeInlineFormats(), isEmpty);
    });

    test('deleting a selection that ends at the caret arms the formats '
        'before the caret', () {
      final controller = controllerWith('abcd', const [
        InlineRange(InlineFormat.bold, 0, 1),
      ]);
      deliver(controller, 'abcd', 3);
      select(controller, 1, 3);
      deliver(controller, 'ad', 1);
      expect(controller.activeInlineFormats(), {InlineFormat.bold});
    });

    test('a toggle after the deletion applies to the text typed next', () {
      final controller = controllerWith('ab', const [
        InlineRange(InlineFormat.bold, 0, 2),
      ]);
      deliver(controller, 'ab', 2);
      select(controller, 1, 2);
      deliver(controller, 'a', 1);
      controller.toggleInline(InlineFormat.bold);
      deliver(controller, 'ax', 2);
      expect(controller.inlineRanges, const [
        InlineRange(InlineFormat.bold, 0, 1),
      ]);
    });

    test('a block toggled after the deletion stays', () {
      final controller = controllerWith('ab', const [
        InlineRange(InlineFormat.bold, 0, 2),
      ]);
      deliver(controller, 'ab', 2);
      select(controller, 0, 2);
      deliver(controller, '', 0);
      controller.toggleBlock(BlockFormat.blockquote);
      deliver(controller, 'x', 1);
      expect(controller.blockRanges, const [
        BlockRange(BlockFormat.blockquote, 0, 1),
      ]);
    });

    test('text pasted after the deletion stays unformatted', () {
      final controller = controllerWith('abc', const [
        InlineRange(InlineFormat.bold, 0, 3),
      ]);
      deliver(controller, 'abc', 3);
      select(controller, 1, 3);
      deliver(controller, 'a', 1);
      controller.pasteUnformatted('x');
      deliver(controller, 'axy', 3);
      expect(controller.inlineRanges, const [
        InlineRange(InlineFormat.bold, 0, 1),
      ]);
    });

    test('a composition after the deletion ends the replacement', () {
      final controller = controllerWith('abcd', const [
        InlineRange(InlineFormat.bold, 0, 4),
      ]);
      deliver(controller, 'abcd', 4);
      select(controller, 3, 4);
      deliver(controller, 'abc', 3);
      deliver(controller, 'abcx', 4, region(3, 4));
      controller.value = const TextEditingValue(
        text: 'abcx',
        selection: TextSelection.collapsed(offset: 0),
        composing: TextRange(start: 3, end: 4),
      );
      deliver(controller, 'abc', 0);
      deliver(controller, 'yabc', 1);
      expect(controller.text, 'yabc');
      expect(controller.inlineRanges, const [
        InlineRange(InlineFormat.bold, 1, 4),
      ]);
    });

    test('a selection the user deletes still arms the formats before the '
        'caret', () {
      final controller = controllerWith('abcd', const [
        InlineRange(InlineFormat.bold, 0, 1),
      ]);
      deliver(controller, 'abcd', 1);
      select(controller, 1, 3);
      deliver(controller, 'ad', 1);
      expect(controller.activeInlineFormats(), {InlineFormat.bold});
    });
  });
}
