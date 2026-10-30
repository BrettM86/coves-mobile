import 'package:coves_flutter/models/facet.dart';
import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:coves_flutter/widgets/composer/facet_serialization.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'facet_fixture_helpers.dart';

void toggleOver(
  FacetEditingController controller,
  InlineFormat format,
  int start,
  int end,
) {
  select(controller, start, end);
  controller.toggleInline(format);
}

void blockOver(
  FacetEditingController controller,
  BlockFormat format,
  int start,
  int end,
) {
  select(controller, start, end);
  controller.toggleBlock(format);
}

/// A controller over [lead] and, on the line after it, [boldWords] single
/// bold words. [format] runs first, while the count is still low; each bold
/// word then adds one grouped facet.
FacetEditingController budgetController(
  String lead, {
  required int boldWords,
  void Function(FacetEditingController controller)? format,
}) {
  final filler = List.filled(boldWords, 'w').join(' ');
  final fillerStart = lead.isEmpty ? 0 : lead.length + 1;
  final controller = FacetEditingController(
    text: lead.isEmpty ? filler : '$lead\n$filler',
  );
  format?.call(controller);
  for (var i = 0; i < boldWords; i++) {
    final start = fillerStart + 2 * i;
    toggleOver(controller, InlineFormat.bold, start, start + 1);
  }
  return controller;
}

/// The grouped facet count the controller's state serializes to, computed
/// by the serializer rather than the budget under test.
int serializedCount(FacetEditingController controller) => serializeFormatting(
  controller.text,
  inlineRanges: controller.inlineRanges,
  blockRanges: controller.blockRanges,
).facets.length;

/// "bold plain" over 199 bold words (200 facets), then an unformatted paste
/// inside "bold" splits it: "boxld plain", 201 facets.
FacetEditingController overLimitController() {
  return budgetController(
      'bold plain',
      boldWords: 199,
      format: (c) => toggleOver(c, InlineFormat.bold, 0, 4),
    )
    ..selection = const TextSelection.collapsed(offset: 2)
    ..pasteUnformatted('x');
}

sealed class Toggle {
  const Toggle();
}

class BlockToggle extends Toggle {
  const BlockToggle(this.format);
  final BlockFormat format;
}

class InlineToggle extends Toggle {
  const InlineToggle(this.format);
  final InlineFormat format;
}

class CostCase {
  const CostCase(
    this.description, {
    required this.build,
    required this.toggle,
    required this.usedBefore,
    required this.cost,
    required this.allowed,
    required this.usedAfter,
  });

  final String description;
  final FacetEditingController Function() build;
  final Toggle toggle;
  final int usedBefore;
  final int cost;
  final bool allowed;
  final int usedAfter;
}

typedef Snapshot = ({
  TextEditingValue value,
  List<InlineRange> inline,
  List<BlockRange> blocks,
});

Snapshot snapshot(FacetEditingController controller) => (
  value: controller.value,
  inline: controller.inlineRanges,
  blocks: controller.blockRanges,
);

void expectUnchanged(FacetEditingController controller, Snapshot before) {
  expect(controller.value, before.value);
  expect(controller.inlineRanges, before.inline);
  expect(controller.blockRanges, before.blocks);
}

/// Three plain lines over 199 bold words, all three lines selected.
FacetEditingController threePlainLinesAt199() =>
    budgetController('a\nb\nc', boldWords: 199)
      ..selection = const TextSelection(baseOffset: 0, extentOffset: 5);

