import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'facet_block_painter.dart';
import 'facet_editing_controller.dart';

/// A text field that edits a [FacetEditingController].
///
/// The [decoration] must not have a prefix, prefixText or prefixIcon: the
/// block painter draws quote bars in the start content padding, where the
/// decorator would put them, so they would overlap. Debug builds assert this.
///
/// Quote bars paint before the text without moving it, in the start content
/// padding plus [outerStartMargin]. Only when that room is less than a bar
/// needs does the field raise its start padding while a quote is present.
class FacetTextField extends StatefulWidget {
  const FacetTextField({
    super.key,
    required this.controller,
    this.focusNode,
    this.decoration,
    this.style,
    this.minLines,
    this.maxLines,
    this.maxLength,
    this.autocorrect = true,
    this.spellCheckConfiguration,
    this.textCapitalization = TextCapitalization.none,
    this.autofocus = false,
    this.outerStartMargin = 0,
  });

  final FacetEditingController controller;
  final FocusNode? focusNode;
  final InputDecoration? decoration;
  final TextStyle? style;
  final int? minLines;
  final int? maxLines;

  /// The most characters (grapheme clusters) the field holds, for typing and
  /// for pastes; null for no limit.
  final int? maxLength;
  final bool autocorrect;
  final SpellCheckConfiguration? spellCheckConfiguration;
  final TextCapitalization textCapitalization;
  final bool autofocus;

  /// Empty space outside the field on its start side, such as a screen's
  /// padding, that the quote bars and code background may paint into.
  final double outerStartMargin;

  @override
  State<FacetTextField> createState() => _FacetTextFieldState();
}

