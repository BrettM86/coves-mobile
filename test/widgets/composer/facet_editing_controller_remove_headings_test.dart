import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Three lines: "aa" [0,2], "bb" [3,5], "cc" [6,8].
const threeLines = 'aa\nbb\ncc';

const quote = BlockFormat.blockquote;
const heading = BlockFormat.heading;

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

/// Selects [start]..[end] (a caret when equal).
void select(FacetEditingController controller, int start, int end) {
  controller.selection = TextSelection(baseOffset: start, extentOffset: end);
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

void main() {
  test('removeHeadings removes only the headings on touched lines', () {
    // "one" [0,3], "two" [4,7].
    final controller = FacetEditingController(text: 'one\ntwo');
    addTearDown(controller.dispose);
    toggleOver(controller, 1, 5, heading);
    expect(controller.blockRanges.toSet(), {
      const BlockRange(heading, 0, 3),
      const BlockRange(heading, 4, 7),
    }, reason: 'precondition: both lines are H1');

    select(controller, 1, 1);
    controller.removeHeadings();

    expect(controller.blockRanges, [const BlockRange(heading, 4, 7)]);
  });

  test('removeHeadings leaves the heading on a line the selection ends at '
      'the start of', () {
    final controller = FacetEditingController(text: 'one\ntwo');
    addTearDown(controller.dispose);
    toggleOver(controller, 1, 5, heading);

    select(controller, 1, 4);
    expect(controller.touchesHeading(), isTrue);
    controller.removeHeadings();

    expect(controller.blockRanges, [const BlockRange(heading, 4, 7)]);
  });

  test('removeHeadings keeps the quote around the heading line', () {
    final controller = FacetEditingController(text: threeLines);
    addTearDown(controller.dispose);
    toggleOver(controller, 0, 8, quote);
    toggleOver(controller, 4, 4, heading, level: 2);
    expect(controller.blockRanges.toSet(), {
      const BlockRange(quote, 0, 8),
      const BlockRange(heading, 3, 5, level: 2),
    }, reason: 'precondition: a quoted H2 middle line');

    select(controller, 4, 4);
    controller.removeHeadings();

    expect(controller.blockRanges, [const BlockRange(quote, 0, 8)]);
  });

  group('removeHeadings during a composition', () {
    /// Puts H2 on "bb", then composes "bb" into "bbx" (line [3,6]).
    FacetEditingController composeOnHeadingLine() {
      final controller = FacetEditingController(text: threeLines);
      addTearDown(controller.dispose);
      toggleOver(controller, 4, 4, heading, level: 2);
      expect(controller.blockRanges.toSet(), {
        const BlockRange(heading, 3, 5, level: 2),
      }, reason: 'precondition: line 2 is H2 before the composition');
      deliver(controller, threeLines, 5);
      deliver(controller, threeLines, 5, const TextRange(start: 3, end: 5));
      deliver(controller, 'aa\nbbx\ncc', 6, const TextRange(start: 3, end: 6));
      controller.removeHeadings();
      expect(
        controller.blockRanges,
        isEmpty,
        reason: 'precondition: the heading is gone while composing',
      );
      return controller;
    }

    test('a committed composition keeps the heading removed', () {
      final controller = composeOnHeadingLine();

      deliver(controller, 'aa\nbbx\ncc', 6);

      expect(controller.text, 'aa\nbbx\ncc');
      expect(controller.blockRanges, isEmpty);
    });

    test('a cancelled composition restores the pre-composition heading', () {
      final controller = composeOnHeadingLine();

      deliver(controller, threeLines, 5);

      expect(controller.text, threeLines);
      expect(controller.blockRanges.toSet(), {
        const BlockRange(heading, 3, 5, level: 2),
      });
    });
  });
}
