import 'package:flutter/cupertino.dart'
    show
        cupertinoDesktopTextSelectionHandleControls,
        cupertinoTextSelectionHandleControls;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// A [StaticSelectionContainerDelegate] whose copied text puts exactly one
/// `\n` between the selected text of consecutive child selectables, so
/// sibling `Text` widgets copy as separate lines.
class SeparatedSelectionContainerDelegate
    extends StaticSelectionContainerDelegate {
  // Registering with the parent region queues a post-frame update without
  // requesting a frame; request one so a region mounted while idle works.
  @override
  void didChangeSelectables() {
    super.didChangeSelectables();
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  @override
  SelectedContent? getSelectedContent() {
    final texts = <String>[
      for (final selectable in selectables)
        if (selectable.getSelectedContent()?.plainText case final String text
            when text.isNotEmpty)
          text,
    ];
    if (texts.isEmpty) {
      return null;
    }
    return SelectedContent(plainText: texts.join('\n'));
  }
}

/// A [SelectionContainer] whose child selectables copy joined by one
/// newline. Its delegate lives exactly as long as this widget's element.
class SeparatedSelectionContainer extends StatefulWidget {
  const SeparatedSelectionContainer({super.key, required this.child});

  final Widget child;

  @override
  State<SeparatedSelectionContainer> createState() =>
      _SeparatedSelectionContainerState();
}

class _SeparatedSelectionContainerState
    extends State<SeparatedSelectionContainer> {
  final SeparatedSelectionContainerDelegate _delegate =
      SeparatedSelectionContainerDelegate();

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SelectionContainer(delegate: _delegate, child: widget.child);
}

/// A self-contained [SelectionArea] for one block of text.
///
/// Selection never crosses into another region, sibling `Text` widgets copy
/// joined by one newline, and tapping outside this region (and its
/// handles and toolbar) clears the selection.
class SeparatedSelectionArea extends StatefulWidget {
  const SeparatedSelectionArea({super.key, required this.child});

  final Widget child;

  @override
  State<SeparatedSelectionArea> createState() => _SeparatedSelectionAreaState();
}

class _SeparatedSelectionAreaState extends State<SeparatedSelectionArea> {
  static final Set<_SeparatedSelectionAreaState> _mounted = {};

  late final SeparatedSelectionContainerDelegate _delegate;
  final FocusNode _focusNode = FocusNode(debugLabel: 'SeparatedSelectionArea');

  @override
  void initState() {
    super.initState();
    _delegate = SeparatedSelectionContainerDelegate();
    _mounted.add(this);
  }

  @override
  void dispose() {
    _mounted.remove(this);
    _delegate.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _unfocusOtherRegions() {
    for (final region in _mounted) {
      if (region != this && region._focusNode.hasFocus) {
        region._focusNode.unfocus();
      }
    }
  }

  /// Whether [globalPosition] is inside the touch target of a selection
  /// handle that another focused region shows.
  bool _isOnOtherRegionHandle(Offset globalPosition) {
    for (final region in _mounted) {
      if (region != this &&
          region._focusNode.hasFocus &&
          region._handleTargetContains(globalPosition)) {
        return true;
      }
    }
    return false;
  }

  /// Mirrors how SelectableRegion places its handles (the handle anchor on
  /// the selection point) and how the handle overlay grows its hit area to
  /// at least [kMinInteractiveDimension], using only public APIs.
  bool _handleTargetContains(Offset globalPosition) {
    final controls = _selectionControls;
    final geometry = _delegate.value;
    if (controls == null || geometry.status == SelectionStatus.none) {
      return false;
    }
    final toGlobal = _delegate.getTransformTo(null);
    for (final point in [
      geometry.startSelectionPoint,
      geometry.endSelectionPoint,
    ]) {
      if (point == null) {
        continue;
      }
      final handle =
          (point.localPosition -
              controls.getHandleAnchor(point.handleType, point.lineHeight)) &
          controls.getHandleSize(point.lineHeight);
      final target = handle.expandToInclude(
        Rect.fromCircle(
          center: handle.center,
          radius: kMinInteractiveDimension / 2,
        ),
      );
      if (MatrixUtils.transformRect(
        toGlobal,
        target,
      ).contains(globalPosition)) {
        return true;
      }
    }
    return false;
  }

  TextSelectionControls? _selectionControls;

  @override
  Widget build(BuildContext context) {
    // The same platform controls SelectionArea picks by default, passed
    // explicitly so handle targets can be computed from them.
    final controls = _selectionControls = switch (Theme.of(context).platform) {
      TargetPlatform.android ||
      TargetPlatform.fuchsia => materialTextSelectionHandleControls,
      TargetPlatform.linux ||
      TargetPlatform.windows => desktopTextSelectionHandleControls,
      TargetPlatform.iOS => cupertinoTextSelectionHandleControls,
      TargetPlatform.macOS => cupertinoDesktopTextSelectionHandleControls,
    };
    // SelectableRegion only clears on outside taps on web; losing focus
    // clears it everywhere. Handles, toolbar and other regions share the
    // SelectableRegion tap group, so tapping them is not "outside".
    // A pointer down in this region unfocuses every other region directly:
    // a quick tap won by a child recognizer (a link, a GestureDetector) never
    // reaches this region's own recognizer, so focus would not move.
    // A handle's touch target is larger than its painted handle, and a
    // pointer in that margin still hit-tests the page below. Where another
    // region's handle target overlaps this region, this region's listener
    // and recognizers stay out of the hit test, so the pointer neither
    // unfocuses that region nor starts a competing drag here. The tap region
    // is translucent so that pointer still counts as inside the group.
    return TapRegion(
      groupId: SelectableRegion,
      behavior: HitTestBehavior.translucent,
      onTapOutside: (_) => _focusNode.unfocus(),
      child: _HitTestExclusion(
        excludes: _isOnOtherRegionHandle,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _unfocusOtherRegions(),
          child: SelectionArea(
            focusNode: _focusNode,
            selectionControls: controls,
            child: SelectionContainer(delegate: _delegate, child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// Leaves its subtree out of hit testing at global positions [excludes]
/// returns true for.
class _HitTestExclusion extends SingleChildRenderObjectWidget {
  const _HitTestExclusion({required this.excludes, super.child});

  final bool Function(Offset globalPosition) excludes;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHitTestExclusion(excludes);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHitTestExclusion renderObject,
  ) {
    renderObject.excludes = excludes;
  }
}

class _RenderHitTestExclusion extends RenderProxyBox {
  _RenderHitTestExclusion(this.excludes);

  bool Function(Offset globalPosition) excludes;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (excludes(localToGlobal(position))) {
      return false;
    }
    return super.hitTest(result, position: position);
  }
}

/// Marks a subtree whose cards copy only their content: inside it, every
/// [ContentOnlySelectionExclusion] leaves selection. Outside it the cards
/// render exactly as they would without it.
class ContentOnlySelectionScope extends InheritedWidget {
  const ContentOnlySelectionScope({super.key, required super.child});

  static bool isActive(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ContentOnlySelectionScope>() !=
      null;

  @override
  bool updateShouldNotify(ContentOnlySelectionScope oldWidget) => false;
}

/// A non-content part of a card (author, timestamps, embeds, controls).
///
/// Inside a [ContentOnlySelectionScope] it is neither selected nor copied,
/// and a long-press on it starts no selection. Elsewhere it is [child]
/// unchanged, so a long-press still reaches the card's own handler.
class ContentOnlySelectionExclusion extends StatelessWidget {
  const ContentOnlySelectionExclusion({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!ContentOnlySelectionScope.isActive(context)) {
      return child;
    }
    // Claims the long-press so the enclosing area does not select the
    // nearest word, also on empty space between the children (translucent);
    // excludeFromSemantics keeps the child's semantics as is.
    return SelectionContainer.disabled(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPress: () {},
        excludeFromSemantics: true,
        child: child,
      ),
    );
  }
}
