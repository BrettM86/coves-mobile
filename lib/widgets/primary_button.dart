import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_colors.dart';

enum ButtonVariant { solid, outline, tertiary }

/// Primary button with Coves design language.
///
/// Features warm coral accent with refined styling across all variants.
///
/// ## Variants
/// - [ButtonVariant.solid]: Filled coral background with subtle shadow.
///   Use for primary actions (e.g., "Sign in", "Submit").
/// - [ButtonVariant.outline]: Transparent with coral border. Use for secondary
///   actions that still need prominence (e.g., "Create account").
/// - [ButtonVariant.tertiary]: Subtle gray background. Use for less important
///   actions (e.g., "Cancel", "Skip").
///
/// ## Icon Parameter
/// Optional widget displayed before the title. Typically an [Icon] widget.
/// The icon inherits the button's text color for consistency.
class PrimaryButton extends StatefulWidget {
  const PrimaryButton({
    super.key,
    required this.title,
    required this.onPressed,
    this.variant = ButtonVariant.solid,
    this.disabled = false,
    this.icon,
  });

  final String title;
  final VoidCallback onPressed;
  final ButtonVariant variant;
  final bool disabled;

  /// Optional icon widget displayed before the title text.
  final Widget? icon;

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.75,
      height: 52,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(100),
            color: _getBackgroundColor(),
            border: _getBorder(),
            boxShadow: _getBoxShadow(),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.disabled ? null : widget.onPressed,
              borderRadius: BorderRadius.circular(100),
              splashFactory: NoSplash.splashFactory,
              highlightColor: Colors.transparent,
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.icon != null) ...[
                      widget.icon!,
                      const SizedBox(width: 10),
                    ],
                    Text(
                      widget.title,
                      style: GoogleFonts.nunito(
                        fontSize: widget.variant == ButtonVariant.tertiary
                            ? 14
                            : 16,
                        fontWeight: widget.variant == ButtonVariant.tertiary
                            ? FontWeight.w600
                            : FontWeight.w700,
                        color: _getTextColor(),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _getBackgroundColor() {
    if (widget.disabled) {
      return _getBaseBackgroundColor().withValues(alpha: 0.4);
    }
    if (_isPressed) {
      return _getPressedBackgroundColor();
    }
    return _getBaseBackgroundColor();
  }

  Color _getBaseBackgroundColor() {
    switch (widget.variant) {
      case ButtonVariant.solid:
        return AppColors.coral;
      case ButtonVariant.outline:
        return Colors.transparent;
      case ButtonVariant.tertiary:
        return AppColors.backgroundSecondary;
    }
  }

  Color _getPressedBackgroundColor() {
    switch (widget.variant) {
      case ButtonVariant.solid:
        return AppColors.coralDark;
      case ButtonVariant.outline:
        return AppColors.coral.withValues(alpha: 0.1);
      case ButtonVariant.tertiary:
        return AppColors.backgroundTertiary;
    }
  }

  Color _getTextColor() {
    if (widget.disabled) {
      return _getBaseTextColor().withValues(alpha: 0.5);
    }
    return _getBaseTextColor();
  }

  Color _getBaseTextColor() {
    switch (widget.variant) {
      case ButtonVariant.solid:
        return AppColors.background;
      case ButtonVariant.outline:
        return AppColors.textPrimary;
      case ButtonVariant.tertiary:
        return AppColors.textSecondary;
    }
  }

  Border? _getBorder() {
    switch (widget.variant) {
      case ButtonVariant.solid:
        return null;
      case ButtonVariant.outline:
        return Border.all(
          color: widget.disabled
              ? AppColors.coral.withValues(alpha: 0.3)
              : _isPressed
                  ? AppColors.coralLight
                  : AppColors.coral,
          width: 2,
        );
      case ButtonVariant.tertiary:
        return Border.all(
          color: AppColors.border,
          width: 1,
        );
    }
  }

  List<BoxShadow>? _getBoxShadow() {
    if (widget.disabled || widget.variant != ButtonVariant.solid) {
      return null;
    }

    if (_isPressed) {
      return null;
    }

    return [
      // Subtle bottom shadow
      BoxShadow(
        color: AppColors.coralDark.withValues(alpha: 0.3),
        blurRadius: 8,
        offset: const Offset(0, 4),
      ),
    ];
  }
}
