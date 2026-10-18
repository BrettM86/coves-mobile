import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../constants/moderation_constants.dart';
import '../constants/threading_colors.dart';
import '../models/comment.dart';
import '../models/moderation.dart';
import '../models/moderation_subject_state.dart';
import '../models/post.dart';
import '../providers/auth_provider.dart';
import '../providers/block_provider.dart';
import '../providers/comments_provider.dart';
import '../providers/viewer_authority_provider.dart';
import '../providers/vote_provider.dart';
import '../services/admin_moderation_flow.dart';
import '../services/admin_tools_gate.dart';
import '../services/api_exceptions.dart';
import '../services/coves_api_service.dart';
import '../services/moderation_errors.dart';
import '../utils/copy_link.dart';
import '../utils/date_time_utils.dart';
import '../utils/error_messages.dart';
import '../utils/post_web_link.dart';
import '../utils/removal_copy.dart';
import '../utils/share_link.dart';
import '../utils/web_link_builder.dart';
import 'animated_vote_count.dart';
import 'block_action_helpers.dart';
import 'icons/animated_heart_icon.dart';
import 'icons/downvote_icon.dart';
import 'icons/share_icon.dart';
import 'moderation/moderation_action_sheet.dart';
import 'moderation/moderation_failure_decision.dart';
import 'report_dialog.dart';
import 'rich_text_renderer.dart';
import 'sign_in_dialog.dart';
import 'tappable_author.dart';
import 'user_avatar.dart';

/// Comment card widget for displaying individual comments
///
/// Displays a comment with:
/// - Author information (avatar, handle, timestamp)
/// - Comment content (supports facets for links/mentions)
/// - Upvote and downvote controls with optimistic updates via VoteProvider
/// - Visual threading indicator based on nesting depth
/// - Tap-to-reply functionality via [onTap] callback
/// - Long-press to collapse thread via [onLongPress] callback
/// - Three-dots menu with delete option (for comment author only)
///
/// ## Deleted Comments
///
/// When [CommentView.isTombstoned] is true, the card displays the
/// placeholder copy from [RemovalCopy.forComment], which names who deleted
/// or removed the comment. The vote controls, actions and [onTap] are
/// dropped, and author information is hidden to preserve privacy.
///
/// The [currentTime] parameter allows passing the current time for
/// time-ago calculations, enabling periodic updates and testing.
///
/// When [isCollapsed] is true, displays a badge showing [collapsedCount]
/// hidden replies on the threading indicator bar.
class CommentCard extends StatefulWidget {
  const CommentCard({
    required this.comment,
    required this.sessionStamp,
    this.depth = 0,
    this.currentTime,
    this.onTap,
    this.onLongPress,
    this.isCollapsed = false,
    this.collapsedCount = 0,
    this.onDelete,
    this.isHighlighted = false,
    this.parentPost,
    this.reloadAfterModeration,
    this.votingEnabled = true,
    super.key,
  }) : assert(
         sessionStamp == null || reloadAfterModeration != null,
         'A surface that offers admin tools must reload after moderation.',
       );

  final CommentView comment;

  /// The session key [comment] was loaded under, from the surface that
  /// loaded it; null for a surface that offers no admin tools, which the
  /// gate denies.
  final Object? sessionStamp;

  /// Reloads what the surface shows when a moderation action finds the
  /// comment changed or gone on the server, completing with whether the
  /// reload landed. Supplied by every surface that passes a [sessionStamp];
  /// the removal itself is recorded on the [CommentsProvider] above the
  /// card.
  final Future<bool> Function()? reloadAfterModeration;

  /// The post this comment belongs to, when the surface showing the comment
  /// has it loaded. Supplies the community and post author a comment
  /// permalink needs.
  final PostView? parentPost;
  final int depth;
  final DateTime? currentTime;

  /// Callback when the comment is tapped (for reply functionality)
  final VoidCallback? onTap;

  /// Callback when the comment is long-pressed (for collapse functionality)
  final VoidCallback? onLongPress;

  /// Whether this comment's thread is currently collapsed
  final bool isCollapsed;

  /// Number of replies hidden when collapsed
  final int collapsedCount;

  /// Callback when the comment is deleted
  final Future<void> Function(String commentUri)? onDelete;