final costCases = [
  const CostCase(
    'at 199, heading over three plain lines costs 3 and is blocked',
    build: threePlainLinesAt199,
    toggle: BlockToggle(BlockFormat.heading),
    usedBefore: 199,
    cost: 3,
    allowed: false,
    usedAfter: 199,
  ),
  CostCase(
    'at 199, heading on one plain line costs 1 and is applied',
    build: () =>
        budgetController('a', boldWords: 199)
          ..selection = const TextSelection.collapsed(offset: 0),
    toggle: const BlockToggle(BlockFormat.heading),
    usedBefore: 199,
    cost: 1,
    allowed: true,
    usedAfter: 200,
  ),
  CostCase(
    'at 200, heading on a fully bold line groups: cost 0, allowed',
    build: () => budgetController(
      'head',
      boldWords: 199,
      format: (c) => toggleOver(c, InlineFormat.bold, 0, 4),
    )..selection = const TextSelection.collapsed(offset: 0),
    toggle: const BlockToggle(BlockFormat.heading),
    usedBefore: 200,
    cost: 0,
    allowed: true,
    usedAfter: 200,
  ),
  CostCase(
    'at 200, bold over an identical italic range groups: cost 0, allowed',
    build: () => budgetController(
      'it',
      boldWords: 199,
      format: (c) => toggleOver(c, InlineFormat.italic, 0, 2),
    )..selection = const TextSelection(baseOffset: 0, extentOffset: 2),
    toggle: const InlineToggle(InlineFormat.bold),
    usedBefore: 200,
    cost: 0,
    allowed: true,
    usedAfter: 200,
  ),
  CostCase(
    'at 200, bold on an unformatted word costs 1 and is blocked',
    build: () =>
        budgetController('plain', boldWords: 200)
          ..selection = const TextSelection(baseOffset: 0, extentOffset: 5),
    toggle: const InlineToggle(InlineFormat.bold),
    usedBefore: 200,
    cost: 1,
    allowed: false,
    usedAfter: 200,
  ),
  CostCase(
    'at 200, bold filling the gap between two bold ranges costs -1',
    build: () => budgetController(
      'ab cd',
      boldWords: 198,
      format: (c) {
        toggleOver(c, InlineFormat.bold, 0, 2);
        toggleOver(c, InlineFormat.bold, 3, 5);
      },
    )..selection = const TextSelection(baseOffset: 1, extentOffset: 4),
    toggle: const InlineToggle(InlineFormat.bold),
    usedBefore: 200,
    cost: -1,
    allowed: true,
    usedAfter: 199,
  ),
  CostCase(
    'at 200, code block over three heading lines costs -2',
    build: () => budgetController(
      'a\nb\nc',
      boldWords: 197,
      format: (c) => blockOver(c, BlockFormat.heading, 0, 5),
    )..selection = const TextSelection(baseOffset: 0, extentOffset: 5),
    toggle: const BlockToggle(BlockFormat.codeBlock),
    usedBefore: 200,
    cost: -2,
    allowed: true,
    usedAfter: 198,
  ),
  CostCase(
    'at 200, removing an active quote costs -1 and is allowed',
    build: () => budgetController(
      'q',
      boldWords: 199,
      format: (c) => blockOver(c, BlockFormat.blockquote, 0, 0),
    )..selection = const TextSelection.collapsed(offset: 0),
    toggle: const BlockToggle(BlockFormat.blockquote),
    usedBefore: 200,
    cost: -1,
    allowed: true,
    usedAfter: 199,
  ),
  CostCase(
    'at 200, removing a quote from its middle line splits it: cost 1, allowed',
    build: () => budgetController(
      'a\nb\nc',
      boldWords: 199,
      format: (c) => blockOver(c, BlockFormat.blockquote, 0, 5),
    )..selection = const TextSelection.collapsed(offset: 2),
    toggle: const BlockToggle(BlockFormat.blockquote),
    usedBefore: 200,
    cost: 1,
    allowed: true,
    usedAfter: 201,
  ),
  CostCase(
    'at 200, code block over a line with bold drops the bold: cost 0',
    build: () => budgetController(
      'bold x',
      boldWords: 199,
      format: (c) => toggleOver(c, InlineFormat.bold, 0, 4),
    )..selection = const TextSelection.collapsed(offset: 0),
    toggle: const BlockToggle(BlockFormat.codeBlock),
    usedBefore: 200,
    cost: 0,
    allowed: true,
    usedAfter: 200,
  ),
];

