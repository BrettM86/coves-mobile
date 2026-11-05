import 'dart:typed_data';

import 'package:coves_flutter/constants/app_colors.dart';
import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/widgets/composer/facet_block_painter.dart';
import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:coves_flutter/widgets/composer/facet_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

final barColor = AppColors.teal.withValues(alpha: 0.6);
const codeBackground = AppColors.insetSurface;

/// Nonzero on every side, so the editable text is offset from the field's
/// origin and a painter that skips that translation draws in the wrong place.
const contentPadding = EdgeInsets.fromLTRB(24, 16, 12, 16);

const decoration = InputDecoration(
  filled: false,
  border: InputBorder.none,
  contentPadding: contentPadding,
);

const baseStyle = TextStyle(fontSize: 20);

/// The fixture text for D2 and D3: a plain line, two formatted lines (the
/// second empty) and a plain line. Lines: [0,5], [6,12], [13,13], [14,19].
const fixtureText = 'plain\nformat\n\nplain';

/// A controller whose block ranges are the given literals, for block shapes
/// the editing API cannot produce yet (nested quote levels).
class LiteralBlocksController extends FacetEditingController {
  LiteralBlocksController({required super.text, required this.literalBlocks});

  final List<BlockRange> literalBlocks;

  @override
  List<BlockRange> get blockRanges => literalBlocks;
}

void toggleOver(
  FacetEditingController controller,
  int start,
  int end,
  BlockFormat format,
) {
  controller
    ..selection = TextSelection(baseOffset: start, extentOffset: end)
    ..toggleBlock(format);
}

final blockPaint = find.byWidgetPredicate(
  (widget) =>
      widget is CustomPaint &&
      (widget.painter is FacetBlockPainter ||
          widget.foregroundPainter is FacetBlockPainter),
);

RenderEditable renderEditable(WidgetTester tester) =>
    tester.state<EditableTextState>(find.byType(EditableText)).renderEditable;

/// The global rect of one logical line [start, end] of the field's text:
/// the union of its glyph boxes, or the caret rect for an empty line.
Rect lineRect(RenderEditable editable, int start, int end) {
  Rect local;
  if (start == end) {
    final point = editable
        .getEndpointsForSelection(TextSelection.collapsed(offset: start))
        .single
        .point;
    local = Rect.fromLTRB(
      point.dx,
      point.dy - editable.preferredLineHeight,
      point.dx + 1,
      point.dy,
    );
  } else {
    local = editable
        .getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: end),
        )
        .map((box) => box.toRect())
        .reduce((a, b) => a.expandToInclude(b));
  }
  return MatrixUtils.transformRect(editable.getTransformTo(null), local);
}

/// The global rects of the visual lines of [start, end] (one per wrapped
/// row), or the caret rect for an empty line.
List<Rect> visualLineRects(RenderEditable editable, int start, int end) {
  if (start == end) {
    return [lineRect(editable, start, end)];
  }
  final rows = <double, Rect>{};
  for (final box in editable.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: end),
  )) {
    final rect = box.toRect();
    final key = rect.top.roundToDouble();
    rows[key] = rows[key]?.expandToInclude(rect) ?? rect;
  }
  final transform = editable.getTransformTo(null);
  return [
    for (final rect in rows.values) MatrixUtils.transformRect(transform, rect),
  ];
}

/// Changes the mounted D4 fixture without remounting it.
typedef FixtureChange = void Function(
  FacetEditingController controller,
  ValueNotifier<double> width,
  WidgetTester tester,
);

/// Toggles a quote over [controller]'s selection and expects every block
/// painter's repaint listenable to notify. The pixel check alone cannot
/// catch a painter that misses block changes: the stock TextField relays
/// out its InputDecorator on every controller notification, and that
/// relayout repaints the painter too.
void toggleQuoteNotifyingPainters(
  FacetEditingController controller,
  WidgetTester tester,
) {
  final painters = [
    for (final widget in tester.widgetList<CustomPaint>(blockPaint))
      ...[
        widget.painter,
        widget.foregroundPainter,
      ].whereType<FacetBlockPainter>(),
  ];
  expect(painters, isNotEmpty);
  var notified = 0;
  void count() => notified += 1;
  for (final painter in painters) {
    painter.addListener(count);
  }
  controller.toggleBlock(BlockFormat.blockquote);
  for (final painter in painters) {
    painter.removeListener(count);
  }
  expect(
    notified,
    painters.length,
    reason: 'each block painter repaints on a block toggle',
  );
}