  /// Tints the card so a comment the user navigated to directly (e.g. from
  /// their profile) stands out from its siblings.
  final bool isHighlighted;

  /// Whether the vote buttons act. False shows them disabled, for a comment
  /// whose vote state [VoteProvider] may not hold for the signed-in account.
  final bool votingEnabled;

  @override
  State<CommentCard> createState() => _CommentCardState();
}

class _CommentCardState extends State<CommentCard> {
  bool _isDeleting = false;

  /// The options button, which the share popover anchors on.
  final GlobalKey _menuTriggerKey = GlobalKey();

  CommentView get comment => widget.comment;
  int get depth => widget.depth;
  DateTime? get currentTime => widget.currentTime;
  VoidCallback? get onTap => widget.onTap;
  VoidCallback? get onLongPress => widget.onLongPress;
  bool get isCollapsed => widget.isCollapsed;
  int get collapsedCount => widget.collapsedCount;
  Future<void> Function(String commentUri)? get onDelete => widget.onDelete;

  @override
  Widget build(BuildContext context) {
    // Placeholders carry no real author (null, or `handle.invalid`).
    // Capture locally so Dart can promote it to non-null below.
    final author = comment.author;
    // A placeholder has nothing to reply to, so its taps are ignored; this
    // guard covers every screen that passes onTap.
    final onTap = comment.isTombstoned ? null : this.onTap;

    // All comments get at least 1 threading line (depth + 1)
    final threadingLineCount = depth + 1;
    // Calculate left padding: (6px per line) + 14px base padding
    final leftPadding = (threadingLineCount * 6.0) + 14.0;
    // Border should start after the threading lines (add 2px to clear
    // the stroke width)
    final borderLeftOffset = (threadingLineCount * 6.0) + 2.0;

    return Semantics(
      // A placeholder ignores taps, so it is not announced as a button.
      button: !comment.isTombstoned,
      hint: onLongPress != null
          ? (isCollapsed
                ? 'Double tap and hold to expand thread'
                : 'Double tap and hold to collapse thread')
          : null,
      child: GestureDetector(
        onLongPress: onLongPress != null
            ? () async {
                try {
                  await HapticFeedback.mediumImpact();
                } on PlatformException catch (e) {
                  if (kDebugMode) {
                    debugPrint('Haptics not supported: $e');
                  }
                }
                onLongPress!();
              }
            : null,
        child: InkWell(
          onTap: onTap != null
              ? () async {
                  try {
                    await HapticFeedback.mediumImpact();
                  } on PlatformException catch (e) {
                    if (kDebugMode) {
                      debugPrint('Haptics not supported: $e');
                    }
                  }
                  onTap();
                }
              : null,
          child: Container(
            decoration: BoxDecoration(
              color: widget.isHighlighted
                  ? AppColors.primary.withValues(alpha: 0.08)
                  : AppColors.background,
            ),
            child: Stack(
              children: [
                // Threading indicators - vertical lines showing
                // nesting ancestry
                Positioned.fill(
                  child: CustomPaint(
                    painter: _CommentDepthPainter(depth: threadingLineCount),
                  ),
                ),
                // Bottom border
                // (starts after threading lines, not overlapping them)
                Positioned(
                  left: borderLeftOffset,
                  right: 0,
                  bottom: 0,
                  child: Container(height: 1, color: AppColors.border),
                ),
                // Comment content with depth-based left padding
                // Animate height changes when collapsing/expanding
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOutCubic,
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      leftPadding,
                      12,
                      16,
                      isCollapsed || comment.isTombstoned ? 12 : 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Author info row
                        Row(
                          children: [
                            // Author avatar and handle (or placeholder for
                            // deleted). The author == null arm is already
                            // covered by isTombstoned; spelling it out lets
                            // Dart promote author to non-null below.
                            // The author cluster takes the slack the Spacer
                            // used to hold, so the timestamp still sits hard
                            // right while the handle now has a bounded width
                            // to ellipsize into. atProto encourages domain
                            // handles, and an unbounded one overflowed this
                            // row on an ordinary phone.
                            if (author == null || comment.isTombstoned)
                              // Show deletion reason as placeholder
                              Expanded(
                                child: Text(
                                  RemovalCopy.forComment(
                                    deletionReason: comment.deletionReason,
                                    moderation: comment.moderation,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors.textPrimary.withValues(
                                      alpha: 0.5,
                                    ),
                                    fontSize: 13,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              )
                            else
                              // Show tappable author for active comments
                              Expanded(
                                child: TappableAuthor(
                                  authorDid: author.did,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Author avatar
                                      _buildAuthorAvatar(author),
                                      const SizedBox(width: 8),
                                      // The handle yields, never the avatar or
                                      // the timestamp - see the note above.
                                      Flexible(
                                        child: Text(
                                          '@${author.handle}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: AppColors.textPrimary
                                                .withValues(
                                                  alpha: isCollapsed
                                                      ? 0.7
                                                      : 0.5,
                                                ),
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            // Keeps an ellipsized handle from butting up
                            // against the timestamp. Invisible at widths where
                            // the row was already clean.
                            const SizedBox(width: 8),
                            // Show collapsed count OR time ago
                            if (isCollapsed && collapsedCount > 0)
                              _buildCollapsedBadge()
                            else
                              Text(
                                DateTimeUtils.formatTimeAgo(
                                  comment.createdAt,
                                  currentTime: currentTime,
                                ),
                                style: TextStyle(
                                  color: AppColors.textPrimary.withValues(
                                    alpha: 0.5,
                                  ),
                                  fontSize: 12,
                                ),
                              ),
                            if (comment.isTombstoned) _buildPlaceholderMenu(),
                          ],
                        ),

                        // Only show content and actions when expanded (skip
                        // for deleted)
                        if (!isCollapsed && !comment.isTombstoned) ...[
                          const SizedBox(height: 8),

                          // Comment content
                          if (comment.content.isNotEmpty) ...[
                            _buildCommentContent(comment),
                            const SizedBox(height: 8),
                          ],

                          // Action buttons (menu and vote)
                          _buildActionButtons(context),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Builds the author avatar widget
  Widget _buildAuthorAvatar(AuthorView author) {
    return UserAvatar(
      name: author.displayName ?? author.handle,
      avatarUrl: author.avatar,
      size: 24,
    );
  }

  /// Builds the compact collapsed badge showing "+X"
  Widget _buildCollapsedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '+$collapsedCount',
        style: TextStyle(
          color: AppColors.primary.withValues(alpha: 0.9),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// Builds the comment content with support for facets
  Widget _buildCommentContent(CommentView comment) {
    return RichTextRenderer(
      text: comment.content,
      facets: comment.contentFacets,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 14,
        height: 1.4,
      ),
    );
  }

  /// Handles menu action selection (report or delete).
  ///
  /// Menu is only visible to authenticated users, so no auth check needed here.
  Future<void> _handleMenuAction(BuildContext context, String action) async {
    if (action == 'blockUser') {
      // Deleted comments have no author to block.
      final author = comment.author;
      if (author == null) {
        return;
      }
      await handleBlockUser(
        context: context,
        authorDid: author.did,
        authorHandle: author.handle,
      );
    } else if (action == 'report') {
      if (!context.mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);

      // Show report dialog
      final reported = await ReportDialog.show(
        context,
        targetUri: comment.uri,
        contentType: 'comment',
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

      // Only proceed if onDelete callback is available
      if (onDelete == null) {
        if (kDebugMode) {
          debugPrint('Delete action triggered but onDelete callback is null');
        }
        setState(() => _isDeleting = false);
        return;
      }

      // Show confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Comment'),
          content: const Text(
            'Are you sure you want to delete this comment? This '
            'cannot be undone.',
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

      try {
        await onDelete!(comment.uri);

        if (context.mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Comment deleted'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } on NetworkException catch (e) {
        if (kDebugMode) {
          debugPrint('Network error deleting comment: $e');
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
          debugPrint('Comment not found: $e');
        }
        if (context.mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Comment not found. It may have already been deleted.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } on ApiException catch (e) {
        if (kDebugMode) {
          debugPrint('Failed to delete comment: $e');
        }
        if (context.mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                e.statusCode == 403
                    ? 'You can only delete your own comments'
                    : 'Could not delete comment. Please try again.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } on Exception catch (e) {
        if (kDebugMode) {
          debugPrint('Failed to delete comment: $e');
        }
        if (context.mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Could not delete comment. Please try again.'),
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

  /// The moderation entries of the comment menu: block and report for another
  /// user's comment, delete for the viewer's own, and remove on either when
  /// [showRemove] says the admin tool is allowed.
  ///
  /// Empty when there is nothing to act on — a signed-out viewer, or a
  /// tombstoned comment. A deleted or removed comment's placeholder carries
  /// only `{did, handle: "handle.invalid"}` as its author, and the action row
  /// is already hidden for it by the same [CommentView.isTombstoned] gate, so
  /// there is nothing to block, report, or delete.
  List<Widget> _buildModerationMenuItems(
    BuildContext context,
    AuthProvider authProvider,
    BlockProvider blockProvider, {
    required bool showRemove,
  }) {
    final author = comment.author;
    if (!authProvider.isAuthenticated ||
        comment.isTombstoned ||
        author == null) {
      return const [];
    }

    final removeItem = MenuItemButton(
      onPressed: () => _removeComment(context),
      leadingIcon: const Icon(
        Icons.delete_outline,
        size: 20,
        color: Colors.red,
      ),
      child: const Text('Remove comment', style: TextStyle(color: Colors.red)),
    );
    final authorDid = author.did;
    final authorHandle = author.handle;
    if (authProvider.did == authorDid) {
      return [
        if (showRemove) removeItem,
        MenuItemButton(
          onPressed: () => _handleMenuAction(context, 'delete'),
          leadingIcon: const Icon(
            Icons.delete_outline,
            size: 20,
            color: Colors.red,
          ),
          child: const Text(
            'Delete comment',
            style: TextStyle(color: Colors.red),
          ),
        ),
      ];
    }

    final isUserBlocked = blockProvider.isUserBlocked(authorDid);
    return [
      buildBlockMenuItem(
        isBlocked: isUserBlocked,
        isPending: blockProvider.isUserBlockPending(authorDid),
        label: isUserBlocked
            ? 'Unblock @$authorHandle'
            : 'Block @$authorHandle',
        onPressed: () => _handleMenuAction(context, 'blockUser'),
      ),
      MenuItemButton(
        onPressed: () => _handleMenuAction(context, 'report'),
        leadingIcon: const Icon(Icons.flag_outlined, size: 20),
        child: const Text('Report comment'),
      ),
      if (showRemove) removeItem,
    ];
  }

  /// Opens the removal sheet for [comment] and applies its outcome: a
  /// confirmed removal becomes the placeholder through the
  /// [CommentsProvider] above the card, a changed or gone comment reloads
  /// through [CommentCard.reloadAfterModeration].
  Future<void> _removeComment(BuildContext context) async {
    final apiService = context.read<CovesApiService>();
    final commentsProvider = context.read<CommentsProvider>();
    final authority = context.read<ViewerAuthorityProvider>();
    final reload = widget.reloadAfterModeration;
    final sessionKey = authority.sessionKey;
    final messenger = ScaffoldMessenger.of(context);
    final subject = StrongRef(uri: comment.uri, cid: comment.cid);
    final flow = AdminModerationFlow(apiService, authority: authority);
    // Anything that lands after the session changed belongs to the previous
    // account and is neither shown nor applied.
    bool sessionChanged() => authority.sessionKey != sessionKey;
    void showMessage(String message) {
      if (messenger.mounted && !sessionChanged()) {
        messenger.showSnackBar(
          SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
        );
      }
    }

    await ModerationActionSheet.show<ModerationFlowResult>(
      context,
      title: 'Remove comment',
      confirmLabel: 'Remove',
      reasons: removalReasons,
      failureMessage: "Couldn't remove this comment. Try again.",
      authority: authority,
      onSubmit: (reason, privateNote) async {
        if (flow.retainedSubmission != null) {
          return (await flow.retry())!;
        }
        return flow.submitRemoval(
          subject: subject,
          reason: reason,
          privateNote: privateNote,
        );
      },
      onResult: (outcome) async {
        if (outcome is ModerationFlowSucceeded) {
          commentsProvider.markCommentRemoved(
            commentUri: subject.uri,
            state: outcome.result.state,
            action: outcome.result.action,
          );
          unawaited(commentsProvider.readBackRemovedComment(subject.uri));
          showMessage(
            outcome.result.outcome == ModerationMutationOutcome.applied
                ? 'Comment removed'
                : 'Comment was already removed',
          );
          return const ModerationSheetDecision();
        }

        return moderationFailureDecision(
          outcome,
          authority: authority,
          showMessage: showMessage,
          resolveStateConflict: (failure) {
            final currentState = failure.currentState;
            if (currentState?.moderation.state != ModerationState.removed) {
              return false;
            }
            commentsProvider.markCommentRemoved(
              commentUri: subject.uri,
              state: currentState!,
            );
            unawaited(commentsProvider.readBackRemovedComment(subject.uri));
            showMessage('Someone else already removed this comment.');
            return true;
          },
          reloadSubject: _reloadThenReport(
            reload,
            showMessage,
            contentChangedMessage:
                'The author edited this comment. Review the new version '
                'before acting.',
          ),
        );
      },
    );
  }

  /// Opens the restore sheet for the removed [comment]'s placeholder. A
  /// restore that leaves the comment visible, or finds it already restored,
  /// drops the local removal on the [CommentsProvider] above the card. Every
  /// accepted restore then reloads through
  /// [CommentCard.reloadAfterModeration], which shows whatever the server
  /// returns.
  Future<void> _restoreComment(BuildContext context) async {
    final apiService = context.read<CovesApiService>();
    final commentsProvider = context.read<CommentsProvider>();
    final authority = context.read<ViewerAuthorityProvider>();
    final reload = widget.reloadAfterModeration;
    final sessionKey = authority.sessionKey;
    final messenger = ScaffoldMessenger.of(context);
    final subjectUri = comment.uri;
    final flow = AdminModerationFlow(apiService, authority: authority);
    // Anything that lands after the session changed belongs to the previous
    // account and is neither shown nor applied.
    bool sessionChanged() => authority.sessionKey != sessionKey;
    void showMessage(String message) {
      if (messenger.mounted && !sessionChanged()) {
        messenger.showSnackBar(
          SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
        );
      }
    }

    await ModerationActionSheet.show<ModerationFlowResult>(
      context,
      title: 'Restore comment',
      confirmLabel: 'Restore',
      reasons: restoreReasons,
      failureMessage: "Couldn't restore this comment. Try again.",
      authority: authority,
      onSubmit: (reason, privateNote) async {
        if (flow.retainedSubmission != null) {
          return (await flow.retry())!;
        }
        return flow.submitRestore(
          subjectUri: subjectUri,
          reason: reason,
          privateNote: privateNote,
        );
      },
      onResult: (outcome) async {
        final restoreOutcome = restoreOutcomeOf(outcome);
        if (restoreOutcome != null) {
          // Only a comment the server shows again drops the local removal:
          // while it stays hidden, the removal still masks snapshots taken
          // before it that no reload replaces.
          if (restoreOutcome == RestoreOutcome.restored ||
              restoreOutcome == RestoreOutcome.notRemoved) {
            commentsProvider.clearCommentRemoval(subjectUri);
          }
          final reloaded = reload != null && await reload();
          showMessage(switch (restoreOutcome) {
            RestoreOutcome.restored when !reloaded =>
              "Comment restored, but couldn't load the latest version. "
                  'Try again.',
            RestoreOutcome.restored => 'Comment restored',
            RestoreOutcome.restoredButDeleted =>
              'Restored, but the author deleted it, so it stays hidden.',
            RestoreOutcome.restoredButUnavailable =>
              "Restored, but it can't be shown right now.",
            RestoreOutcome.notRemoved => 'This is no longer removed.',
          });
          return const ModerationSheetDecision();
        }

        return moderationFailureDecision(
          outcome,
          authority: authority,
          showMessage: showMessage,
          // A conflicting decision changed the removal: show the comment as
          // it is now rather than asking to confirm a restore of a stale
          // view. The sheet closes at once; the message waits for the reload.
          resolveStateConflict: (_) {
            unawaited(() async {
              final reloaded = reload != null && await reload();
              showMessage(
                reloaded
                    ? 'This item changed. Showing the latest version.'
                    : "Couldn't load the latest version. Try again.",
              );
            }());
            return true;
          },
          reloadSubject: _reloadThenReport(
            reload,
            showMessage,
            contentChangedMessage:
                'The author edited this comment. Try restoring again.',
          ),
        );
      },
    );
  }

  /// A `reloadSubject` for [moderationFailureDecision]: reloads through
  /// [reload], then shows [contentChangedMessage] for an edited comment or
  /// the error's own message otherwise.
  ///
  /// Without a reload the stale comment stays shown, so that is reported as
  /// a failed reload rather than as the latest version.
  static Future<void> Function(ModerationError error) _reloadThenReport(
    Future<bool> Function()? reload,
    void Function(String message) showMessage, {
    required String contentChangedMessage,
  }) {
    return (error) async {
      final reloaded = reload != null && await reload();
      if (!reloaded) {
        showMessage("Couldn't load the latest version. Try again.");
      } else if (error.code == ModerationErrorCode.contentChanged) {
        showMessage(contentChangedMessage);
      } else {
        showMessage(error.message);
      }
    };
  }

  /// Builds the three-dots menu for comment actions.
  ///
  /// Share and copy link need no account — a link is public — but need the
  /// parent post the permalink is built under, so they appear only where the
  /// surface showing the comment has it. The moderation items stay
  /// signed-in only, and the menu disappears entirely when neither is
  /// available.
  Widget _buildCommentMenu(BuildContext context) {
    final parentPost = widget.parentPost;

    return Consumer2<AuthProvider, BlockProvider>(
      builder: (context, authProvider, blockProvider, child) {
        final capabilities =
            comment.viewer?.moderation ?? const <ModerationCapability>{};
        // Only a card carrying the token looks the authority up, so trees
        // with no admin tools need not provide it.
        final authority = capabilities.contains(ModerationCapability.remove)
            ? context.watch<ViewerAuthorityProvider>()
            : null;
        final moderationItems = _buildModerationMenuItems(
          context,
          authProvider,
          blockProvider,
          showRemove:
              authority != null &&
              adminToolAllowed(
                capability: ModerationCapability.remove,
                capabilities: capabilities,
                loadedUnderSessionKey: widget.sessionStamp,
                authority: authority,
              ),
        );
        if (parentPost == null && moderationItems.isEmpty) {
          return const SizedBox.shrink();
        }

        final permalink = parentPost == null
            ? null
            : comment.webUrl(WebLinkBuilder.current(), parentPost: parentPost);

        return _buildMenuAnchor(
          menuChildren: [
            if (parentPost != null) ...[
              MenuItemButton(
                // The tapped item is gone by the time the sheet opens, so the
                // popover anchors on the trigger, which stays put.
                onPressed: () => shareLinkFrom(
                  context,
                  permalink,
                  globalRectOf(_menuTriggerKey.currentContext),
                ),
                leadingIcon: const ShareIcon(size: 20),
                child: const Text('Share'),
              ),
              MenuItemButton(
                onPressed: () => copyLinkToClipboard(context, permalink),
                leadingIcon: const Icon(Icons.link, size: 20),
                child: const Text('Copy link'),
              ),
            ],
            ...moderationItems,
          ],
        );
      },
    );
  }

  /// The "Comment options" trigger and the menu it opens with
  /// [menuChildren].
  Widget _buildMenuAnchor({required List<Widget> menuChildren}) {
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(
          AppColors.backgroundSecondary,
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      menuChildren: menuChildren,
      builder: (context, controller, child) {
        return IconButton(
          key: _menuTriggerKey,
          icon: Icon(
            Icons.more_horiz,
            size: 18,
            color: AppColors.textPrimary.withValues(alpha: 0.6),
          ),
          tooltip: 'Comment options',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          style: const ButtonStyle(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
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
  }

  /// The removed placeholder's menu, holding only "Restore comment", when
  /// the restore admin tool is allowed for [comment]; nothing otherwise.
  ///
  /// Reads no [CommentsProvider] while building: a placeholder can be shown
  /// where none is above the card.
  Widget _buildPlaceholderMenu() {
    final capabilities =
        comment.viewer?.moderation ?? const <ModerationCapability>{};
    // Only a card carrying the token looks the authority up, so trees with
    // no admin tools need not provide it.
    if (!capabilities.contains(ModerationCapability.restore)) {
      return const SizedBox.shrink();
    }
    return Builder(
      builder: (context) {
        final allowed = adminToolAllowed(
          capability: ModerationCapability.restore,
          capabilities: capabilities,
          loadedUnderSessionKey: widget.sessionStamp,
          authority: context.watch<ViewerAuthorityProvider>(),
        );
        if (!allowed) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(left: 8),
          child: _buildMenuAnchor(
            menuChildren: [
              MenuItemButton(
                onPressed: () => _restoreComment(context),
                leadingIcon: const Icon(Icons.restore, size: 20),
                child: const Text('Restore comment'),
              ),
            ],
          ),
        );
      },
    );
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
        message: 'You need to sign in to vote on comments.',
      );

      if ((shouldSignIn ?? false) && context.mounted) {
        await context.push('/login');
      }
      return;
    }

    // Do not delay VoteProvider's per-subject lock on non-essential haptics.
    HapticFeedback.lightImpact().ignore();

    try {
      await voteProvider.toggleVote(
        postUri: comment.uri,
        postCid: comment.cid,
        direction: direction,
      );
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to vote on comment: $e');
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorMessage.vote(e)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// Builds the action buttons row (menu and vote controls)
  Widget _buildActionButtons(BuildContext context) {
    // Selects this comment's vote state only, so a vote elsewhere in the
    // thread doesn't rebuild every comment's action row.
    return Selector<VoteProvider, (bool, bool, bool, int)>(
      selector: (_, voteProvider) {
        final uri = comment.uri;
        final voteState = voteProvider.getVoteState(uri);
        return (
          voteProvider.isLiked(uri),
          voteState != null &&
              voteState.direction == 'down' &&
              !voteState.deleted,
          voteProvider.isPending(uri),
          voteProvider.getAdjustedScore(uri, comment.stats.score),
        );
      },
      builder: (context, vote, child) {
        final (isLiked, isDownvoted, isPending, adjustedScore) = vote;
        final canVote = widget.votingEnabled && !isPending;
        final voteProvider = context.read<VoteProvider>();
        final neutralColor = AppColors.textPrimary.withValues(alpha: 0.6);
        final downvoteLabel = isDownvoted
            ? 'Remove downvote'
            : 'Downvote comment';

        return Row(
          children: [
            _buildCommentMenu(context),
            const Spacer(),
            Semantics(
              button: true,
              enabled: canVote,
              label: isLiked ? 'Remove upvote' : 'Upvote comment',
              value: 'Score $adjustedScore',
              child: InkWell(
                onTap: canVote
                    ? () => _handleVote(context, voteProvider, direction: 'up')
                    : null,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedHeartIcon(
                          isLiked: isLiked,
                          size: 16,
                          color: neutralColor,
                          likedColor: AppColors.voteLiked,
                        ),
                        const SizedBox(width: 5),
                        ExcludeSemantics(
                          child: AnimatedVoteCount(
                            count: adjustedScore,
                            key: ValueKey('vote-count:${comment.uri}'),
                            style: TextStyle(
                              color: isLiked
                                  ? AppColors.voteLiked
                                  : neutralColor,
                              fontSize: 12,
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
                enabled: canVote,
                label: downvoteLabel,
                value: 'Score $adjustedScore',
                child: InkWell(
                  onTap: canVote
                      ? () => _handleVote(
                          context,
                          voteProvider,
                          direction: 'down',
                        )
                      : null,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    child: Center(
                      child: DownvoteIcon(
                        key: ValueKey('downvote:${comment.uri}'),
                        size: 16,
                        color: isDownvoted ? AppColors.teal : neutralColor,
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
    );
  }
}

/// Custom painter for drawing comment depth indicator lines
class _CommentDepthPainter extends CustomPainter {
  _CommentDepthPainter({required this.depth});
  final int depth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    // Draw vertical line for each depth level with different colors
    for (var i = 0; i < depth; i++) {
      // Cycle through colors based on depth level
      paint.color = kThreadingColors[i % kThreadingColors.length].withValues(
        alpha: 0.5,
      );

      final xPosition = (i + 1) * 6.0;
      canvas.drawLine(
        Offset(xPosition, 0),
        Offset(xPosition, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_CommentDepthPainter oldDelegate) {
    return oldDelegate.depth != depth;
  }
}