/// [count] single-character words 'a a a ...'; word i is bytes and UTF-16
/// [2i, 2i + 1).
String singleCharWords(int count) => List.filled(count, 'a').join(' ');

/// A loaded record over [singleCharWords] of [boldWords] + [tail].length
/// words: the first [boldWords] words bold, then word `boldWords + j`
/// carrying the features `tail[j]`.
FacetEditingController loadedController({
  required int boldWords,
  List<List<FacetFeature>> tail = const [],
}) {
  final controller = FacetEditingController.fromRecord(
    singleCharWords(boldWords + tail.length),
    [
      for (var i = 0; i < boldWords; i++)
        facet(2 * i, 2 * i + 1, const [BoldFacetFeature()]),
      for (var j = 0; j < tail.length; j++)
        facet(2 * (boldWords + j), 2 * (boldWords + j) + 1, tail[j]),
    ],
  );
  addTearDown(controller.dispose);
  return controller;
}

/// Saves [controller] with all three range lists.
SerializedFormatting save(FacetEditingController controller) =>
    serializeFormatting(
      controller.text,
      inlineRanges: controller.inlineRanges,
      blockRanges: controller.blockRanges,
      featureRanges: controller.featureRanges,
    );

class SplitBoundaryCase {
  const SplitBoundaryCase(
    this.description, {
    required this.unknownCount,
    required this.cost,
    required this.allowed,
    required this.usedAfter,
  });

  final String description;
  final int unknownCount;
  final int cost;
  final bool allowed;
  final int usedAfter;
}

const splitBoundaryCases = [
  SplitBoundaryCase(
    'italic on a 20-unknown character at 200 splits it: cost 1, blocked',
    unknownCount: 20,
    cost: 1,
    allowed: false,
    usedAfter: 200,
  ),
  SplitBoundaryCase(
    'italic on a 19-unknown character at 200 fills it to 20: cost 0, applied',
    unknownCount: 19,
    cost: 0,
    allowed: true,
    usedAfter: 200,
  ),
];