class _FacetTextFieldState extends State<FacetTextField>
    with WidgetsBindingObserver {
  /// Keys the block painter's [CustomPaint], whose render box is the origin
  /// the painter measures the field's lines from.
  final _paintKey = GlobalKey();

  /// The field's own scroll controller, so the block painter repaints when
  /// a bounded field scrolls.
  final _scrollController = ScrollController();

  /// The focus node the field creates when none is supplied. It lives until
  /// [dispose], so a widget that switches to a supplied node and back reuses
  /// it, and EditableText never detaches from a disposed node.
  FocusNode? _ownFocusNode;

  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownFocusNode ??= FocusNode());

  /// The selection controls, kept across rebuilds: EditableText disposes and
  /// recreates its selection overlay whenever it gets a different controls
  /// object, which ends a handle drag in progress. Rebuilt only when the
  /// platform changes.
  _UnformattedPasteSelectionControls? _selectionControls;

  _UnformattedPasteSelectionControls _selectionControlsFor(
    TargetPlatform platform,
  ) {
    final stock = _stockSelectionControls(platform);
    final cached = _selectionControls;
    if (cached != null && identical(cached.stock, stock)) {
      return cached;
    }
    return _selectionControls = _UnformattedPasteSelectionControls(
      stock: stock,
      paste: (editable) => _pasteUnformatted(editable, hideToolbar: true),
    );
  }

  /// The view the field is in, cached for [didChangeMetrics].
  ui.FlutterView? _view;

  /// The view's bottom inset when metrics last changed, so closing the soft
  /// keyboard (the inset dropping to zero) can be told apart from a
  /// hardware keyboard, which never raises it.
  double? _bottomInset;

  /// The least start room (padding plus [FacetTextField.outerStartMargin])
  /// the block decorations need right now; the field rebuilds only when it
  /// changes, not on every edit.
  late double _requiredStartRoom;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requiredStartRoom = _startRoomFor(widget.controller);
    widget.controller.addListener(_updateRequiredStartRoom);
  }

  @override
  void didUpdateWidget(FacetTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_updateRequiredStartRoom);
      widget.controller.addListener(_updateRequiredStartRoom);
      _requiredStartRoom = _startRoomFor(widget.controller);
    }
  }

  /// The start room [controller]'s blocks need: room for the deepest quote's
  /// bars while any quote is present, the code background's lead-in while
  /// only code blocks are, and none otherwise.
  static double _startRoomFor(FacetEditingController controller) {
    var deepestQuote = 0;
    var hasCode = false;
    for (final block in controller.blockRanges) {
      switch (block.format) {
        case BlockFormat.blockquote:
          deepestQuote = math.max(deepestQuote, block.level);
        case BlockFormat.codeBlock:
          hasCode = true;
        case BlockFormat.heading:
          break;
      }
    }
    if (deepestQuote > 0) {
      return FacetBlockPainter.quoteRoomFor(deepestQuote);
    }
    return hasCode ? FacetBlockPainter.codePadding : 0;
  }

  void _updateRequiredStartRoom() {
    final room = _startRoomFor(widget.controller);
    if (room != _requiredStartRoom) {
      setState(() => _requiredStartRoom = room);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final view = View.of(context);
    _view = view;
    _bottomInset ??= view.viewInsets.bottom;
  }

  /// Unfocuses the field when the soft keyboard closes while the app is in
  /// the foreground, so the system back gesture that dismissed the keyboard
  /// also ends editing. An inset drop while the app is not resumed (the
  /// system hiding the keyboard as the app leaves the foreground) keeps the
  /// focus, but still updates the remembered inset. A null lifecycle state
  /// counts as resumed.
  @override
  void didChangeMetrics() {
    final view = _view;
    if (!mounted || view == null) {
      return;
    }
    final bottomInset = view.viewInsets.bottom;
    final keyboardClosed = (_bottomInset ?? 0) > 0 && bottomInset == 0;
    _bottomInset = bottomInset;
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    final resumed =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    if (keyboardClosed && resumed && _focusNode.hasFocus) {
      _focusNode.unfocus();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_updateRequiredStartRoom);
    _ownFocusNode?.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Pastes the clipboard's plain text into [editable] as unformatted text,
  /// so it takes no inline format from the text around it, then brings the
  /// caret into view once the pasted text is laid out. Every paste route
  /// (keyboard shortcut, context menu, accessibility action) goes through
  /// here.
  Future<void> _pasteUnformatted(
    TextSelectionDelegate editable, {
    required bool hideToolbar,
  }) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    var text = data?.text;
    if (!mounted || text == null || text.isEmpty) {
      return;
    }
    final maxLength = widget.maxLength;
    if (maxLength != null) {
      // The paste replaces the selection, so only the text outside it counts
      final controller = widget.controller;
      final selection = controller.selection;
      final kept = selection.isValid
          ? selection.textBefore(controller.text) +
                selection.textAfter(controller.text)
          : controller.text;
      final room = math.max(0, maxLength - kept.characters.length);
      text = text.characters.take(room).toString();
      if (text.isEmpty) {
        return;
      }
    }
    widget.controller.pasteUnformatted(text);
    if (hideToolbar) {
      editable.hideToolbar();
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        editable.bringIntoView(widget.controller.selection.extent);
      }
    }, debugLabel: 'FacetTextField.bringCaretIntoView');
  }

  /// The stock context menu with its Paste item replaced by an unformatted
  /// paste; the other items stay stock.
  Widget _buildContextMenu(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    final buttonItems = [
      for (final item in editableTextState.contextMenuButtonItems)
        if (item.type == ContextMenuButtonType.paste)
          item.copyWith(
            onPressed: () =>
                _pasteUnformatted(editableTextState, hideToolbar: true),
          )
        else
          item,
    ];
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: buttonItems,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textDirection = Directionality.of(context);
    final decoration = (widget.decoration ?? const InputDecoration())
        .applyDefaults(theme.inputDecorationTheme);
    assert(
      decoration.prefix == null &&
          decoration.prefixText == null &&
          decoration.prefixIcon == null,
      'FacetTextField does not support a decoration prefix, prefixText or '
      'prefixIcon: they would overlap the quote bars in the start padding.',
    );
    final repaint = Listenable.merge([widget.controller, _scrollController]);
    final contentPadding = _contentPadding(
      decoration,
      theme,
      textDirection,
      math.max(0, _requiredStartRoom - widget.outerStartMargin),
    );
    final startRoom = contentPadding.start + widget.outerStartMargin;
    return Actions(
      actions: {PasteTextIntent: _UnformattedPasteAction(this)},
      child: CustomPaint(
        key: _paintKey,
        painter: FacetBlockPainter(
          controller: widget.controller,
          fieldKey: _paintKey,
          layer: FacetBlockLayer.background,
          fillColor: _fillColor(decoration, theme),
          fillBorder:
              decoration.enabledBorder ??
              decoration.border ??
              const UnderlineInputBorder(),
          textDirection: textDirection,
          startRoom: startRoom,
          repaint: repaint,
        ),
        foregroundPainter: FacetBlockPainter(
          controller: widget.controller,
          fieldKey: _paintKey,
          layer: FacetBlockLayer.quoteBars,
          startRoom: startRoom,
          repaint: repaint,
        ),
        child: TextField(
          controller: widget.controller,
          scrollController: _scrollController,
          focusNode: _focusNode,
          // Flutter's default `max` width (on every non-web platform)
          // highlights every selected line to the widest line's edge.
          selectionWidthStyle: ui.BoxWidthStyle.tight,
          // The block painter paints the fill, below the code backgrounds;
          // the decorator's own fill would cover them.
          decoration: decoration.copyWith(
            filled: false,
            contentPadding: contentPadding,
          ),
          style: widget.style,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          maxLength: widget.maxLength,
          autocorrect: widget.autocorrect,
          spellCheckConfiguration: widget.spellCheckConfiguration,
          textCapitalization: widget.textCapitalization,
          autofocus: widget.autofocus,
          contextMenuBuilder: _buildContextMenu,
          selectionControls: _selectionControlsFor(theme.platform),
        ),
      ),
    );
  }
}

