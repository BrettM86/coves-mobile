import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// A labelled dark-theme text field for the admin forms.
///
/// Deliberately dumb: it renders a label, a [TextField] and either a helper
/// or an error line, and owns nothing. The [controller] is created, listened
/// to and disposed by the form that supplies it — the admin create form
/// attaches ONE shared listener across all of its fields, and a listener
/// added here per field would quietly break that.
class AdminTextField extends StatelessWidget {
  const AdminTextField({
    required this.controller,
    required this.label,
    required this.hint,
    this.helperText,
    this.errorText,
    this.maxLines = 1,
    super.key,
  });

  /// Owned by the caller: never listened to or disposed here.
  final TextEditingController controller;

  /// Field label rendered above the input.
  final String label;

  /// Placeholder shown while the field is empty.
  final String hint;

  /// Guidance shown below the input. Suppressed while [errorText] is set,
  /// so the two never stack.
  final String? helperText;

  /// Validation message. Non-null also turns the borders red.
  final String? errorText;

  /// Number of visible lines; more than one makes the field multiline.
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
            helperText: hasError ? null : helperText,
            helperStyle: const TextStyle(color: Color(0xFFB6C2D2)),
            errorText: errorText,
            errorStyle: const TextStyle(color: Colors.red),
            filled: true,
            fillColor: AppColors.backgroundSecondary,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: hasError ? Colors.red : AppColors.border,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: hasError ? Colors.red : AppColors.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
