import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../models/moderation.dart';
import '../models/post.dart';
import '../providers/auth_provider.dart';
import '../providers/block_provider.dart';
import '../providers/community_subscription_provider.dart';
import '../providers/viewer_authority_provider.dart';
import '../services/api_exceptions.dart';
import '../services/coves_api_service.dart';
import '../services/post_change_broadcast.dart';
import 'block_action_helpers.dart';
import 'moderation/post_admin_tools.dart';
import 'report_dialog.dart';
import 'sign_in_dialog.dart';

/// The options menu for a post, shared by the feed card's ⋯ and the post
/// detail app bar's ⋮.
///
/// Entries are grouped, with a divider between groups: the community
/// subscription; blocks; reporting or deleting; then any admin tools.
///
/// Account, subscription, block and authority state is looked up only by
/// the open menu's entries, so a tree without those providers builds while
/// the menu is closed.
class PostOptionsMenu extends StatefulWidget {
  const PostOptionsMenu({
    required this.post,
    required this.sessionStamp,
    required this.anchorBuilder,
    this.onDeleted,
    super.key,
  });

  final FeedViewPost post;

  /// The session key [post] was loaded under; null denies admin tools.
  final Object? sessionStamp;

  /// Builds the button that toggles the menu through its controller.
  final Widget Function(BuildContext context, MenuController controller)
  anchorBuilder;

  /// Called once the server has accepted a delete, before the removal is
  /// broadcast to every surface showing the post.
  final VoidCallback? onDeleted;

  @override
  State<PostOptionsMenu> createState() => _PostOptionsMenuState();
}

class _PostOptionsMenuState extends State<PostOptionsMenu> {
  bool _isDeleting = false;

  PostView get _post => widget.post.post;

  /// The admin tools the menu offers on the post, read with [watch] while
  /// the menu is open so a change in authority redraws it.
  List<PostAdminTool> _adminTools(BuildContext context, {bool watch = false}) {
    final capabilities =
        _post.viewer?.moderation ?? const <ModerationCapability>{};
    // Authority is looked up only for a post that carries a moderation
    // token: most trees showing posts have no admin tools to gate.
    if (capabilities.isEmpty) {
      return const [];
    }
    return allowedPostAdminTools(
      capabilities: capabilities,
      sessionStamp: widget.sessionStamp,
      authority: watch
          ? context.watch<ViewerAuthorityProvider>()
          : context.read<ViewerAuthorityProvider>(),
    );
  }

