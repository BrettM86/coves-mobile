import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_colors.dart';
import 'icons/share_icon.dart';

/// Standardized share button used across the app
///
/// Displays the ArrowShareRight icon from Bluesky's design system.
/// Shows a "Share coming soon!" snackbar when tapped.
class ShareButton extends StatelessWidget {
  const ShareButton({
    this.size = 18,
    this.color,
    this.tooltip = 'Share',
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    this.useIconButton = false,
    super.key,
  });

  /// Size of the share icon
  final double size;

  /// Color of the share icon (defaults to theme icon color with 0.6 opacity)
  final Color? color;

  /// Tooltip text shown on long press
  final String tooltip;

  /// Padding around the icon (ignored when useIconButton is true)
  final EdgeInsets padding;

  /// Whether to use IconButton style (for app bars) vs InkWell style (for cards)
  final bool useIconButton;

  Future<void> _handleTap(BuildContext context) async {
    try {
      await HapticFeedback.lightImpact();
    } on PlatformException {
      // Haptics not supported on this platform - ignore
    }

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Share coming soon!'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

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