/// Overrides [EditableText]'s keyboard paste with an unformatted paste into
/// the [EditableTextState] the shortcut was invoked from.
class _UnformattedPasteAction extends ContextAction<PasteTextIntent> {
  _UnformattedPasteAction(this.field);

  final _FacetTextFieldState field;

  @override
  Object? invoke(PasteTextIntent intent, [BuildContext? context]) {
    final editable = context?.findAncestorStateOfType<EditableTextState>();
    if (editable == null || !editable.widget.selectionEnabled) {
      return null;
    }
    return field._pasteUnformatted(editable, hideToolbar: false);
  }
}

/// The stock handle controls TextField picks for [platform].
TextSelectionControls _stockSelectionControls(TargetPlatform platform) {
  return switch (platform) {
    TargetPlatform.iOS => cupertinoTextSelectionHandleControls,
    TargetPlatform.macOS => cupertinoDesktopTextSelectionHandleControls,
    TargetPlatform.android ||
    TargetPlatform.fuchsia => materialTextSelectionHandleControls,
    TargetPlatform.linux ||
    TargetPlatform.windows => desktopTextSelectionHandleControls,
  };
}

/// The platform's stock selection handles, with the accessibility paste
/// action routed to an unformatted paste.
///
/// EditableText's semantics paste awaits [handlePaste] and then runs its own
/// stock paste (Flutter 3.47.2, `EditableTextState._semanticsOnPaste`).
/// [handlePaste] does the unformatted paste and then never completes, so the
/// stock paste never runs; nothing else awaits it, so the suspended callback
/// is simply collected.
class _UnformattedPasteSelectionControls extends TextSelectionControls
    with TextSelectionHandleControls {
  _UnformattedPasteSelectionControls({
    required this.stock,
    required this.paste,
  });

  final TextSelectionControls stock;
  final Future<void> Function(TextSelectionDelegate editable) paste;

  @override
  Widget buildHandle(
    BuildContext context,
    TextSelectionHandleType type,
    double textLineHeight, [
    VoidCallback? onTap,
  ]) => stock.buildHandle(context, type, textLineHeight, onTap);

  @override
  Offset getHandleAnchor(TextSelectionHandleType type, double textLineHeight) =>
      stock.getHandleAnchor(type, textLineHeight);

  @override
  Size getHandleSize(double textLineHeight) =>
      stock.getHandleSize(textLineHeight);

  @override
  Future<void> handlePaste(TextSelectionDelegate delegate) async {
    await paste(delegate);
    await Completer<void>().future;
  }
}

/// The fill [decoration] asks for, as the InputDecorator would resolve it
/// (hover and focus tints aside); null when it is not filled.
Color? _fillColor(InputDecoration decoration, ThemeData theme) {
  if (decoration.filled != true) {
    return null;
  }
  final states = {if (!decoration.enabled) WidgetState.disabled};
  final fillColor = decoration.fillColor;
  if (fillColor != null) {
    return WidgetStateProperty.resolveAs(fillColor, states);
  }
  return decoration.enabled
      ? theme.colorScheme.surfaceContainerHighest
      : theme.colorScheme.onSurface.withValues(alpha: 0.04);
}

/// [decoration]'s content padding, or the InputDecorator's Material 3
/// default for it when it has none, with the start raised to [minimumStart]
/// so the quote bars and code background fit beside the text.
EdgeInsetsDirectional _contentPadding(
  InputDecoration decoration,
  ThemeData theme,
  TextDirection textDirection,
  double minimumStart,
) {
  final EdgeInsetsDirectional padding;
  final explicit = decoration.contentPadding?.resolve(textDirection);
  if (explicit != null) {
    final rtl = textDirection == TextDirection.rtl;
    padding = EdgeInsetsDirectional.fromSTEB(
      rtl ? explicit.right : explicit.left,
      explicit.top,
      rtl ? explicit.left : explicit.right,
      explicit.bottom,
    );
  } else if (decoration.isCollapsed ?? false) {
    padding = EdgeInsetsDirectional.zero;
  } else {
    final dense = decoration.isDense ?? false;
    final outline =
        (decoration.enabledBorder ?? decoration.border)?.isOutline ?? false;
    if (outline) {
      padding = dense
          ? const EdgeInsetsDirectional.fromSTEB(12, 16, 12, 8)
          : const EdgeInsetsDirectional.fromSTEB(12, 20, 12, 12);
    } else {
      final horizontal = decoration.filled ?? false ? 12.0 : 0.0;
      final vertical = dense ? 4.0 : 8.0;
      padding = EdgeInsetsDirectional.fromSTEB(
        horizontal,
        vertical,
        horizontal,
        vertical,
      );
    }
  }
  return EdgeInsetsDirectional.fromSTEB(
    math.max(padding.start, minimumStart),
    padding.top,
    padding.end,
    padding.bottom,
  );
}
