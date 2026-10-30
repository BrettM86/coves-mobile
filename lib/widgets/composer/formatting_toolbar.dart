import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../icons/lucide_icon_painter.dart';
import '../icons/lucide_paths.dart';
import 'facet_editing_controller.dart';

/// The composer's formatting buttons over a [FacetEditingController].
///
/// The buttons scroll horizontally between the host's [leading] and
/// [trailing] controls, which stay in place. Tapping a button never takes
/// focus from the text field, so the field keeps its selection.
class FormattingToolbar extends StatelessWidget {
  const FormattingToolbar({
    super.key,
    required this.controller,
    this.leading = const [],
    this.trailing = const [],
  });

  final FacetEditingController controller;
  final List<Widget> leading;
  final List<Widget> trailing;

  static const _inlineButtons = [
    (label: 'Bold', format: InlineFormat.bold, glyph: LucidePaths.bold),
    (label: 'Italic', format: InlineFormat.italic, glyph: LucidePaths.italic),
    (
      label: 'Strikethrough',
      format: InlineFormat.strikethrough,
      glyph: LucidePaths.strikethrough,
    ),
    (label: 'Spoiler', format: InlineFormat.spoiler, glyph: LucidePaths.eyeOff),
    (label: 'Code', format: InlineFormat.code, glyph: LucidePaths.code),
  ];

  static const _quote = (
    label: 'Quote',
    format: BlockFormat.blockquote,
    glyph: LucidePaths.textQuote,
  );
  static const _codeBlock = (
    label: 'Code block',
    format: BlockFormat.codeBlock,
    glyph: LucidePaths.squareCode,
  );

  @override
  Widget build(BuildContext context) {
    return TextFieldTapRegion(
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          // With no valid selection (never focused, or unfocused) there is
          // no caret to format, so every button is disabled and inactive.
          final hasSelection = controller.selection.isValid;
          final activeInline = hasSelection
              ? controller.activeInlineFormats()
              : const <InlineFormat>{};
          final activeBlock = hasSelection
              ? controller.activeBlockFormats()
              : const <BlockFormat>{};
          final inlineEnabled =
              hasSelection && !controller.isSelectionInCodeBlock();
          return Row(
            children: [
              ...leading,
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final button in _inlineButtons)
                        _FormatButton(
                          label: button.label,
                          glyph: button.glyph,
                          active: activeInline.contains(button.format),
                          enabled:
                              inlineEnabled &&
                              controller.canToggleInline(button.format),
                          onPressed: () =>
                              controller.toggleInline(button.format),
                        ),
                      _blockButton(_quote, activeBlock, hasSelection),
                      _HeadingButton(
                        controller: controller,
                        active: activeBlock.contains(BlockFormat.heading),
                        enabled: hasSelection,
                      ),
                      _blockButton(_codeBlock, activeBlock, hasSelection),
                    ],
                  ),
                ),
              ),
              ...trailing,
            ],
          );
        },
      ),
    );
  }

  Widget _blockButton(
    ({String label, BlockFormat format, List<String> glyph}) button,
    Set<BlockFormat> activeBlock,
    bool hasSelection,
  ) => _FormatButton(
    label: button.label,
    glyph: button.glyph,
    active: activeBlock.contains(button.format),
    enabled: hasSelection && controller.canToggleBlock(button.format),
    onPressed: () => controller.toggleBlock(button.format),
  );
}

/// The Heading button and the picker it opens: one entry per heading level
/// 1–3, an entry for a loaded level 4–6 while every touched line has that
/// level, and 'Normal text', which removes the heading from every touched
/// line.
///
/// The picker lives in an overlay, outside the toolbar's tap region, so it
/// joins the text field's tap region itself and its entries never take
/// focus: picking keeps the field's focus and selection.
class _HeadingButton extends StatefulWidget {
  const _HeadingButton({
    required this.controller,
    required this.active,
    required this.enabled,
  });

  final FacetEditingController controller;
  final bool active;

  /// Whether the selection is valid; the budget narrows it further.
  final bool enabled;

  @override
  State<_HeadingButton> createState() => _HeadingButtonState();
}

class _HeadingButtonState extends State<_HeadingButton> {
  final _menu = MenuController();

  void _pick(VoidCallback command) {
    _menu.close();
    command();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final activeLevel = widget.enabled ? controller.activeHeadingLevel() : null;
    final levels = [
      // A loaded level 4–6 heading gets its own entry while every touched
      // line has it; the editor itself only applies levels 1–3.
      for (final level in [
        1,
        2,
        3,
        if (activeLevel != null && activeLevel >= 4) activeLevel,
      ])
        (
          level: level,
          allowed:
              widget.enabled &&
              controller.canToggleBlock(BlockFormat.heading, level: level),
        ),
    ];
    final hasHeading = widget.enabled && controller.touchesHeading();
    final enabled = hasHeading || levels.any((entry) => entry.allowed);
    return MenuAnchor(
      controller: _menu,
      style: const MenuStyle(
        backgroundColor: WidgetStatePropertyAll(AppColors.backgroundSecondary),
      ),
      menuChildren: [
        TextFieldTapRegion(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final entry in levels)
                _PickerEntry(
                  label: 'Heading ${entry.level}',
                  selected: activeLevel == entry.level,
                  enabled: entry.allowed,
                  onPressed: () => _pick(
                    () => controller.toggleBlock(
                      BlockFormat.heading,
                      level: entry.level,
                    ),
                  ),
                ),
              _PickerEntry(
                label: 'Normal text',
                selected: widget.enabled && !hasHeading,
                enabled: widget.enabled,
                onPressed: () => _pick(controller.removeHeadings),
              ),
            ],
          ),
        ),
      ],
      builder: (context, menu, _) => _FormatButton(
        label: 'Heading',
        glyph: LucidePaths.heading,
        active: widget.active,
        enabled: enabled,
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
      ),
    );
  }
}

class _PickerEntry extends StatelessWidget {
  const _PickerEntry({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? AppColors.textMuted
        : selected
        ? AppColors.primary
        : AppColors.textPrimary;
    final onTap = enabled ? onPressed : null;
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.centerLeft,
          child: Text(label, style: TextStyle(color: color)),
        ),
      ),
    );
  }
}

class _FormatButton extends StatelessWidget {
  const _FormatButton({
    required this.label,
    required this.glyph,
    required this.active,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final List<String> glyph;
  final bool active;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? AppColors.textMuted
        : active
        ? AppColors.primary
        : AppColors.textSecondary;
    final onTap = enabled ? onPressed : null;
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      selected: active,
      enabled: enabled,
      label: label,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(child: LucideGlyph(glyph, size: 20, color: color)),
        ),
      ),
    );
  }
}
