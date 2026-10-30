import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../constants/app_colors.dart';
import 'facet_editing_controller.dart';

/// Which part of a FacetTextField's block decorations a [FacetBlockPainter]
/// paints.
enum FacetBlockLayer {
  /// Behind the field: the decoration fill, then each code block's
  /// background behind its lines.
  background,

  /// In front of the field: the quote gutter bars, one per level, on the
  /// start side of each quoted line (the left in LTR, the right in RTL).
  /// They sit in the gutter, clear of the text.
  quoteBars,
}

/// Paints one [FacetBlockLayer] of a FacetTextField's block decorations.
/// Text is never indented; the field keeps a fixed start gutter of
/// [gutterWidth] whether or not a quote is present, and the bars fit in it
/// at every quote level.
///
/// Geometry comes from the field's laid-out [RenderEditable], found under
/// the render box of the widget [fieldKey] is attached to, which must be the
/// [CustomPaint] this painter paints for. The fill's rect is the
/// decorator's container, from [InputDecorator.containerOf] with the
/// field's [EditableText] element. The blocks follow the editable's text
/// direction: bars and the code background's lead-in sit on its start side.
/// The `repaint` listenable must notify whenever the text, the block ranges
/// or the scroll offset change.
/// A layout change that resizes the [CustomPaint] (such as a width change
/// that rewraps lines) repaints it through the render tree, and every
/// rebuild with a new painter repaints it ([shouldRepaint] is always true).
class FacetBlockPainter extends CustomPainter {
  FacetBlockPainter({
    required this.controller,
    required this.fieldKey,
    required this.layer,
    this.fillColor,
    this.fillBorder = InputBorder.none,
    this.textDirection = TextDirection.ltr,
    super.repaint,
  });

  final FacetEditingController controller;
  final GlobalKey fieldKey;
  final FacetBlockLayer layer;

  /// The decoration fill, painted behind the code backgrounds in the
  /// [FacetBlockLayer.background] layer; null for an unfilled field.
  final Color? fillColor;

  /// The border whose outer path shapes the fill.
  final InputBorder fillBorder;
  final TextDirection textDirection;

  /// The minimum start padding of the field's text, in logical pixels: the
  /// space the quote bars and the code background's lead-in paint in.
  static const gutterWidth = 28.0;

  static const _barWidth = 3.0;
  static const _barGap = 4.0;

  /// How far the code background reaches left of the text.
  static const _codePadding = 4.0;

  /// Space kept clear between the outermost bar and the field's start edge,
  /// so bars never cross a border drawn there.
  static const _edgeMargin = 2.0;