typedef PaintedRect = ({Rect rect, Color color});

/// Every rect the block-paint render object draws, in global coordinates,
/// with the canvas transforms in effect at the time of each draw applied.
List<PaintedRect> paintedRects(WidgetTester tester) {
  final renderObject = tester.renderObject<RenderBox>(blockPaint);
  final canvas = TestRecordingCanvas();
  renderObject.paint(TestRecordingPaintingContext(canvas), Offset.zero);
  final toGlobal = renderObject.getTransformTo(null);
  final stack = <Matrix4>[];
  var current = Matrix4.identity();
  final rects = <PaintedRect>[];
  for (final call in canvas.invocations) {
    final invocation = call.invocation;
    final arguments = invocation.positionalArguments;
    switch (invocation.memberName) {
      case #save || #saveLayer:
        stack.add(current.clone());
      case #restore:
        current = stack.removeLast();
      case #translate:
        current = current.clone()
          ..translateByDouble(
            (arguments[0] as num).toDouble(),
            (arguments[1] as num).toDouble(),
            0,
            1,
          );
      case #transform:
        current = current.multiplied(
          Matrix4.fromFloat64List(arguments[0] as Float64List),
        );
      case #drawRect:
        rects.add((
          rect: MatrixUtils.transformRect(
            toGlobal.multiplied(current),
            arguments[0] as Rect,
          ),
          color: (arguments[1] as Paint).color,
        ));
      case #drawRRect:
        rects.add((
          rect: MatrixUtils.transformRect(
            toGlobal.multiplied(current),
            (arguments[0] as RRect).outerRect,
          ),
          color: (arguments[1] as Paint).color,
        ));
    }
  }
  return rects;
}

bool sameColor(Color a, Color b) => a.toARGB32() == b.toARGB32();

/// The rects of [color] whose vertical extent crosses the middle of [line].
List<Rect> rectsBeside(List<PaintedRect> rects, Color color, Rect line) => [
  for (final painted in rects)
    if (sameColor(painted.color, color) &&
        painted.rect.top < line.center.dy &&
        painted.rect.bottom > line.center.dy)
      painted.rect,
];

Future<void> pumpField(
  WidgetTester tester,
  FacetEditingController controller,
) async {
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: FacetTextField(
          controller: controller,
          decoration: decoration,
          style: baseStyle,
        ),
      ),
    ),
  );
}

/// Pixels of the frame last rendered into [boundary], as read back from its
/// layer (no extra paint is forced).
Future<({ByteData bytes, int width})> renderedPixels(
  WidgetTester tester,
  RenderRepaintBoundary boundary,
) async {
  final result = await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData();
    final width = image.width;
    image.dispose();
    return (bytes: bytes!, width: width);
  });
  return result!;
}

/// The color of the pixel at global [point] in [pixels], read back from
/// [boundary].
Color pixelAt(
  ({ByteData bytes, int width}) pixels,
  RenderRepaintBoundary boundary,
  Offset point,
) {
  final local = boundary.globalToLocal(point);
  final index = (local.dy.floor() * pixels.width + local.dx.floor()) * 4;
  return Color.fromARGB(
    pixels.bytes.getUint8(index + 3),
    pixels.bytes.getUint8(index),
    pixels.bytes.getUint8(index + 1),
    pixels.bytes.getUint8(index + 2),
  );
}

/// Whether [pixel] matches [expected] within [pixelTolerance] per channel.
bool nearColor(Color pixel, Color expected) {
  int channel(double value) => (value * 255).round();
  return (channel(pixel.r) - channel(expected.r)).abs() <= pixelTolerance &&
      (channel(pixel.g) - channel(expected.g)).abs() <= pixelTolerance &&
      (channel(pixel.b) - channel(expected.b)).abs() <= pixelTolerance;
}