void main() {
  group('B1 formatting budget follows the serialized facet count', () {
    test('200 grouped facets exhaust the budget without exceeding it', () {
      final budget = budgetController('', boldWords: 200).formattingBudget;
      expect(budget.used, 200);
      expect(budget.remaining, 0);
      expect(budget.isExhausted, isTrue);
      expect(budget.isOverLimit, isFalse);
    });

    test('199 grouped facets leave one', () {
      final budget = budgetController('', boldWords: 199).formattingBudget;
      expect(budget.used, 199);
      expect(budget.remaining, 1);
      expect(budget.isExhausted, isFalse);
      expect(budget.isOverLimit, isFalse);
    });

    test('bold and italic over the identical range count as one facet', () {
      final controller = FacetEditingController(text: 'xy');
      toggleOver(controller, InlineFormat.bold, 0, 2);
      toggleOver(controller, InlineFormat.italic, 0, 2);
      expect(controller.formattingBudget.used, 1);
    });

    test('ranges the serializer drops count zero', () {
      // Bold over trailing whitespace is trimmed away; a quote on an empty
      // line is a block of empty lines alone. Only the italic "x" counts.
      final controller = FacetEditingController(text: 'x\n\ny   ');
      toggleOver(controller, InlineFormat.italic, 0, 1);
      toggleOver(controller, InlineFormat.bold, 4, 7);
      blockOver(controller, BlockFormat.blockquote, 2, 2);
      expect(controller.inlineRanges, hasLength(2));
      expect(controller.blockRanges, hasLength(1));
      expect(controller.formattingBudget.used, 1);
    });
  });

  group('B2 toggle cost and gating', () {
    for (final costCase in costCases) {
      test(costCase.description, () {
        final controller = costCase.build();
        expect(serializedCount(controller), costCase.usedBefore);

        var notifications = 0;
        controller.addListener(() => notifications++);
        final before = snapshot(controller);

        final (cost, allowed) = switch (costCase.toggle) {
          BlockToggle(:final format) => (
            controller.toggleBlockCost(format),
            controller.canToggleBlock(format),
          ),
          InlineToggle(:final format) => (
            controller.toggleInlineCost(format),
            controller.canToggleInline(format),
          ),
        };
        // Queries never change state or notify
        expectUnchanged(controller, before);
        expect(notifications, 0);

        expect(cost, costCase.cost);
        expect(allowed, costCase.allowed);

        switch (costCase.toggle) {
          case BlockToggle(:final format):
            controller.toggleBlock(format);
          case InlineToggle(:final format):
            controller.toggleInline(format);
        }

        if (costCase.allowed) {
          expect(notifications, greaterThan(0));
        } else {
          expectUnchanged(controller, before);
          expect(notifications, 0);
        }
        expect(controller.formattingBudget.used, costCase.usedAfter);
      });
    }
  });

  group('B3 edits are never blocked at the limit', () {
    test('an unformatted paste inside a bold range goes past 200', () {
      final controller = overLimitController();
      expect(controller.text, startsWith('boxld plain\n'));
      expect(
        controller.inlineRanges,
        containsAll(const [
          InlineRange(InlineFormat.bold, 0, 2),
          InlineRange(InlineFormat.bold, 3, 5),
        ]),
      );
      final budget = controller.formattingBudget;
      expect(budget.used, 201);
      expect(budget.isOverLimit, isTrue);
      expect(budget.remaining, 0);
      expect(budget.isExhausted, isTrue);
    });

    test('removing bold from the middle of a bold range goes past 200', () {
      final controller = budgetController(
        'bold',
        boldWords: 199,
        format: (c) => toggleOver(c, InlineFormat.bold, 0, 4),
      );
      select(controller, 1, 3);
      expect(controller.toggleInlineCost(InlineFormat.bold), 1);
      expect(controller.canToggleInline(InlineFormat.bold), isTrue);
      controller.toggleInline(InlineFormat.bold);
      expect(
        controller.inlineRanges,
        containsAll(const [
          InlineRange(InlineFormat.bold, 0, 1),
          InlineRange(InlineFormat.bold, 3, 4),
        ]),
      );
      expect(controller.formattingBudget.used, 201);
    });

    test('arming bold at a caret is free and typing then goes past 200', () {
      final controller = budgetController('plain', boldWords: 200)
        ..selection = const TextSelection.collapsed(offset: 5);
      expect(controller.toggleInlineCost(InlineFormat.bold), 0);
      expect(controller.canToggleInline(InlineFormat.bold), isTrue);
      controller.toggleInline(InlineFormat.bold);

      final text = controller.text;
      controller.value = TextEditingValue(
        text: '${text.substring(0, 5)}x${text.substring(5)}',
        selection: const TextSelection.collapsed(offset: 6),
      );
      expect(controller.text, startsWith('plainx\n'));
      expect(
        controller.inlineRanges,
        contains(const InlineRange(InlineFormat.bold, 5, 6)),
      );
      expect(controller.formattingBudget.used, 201);
    });

    test('at 200, a caret toggle during a composition costs its facet', () {
      final controller = budgetController('plain', boldWords: 200)
        ..selection = const TextSelection.collapsed(offset: 5);
      final text = controller.text;
      // An IME composes an unformatted "x" after "plain"
      controller.value = TextEditingValue(
        text: '${text.substring(0, 5)}x${text.substring(5)}',
        selection: const TextSelection.collapsed(offset: 6),
        composing: const TextRange(start: 5, end: 6),
      );
      expect(controller.formattingBudget.used, 200);

      var notifications = 0;
      controller.addListener(() => notifications++);
      final before = snapshot(controller);

      // Bold over the composed "x" would be a 201st facet
      expect(controller.toggleInlineCost(InlineFormat.bold), 1);
      expect(controller.canToggleInline(InlineFormat.bold), isFalse);
      controller.toggleInline(InlineFormat.bold);
      expectUnchanged(controller, before);
      expect(notifications, 0);
      expect(controller.formattingBudget.used, 200);
    });

    test('over the limit, additions are blocked and removals allowed', () {
      final controller = overLimitController();
      expect(controller.text, startsWith('boxld plain\n'));

      var notifications = 0;
      controller.addListener(() => notifications++);

      // Bold on the unformatted "plain"
      select(controller, 6, 11);
      notifications = 0;
      final before = snapshot(controller);
      expect(controller.toggleInlineCost(InlineFormat.bold), 1);
      expect(controller.canToggleInline(InlineFormat.bold), isFalse);
      controller.toggleInline(InlineFormat.bold);
      expectUnchanged(controller, before);
      expect(notifications, 0);

      // Removing bold from "bo"
      select(controller, 0, 2);
      expect(controller.toggleInlineCost(InlineFormat.bold), -1);
      expect(controller.canToggleInline(InlineFormat.bold), isTrue);
      controller.toggleInline(InlineFormat.bold);
      expect(
        controller.inlineRanges,
        isNot(contains(const InlineRange(InlineFormat.bold, 0, 2))),
      );
      expect(controller.formattingBudget.used, 200);
    });
  });

  group('B4 serialization at the limit', () {
    test('a blocked toggle leaves 199 facets with every range present', () {
      final controller = threePlainLinesAt199()
        ..toggleBlock(BlockFormat.heading);
      final serialized = serializeFormatting(
        controller.text,
        inlineRanges: controller.inlineRanges,
        blockRanges: controller.blockRanges,
      );
      expect(serialized.facets, hasLength(199));
      expect(controller.inlineRanges, hasLength(199));
      expect(controller.blockRanges, isEmpty);
    });

    test('200 facets serialize; 201 throw FacetLimitExceededException', () {
      final atLimit = budgetController('', boldWords: 200);
      expect(
        serializeFormatting(
          atLimit.text,
          inlineRanges: atLimit.inlineRanges,
          blockRanges: atLimit.blockRanges,
        ).facets,
        hasLength(200),
      );

      final overLimit = overLimitController();
      expect(
        () => serializeFormatting(
          overLimit.text,
          inlineRanges: overLimit.inlineRanges,
          blockRanges: overLimit.blockRanges,
        ),
        throwsA(
          isA<FacetLimitExceededException>()
              .having((e) => e.facetCount, 'facetCount', 201)
              .having((e) => e.limit, 'limit', 200),
        ),
      );
    });
  });

  group('B5 the budget counts loaded grouped facets', () {
    test('unknown features count, grouped with formatting on their range', () {
      // 'aa bb cc dd': bold and an unknown on [0,2) group into one facet.
      final controller = FacetEditingController.fromRecord('aa bb cc dd', [
        facet(0, 2, const [BoldFacetFeature()]),
        facet(3, 5, const [SpoilerFacetFeature(reason: 'r')]),
        facet(6, 8, [unknown(1)]),
        facet(0, 2, [unknown(2)]),
      ]);
      addTearDown(controller.dispose);
      expect(controller.formattingBudget.used, 3);
    });

    test('at 200 with a loaded unknown, italic on a space is blocked', () {
      final controller = loadedController(
        boldWords: 199,
        tail: [
          [unknown(1)],
        ],
      );
      expect(controller.formattingBudget.used, 200);
      select(controller, 1, 2);
      final before = snapshot(controller);
      expect(controller.canToggleInline(InlineFormat.italic), isFalse);
      controller.toggleInline(InlineFormat.italic);
      expectUnchanged(controller, before);
      expect(controller.formattingBudget.used, 200);
    });

    test('at 200 with a loaded unknown, removing bold is allowed', () {
      final controller = loadedController(
        boldWords: 199,
        tail: [
          [unknown(1)],
        ],
      );
      select(controller, 0, 1);
      expect(controller.canToggleInline(InlineFormat.bold), isTrue);
      controller.toggleInline(InlineFormat.bold);
      expect(
        controller.inlineRanges,
        isNot(contains(const InlineRange(InlineFormat.bold, 0, 1))),
      );
      expect(controller.formattingBudget.used, 199);
    });

    test('at 200 with a loaded unknown, typing edits and saves 200', () {
      final controller = loadedController(
        boldWords: 199,
        tail: [
          [unknown(1)],
        ],
      )..selection = const TextSelection.collapsed(offset: 399);
      final text = controller.text;
      controller.value = TextEditingValue(
        text: '${text}b',
        selection: const TextSelection.collapsed(offset: 400),
      );
      expect(controller.text, endsWith(' ab'));
      expect(controller.formattingBudget.used, 200);
      expect(save(controller).facets, hasLength(200));
    });

    test('200 bold and a loaded unknown are over the limit until one goes', () {
      final controller = loadedController(
        boldWords: 200,
        tail: [
          [unknown(1)],
        ],
      );
      final budget = controller.formattingBudget;
      expect(budget.used, 201);
      expect(budget.isOverLimit, isTrue);
      expect(
        () => save(controller),
        throwsA(
          isA<FacetLimitExceededException>().having(
            (e) => e.facetCount,
            'facetCount',
            201,
          ),
        ),
      );

      toggleOver(controller, InlineFormat.bold, 0, 1);
      expect(controller.formattingBudget.used, 200);
      expect(save(controller).facets, hasLength(200));
    });
  });

  group('B6 the budget counts facets split at 20 features', () {
    test('22 unknown features on one range count as 2 facets', () {
      final controller = FacetEditingController.fromRecord('word', [
        facet(0, 4, unknowns(1, 11)),
        facet(0, 4, unknowns(12, 22)),
      ]);
      addTearDown(controller.dispose);
      expect(controller.formattingBudget.used, 2);
    });

    test('197 bold and two 22-unknown ranges are 201 facets', () {
      final controller = loadedController(
        boldWords: 197,
        tail: [unknowns(1, 22), unknowns(1, 22)],
      );
      final budget = controller.formattingBudget;
      expect(budget.used, 201);
      expect(budget.isOverLimit, isTrue);
      expect(
        () => save(controller),
        throwsA(
          isA<FacetLimitExceededException>().having(
            (e) => e.facetCount,
            'facetCount',
            201,
          ),
        ),
      );
      select(controller, 1, 2);
      expect(controller.canToggleInline(InlineFormat.italic), isFalse);
    });

    test('198 bold and one 22-unknown range are exactly 200 facets', () {
      final controller = loadedController(
        boldWords: 198,
        tail: [unknowns(1, 22)],
      );
      expect(controller.formattingBudget.used, 200);
      expect(save(controller).facets, hasLength(200));
    });

    for (final boundaryCase in splitBoundaryCases) {
      test(boundaryCase.description, () {
        final controller = loadedController(
          boldWords: 199,
          tail: [unknowns(1, boundaryCase.unknownCount)],
        );
        expect(controller.formattingBudget.used, 200);
        select(controller, 398, 399);
        expect(
          controller.toggleInlineCost(InlineFormat.italic),
          boundaryCase.cost,
        );
        expect(
          controller.canToggleInline(InlineFormat.italic),
          boundaryCase.allowed,
        );
        controller.toggleInline(InlineFormat.italic);
        expect(
          controller.inlineRanges.contains(
            const InlineRange(InlineFormat.italic, 398, 399),
          ),
          boundaryCase.allowed,
        );
        expect(controller.formattingBudget.used, boundaryCase.usedAfter);
      });
    }
  });
}
