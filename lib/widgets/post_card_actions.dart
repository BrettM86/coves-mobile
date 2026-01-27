import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../models/post.dart';
import '../providers/auth_provider.dart';
import '../providers/community_subscription_provider.dart';
import '../providers/vote_provider.dart';
import '../services/api_exceptions.dart';
import '../services/coves_api_service.dart';
import '../utils/date_time_utils.dart';
import 'icons/animated_heart_icon.dart';
import 'icons/share_icon.dart';
import 'sign_in_dialog.dart';

/// Action buttons row for post cards
///
/// Displays menu, share, comment, and like buttons with proper
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
      // Check authentication
      final authProvider = context.read<AuthProvider>();
      if (!authProvider.isAuthenticated) {
        if (!context.mounted) return;
        final shouldSignIn = await SignInDialog.show(
          context,
          message: 'You need to sign in to subscribe to communities.',
        );
        if ((shouldSignIn ?? false) && context.mounted) {
          if (kDebugMode) {
            debugPrint('Navigate to sign-in screen');
          }
        }
        return;
      }

      // Toggle subscription
      try {
        await HapticFeedback.lightImpact();
      } on PlatformException {
        // Haptics not supported
      }

      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final subscriptionProvider =
          context.read<CommunitySubscriptionProvider>();

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
    } else if (action == 'delete') {
      // Prevent multiple taps - set flag immediately before dialog
      if (_isDeleting) return;
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
        if (mounted) setState(() => _isDeleting = false);
        return;
      }

      try {
        await HapticFeedback.lightImpact();
      } on PlatformException catch (e) {
        if (kDebugMode) {
          debugPrint('Haptics not supported: $e');
        }
      }

      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);

      final apiService = CovesApiService(
        tokenGetter: authProvider.getAccessToken,
        tokenRefresher: authProvider.refreshToken,
        signOutHandler: authProvider.signOut,
      );

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
              content: Text('Post not found. It may have already been deleted.'),
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
        apiService.dispose();
        if (mounted) {
          setState(() => _isDeleting = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Left side: Three dots menu and share
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Three dots menu button
            Consumer2<CommunitySubscriptionProvider, AuthProvider>(
              builder: (context, subscriptionProvider, authProvider, child) {
                final communityDid = post.post.community.did;
                final communityName = post.post.community.name;
                final isSubscribed =
                    subscriptionProvider.isSubscribed(communityDid);
                final isPending = subscriptionProvider.isPending(communityDid);
                final isPostAuthor =
                    authProvider.did == post.post.author.did;

                return PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_horiz,
                    size: 20,
                    color: AppColors.textPrimary.withValues(alpha: 0.6),
                  ),
                  tooltip: 'Post options',
                  color: AppColors.backgroundSecondary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onSelected: (action) => _handleMenuAction(context, action),
                  itemBuilder: (context) => [
                    PopupMenuItem<String>(
                      value: 'subscribe',
                      enabled: !isPending,
                      child: Row(
                        children: [
                          if (isPending)
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          else
                            Icon(
                              isSubscribed
                                  ? Icons.remove_circle_outline
                                  : Icons.add_circle_outline,
                              size: 20,
                            ),
                          const SizedBox(width: 12),
                          Expanded(
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
                          if (isSubscribed && !isPending)
                            const Icon(
                              Icons.check,
                              color: AppColors.primary,
                              size: 20,
                            ),
                        ],
                      ),
                    ),
                    // Delete option (only for post author)
                    if (isPostAuthor)
                      const PopupMenuItem<String>(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline,
                              size: 20,
                              color: Colors.red,
                            ),
                            SizedBox(width: 12),
                            Text(
                              'Delete post',
                              style: TextStyle(color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),

            // Share button
            Semantics(
              button: true,
              label: 'Share post',
              child: InkWell(
                onTap: () async {
                  try {
                    await HapticFeedback.lightImpact();
                  } on PlatformException {
                    // Haptics not supported on this platform - ignore
                  }

                  if (!context.mounted) {
                    return;
                  }

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Share feature coming soon!'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                  child: ShareIcon(
                    color: AppColors.textPrimary.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
          ],
        ),

        // Right side: Comment and heart
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
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 20,
                              color: AppColors.textPrimary.withValues(
                                alpha: 0.6,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              DateTimeUtils.formatCount(count),
                              style: TextStyle(
                                color: AppColors.textPrimary.withValues(
                                  alpha: 0.6,
                                ),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
            ],

            // Heart button
            Consumer<VoteProvider>(
              builder: (context, voteProvider, child) {
                final isLiked = voteProvider.isLiked(post.post.uri);
                final adjustedScore = voteProvider.getAdjustedScore(
                  post.post.uri,
                  post.post.stats.score,
                );

                return Semantics(
                  button: true,
                  label:
                      isLiked
                          ? 'Unlike post, $adjustedScore '
                              '${adjustedScore == 1 ? "like" : "likes"}'
                          : 'Like post, $adjustedScore '
                              '${adjustedScore == 1 ? "like" : "likes"}',
                  child: InkWell(
                    onTap: () async {
                      // Check authentication
                      final authProvider = context.read<AuthProvider>();
                      if (!authProvider.isAuthenticated) {
                        // Show sign-in dialog
                        final shouldSignIn = await SignInDialog.show(
                          context,
                          message: 'You need to sign in to like posts.',
                        );

                        if ((shouldSignIn ?? false) && context.mounted) {
                          // TODO: Navigate to sign-in screen
                          if (kDebugMode) {
                            debugPrint('Navigate to sign-in screen');
                          }
                        }
                        return;
                      }

                      // Capture messenger before async gap
                      final messenger = ScaffoldMessenger.of(context);

                      // Light haptic feedback on both like and unlike
                      try {
                        await HapticFeedback.lightImpact();
                      } on PlatformException {
                        // Haptics not supported on this platform - ignore
                      }

                      // Toggle vote with optimistic update
                      try {
                        await voteProvider.toggleVote(
                          postUri: post.post.uri,
                          postCid: post.post.cid,
                        );
                      } on Exception catch (e) {
                        if (kDebugMode) {
                          debugPrint('Failed to toggle vote: $e');
                        }
                        if (context.mounted) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Could not update your vote. Please try again.',
                              ),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedHeartIcon(
                            isLiked: isLiked,
                            color: AppColors.textPrimary.withValues(alpha: 0.6),
                            likedColor: const Color(0xFFFF0033),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            DateTimeUtils.formatCount(adjustedScore),
                            style: TextStyle(
                              color: AppColors.textPrimary.withValues(
                                alpha: 0.6,
                              ),
                              fontSize: 13,
                              fontWeight:
                                  isLiked ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}
