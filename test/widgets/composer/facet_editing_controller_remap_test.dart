import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Selects [baseOffset, extentOffset) and toggles [format] over it.
void toggleOver(
  FacetEditingController controller,
  InlineFormat format,
  int baseOffset,
  int extentOffset,
) {
  controller
    ..selection = TextSelection(
      baseOffset: baseOffset,
      extentOffset: extentOffset,
    )
    ..toggleInline(format);
}

/// Moves the caret without changing the text.
void moveCaret(FacetEditingController controller, int offset) {
  controller.selection = TextSelection.collapsed(offset: offset);
}

/// Delivers [newText] as one value update with the caret at [caret], the way
/// EditableText reports a keystroke or keyboard replacement.
void deliver(FacetEditingController controller, String newText, int caret) {
  controller.value = TextEditingValue(
    text: newText,
    selection: TextSelection.collapsed(offset: caret),
  );
}

/// Types [characters] one value update per character at the current caret.
void typeCharacters(FacetEditingController controller, String characters) {
  for (final character in characters.split('')) {
    final caret = controller.selection.baseOffset;
    final text = controller.text;
    deliver(
      controller,
      text.substring(0, caret) + character + text.substring(caret),
      caret + 1,
    );
  }
}

void main() {
  test('B1 a single insertion remaps ranges by their position', () {
    const cases = [
      (
        boldStart: 2,
        boldEnd: 6,
        expected: [InlineRange(InlineFormat.bold, 2, 8)],
      ),
      (
        boldStart: 4,
        boldEnd: 6,
        expected: [InlineRange(InlineFormat.bold, 6, 8)],
      ),
    ];
    for (final testCase in cases) {
      final controller = FacetEditingController(text: 'abcdefgh');
      toggleOver(
        controller,
        InlineFormat.bold,
        testCase.boldStart,
        testCase.boldEnd,
      );
      moveCaret(controller, 4);
      deliver(controller, 'abcdxyefgh', 6);
      expect(
        controller.inlineRanges,
        testCase.expected,
        reason: 'bold [${testCase.boldStart}, ${testCase.boldEnd})',
      );
    }
  });

  test('B1 listeners see remapped ranges inside their callback', () {
    final controller = FacetEditingController(text: 'abcdefgh');
    toggleOver(controller, InlineFormat.bold, 2, 6);
    moveCaret(controller, 4);
    List<InlineRange>? rangesSeenByListener;
    controller.addListener(() {
      rangesSeenByListener = controller.inlineRanges;
    });
    deliver(controller, 'abcdxyefgh', 6);
    expect(rangesSeenByListener, const [InlineRange(InlineFormat.bold, 2, 8)]);
  });

  test('B2 a caret at the end of a range arms its format', () {
    final controller = FacetEditingController(text: 'abcdefgh');
    toggleOver(controller, InlineFormat.bold, 2, 6);
    moveCaret(controller, 6);
    expect(controller.activeInlineFormats(), {InlineFormat.bold});
  });

  test('B2 typing at the end of a range extends it', () {
    final controller = FacetEditingController(text: 'abcdefgh');
    toggleOver(controller, InlineFormat.bold, 2, 6);
    moveCaret(controller, 6);
    typeCharacters(controller, 'xy');
    expect(controller.inlineRanges, const [
      InlineRange(InlineFormat.bold, 2, 8),
    ]);
  });

  test('B3 toggling an armed format off keeps typed text unformatted', () {
    const cases = [
      (caret: 6, expected: [InlineRange(InlineFormat.bold, 2, 6)]),
      (
        caret: 4,
        expected: [
          InlineRange(InlineFormat.bold, 2, 4),
          InlineRange(InlineFormat.bold, 6, 8),
        ],
      ),
    ];
    for (final testCase in cases) {
      final controller = FacetEditingController(text: 'abcdefgh');
      toggleOver(controller, InlineFormat.bold, 2, 6);
      moveCaret(controller, testCase.caret);
      controller.toggleInline(InlineFormat.bold);
      expect(
        controller.activeInlineFormats(),
        isEmpty,
        reason: 'caret ${testCase.caret}',
      );
      typeCharacters(controller, 'xy');
      expect(
        controller.inlineRanges,
        testCase.expected,
        reason: 'caret ${testCase.caret}',
      );
    }
  });

  test('B4 a format toggled at a caret applies to the text typed next', () {
    final controller = FacetEditingController(text: 'abcdefgh');
    moveCaret(controller, 4);
    controller.toggleInline(InlineFormat.bold);
    typeCharacters(controller, 'xy');
    expect(controller.inlineRanges, const [
      InlineRange(InlineFormat.bold, 4, 6),
    ]);
  });

  test('B4 moving the caret clears a toggled format', () {
    final controller = FacetEditingController(text: 'abcdefgh');
    moveCaret(controller, 4);
    controller.toggleInline(InlineFormat.bold);
    moveCaret(controller, 1);
    moveCaret(controller, 4);
    typeCharacters(controller, 'xy');
    expect(controller.inlineRanges, isEmpty);
  });

  test('B4 several formats toggled at a caret all apply to typed text', () {
    final controller = FacetEditingController(text: 'abcdefgh');
    moveCaret(controller, 4);
    controller
      ..toggleInline(InlineFormat.bold)
      ..toggleInline(InlineFormat.italic);
    typeCharacters(controller, 'xy');
    expect(controller.inlineRanges, const [
      InlineRange(InlineFormat.bold, 4, 6),
      InlineRange(InlineFormat.italic, 4, 6),
    ]);
  });

  test('B4 assigning an identical value keeps a toggled format armed', () {
    final controller = FacetEditingController(text: 'abcdefgh');
    moveCaret(controller, 4);
    controller.toggleInline(InlineFormat.bold);
    deliver(controller, 'abcdefgh', 4);
    expect(controller.activeInlineFormats(), {InlineFormat.bold});
  });

  test('B4 a toggle at a caret notifies listeners once', () {
    final controller = FacetEditingController(text: 'abcdefgh');
    moveCaret(controller, 4);
    var notificationCount = 0;
    controller
      ..addListener(() => notificationCount++)
      ..toggleInline(InlineFormat.bold);
    expect(notificationCount, 1);
  });

  test('B4 a block toggle at a caret notifies listeners once', () {
    final controller = FacetEditingController(text: 'aa\nbb\ncc');
    moveCaret(controller, 4);
    var notificationCount = 0;
    controller
      ..addListener(() => notificationCount++)
      ..toggleBlock(BlockFormat.blockquote);
    expect(notificationCount, 1);
  });

  test('B5 a deletion shrinks or shifts ranges', () {
    const cases = [
      (
        boldStart: 2,
        boldEnd: 8,
        // "abcdefgh" with [4,6) "ef" deleted.
        newText: 'abcdgh',
        caret: 4,
        expected: [InlineRange(InlineFormat.bold, 2, 6)],
      ),
      (
        boldStart: 4,
        boldEnd: 6,
        // "abcdefgh" with [0,2) "ab" deleted.
        newText: 'cdefgh',
        caret: 0,
        expected: [InlineRange(InlineFormat.bold, 2, 4)],
      ),
    ];
    for (final testCase in cases) {
      final controller = FacetEditingController(text: 'abcdefgh');
      toggleOver(
        controller,
        InlineFormat.bold,
        testCase.boldStart,
        testCase.boldEnd,
      );
      deliver(controller, testCase.newText, testCase.caret);
      expect(
        controller.inlineRanges,
        testCase.expected,
        reason: 'bold [${testCase.boldStart}, ${testCase.boldEnd})',
      );
    }
  });

  test('B6 deleting all of a range drops it', () {
    final controller = FacetEditingController(text: 'abcdefgh');
    toggleOver(controller, InlineFormat.bold, 2, 6);
    // "abcdefgh" with [1,7) "bcdefg" deleted.
    deliver(controller, 'ah', 1);
    expect(controller.inlineRanges, isEmpty);
  });
  test('B7 a transposition fix keeps each format on its own letters', () {
    final controller = FacetEditingController(text: 'the wrold');
    toggleOver(controller, InlineFormat.bold, 4, 6);
    toggleOver(controller, InlineFormat.italic, 6, 9);
    moveCaret(controller, 9);
    deliver(controller, 'the world', 9);
    expect(controller.inlineRanges, const [
      InlineRange(InlineFormat.bold, 4, 7),
      InlineRange(InlineFormat.italic, 7, 9),
    ]);
  });

  test('B8 an ambiguous insertion of a repeated character follows the '
      'caret', () {
    const cases = [
      (caret: 1, expected: [InlineRange(InlineFormat.bold, 2, 3)]),
      (caret: 3, expected: [InlineRange(InlineFormat.bold, 1, 3)]),
    ];
    for (final testCase in cases) {
      final controller = FacetEditingController(text: 'aaa');
      toggleOver(controller, InlineFormat.bold, 1, 2);
      moveCaret(controller, 3);
      deliver(controller, 'aaaa', testCase.caret);
      expect(
        controller.inlineRanges,
        testCase.expected,
        reason: 'new caret ${testCase.caret}',
      );
    }
  });

  test('B8 an ambiguous deletion of a repeated character follows the '
      'caret', () {
    const cases = [
      (oldCaret: 2, newCaret: 1, expected: <InlineRange>[]),
      (
        oldCaret: 3,
        newCaret: 2,
        expected: [InlineRange(InlineFormat.bold, 1, 2)],
      ),
    ];
    for (final testCase in cases) {
      final controller = FacetEditingController(text: 'aaa');
      toggleOver(controller, InlineFormat.bold, 1, 2);
      moveCaret(controller, testCase.oldCaret);
      deliver(controller, 'aa', testCase.newCaret);
      expect(
        controller.inlineRanges,
        testCase.expected,
        reason: 'caret ${testCase.oldCaret} -> ${testCase.newCaret}',
      );
    }
  });

  test('B11 replacing formatted text gives the replacement the format of '
      'the first replaced character', () {
    final cases = [
      (
        // iOS auto-capitalisation: "i" becomes "I ".
        oldText: 'x i',
        boldStart: 2,
        boldEnd: 3,
        selection: const TextSelection.collapsed(offset: 3),
        newText: 'x I ',
        caret: 4,
        expected: const [InlineRange(InlineFormat.bold, 2, 4)],
      ),
      (
        // Whole-word suggestion: "cat" becomes "dog".
        oldText: 'the cat sat',
        boldStart: 4,
        boldEnd: 7,
        selection: const TextSelection.collapsed(offset: 7),
        newText: 'the dog sat',
        caret: 7,
        expected: const [InlineRange(InlineFormat.bold, 4, 7)],
      ),
      (
        // Typing "d" over the selected bold word "cat".
        oldText: 'the cat sat',
        boldStart: 4,
        boldEnd: 7,
        selection: const TextSelection(baseOffset: 4, extentOffset: 7),
        newText: 'the d sat',
        caret: 5,
        expected: const [InlineRange(InlineFormat.bold, 4, 5)],
      ),
    ];
    for (final testCase in cases) {
      final controller = FacetEditingController(text: testCase.oldText);
      toggleOver(
        controller,
        InlineFormat.bold,
        testCase.boldStart,
        testCase.boldEnd,
      );
      controller.selection = testCase.selection;
      deliver(controller, testCase.newText, testCase.caret);
      expect(
        controller.inlineRanges,
        testCase.expected,
        reason: '"${testCase.oldText}" -> "${testCase.newText}"',
      );
    }
  });

  test('B9 edits inside grapheme clusters keep ranges on cluster '
      'boundaries', () {
    // UTF-16 lengths: 👍 U+1F44D = 2, 🏽 U+1F3FD = 2, 👩 U+1F469 = 2,
    // ZWJ U+200D = 1, each regional indicator (🇺 🇸 🇦) = 2.
    const cases = [
      (
        name: 'r1 insert x before a thumbs up',
        // a=[0,1) 👍=[1,3) b=[3,4).
        oldText: 'a👍b',
        boldStart: 1,
        boldEnd: 3,
        // a=[0,1) x=[1,2) 👍=[2,4) b=[4,5); bold shifts right by 1.
        newText: 'ax👍b',
        caret: 2,
        expected: [InlineRange(InlineFormat.bold, 2, 4)],
        boundaries: [0, 1, 2, 4, 5],
      ),
      (
        name: 'r2 skin tone added to a bold thumbs up',
        oldText: 'a👍b',
        boldStart: 1,
        boldEnd: 3,
        // a=[0,1) 👍🏽=[1,5) (2 + 2) b=[5,6).
        newText: 'a👍🏽b',
        caret: 5,
        expected: [InlineRange(InlineFormat.bold, 1, 5)],
        boundaries: [0, 1, 5, 6],
      ),
      (
        name: 'r3 ZWJ joins a bold woman to a plain one',
        // x=[0,1) 👩=[1,3) 👩=[3,5) y=[5,6).
        oldText: 'x👩👩y',
        boldStart: 1,
        boldEnd: 3,
        // x=[0,1) 👩‍👩=[1,6) (2 + 1 + 2) y=[6,7).
        newText: 'x👩‍👩y',
        caret: 4,
        expected: [InlineRange(InlineFormat.bold, 1, 6)],
        boundaries: [0, 1, 6, 7],
      ),
      (
        name: 'r4 ZWJ joins a plain woman to a bold one',
        // a=[0,1) b=[1,2) 👩=[2,4) 👩=[4,6).
        oldText: 'ab👩👩',
        boldStart: 4,
        boldEnd: 6,
        // a=[0,1) b=[1,2) 👩‍👩=[2,7) (2 + 1 + 2).
        newText: 'ab👩‍👩',
        caret: 5,
        expected: [InlineRange(InlineFormat.bold, 2, 7)],
        boundaries: [0, 1, 2, 7],
      ),
      (
        name: 'r5 ZWJ removed from a bold sequence',
        // x=[0,1) 👩‍👩=[1,6) y=[6,7).
        oldText: 'x👩‍👩y',
        boldStart: 1,
        boldEnd: 6,
        // x=[0,1) 👩=[1,3) 👩=[3,5) y=[5,6); bold loses the 1-unit ZWJ.
        newText: 'x👩👩y',
        caret: 3,
        expected: [InlineRange(InlineFormat.bold, 1, 5)],
        boundaries: [0, 1, 3, 5, 6],
      ),
      (
        name: 'r6 keyboard suggestion swaps a flag',
        // 🇺🇸=[0,4) space=[4,5) h=[5,6) i=[6,7).
        oldText: '🇺🇸 hi',
        boldStart: 0,
        boldEnd: 4,
        // 🇺🇦=[0,4) space=[4,5) h=[5,6) i=[6,7).
        newText: '🇺🇦 hi',
        caret: 4,
        expected: [InlineRange(InlineFormat.bold, 0, 4)],
        boundaries: [0, 4, 5, 6, 7],
      ),
    ];
    for (final testCase in cases) {
      final controller = FacetEditingController(text: testCase.oldText);
      toggleOver(
        controller,
        InlineFormat.bold,
        testCase.boldStart,
        testCase.boldEnd,
      );
      moveCaret(controller, testCase.oldText.length);
      deliver(controller, testCase.newText, testCase.caret);
      expect(controller.inlineRanges, testCase.expected, reason: testCase.name);
      for (final range in controller.inlineRanges) {
        expect(
          testCase.boundaries,
          containsAll([range.start, range.end]),
          reason: '${testCase.name}: $range',
        );
      }
    }
  });

  test('B10 a programmatic value set remaps ranges by the same diff', () {
    const cases = [
      (
        name: 'shortened to help',
        // "hello world" -> "help": [3,11) "lo world" replaced by "p".
        newText: 'help',
        expected: [InlineRange(InlineFormat.bold, 0, 4)],
      ),
      (
        name: 'replaced by unrelated text',
        // No common prefix or suffix: the whole text is replaced, and the
        // replacement takes the format of the first replaced character "h".
        newText: 'xyz',
        expected: [InlineRange(InlineFormat.bold, 0, 3)],
      ),
    ];
    for (final testCase in cases) {
      final controller = FacetEditingController(text: 'hello world');
      toggleOver(controller, InlineFormat.bold, 0, 5);
      deliver(controller, testCase.newText, testCase.newText.length);
      expect(controller.inlineRanges, testCase.expected, reason: testCase.name);
    }
  });

  test('B10 clear drops every range', () {
    final controller = FacetEditingController(text: 'hello world');
    toggleOver(controller, InlineFormat.bold, 0, 5);
    controller.clear();
    expect(controller.inlineRanges, isEmpty);
  });

  test('B10 clear disarms a format armed at the caret on the empty body', () {
    final controller = FacetEditingController();
    addTearDown(controller.dispose);
    moveCaret(controller, 0);
    controller.toggleInline(InlineFormat.bold);
    expect(controller.activeInlineFormats(), {
      InlineFormat.bold,
    }, reason: 'precondition: bold is armed at the caret');

    final seenByListener = <Set<InlineFormat>>[];
    controller
      ..addListener(() => seenByListener.add(controller.activeInlineFormats()))
      ..clear();
    expect(controller.activeInlineFormats(), isEmpty);
    expect(seenByListener, [
      isEmpty,
    ], reason: 'one notification, after the format is disarmed');

    deliver(controller, 'x', 1);
    expect(controller.inlineRanges, isEmpty);
  });

  test('B10 setting shorter text leaves no range past the new length', () {
    final controller = FacetEditingController(text: 'hello world');
    toggleOver(controller, InlineFormat.bold, 3, 9);
    controller.text = 'hello';
    // "hello world" -> "hello" deletes [5,11), so bold [3,9) becomes [3,5).
    expect(controller.inlineRanges, const [
      InlineRange(InlineFormat.bold, 3, 5),
    ]);
  });
}
