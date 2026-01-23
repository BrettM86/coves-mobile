import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../constants/bluesky_colors.dart';

/// Animation duration for press state transitions.
const _kPressAnimationDuration = Duration(milliseconds: 150);

/// Sign in with Bluesky button component.
///
/// A branded outline button for Bluesky authentication that integrates
/// seamlessly with the Coves design system while maintaining Bluesky's
/// brand identity.
///
/// Features:
/// - Transparent background with Bluesky blue border
/// - Official butterfly logo in Bluesky blue
/// - Smooth press state animations
/// - Disabled state support
/// - Consistent with Coves button sizing (75% width, 52px height)
class BlueskySignInButton extends StatefulWidget {
  const BlueskySignInButton({
    super.key,
    required this.onPressed,
    this.disabled = false,
    this.title = 'Sign in with Bluesky',
  });

  final VoidCallback onPressed;
  final bool disabled;
  final String title;

  @override
  State<BlueskySignInButton> createState() => _BlueskySignInButtonState();
}

class _BlueskySignInButtonState extends State<BlueskySignInButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.75,
      height: 52,
      child: GestureDetector(
        onTapDown: (_) {
          if (!widget.disabled) {
            setState(() => _isPressed = true);
          }
        },
        onTapUp: (_) {
          if (_isPressed) {
            setState(() => _isPressed = false);
            widget.onPressed();
          }
        },
        onTapCancel: () {
          if (_isPressed) {
            setState(() => _isPressed = false);
          }
        },
        child: AnimatedContainer(
          duration: _kPressAnimationDuration,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(100),
            color: _getBackgroundColor(),
            border: Border.all(
              color: _getBorderColor(),
              width: 2,
            ),
          ),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Official Bluesky butterfly logo
                SvgPicture.asset(
                  'assets/icons/bluesky_butterfly.svg',
                  width: 22,
                  height: 22,
                  colorFilter: ColorFilter.mode(
                    _getContentColor(),
                    BlendMode.srcIn,
                  ),
                  errorBuilder: (context, error, stackTrace) {
                    unawaited(
                      Sentry.captureException(
                        error,
                        stackTrace: stackTrace,
                        withScope: (scope) {
                          scope
                            ..setTag('asset', 'bluesky_butterfly.svg')
                            ..setTag('widget', 'BlueskySignInButton');
                        },
                      ),
                    );
                    return Icon(
                      Icons.cloud_outlined,
                      size: 22,
                      color: _getContentColor(),
                    );
                  },
                ),
                const SizedBox(width: 12),
                Text(
                  widget.title,
                  style: GoogleFonts.nunito(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _getContentColor(),
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getBackgroundColor() {
    if (_isPressed) {
      return BlueskyColors.linkBlue.withValues(alpha: 0.1);
    }
    return Colors.transparent;
  }

  Color _getBorderColor() {
    if (widget.disabled) {
      return BlueskyColors.linkBlue.withValues(alpha: 0.3);
    }
    if (_isPressed) {
      return BlueskyColors.linkBlueLight;
    }
    return BlueskyColors.linkBlue;
  }

  Color _getContentColor() {
    if (widget.disabled) {
      return BlueskyColors.linkBlue.withValues(alpha: 0.5);
    }
    return BlueskyColors.linkBlue;
  }
}
