import 'package:flutter/material.dart';

enum ButtonVariant { solid, outline, tertiary }

class PrimaryButton extends StatelessWidget {
  final String title;
  final VoidCallback onPressed;
  final ButtonVariant variant;
  final bool disabled;

  const PrimaryButton({
    super.key,
    required this.title,
    required this.onPressed,
    this.variant = ButtonVariant.solid,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.75,
      height: 48,
      child: ElevatedButton(
        onPressed: disabled ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _getBackgroundColor(),
          foregroundColor: _getTextColor(),
          disabledBackgroundColor: _getBackgroundColor().withOpacity(0.5),
          disabledForegroundColor: _getTextColor().withOpacity(0.5),
          overlayColor: _getOverlayColor(),
          splashFactory: NoSplash.splashFactory,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9999),
            side: _getBorderSide(),
          ),
          elevation: variant == ButtonVariant.solid ? 8 : 0,
          shadowColor:
              variant == ButtonVariant.solid
                  ? const Color(0xFFD84315).withOpacity(0.4)
                  : Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: variant == ButtonVariant.tertiary ? 14 : 16,
            fontWeight:
                variant == ButtonVariant.tertiary
                    ? FontWeight.w500
                    : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Color _getBackgroundColor() {
    switch (variant) {
      case ButtonVariant.solid:
        return const Color(0xFFFF6B35);
      case ButtonVariant.outline:
        return const Color(0xFF5A6B7F).withOpacity(0.1);
      case ButtonVariant.tertiary:
        return const Color(0xFF1A1F27);
    }
  }

  Color _getTextColor() {
    switch (variant) {
      case ButtonVariant.solid:
        return const Color(0xFF0B0F14);
      case ButtonVariant.outline:
        return const Color(0xFFB6C2D2);
      case ButtonVariant.tertiary:
        return const Color(0xFF8A96A6);
    }
  }

  BorderSide _getBorderSide() {
    if (variant == ButtonVariant.outline) {
      return const BorderSide(color: Color(0xFF5A6B7F), width: 2);
    }
    return BorderSide.none;
  }

  Color _getOverlayColor() {
    switch (variant) {
      case ButtonVariant.solid:
        return const Color(0xFFD84315).withOpacity(0.2);
      case ButtonVariant.outline:
        return const Color(0xFF5A6B7F).withOpacity(0.15);
      case ButtonVariant.tertiary:
        return const Color(0xFF2A3441).withOpacity(0.3);
    }
  }
}
