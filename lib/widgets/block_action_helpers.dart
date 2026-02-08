import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/block_provider.dart';
import '../utils/error_messages.dart';
import 'sign_in_dialog.dart';

/// Builds a block/unblock menu item for users or communities.
///
/// Shows a spinner when the block request is pending, and toggles
/// between block/unblock icon and label based on current state.
MenuItemButton buildBlockMenuItem({
  required bool isBlocked,
  required bool isPending,
  required String label,
  required VoidCallback onPressed,
}) {
  return MenuItemButton(
    onPressed: isPending ? null : onPressed,
    leadingIcon: isPending
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(
            isBlocked ? Icons.check_circle_outline : Icons.block,
            size: 20,
          ),
    child: Text(
      isPending
          ? (isBlocked ? 'Unblocking...' : 'Blocking...')
          : label,
    ),
  );
}

/// Handles the full block/unblock user flow:
/// 1. Auth check with sign-in dialog
/// 2. Confirmation dialog (only when blocking)
/// 3. Haptic feedback
/// 4. API call via BlockProvider
/// 5. Success/error snackbar
///
/// Parameters:
/// - [context]: BuildContext
/// - [authorDid]: DID of the user to block
/// - [authorHandle]: Handle for display in dialogs/snackbars
Future<void> handleBlockUser({
  required BuildContext context,
  required String authorDid,
  required String authorHandle,
}) async {
  // Check authentication
  final authProvider = context.read<AuthProvider>();
  if (!authProvider.isAuthenticated) {
    if (!context.mounted) return;
    final shouldSignIn = await SignInDialog.show(
      context,
      message: 'You need to sign in to block users.',
    );
    if (shouldSignIn != true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sign in required to block users'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return;
  }

  final blockProvider = context.read<BlockProvider>();
  final isUserBlocked = blockProvider.isUserBlocked(authorDid);

  // Show confirmation dialog only when blocking
  if (!isUserBlocked) {
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Block User'),
        content: Text(
          'Block @$authorHandle? You won\'t see their posts or comments.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
  }

  try {
    await HapticFeedback.lightImpact();
  } on PlatformException {
    // Haptics not supported
  }

  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);

  try {
    final nowBlocked = await blockProvider.toggleUserBlock(
      userDid: authorDid,
    );

    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            nowBlocked
                ? 'Blocked @$authorHandle'
                : 'Unblocked @$authorHandle',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  } on Exception catch (e) {
    if (kDebugMode) {
      debugPrint('Failed to toggle user block: $e');
    }
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(ErrorMessage.block(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

/// Handles the full block/unblock community flow.
///
/// Same pattern as [handleBlockUser] but for communities.
Future<void> handleBlockCommunity({
  required BuildContext context,
  required String communityDid,
  required String communityName,
}) async {
  // Check authentication
  final authProvider = context.read<AuthProvider>();
  if (!authProvider.isAuthenticated) {
    if (!context.mounted) return;
    final shouldSignIn = await SignInDialog.show(
      context,
      message: 'You need to sign in to block communities.',
    );
    if (shouldSignIn != true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sign in required to block communities'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return;
  }

  final blockProvider = context.read<BlockProvider>();
  final isCommunityBlocked =
      blockProvider.isCommunityBlocked(communityDid);

  // Show confirmation dialog only when blocking
  if (!isCommunityBlocked) {
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Block Community'),
        content: Text(
          'Block !$communityName? You won\'t see posts from this community.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
  }

  try {
    await HapticFeedback.lightImpact();
  } on PlatformException {
    // Haptics not supported
  }

  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);

  try {
    final nowBlocked = await blockProvider.toggleCommunityBlock(
      communityDid: communityDid,
    );

    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            nowBlocked
                ? 'Blocked !$communityName'
                : 'Unblocked !$communityName',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  } on Exception catch (e) {
    if (kDebugMode) {
      debugPrint('Failed to toggle community block: $e');
    }
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(ErrorMessage.block(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
