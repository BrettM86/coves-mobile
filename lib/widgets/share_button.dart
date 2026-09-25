import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../services/link_sharer.dart';
import '../utils/share_link.dart';
import 'icons/share_icon.dart';

/// Standardized share button used across the app
///
/// Displays the ArrowShareRight icon from Bluesky's design system.
/// Hands [url] to the ambient [LinkSharer] when tapped.
class ShareButton extends StatelessWidget {
  const ShareButton({
    required this.url,
    this.size = 18,
    this.color,
    this.tooltip = 'Share',
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    this.useIconButton = false,
    super.key,
  });

  /// Web URL this button shares.
  ///
  /// Required so a call site cannot quietly render a button with nothing to
  /// share. Null when the surface cannot build a link for what it is showing;
  /// tapping then reports that instead of sharing.
  final String? url;

  /// Size of the share icon
  final double size;

  /// Color of the share icon (defaults to theme icon color with 0.6 opacity)
  final Color? color;

  /// Tooltip text shown on long press
  final String tooltip;

  /// Padding around the icon (ignored when useIconButton is true)
  final EdgeInsets padding;

  /// Whether to use IconButton style (for app bars) vs InkWell style (for
  /// cards)
  final bool useIconButton;

  /// The share sheet is anchored on this button's own bounds, which is what
  /// iPad puts the popover next to.
  Future<void> _handleTap(BuildContext context) =>
      shareLinkFrom(context, url, globalRectOf(context));

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        color ?? AppColors.textPrimary.withValues(alpha: 0.6);

    if (useIconButton) {
      return IconButton(
        icon: ShareIcon(size: size, color: effectiveColor),
        onPressed: () => _handleTap(context),
        tooltip: tooltip,
      );
    }

    return Semantics(
      button: true,
      label: tooltip,
      child: InkWell(
        onTap: () => _handleTap(context),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: padding,
          child: ShareIcon(size: size, color: effectiveColor),
        ),
      ),
    );
  }
}
