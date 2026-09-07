import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../models/post.dart';
import '../providers/auth_provider.dart';
import '../providers/block_provider.dart';
import '../providers/community_subscription_provider.dart';
import '../providers/vote_provider.dart';
import '../services/api_exceptions.dart';
import '../services/coves_api_service.dart';
import '../utils/display_utils.dart';
import '../utils/error_messages.dart';
import 'animated_vote_count.dart';
import 'block_action_helpers.dart';
import 'icons/animated_heart_icon.dart';
import 'icons/downvote_icon.dart';
import 'icons/reply_icon.dart';
import 'report_dialog.dart';
import 'share_button.dart';
import 'sign_in_dialog.dart';

/// Action buttons row for post cards
///
/// Displays menu, share, comment, and vote buttons with proper
/// authentication handling and optimistic updates.
class PostCardActions extends StatefulWidget {
  const PostCardActions({
    required this.post,
    this.showCommentButton = true,
    this.onDeleted,
    super.key,
  });

  final FeedViewPost post;
  final bool showCommentButton;
  final VoidCallback? onDeleted;

  @override
  State<PostCardActions> createState() => _PostCardActionsState();
}

class _PostCardActionsState extends State<PostCardActions> {
  bool _isDeleting = false;

  FeedViewPost get post => widget.post;
  bool get showCommentButton => widget.showCommentButton;
  VoidCallback? get onDeleted => widget.onDeleted;

