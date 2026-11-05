import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../providers/auth_provider.dart';

/// Asks the user to sign in again as the current account so image uploads
/// get the permission they were refused, and runs
/// [AuthProvider.reauthenticate] when they agree.
///
/// The dialog closes on success or a cancelled sign-in; a failed sign-in or
/// a different account shows a message and keeps it open. The composer
/// behind it is left as it was, so the user taps Post or Send again.
Future<void> showSignInAgainDialog(
  BuildContext context, {
  required AuthProvider authProvider,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => SignInAgainDialog(authProvider: authProvider),
  );
}

/// The dialog shown by [showSignInAgainDialog].
class SignInAgainDialog extends StatefulWidget {
  const SignInAgainDialog({required this.authProvider, super.key});

  final AuthProvider authProvider;

  @override
  State<SignInAgainDialog> createState() => _SignInAgainDialogState();
}

class _SignInAgainDialogState extends State<SignInAgainDialog> {
  bool _signingIn = false;
  ReauthenticationResult? _lastResult;

  Future<void> _signIn() async {
    setState(() {
      _signingIn = true;
      _lastResult = null;
    });
    final result = await widget.authProvider.reauthenticate();
    if (!mounted) {
      return;
    }
    if (result == ReauthenticationResult.success ||
        result == ReauthenticationResult.cancelled) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _signingIn = false;
      _lastResult = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    const messageStyle = TextStyle(color: AppColors.error, fontSize: 14);
    return AlertDialog(
      key: const Key('sign-in-again-dialog'),
      backgroundColor: AppColors.background,
      title: const Text(
        'Sign in again to upload images',
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your session does not allow image uploads. Sign in again with '
            'the same account, then try again.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
          if (_lastResult == ReauthenticationResult.differentAccount) ...[
            const SizedBox(height: 12),
            const Text(
              'That was a different account. Sign in with the account you '
              'are posting as.',
              key: Key('sign-in-again-different-account'),
              style: messageStyle,
            ),
          ],
          if (_lastResult == ReauthenticationResult.failed) ...[
            const SizedBox(height: 12),
            const Text(
              "Couldn't sign in. Please try again.",
              key: Key('sign-in-again-failed'),
              style: messageStyle,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _signingIn ? null : () => Navigator.of(context).pop(),
          child: const Text(
            'Cancel',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        ElevatedButton(
          onPressed: _signingIn ? null : _signIn,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.textPrimary,
          ),
          child: const Text('Sign in'),
        ),
      ],
    );
  }
}