/// Pumps [field] inside a repaint boundary over [AppColors.background],
/// [left] pixels from the boundary's left edge, and returns the boundary.
Future<RenderRepaintBoundary> pumpInBoundary(
  WidgetTester tester,
  Widget field, {
  double left = 0,
}) async {
  final boundaryKey = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: boundaryKey,
            child: ColoredBox(
              color: AppColors.background,
              child: Padding(
                padding: EdgeInsets.only(left: left),
                child: SizedBox(width: 400, child: field),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return boundaryKey.currentContext!.findRenderObject()!
      as RenderRepaintBoundary;
}

/// AppColors.teal (99, 181, 177) at alpha 0.6 over AppColors.background
/// (11, 15, 20): 0.6 * teal + 0.4 * background, rounded.
const blendedBar = (red: 64, green: 115, blue: 114);
const pixelTolerance = 3;

void main() {
  testWidgets('D2 quote bars: one per level beside each quoted line', (
    tester,
  ) async {
    final rows = [
      (
        name: 'level 1',
        bars: 1,
        controller: () {
          final controller = FacetEditingController(text: fixtureText);
          toggleOver(controller, 6, 14, BlockFormat.blockquote);
          expect(controller.blockRanges.toSet(), {
            const BlockRange(BlockFormat.blockquote, 6, 13),
          });
          return controller;
        },
      ),
      (
        name: 'level 2',
        bars: 2,
        controller: () => LiteralBlocksController(
          text: fixtureText,
          literalBlocks: const [
            BlockRange(BlockFormat.blockquote, 6, 13, level: 2),
          ],
        ),
      ),
    ];
    for (final row in rows) {
      await pumpField(tester, row.controller());
      final editable = renderEditable(tester);
      final rects = paintedRects(tester);
      final plainLeft = lineRect(editable, 0, 5).left;

      for (final (start, end) in const [(6, 12), (13, 13)]) {
        final line = lineRect(editable, start, end);
        final reason = '${row.name} line [$start,$end]';
        final bars = rectsBeside(rects, barColor, line);
        expect(bars, hasLength(row.bars), reason: reason);
        expect(
          bars.map((bar) => bar.left.roundToDouble()).toSet(),
          hasLength(row.bars),
          reason: '$reason: one bar per level, side by side',
        );
        for (final bar in bars) {
          expect(bar.width, closeTo(3, 0.01), reason: reason);
          expect(bar.top, lessThanOrEqualTo(line.top + 0.5), reason: reason);
          expect(
            bar.bottom,
            greaterThanOrEqualTo(line.bottom - 0.5),
            reason: reason,
          );
          expect(
            bar.right,
            lessThanOrEqualTo(line.left + 0.01),
            reason: reason,
          );
        }
      }
      expect(
        lineRect(editable, 6, 12).left,
        closeTo(plainLeft, 0.5),
        reason: '${row.name}: quoted text is not indented',
      );
      for (final (start, end) in const [(0, 5), (14, 19)]) {
        expect(
          rectsBeside(rects, barColor, lineRect(editable, start, end)),
          isEmpty,
          reason: '${row.name} plain line [$start,$end]',
        );
      }
    }
  });

  testWidgets('D2 deep quotes keep every bar inside the field', (tester) async {
    const fieldLeft = 40.0;
    for (final level in const [3, 6]) {
      final controller = LiteralBlocksController(
        text: fixtureText,
        literalBlocks: [
          BlockRange(BlockFormat.blockquote, 6, 13, level: level),
        ],
      );
      addTearDown(controller.dispose);
      final boundary = await pumpInBoundary(
        tester,
        FacetTextField(controller: controller, style: baseStyle),
        left: fieldLeft,
      );
      final field = tester.getRect(find.byType(FacetTextField));
      expect(field.left, fieldLeft);
      final editable = renderEditable(tester);
      final line = lineRect(editable, 6, 12);
      final reason = 'level $level';

      final bars = rectsBeside(paintedRects(tester), barColor, line)
        ..sort((a, b) => a.left.compareTo(b.left));
      expect(bars, hasLength(level), reason: reason);
      for (var index = 0; index < bars.length; index++) {
        expect(
          bars[index].left,
          greaterThanOrEqualTo(field.left),
          reason: reason,
        );
        expect(bars[index].right, lessThanOrEqualTo(line.left), reason: reason);
        if (index > 0) {
          expect(
            bars[index].left,
            greaterThan(bars[index - 1].right),
            reason: '$reason: bars do not overlap',
          );
        }
      }

      final pixels = await renderedPixels(tester, boundary);
      for (final (start, end) in const [(6, 12), (13, 13)]) {
        final y = lineRect(editable, start, end).center.dy;
        for (var x = 0.5; x < field.left; x += 1) {
          final pixel = pixelAt(pixels, boundary, Offset(x, y));
          expect(
            nearColor(pixel, AppColors.background),
            isTrue,
            reason:
                '$reason line [$start,$end]: nothing paints at x $x, '
                'left of the field, found $pixel',
          );
        }
      }
      if (level == 3) {
        final blended = Color.alphaBlend(barColor, AppColors.background);
        var runs = 0;
        var inRun = false;
        for (var x = field.left + 0.5; x < line.left; x += 1) {
          final isBar = nearColor(
            pixelAt(pixels, boundary, Offset(x, line.center.dy)),
            blended,
          );
          if (isBar && !inRun) {
            runs += 1;
          }
          inRun = isBar;
        }
        expect(runs, 3, reason: '$reason: three bars render in the gutter');
      }
    }
  });

  testWidgets(
    'D3 an opaque filled decoration shows code backgrounds and quote bars',
    (tester) async {
      final controller = FacetEditingController(text: fixtureText);
      addTearDown(controller.dispose);
      toggleOver(controller, 6, 14, BlockFormat.codeBlock);
      toggleOver(controller, 6, 14, BlockFormat.blockquote);
      final boundary = await pumpInBoundary(
        tester,
        FacetTextField(
          controller: controller,
          style: baseStyle,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.backgroundTertiary,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.all(16),
          ),
        ),
      );
      final editable = renderEditable(tester);
      final pixels = await renderedPixels(tester, boundary);
      final field = tester.getRect(find.byType(FacetTextField));
      final barOverFill = Color.alphaBlend(
        barColor,
        AppColors.backgroundTertiary,
      );

      for (final (start, end) in const [(6, 12), (13, 13)]) {
        final line = lineRect(editable, start, end);
        final reason = 'code line [$start,$end]';
        final background = pixelAt(
          pixels,
          boundary,
          Offset(line.right + 20, line.center.dy),
        );
        expect(
          nearColor(background, codeBackground),
          isTrue,
          reason: '$reason: code background visible, found $background',
        );
        final bar = pixelAt(
          pixels,
          boundary,
          Offset(line.left - 9.5, line.center.dy),
        );
        expect(
          nearColor(bar, barOverFill),
          isTrue,
          reason: '$reason: quote bar visible over the fill, found $bar',
        );
      }
      final plain = lineRect(editable, 0, 5);
      final fill = pixelAt(
        pixels,
        boundary,
        Offset(plain.left - 9.5, plain.center.dy),
      );
      expect(
        nearColor(fill, AppColors.backgroundTertiary),
        isTrue,
        reason: 'the decoration fill paints beside a plain line, found $fill',
      );
      final corner = pixelAt(
        pixels,
        boundary,
        field.topLeft + const Offset(1, 1),
      );
      expect(
        nearColor(corner, AppColors.background),
        isTrue,
        reason: 'the fill follows the rounded border, found $corner',
      );
    },
  );

  testWidgets('D3 code-block background and monospace code text', (
    tester,
  ) async {
    final rows = [
      (name: 'code', quoted: false),
      (name: 'quote and code on the same lines', quoted: true),
    ];
    for (final row in rows) {
      final controller = FacetEditingController(text: fixtureText);
      toggleOver(controller, 6, 14, BlockFormat.codeBlock);
      if (row.quoted) {
        toggleOver(controller, 6, 14, BlockFormat.blockquote);
      }
      expect(controller.blockRanges.toSet(), {
        const BlockRange(BlockFormat.codeBlock, 6, 13),
        if (row.quoted) const BlockRange(BlockFormat.blockquote, 6, 13),
      }, reason: row.name);
      await pumpField(tester, controller);
      final editable = renderEditable(tester);
      final rects = paintedRects(tester);

      final backgrounds = <Rect>[];
      for (final (start, end) in const [(6, 12), (13, 13)]) {
        final line = lineRect(editable, start, end);
        final reason = '${row.name} line [$start,$end]';
        final covering = rectsBeside(rects, codeBackground, line).where(
          (rect) =>
              rect.left <= line.left + 0.5 &&
              rect.right >= line.right - 0.5 &&
              rect.top <= line.top + 0.5 &&
              rect.bottom >= line.bottom - 0.5,
        );
        expect(covering, isNotEmpty, reason: reason);
        backgrounds.addAll(covering);
      }
      for (final offset in const [6, 7, 8, 9, 10, 11]) {
        expect(
          styleAt(editable.text!, offset)?.fontFamily,
          'monospace',
          reason: '${row.name} offset $offset',
        );
      }
      if (row.quoted) {
        final bars = [
          for (final (start, end) in const [(6, 12), (13, 13)])
            ...rectsBeside(rects, barColor, lineRect(editable, start, end)),
        ];
        expect(bars, isNotEmpty, reason: row.name);
        final backgroundLeft = backgrounds
            .map((rect) => rect.left)
            .reduce((a, b) => a < b ? a : b);
        for (final bar in bars) {
          expect(
            bar.right,
            lessThanOrEqualTo(backgroundLeft + 0.01),
            reason: '${row.name}: the quote is outside the code block',
          );
        }
      }
    }
  });

  testWidgets(
    'D4 the rendered frame keeps quote bars beside the quoted line as it moves',
    (tester) async {
      final rows =
          <
            ({
              String name,
              String text,
              (int, int) quote,
              bool quotedAtStart,
              bool lineMoves,
              int? maxLines,
              FixtureChange change,
            })
          >[
            (
              name: 'line inserted above',
              text: 'plain\nquoted',
              quote: (6, 12),
              quotedAtStart: true,
              lineMoves: true,
              maxLines: null,
              change:
                  (
                    FacetEditingController controller,
                    ValueNotifier<double> width,
                    WidgetTester tester,
                  ) {
                    controller.value = const TextEditingValue(
                      text: 'new\nplain\nquoted',
                      selection: TextSelection.collapsed(offset: 4),
                    );
                    expect(controller.blockRanges.toSet(), {
                      const BlockRange(BlockFormat.blockquote, 10, 16),
                    });
                  },
            ),
            (
              name: 'width shrinks so the quoted line wraps',
              text: 'qqqq qqqq qqqq\nplain',
              quote: (0, 14),
              quotedAtStart: true,
              lineMoves: true,
              maxLines: null,
              change:
                  (
                    FacetEditingController controller,
                    ValueNotifier<double> width,
                    WidgetTester tester,
                  ) {
                    width.value = 220;
                  },
            ),
            (
              name: 'bounded field scrolls',
              text: 'l0\nl1\nq2\nl3\nl4',
              quote: (6, 8),
              quotedAtStart: true,
              lineMoves: true,
              maxLines: 3,
              change:
                  (
                    FacetEditingController controller,
                    ValueNotifier<double> width,
                    WidgetTester tester,
                  ) {
                    final editable = renderEditable(tester);
                    final lineStep =
                        lineRect(editable, 3, 5).top -
                        lineRect(editable, 0, 2).top;
                    tester
                        .state<ScrollableState>(
                          find.descendant(
                            of: find.byType(FacetTextField),
                            matching: find.byType(Scrollable),
                          ),
                        )
                        .position
                        .jumpTo(lineStep);
                  },
            ),
            (
              name: 'quote toggled on, text unchanged',
              text: 'plain\nquoted\nplain',
              quote: (6, 12),
              quotedAtStart: false,
              lineMoves: false,
              maxLines: null,
              change:
                  (
                    FacetEditingController controller,
                    ValueNotifier<double> width,
                    WidgetTester tester,
                  ) {
                    toggleQuoteNotifyingPainters(controller, tester);
                    expect(controller.text, 'plain\nquoted\nplain');
                    expect(controller.blockRanges.toSet(), {
                      const BlockRange(BlockFormat.blockquote, 6, 12),
                    });
                  },
            ),
            (
              name: 'quote toggled off, text unchanged',
              text: 'plain\nquoted\nplain',
              quote: (6, 12),
              quotedAtStart: true,
              lineMoves: false,
              maxLines: null,
              change:
                  (
                    FacetEditingController controller,
                    ValueNotifier<double> width,
                    WidgetTester tester,
                  ) {
                    toggleQuoteNotifyingPainters(controller, tester);
                    expect(controller.text, 'plain\nquoted\nplain');
                    expect(controller.blockRanges, isEmpty);
                  },
            ),
          ];

      for (final row in rows) {
        final controller = FacetEditingController(text: row.text);
        addTearDown(controller.dispose);
        if (row.quotedAtStart) {
          toggleOver(
            controller,
            row.quote.$1,
            row.quote.$2,
            BlockFormat.blockquote,
          );
        } else {
          // The selection the change toggles over, set before the first
          // frame so the change itself only toggles the block.
          controller.selection = TextSelection(
            baseOffset: row.quote.$1,
            extentOffset: row.quote.$2,
          );
        }
        expect(controller.blockRanges.toSet(), {
          if (row.quotedAtStart)
            BlockRange(BlockFormat.blockquote, row.quote.$1, row.quote.$2),
        }, reason: row.name);
        final width = ValueNotifier<double>(400);
        addTearDown(width.dispose);
        final boundaryKey = GlobalKey();

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: RepaintBoundary(
                  key: boundaryKey,
                  child: ColoredBox(
                    color: AppColors.background,
                    child: ValueListenableBuilder<double>(
                      valueListenable: width,
                      builder: (context, value, _) => SizedBox(
                        width: value,
                        child: FacetTextField(
                          controller: controller,
                          decoration: decoration,
                          style: baseStyle,
                          maxLines: row.maxLines,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final editable = renderEditable(tester);
        final quotedBefore = visualLineRects(
          editable,
          row.quote.$1,
          row.quote.$2,
        );
        await expectBarsBesideQuotedLinesOnly(
          tester,
          boundary,
          '${row.name} (before)',
        );

        row.change(controller, width, tester);
        await tester.pump();

        if (row.lineMoves) {
          final quoted = controller.blockRanges.single;
          final quotedAfter = visualLineRects(
            editable,
            quoted.start,
            quoted.end,
          );
          expect(
            quotedAfter.length != quotedBefore.length ||
                (quotedAfter.first.top - quotedBefore.first.top).abs() > 1,
            isTrue,
            reason: '${row.name}: the quoted line moved or wrapped',
          );
        }
        await expectBarsBesideQuotedLinesOnly(tester, boundary, row.name);
      }
    },
  );

  testWidgets(
    'D3 the fill covers exactly the decoration container, not an icon '
    'CustomPaint or the helper and counter rows',
    (tester) async {
      final controller = FacetEditingController(text: 'plain');
      addTearDown(controller.dispose);
      final boundary = await pumpInBoundary(
        tester,
        FacetTextField(
          controller: controller,
          style: baseStyle,
          maxLines: 3,
          decoration: const InputDecoration(
            filled: true,
            fillColor: AppColors.backgroundTertiary,
            border: InputBorder.none,
            contentPadding: EdgeInsets.all(16),
            icon: SizedBox.square(
              dimension: 24,
              child: CustomPaint(foregroundPainter: MarkerPainter()),
            ),
            helperText: 'Helper',
            counterText: '0/10',
          ),
        ),
      );
      final container = InputDecorator.containerOf(
        tester.element(find.byType(EditableText)),
      )!;
      final containerRect = MatrixUtils.transformRect(
        container.getTransformTo(null),
        Offset.zero & container.size,
      );
      final field = tester.getRect(find.byType(FacetTextField));
      expect(
        containerRect.bottom,
        lessThan(field.bottom - 8),
        reason: 'the helper and counter rows sit below the container',
      );
      final pixels = await renderedPixels(tester, boundary);
      Color at(Offset point) => pixelAt(pixels, boundary, point);
      final inside = [
        containerRect.topLeft + const Offset(1, 1),
        containerRect.topRight + const Offset(-1, 1),
        containerRect.bottomLeft + const Offset(1, -1),
        containerRect.bottomRight + const Offset(-1, -1),
        containerRect.center + Offset(containerRect.width / 4, 0),
      ];
      for (final point in inside) {
        expect(
          nearColor(at(point), AppColors.backgroundTertiary),
          isTrue,
          reason: 'fill inside the container at $point, found ${at(point)}',
        );
      }
      final outside = [
        Offset(containerRect.center.dx, containerRect.bottom + 2),
        Offset(containerRect.center.dx, field.bottom - 1),
        Offset(containerRect.left - 2, containerRect.center.dy),
      ];
      for (final point in outside) {
        expect(
          nearColor(at(point), AppColors.background),
          isTrue,
          reason: 'no fill outside the container at $point, found ${at(point)}',
        );
      }
    },
  );

  testWidgets('D2 RTL with zero content padding draws bars in the reserved '
      'start gutter, inside the field', (tester) async {
    final controller = FacetEditingController(text: fixtureText);
    addTearDown(controller.dispose);
    toggleOver(controller, 6, 14, BlockFormat.blockquote);
    final boundary = await pumpInBoundary(
      tester,
      Directionality(
        textDirection: TextDirection.rtl,
        child: FacetTextField(
          controller: controller,
          style: baseStyle,
          decoration: const InputDecoration(
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
      left: 40,
    );
    final field = tester.getRect(find.byType(FacetTextField));
    final editable = renderEditable(tester);
    final editableRect = MatrixUtils.transformRect(
      editable.getTransformTo(null),
      Offset.zero & editable.size,
    );
    expect(
      field.right - editableRect.right,
      greaterThanOrEqualTo(FacetBlockPainter.gutterWidth),
      reason: 'the gutter is reserved on the start (right) side',
    );
    final pixels = await renderedPixels(tester, boundary);
    final blended = Color.alphaBlend(barColor, AppColors.background);
    for (final (start, end) in const [(6, 12), (13, 13)]) {
      final line = lineRect(editable, start, end);
      final reason = 'line [$start,$end]';
      final bars = rectsBeside(paintedRects(tester), barColor, line);
      expect(bars, hasLength(1), reason: reason);
      expect(bars.single.left, greaterThanOrEqualTo(editableRect.right));
      expect(bars.single.right, lessThanOrEqualTo(field.right), reason: reason);
      var barPixels = 0;
      for (var x = editableRect.right + 0.5; x < field.right; x += 1) {
        if (nearColor(
          pixelAt(pixels, boundary, Offset(x, line.center.dy)),
          blended,
        )) {
          barPixels += 1;
        }
      }
      expect(barPixels, 3, reason: '$reason: the bar renders in the gutter');
      for (var x = field.left + 0.5; x < editableRect.left; x += 1) {
        expect(
          nearColor(
            pixelAt(pixels, boundary, Offset(x, line.center.dy)),
            AppColors.background,
          ),
          isTrue,
          reason: '$reason: nothing paints on the end (left) side at $x',
        );
      }
    }
  });
}

/// A childless foreground [CustomPaint] painter, like the decorator's own
/// container, for a decoration slot.
class MarkerPainter extends CustomPainter {
  const MarkerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.teal);
  }

  @override
  bool shouldRepaint(MarkerPainter oldDelegate) => false;
}

/// Reads the frame last rendered into [boundary] and checks every visible
/// visual line of the field: the gutter left of its text shows the blended
/// bar color if and only if the line is quoted.
Future<void> expectBarsBesideQuotedLinesOnly(
  WidgetTester tester,
  RenderRepaintBoundary boundary,
  String name,
) async {
  final editable = renderEditable(tester);
  final controller =
      tester.widget<EditableText>(find.byType(EditableText)).controller
          as FacetEditingController;
  final quotes = controller.blockRanges
      .where((range) => range.format == BlockFormat.blockquote)
      .toList();
  final pixels = await renderedPixels(tester, boundary);
  final visible = MatrixUtils.transformRect(
    editable.getTransformTo(null),
    Offset.zero & editable.size,
  );

  bool barPixelInRow(int y, int beforeX) {
    for (var x = 0; x < beforeX; x++) {
      final index = (y * pixels.width + x) * 4;
      if ((pixels.bytes.getUint8(index) - blendedBar.red).abs() <=
              pixelTolerance &&
          (pixels.bytes.getUint8(index + 1) - blendedBar.green).abs() <=
              pixelTolerance &&
          (pixels.bytes.getUint8(index + 2) - blendedBar.blue).abs() <=
              pixelTolerance) {
        return true;
      }
    }
    return false;
  }

  final text = controller.text;
  var start = 0;
  var checked = 0;
  for (final line in text.split('\n')) {
    final end = start + line.length;
    final quoted = quotes.any(
      (range) => range.start <= start && end <= range.end,
    );
    for (final rect in visualLineRects(editable, start, end)) {
      if (rect.center.dy <= visible.top || rect.center.dy >= visible.bottom) {
        continue;
      }
      final local = MatrixUtils.transformRect(
        boundary.getTransformTo(null)..invert(),
        rect,
      );
      final y = local.center.dy.floor();
      final beforeX = local.left.floor();
      expect(
        barPixelInRow(y, beforeX),
        quoted,
        reason:
            '$name: line [$start,$end] at y $y '
            '${quoted ? 'shows' : 'does not show'} a bar left of x $beforeX',
      );
      checked += 1;
    }
    start = end + 1;
  }
  expect(checked, greaterThan(1), reason: '$name: visible lines checked');
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
