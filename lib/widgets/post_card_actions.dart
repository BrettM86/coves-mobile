import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../constants/app_colors.dart';
import '../models/post.dart';
import '../providers/auth_provider.dart';
import '../providers/vote_provider.dart';
import '../utils/date_time_utils.dart';
import 'icons/animated_heart_icon.dart';
import 'icons/share_icon.dart';
import 'sign_in_dialog.dart';

/// Action buttons row for post cards
///
/// Displays menu, share, comment, and like buttons with proper
/// authentication handling and optimistic updates.
class PostCardActions extends StatelessWidget {
  const PostCardActions({
    required this.post,
    this.showCommentButton = true,
    super.key,
  });

  final FeedViewPost post;
  final bool showCommentButton;

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
            Semantics(
              button: true,
              label: 'Post options menu',
              child: InkWell(
                onTap: () {
                  // TODO: Show post options menu
                  if (kDebugMode) {
                    debugPrint('Menu button tapped for post');
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                  child: Icon(
                    Icons.more_horiz,
                    size: 20,
                    color: AppColors.textPrimary.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),

            // Share button
            Semantics(
              button: true,
              label: 'Share post',
              child: InkWell(
                onTap: () async {
                  // Add haptic feedback
                  await HapticFeedback.lightImpact();

                  // Share post title and URI
                  final postUri = post.post.uri;
                  final title = post.post.title ?? 'Check out this post';
                  await Share.share('$title\n\n$postUri', subject: title);
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
                              color:
                                  AppColors.textPrimary.withValues(
                                    alpha: 0.6,
                                  ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              DateTimeUtils.formatCount(count),
                              style: TextStyle(
                                color:
                                    AppColors.textPrimary.withValues(
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

                      // Light haptic feedback on both like and unlike
                      await HapticFeedback.lightImpact();

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
                        // TODO: Show error snackbar
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