  Future<void> _handleMenuAction(BuildContext context, String action) async {
    final communityDid = post.post.community.did;
    final communityName = post.post.community.name;

    if (action == 'subscribe') {
      // Check authentication - subscribe requires sign-in
      final authProvider = context.read<AuthProvider>();
      if (!authProvider.isAuthenticated) {
        if (!context.mounted) {
          return;
        }
        final shouldSignIn = await SignInDialog.show(
          context,
          message: 'You need to sign in to subscribe to communities.',
        );
        if (shouldSignIn != true && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sign in required to subscribe'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // Toggle subscription
      try {
        await HapticFeedback.lightImpact();
      } on PlatformException {
        // Haptics not supported
      }

      if (!context.mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      final subscriptionProvider = context
          .read<CommunitySubscriptionProvider>();

      try {
        final nowSubscribed = await subscriptionProvider.toggleSubscription(
          communityDid: communityDid,
        );

        if (context.mounted) {
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
        if (context.mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Could not update subscription. Please try again.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } else if (action == 'blockCommunity') {
      await handleBlockCommunity(
        context: context,
        communityDid: communityDid,
        communityName: communityName,
      );
    } else if (action == 'blockUser') {
      await handleBlockUser(
        context: context,
        authorDid: post.post.author.did,
        authorHandle: post.post.author.handle,
      );
    } else if (action == 'report') {
      // Check authentication - report requires sign-in
      final authProvider = context.read<AuthProvider>();
      if (!authProvider.isAuthenticated) {
        if (!context.mounted) {
          return;
        }
        final shouldSignIn = await SignInDialog.show(
          context,
          message: 'You need to sign in to report content.',
        );
        if (shouldSignIn != true && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sign in required to report content'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      if (!context.mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);

      // Show report dialog
      final reported = await ReportDialog.show(
        context,
        targetUri: post.post.uri,
        contentType: 'post',
      );

      if ((reported ?? false) && context.mounted) {
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
    } else if (action == 'delete') {
      // Prevent multiple taps - set flag immediately before dialog
      if (_isDeleting) {
        return;
      }
      setState(() => _isDeleting = true);

      // Check authentication
      final authProvider = context.read<AuthProvider>();
      if (!authProvider.isAuthenticated) {
        setState(() => _isDeleting = false);
        return;
      }

      // Show confirmation dialog
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

      if (confirmed != true || !context.mounted) {
        if (mounted) {
          setState(() => _isDeleting = false);
        }
        return;
      }

      try {
        await HapticFeedback.lightImpact();
      } on PlatformException catch (e) {
        if (kDebugMode) {
          debugPrint('Haptics not supported: $e');
        }
      }

      if (!context.mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);

      // Shared app-wide API client (owned by main.dart) — do not dispose
      final apiService = context.read<CovesApiService>();

      try {
        await apiService.deletePost(uri: post.post.uri);

        if (context.mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Post deleted'),
              behavior: SnackBarBehavior.floating,
            ),
          );

          // Notify parent to handle post removal from feed
          onDeleted?.call();
        }
      } on NetworkException catch (e) {
        if (kDebugMode) {
          debugPrint('Network error deleting post: $e');
        }
        if (context.mounted) {
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
        if (context.mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Post not found. It may have already been deleted.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } on ApiException catch (e) {
        if (kDebugMode) {
          debugPrint('Failed to delete post: $e');
        }
        if (context.mounted) {
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
        if (context.mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Could not delete post. Please try again.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isDeleting = false);
        }
      }
    }
  }

  Future<void> _handleVote(
    BuildContext context,
    VoteProvider voteProvider, {
    required String direction,
  }) async {
    final authProvider = context.read<AuthProvider>();
    if (!authProvider.isAuthenticated) {
      final shouldSignIn = await SignInDialog.show(
        context,
        message: 'You need to sign in to vote on posts.',
      );

      if ((shouldSignIn ?? false) && context.mounted) {
        if (kDebugMode) {
          debugPrint('Navigate to sign-in screen');
        }
      }
      return;
    }

    final messenger = ScaffoldMessenger.of(context);

    // Do not delay VoteProvider's per-subject lock on non-essential haptics.
    HapticFeedback.lightImpact().ignore();

    try {
      await voteProvider.toggleVote(
        postUri: post.post.uri,
        postCid: post.post.cid,
        direction: direction,
      );
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to toggle vote: $e');
      }
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(ErrorMessage.vote(e)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final compactActions = MediaQuery.sizeOf(context).width <= 340;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Left side: Three dots menu and share
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Three dots menu button
            Consumer3<
              CommunitySubscriptionProvider,
              AuthProvider,
              BlockProvider
            >(
              builder:
                  (
                    context,
                    subscriptionProvider,
                    authProvider,
                    blockProvider,
                    child,
                  ) {
                    final communityDid = post.post.community.did;
                    final communityName = post.post.community.name;
                    final isSubscribed = subscriptionProvider.isSubscribed(
                      communityDid,
                    );
                    final isPending = subscriptionProvider.isPending(
                      communityDid,
                    );
                    final isPostAuthor =
                        authProvider.did == post.post.author.did;
                    final authorDid = post.post.author.did;
                    final authorHandle = post.post.author.handle;
                    final isUserBlocked = blockProvider.isUserBlocked(
                      authorDid,
                    );
                    final isUserBlockPending = blockProvider.isUserBlockPending(
                      authorDid,
                    );
                    final isCommunityBlocked = blockProvider.isCommunityBlocked(
                      communityDid,
                    );
                    final isCommunityBlockPending = blockProvider
                        .isCommunityBlockPending(communityDid);
                    // TODO: Set to true when the user is the community owner.
                    // CommunityRef currently lacks an owner/creator DID field,
                    // so we cannot determine ownership from post data alone.
                    const isCommunityOwner = false;

                    return MenuAnchor(
                      style: MenuStyle(
                        backgroundColor: const WidgetStatePropertyAll(
                          AppColors.backgroundSecondary,
                        ),
                        shape: WidgetStatePropertyAll(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      menuChildren: [
                        MenuItemButton(
                          onPressed: isPending
                              ? null
                              : () => _handleMenuAction(context, 'subscribe'),
                          leadingIcon: isPending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  isSubscribed
                                      ? Icons.remove_circle_outline
                                      : Icons.add_circle_outline,
                                  size: 20,
                                ),
                          trailingIcon: isSubscribed && !isPending
                              ? const Icon(
                                  Icons.check,
                                  color: AppColors.primary,
                                  size: 20,
                                )
                              : null,
                          child: Text(
                            isPending
                                ? (isSubscribed
                                      ? 'Unsubscribing...'
                                      : 'Subscribing...')
                                : (isSubscribed
                                      ? 'Unsubscribe from !$communityName'
                                      : 'Subscribe to !$communityName'),
                          ),
                        ),
                        // Block community option (hidden for community owners)
                        if (!isCommunityOwner)
                          buildBlockMenuItem(
                            isBlocked: isCommunityBlocked,
                            isPending: isCommunityBlockPending,
                            label: isCommunityBlocked
                                ? 'Unblock !$communityName'
                                : 'Block !$communityName',
                            onPressed: () =>
                                _handleMenuAction(context, 'blockCommunity'),
                          ),
                        // Block user option (except own posts)
                        if (!isPostAuthor)
                          buildBlockMenuItem(
                            isBlocked: isUserBlocked,
                            isPending: isUserBlockPending,
                            label: isUserBlocked
                                ? 'Unblock @$authorHandle'
                                : 'Block @$authorHandle',
                            onPressed: () =>
                                _handleMenuAction(context, 'blockUser'),
                          ),
                        // Report option (for all authenticated users,
                        // except own posts)
                        if (!isPostAuthor)
                          MenuItemButton(
                            onPressed: () =>
                                _handleMenuAction(context, 'report'),
                            leadingIcon: const Icon(
                              Icons.flag_outlined,
                              size: 20,
                            ),
                            child: const Text('Report post'),
                          ),
                        // Delete option (only for post author)
                        if (isPostAuthor)
                          MenuItemButton(
                            onPressed: () =>
                                _handleMenuAction(context, 'delete'),
                            leadingIcon: const Icon(
                              Icons.delete_outline,
                              size: 20,
                              color: Colors.red,
                            ),
                            child: const Text(
                              'Delete post',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                      ],
                      builder: (context, controller, child) {
                        return IconButton(
                          icon: Icon(
                            Icons.more_horiz,
                            size: 20,
                            color: AppColors.textPrimary.withValues(alpha: 0.6),
                          ),
                          tooltip: 'Post options',
                          onPressed: () {
                            if (controller.isOpen) {
                              controller.close();
                            } else {
                              controller.open();
                            }
                          },
                        );
                      },
                    );
                  },
            ),

            // Share button
            const ShareButton(tooltip: 'Share post'),
          ],
        ),

        // Right side: Comment and voting
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Comment button (hidden in detail view)
            if (showCommentButton) ...[
              Builder(
                builder: (context) {
                  final count = post.post.stats.commentCount;
                  final commentText = count == 1 ? 'comment' : 'comments';
                  return Semantics(
                    button: true,
                    label: 'View $count $commentText',
                    child: InkWell(
                      onTap: () {
                        // Navigate to post detail screen (ALL post types)
                        final encodedUri = Uri.encodeComponent(post.post.uri);
                        context.push('/post/$encodedUri', extra: post);
                      },
                      child: SizedBox(
                        width: compactActions ? 48 : null,
                        height: 48,
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: compactActions ? 0 : 12,
                          ),
                          child: Row(
                            mainAxisSize: compactActions
                                ? MainAxisSize.max
                                : MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ReplyIcon(
                                color: AppColors.textPrimary.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                              if (!compactActions) ...[
                                const SizedBox(width: 5),
                                Text(
                                  DisplayUtils.formatCount(count),
                                  style: TextStyle(
                                    color: AppColors.textPrimary.withValues(
                                      alpha: 0.6,
                                    ),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
            ],

            // Vote group
            Consumer<VoteProvider>(
              builder: (context, voteProvider, child) {
                final isLiked = voteProvider.isLiked(post.post.uri);
                final voteState = voteProvider.getVoteState(post.post.uri);
                final isDownvoted =
                    voteState != null &&
                    voteState.direction == 'down' &&
                    !voteState.deleted;
                final isPending = voteProvider.isPending(post.post.uri);
                final adjustedScore = voteProvider.getAdjustedScore(
                  post.post.uri,
                  post.post.stats.score,
                );
                final neutralColor = AppColors.textPrimary.withValues(
                  alpha: 0.6,
                );
                final downvoteLabel = isDownvoted
                    ? 'Remove downvote'
                    : 'Downvote post';

                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      button: true,
                      enabled: !isPending,
                      label: isLiked ? 'Remove upvote' : 'Upvote post',
                      value: 'Score $adjustedScore',
                      child: InkWell(
                        onTap: isPending
                            ? null
                            : () => _handleVote(
                                context,
                                voteProvider,
                                direction: 'up',
                              ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                AnimatedHeartIcon(
                                  isLiked: isLiked,
                                  color: neutralColor,
                                  likedColor: AppColors.voteLiked,
                                ),
                                const SizedBox(width: 5),
                                ExcludeSemantics(
                                  child: AnimatedVoteCount(
                                    count: adjustedScore,
                                    key: ValueKey(
                                      'vote-count:${post.post.uri}',
                                    ),
                                    style: TextStyle(
                                      color: isLiked
                                          ? AppColors.voteLiked
                                          : neutralColor,
                                      fontSize: 13,
                                      fontWeight: isLiked
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Tooltip(
                      message: downvoteLabel,
                      excludeFromSemantics: true,
                      child: Semantics(
                        button: true,
                        enabled: !isPending,
                        label: downvoteLabel,
                        value: 'Score $adjustedScore',
                        child: InkWell(
                          onTap: isPending
                              ? null
                              : () => _handleVote(
                                  context,
                                  voteProvider,
                                  direction: 'down',
                                ),
                          child: SizedBox.square(
                            dimension: 48,
                            child: Center(
                              child: DownvoteIcon(
                                key: ValueKey('downvote:${post.post.uri}'),
                                color: isDownvoted
                                    ? AppColors.teal
                                    : neutralColor,
                                isDownvoted: isDownvoted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}