  /// The width left for the bars: the gutter less the edge margin, the code
  /// background's lead-in and the gap before the innermost bar.
  static const _barSpan = gutterWidth - _edgeMargin - _codePadding - _barGap;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = fieldKey.currentContext?.findRenderObject();
    if (origin is! RenderBox || !origin.attached) {
      return;
    }
    canvas
      ..save()
      ..clipRect(Offset.zero & size);
    if (layer == FacetBlockLayer.background && fillColor != null) {
      _paintFill(canvas, origin);
    }
    final editable = _findRenderEditable(origin);
    if (editable != null && editable.hasSize) {
      _paintBlocks(canvas, origin, editable);
    }
    canvas.restore();
  }

  /// Fills the decoration's container (the field less any helper or counter
  /// text below it), shaped by [fillBorder].
  void _paintFill(Canvas canvas, RenderBox origin) {
    final container = _decorationContainer(fieldKey.currentContext!);
    if (container == null || !container.hasSize || !container.attached) {
      return;
    }
    final rect = MatrixUtils.transformRect(
      container.getTransformTo(origin),
      Offset.zero & container.size,
    );
    canvas.drawPath(
      fillBorder.getOuterPath(rect, textDirection: textDirection),
      Paint()..color = fillColor!,
    );
  }

  void _paintBlocks(Canvas canvas, RenderBox origin, RenderEditable editable) {
    final text = editable.plainText;
    final format = switch (layer) {
      FacetBlockLayer.background => BlockFormat.codeBlock,
      FacetBlockLayer.quoteBars => BlockFormat.blockquote,
    };
    final visible = _visibleTextRange(editable);
    final blocks = [
      for (final block in controller.blockRanges)
        if (block.format == format &&
            block.start >= 0 &&
            block.start <= block.end &&
            block.end <= text.length &&
            block.end >= visible.start &&
            block.start <= visible.end)
          block,
    ];
    if (blocks.isEmpty) {
      return;
    }

    canvas
      ..save()
      ..transform(editable.getTransformTo(origin).storage)
      // Lines scrolled out of the field must not draw over its decoration.
      ..clipRect(
        Rect.fromLTRB(
          -gutterWidth,
          0,
          editable.size.width + gutterWidth,
          editable.size.height,
        ),
      );
    final paint = Paint()
      ..color = switch (layer) {
        FacetBlockLayer.background => AppColors.insetSurface,
        FacetBlockLayer.quoteBars => AppColors.teal.withValues(alpha: 0.6),
      };
    // Offsets below are laid out for LTR, start on the left; RTL mirrors
    // them so the blocks sit on the start side the gutter is reserved on.
    final rtl = editable.textDirection == TextDirection.rtl;
    final width = editable.size.width;
    Rect startSide(double left, double top, double right, double bottom) => rtl
        ? Rect.fromLTRB(width - right, top, width - left, bottom)
        : Rect.fromLTRB(left, top, right, bottom);
    for (final block in blocks) {
      final extent = _verticalExtent(editable, text, block);
      if (extent == null) {
        continue;
      }
      if (layer == FacetBlockLayer.background) {
        canvas.drawRect(
          startSide(-_codePadding, extent.top, width, extent.bottom),
          paint,
        );
        continue;
      }
      // Level 1 is innermost, closest to the text, and outside any code
      // background on the same lines (the quote is the outer block). Deep
      // levels shrink the bars and gaps evenly to stay in the gutter.
      final naturalSpan = block.level * _barWidth + (block.level - 1) * _barGap;
      final scale = math.min(naturalSpan, _barSpan) / naturalSpan;
      final barWidth = _barWidth * scale;
      final barGap = _barGap * scale;
      for (var level = 1; level <= block.level; level++) {
        final right =
            -(_codePadding + _barGap) - (level - 1) * (barWidth + barGap);
        canvas.drawRect(
          startSide(right - barWidth, extent.top, right, extent.bottom),
          paint,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(FacetBlockPainter oldDelegate) => true;
}

/// The text offsets of the first and last lines visible in [editable].
({int start, int end}) _visibleTextRange(RenderEditable editable) {
  final start = editable.getPositionForPoint(
    editable.localToGlobal(Offset.zero),
  );
  final end = editable.getPositionForPoint(
    editable.localToGlobal(editable.size.bottomRight(Offset.zero)),
  );
  return (start: start.offset, end: end.offset);
}

/// The container of the InputDecorator around the first [EditableText]
/// under [root], as [InputDecorator.containerOf] reports it: the area the
/// decoration fills, above any helper, error or counter text. Null when
/// there is no such field or decorator.
RenderBox? _decorationContainer(BuildContext root) {
  Element? editableText;
  void visit(Element element) {
    if (editableText != null) {
      return;
    }
    if (element.widget is EditableText) {
      editableText = element;
      return;
    }
    element.visitChildElements(visit);
  }

  root.visitChildElements(visit);
  final found = editableText;
  return found == null ? null : InputDecorator.containerOf(found);
}

/// The first [RenderEditable] under [root], depth first.
RenderEditable? _findRenderEditable(RenderObject root) {
  RenderEditable? found;
  void visit(RenderObject child) {
    if (found != null) {
      return;
    }
    if (child is RenderEditable) {
      found = child;
      return;
    }
    child.visitChildren(visit);
  }

  root.visitChildren(visit);
  return found;
}

/// The top and bottom, in [editable]'s coordinates (scroll included), of
/// the lines [block] covers: the glyph boxes of the whole block in one
/// layout query, widened by the caret rect where the first or last line is
/// empty (an empty line has no glyph box); null when the layout reports no
/// height.
({double top, double bottom})? _verticalExtent(
  RenderEditable editable,
  String text,
  BlockRange block,
) {
  var top = double.infinity;
  var bottom = double.negativeInfinity;
  void include(Rect rect) {
    top = math.min(top, rect.top);
    bottom = math.max(bottom, rect.bottom);
  }

  if (block.start < block.end) {
    for (final box in editable.getBoxesForSelection(
      TextSelection(baseOffset: block.start, extentOffset: block.end),
    )) {
      include(box.toRect());
    }
  }
  final firstLineEmpty =
      block.start == block.end ||
      block.start == text.length ||
      text[block.start] == '\n';
  final lastLineEmpty = block.start == block.end || text[block.end - 1] == '\n';
  if (firstLineEmpty) {
    include(editable.getLocalRectForCaret(TextPosition(offset: block.start)));
  }
  if (lastLineEmpty) {
    include(editable.getLocalRectForCaret(TextPosition(offset: block.end)));
  }
  return top < bottom ? (top: top, bottom: bottom) : null;
}
