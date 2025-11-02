import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Sign In Dialog
///
/// Shows a dialog prompting users to sign in before performing actions
/// that require authentication (like voting, commenting, etc.)
class SignInDialog extends StatelessWidget {
  const SignInDialog({
    this.title = 'Sign in required',
    this.message = 'You need to sign in to interact with posts.',
    super.key,
  });

  final String title;
  final String message;

  /// Show the dialog
  static Future<bool?> show(
    BuildContext context, {
    String? title,
    String? message,
  }) {
    return showDialog<bool>(
      context: context,
      builder:
          (context) => SignInDialog(
            title: title ?? 'Sign in required',
            message: message ?? 'You need to sign in to interact with posts.',
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.background,
      title: Text(
        title,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: Text(
        message,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(
            'Cancel',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.textPrimary,
          ),
          child: const Text('Sign In'),
        ),
      ],
    );
  }
}