  Future<void> _toggleSubscription() async {
    if (!context.read<AuthProvider>().isAuthenticated) {
      await promptSignIn(
        context,
        message: 'You need to sign in to subscribe to communities.',
        declinedMessage: 'Sign in required to subscribe',
      );
      return;
    }

    try {
      await HapticFeedback.lightImpact();
    } on PlatformException {
      // Haptics not supported
    }

    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final subscriptionProvider = context.read<CommunitySubscriptionProvider>();
    final communityName = _post.community.name;

    try {
      final nowSubscribed = await subscriptionProvider.toggleSubscription(
        communityDid: _post.community.did,
      );

      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              nowSubscribed
                  ? 'Subscribed to !$communityName'
                  : 'Unsubscribed from !$communityName',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to toggle subscription: $e');
      }
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Could not update subscription. Please try again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _report() async {
    if (!context.read<AuthProvider>().isAuthenticated) {
      await promptSignIn(
        context,
        message: 'You need to sign in to report content.',
        declinedMessage: 'Sign in required to report content',
      );
      return;
    }

    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);

    final reported = await ReportDialog.show(
      context,
      targetUri: _post.uri,
      contentType: 'post',
    );

    if ((reported ?? false) && mounted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Report submitted. Thank you for helping keep our '
            'community safe.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _delete() async {
    // Prevent multiple taps - set flag immediately before dialog
    if (_isDeleting) {
      return;
    }
    _isDeleting = true;

    if (!context.read<AuthProvider>().isAuthenticated) {
      _isDeleting = false;
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Post'),
        content: const Text(
          'Are you sure you want to delete this post? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      _isDeleting = false;
      return;
    }

    try {
      await HapticFeedback.lightImpact();
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('Haptics not supported: $e');
      }
    }

    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);

    // Shared app-wide API client (owned by main.dart) — do not dispose
    final apiService = context.read<CovesApiService>();
    // Capture both before the request: the menu may leave the tree while
    // deletion is in flight, but every loaded owner still needs the event.
    final broadcast = context.read<PostChangeBroadcast>();
    final onDeleted = widget.onDeleted;
    final uri = _post.uri;

    var deleted = false;
    try {
      await apiService.deletePost(uri: uri);
      deleted = true;
    } on NetworkException catch (e) {
      if (kDebugMode) {
        debugPrint('Network error deleting post: $e');
      }
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Network error. Please check your connection and try again.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on NotFoundException catch (e) {
      if (kDebugMode) {
        debugPrint('Post not found: $e');
      }
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Post not found. It may have already been deleted.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on ApiException catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to delete post: $e');
      }
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              e.statusCode == 403
                  ? 'You can only delete your own posts'
                  : 'Could not delete post. Please try again.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to delete post: $e');
      }
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Could not delete post. Please try again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      _isDeleting = false;
    }

    // Outside the try so an error thrown by a listener is not reported
    // as a failed delete.
    if (deleted) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Post deleted'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      // Before the broadcast, so a surface leaving on delete does so before
      // the removal reaches it.
      onDeleted?.call();
      broadcast.removePost(uri);
    }
  }

  /// Whether the signed-in viewer wrote the post, watched by the open menu.
  bool _watchIsPostAuthor(BuildContext context) =>
      context.watch<AuthProvider>().did == _post.author.did;

  /// Runs [tool] if authority still allows it: an open menu may have been
  /// built before authority changed.
  Future<void> _runAdminTool(PostAdminTool tool) async {
    if (mounted && _adminTools(context).contains(tool)) {
      await runPostAdminTool(context, shownPost: _post, tool: tool);
    }
  }

  @override
  Widget build(BuildContext context) {
    final communityDid = _post.community.did;
    final communityName = _post.community.name;
    final authorDid = _post.author.did;
    final authorHandle = _post.author.handle;

    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(
          AppColors.backgroundSecondary,
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      menuChildren: [
        Consumer<CommunitySubscriptionProvider>(
          builder: (context, subscriptionProvider, _) {
            final isSubscribed = subscriptionProvider.isSubscribed(
              communityDid,
            );
            final isPending = subscriptionProvider.isPending(communityDid);
            return MenuItemButton(
              onPressed: isPending ? null : _toggleSubscription,
              leadingIcon: isPending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      isSubscribed
                          ? Icons.remove_circle_outline
                          : Icons.add_circle_outline,
                      size: 20,
                    ),
              trailingIcon: isSubscribed && !isPending
                  ? const Icon(Icons.check, color: AppColors.primary, size: 20)
                  : null,
              child: Text(
                isPending
                    ? (isSubscribed ? 'Unsubscribing...' : 'Subscribing...')
                    : (isSubscribed
                          ? 'Unsubscribe from !$communityName'
                          : 'Subscribe to !$communityName'),
              ),
            );
          },
        ),
        const Divider(),
        // Block user option (except own posts)
        Consumer<BlockProvider>(
          builder: (context, blockProvider, _) {
            if (_watchIsPostAuthor(context)) {
              return const SizedBox.shrink();
            }
            final isBlocked = blockProvider.isUserBlocked(authorDid);
            return buildBlockMenuItem(
              isBlocked: isBlocked,
              isPending: blockProvider.isUserBlockPending(authorDid),
              label: isBlocked
                  ? 'Unblock @$authorHandle'
                  : 'Block @$authorHandle',
              onPressed: () => handleBlockUser(
                context: this.context,
                authorDid: authorDid,
                authorHandle: authorHandle,
              ),
            );
          },
        ),
        Consumer<BlockProvider>(
          builder: (context, blockProvider, _) {
            final isBlocked = blockProvider.isCommunityBlocked(communityDid);
            return buildBlockMenuItem(
              isBlocked: isBlocked,
              isPending: blockProvider.isCommunityBlockPending(communityDid),
              label: isBlocked
                  ? 'Unblock !$communityName'
                  : 'Block !$communityName',
              onPressed: () => handleBlockCommunity(
                context: this.context,
                communityDid: communityDid,
                communityName: communityName,
              ),
            );
          },
        ),
        const Divider(),
        // Delete for the post's author, Report for everyone else
        Builder(
          builder: (context) => _watchIsPostAuthor(context)
              ? MenuItemButton(
                  onPressed: _delete,
                  leadingIcon: const Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: Colors.red,
                  ),
                  child: const Text(
                    'Delete post',
                    style: TextStyle(color: Colors.red),
                  ),
                )
              : MenuItemButton(
                  onPressed: _report,
                  leadingIcon: const Icon(Icons.flag_outlined, size: 20),
                  child: const Text('Report post'),
                ),
        ),
        Builder(
          builder: (context) {
            final adminTools = _adminTools(context, watch: true);
            if (adminTools.isEmpty) {
              return const SizedBox.shrink();
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Divider(),
                for (final tool in adminTools)
                  MenuItemButton(
                    onPressed: () => _runAdminTool(tool),
                    leadingIcon: Icon(
                      tool.icon,
                      size: 20,
                      color: tool.destructive ? Colors.red : null,
                    ),
                    child: Text(
                      tool.label,
                      style: tool.destructive
                          ? const TextStyle(color: Colors.red)
                          : null,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
      builder: (context, controller, _) =>
          widget.anchorBuilder(context, controller),
    );
  }
}
