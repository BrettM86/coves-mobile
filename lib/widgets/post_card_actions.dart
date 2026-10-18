import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../models/post.dart';
import '../providers/auth_provider.dart';
import '../providers/vote_provider.dart';
import '../utils/display_utils.dart';
import '../utils/error_messages.dart';
import '../utils/post_detail_route.dart';
import '../utils/post_web_link.dart';
import '../utils/web_link_builder.dart';
import 'animated_vote_count.dart';
import 'icons/animated_heart_icon.dart';
import 'icons/downvote_icon.dart';
import 'icons/reply_icon.dart';
import 'post_options_menu.dart';
import 'share_button.dart';
import 'sign_in_dialog.dart';

/// Action buttons row for post cards
///
/// Displays menu, share, comment, and vote buttons with proper
/// authentication handling and optimistic updates.
class PostCardActions extends StatefulWidget {
  const PostCardActions({
    required this.post,
    required this.sessionStamp,
    this.showCommentButton = true,
    super.key,
  });

  final FeedViewPost post;
  final bool showCommentButton;

  /// The session key [post] was loaded under, from the surface that loaded
  /// it; null for a surface that offers no admin tools, which the gate
  /// denies.
  final Object? sessionStamp;

  @override
  State<PostCardActions> createState() => _PostCardActionsState();
}

class _PostCardActionsState extends State<PostCardActions> {
  FeedViewPost get post => widget.post;
  bool get showCommentButton => widget.showCommentButton;

  /// The post's link on the web client, shared from here. Null
  /// when the post's at-URI yields no canonical URL.
  String? get _postWebUrl => post.post.webUrl(WebLinkBuilder.current());

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
            PostOptionsMenu(
              post: post,
              sessionStamp: widget.sessionStamp,
              anchorBuilder: (context, controller) => IconButton(
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
              ),
            ),

            // Share button
            ShareButton(url: _postWebUrl, tooltip: 'Share post'),
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
                        pushPostDetail(
                          context,
                          post: post,
                          sessionStamp: widget.sessionStamp,
                        );
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
            // Selects this post's vote state only: VoteProvider notifies on
            // every vote anywhere, and a plain Consumer rebuilt the vote row
            // of every card on screen (and in the kept-alive tabs) for it.
            Selector<VoteProvider, (bool, bool, bool, int)>(
              selector: (_, voteProvider) {
                final uri = post.post.uri;
                final voteState = voteProvider.getVoteState(uri);
                return (
                  voteProvider.isLiked(uri),
                  voteState != null &&
                      voteState.direction == 'down' &&
                      !voteState.deleted,
                  voteProvider.isPending(uri),
                  voteProvider.getAdjustedScore(uri, post.post.stats.score),
                );
              },
              builder: (context, vote, child) {
                final (isLiked, isDownvoted, isPending, adjustedScore) = vote;
                final voteProvider = context.read<VoteProvider>();
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
