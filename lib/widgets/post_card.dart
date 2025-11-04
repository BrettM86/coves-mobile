import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../models/post.dart';
import '../providers/auth_provider.dart';
import '../providers/vote_provider.dart';
import '../utils/date_time_utils.dart';
import 'icons/animated_heart_icon.dart';
import 'icons/reply_icon.dart';
import 'icons/share_icon.dart';
import 'sign_in_dialog.dart';

/// Post card widget for displaying feed posts
///
/// Displays a post with:
/// - Community and author information
/// - Post title and text content
/// - External embed (link preview with image)
/// - Action buttons (share, comment, like)
///
/// The [currentTime] parameter allows passing the current time for
/// time-ago calculations, enabling:
/// - Periodic updates of time strings
/// - Deterministic testing without DateTime.now()
class PostCard extends StatelessWidget {
  const PostCard({required this.post, this.currentTime, super.key});

  final FeedViewPost post;
  final DateTime? currentTime;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Community and author info
            Row(
              children: [
                // Community avatar placeholder
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Center(
                    child: Text(
                      post.post.community.name[0].toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'c/${post.post.community.name}',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '@${post.post.author.handle}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                // Time ago
                Text(
                  DateTimeUtils.formatTimeAgo(
                    post.post.createdAt,
                    currentTime: currentTime,
                  ),
                  style: TextStyle(
                    color: AppColors.textPrimary.withValues(alpha: 0.5),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Post title
            if (post.post.title != null) ...[
              Text(
                post.post.title!,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],

            // Spacing after title (only if we have content below)
            if (post.post.title != null &&
                (post.post.embed?.external != null ||
                    post.post.text.isNotEmpty))
              const SizedBox(height: 8),

            // Embed (link preview)
            if (post.post.embed?.external != null) ...[
              _EmbedCard(embed: post.post.embed!.external!),
              const SizedBox(height: 8),
            ],

            // Post text body preview
            if (post.post.text.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.backgroundSecondary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  post.post.text,
                  style: TextStyle(
                    color: AppColors.textPrimary.withValues(alpha: 0.7),
                    fontSize: 13,
                    height: 1.4,
                  ),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],

            // Reduced spacing before action buttons
            const SizedBox(height: 4),

            // Action buttons row
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Share button
                InkWell(
                  onTap: () {
                    // TODO: Handle share interaction with backend
                    if (kDebugMode) {
                      debugPrint('Share button tapped for post');
                    }
                  },
                  child: Padding(
                    // Increased padding for better touch targets
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: ShareIcon(
                      color: AppColors.textPrimary.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Comment button
                InkWell(
                  onTap: () {
                    // TODO: Navigate to post detail/comments screen
                    if (kDebugMode) {
                      debugPrint('Comment button tapped for post');
                    }
                  },
                  child: Padding(
                    // Increased padding for better touch targets
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ReplyIcon(
                          color: AppColors.textPrimary.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          DateTimeUtils.formatCount(
                            post.post.stats.commentCount,
                          ),
                          style: TextStyle(
                            color: AppColors.textPrimary.withValues(alpha: 0.6),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Heart button
                Consumer<VoteProvider>(
                  builder: (context, voteProvider, child) {
                    final isLiked = voteProvider.isLiked(post.post.uri);
                    final adjustedScore = voteProvider.getAdjustedScore(
                      post.post.uri,
                      post.post.stats.score,
                    );

                    return InkWell(
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
                        // Increased padding for better touch targets
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedHeartIcon(
                              isLiked: isLiked,
                              color: AppColors.textPrimary
                                  .withValues(alpha: 0.6),
                              likedColor: const Color(0xFFFF0033),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              DateTimeUtils.formatCount(adjustedScore),
                              style: TextStyle(
                                color: AppColors.textPrimary
                                    .withValues(alpha: 0.6),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Embed card widget for displaying link previews
///
/// Shows a thumbnail image for external embeds with loading and error states.
class _EmbedCard extends StatelessWidget {
  const _EmbedCard({required this.embed});

  final ExternalEmbed embed;

  @override
  Widget build(BuildContext context) {
    // Only show image if thumbnail exists
    if (embed.thumb == null) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: CachedNetworkImage(
        imageUrl: embed.thumb!,
        width: double.infinity,
        height: 180,
        fit: BoxFit.cover,
        placeholder:
            (context, url) => Container(
              width: double.infinity,
              height: 180,
              color: AppColors.background,
              child: const Center(
                child: CircularProgressIndicator(
                  color: AppColors.loadingIndicator,
                ),
              ),
            ),
        errorWidget: (context, url, error) {
          if (kDebugMode) {
            debugPrint('❌ Image load error: $error');
            debugPrint('URL: $url');
          }
          return Container(
            width: double.infinity,
            height: 180,
            color: AppColors.background,
            child: const Icon(
              Icons.broken_image,
              color: AppColors.loadingIndicator,
              size: 48,
            ),
          );
        },
      ),
    );
  }
}
