import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../models/notification.dart';
import '../../utils/community_handle_utils.dart';
import '../../utils/date_time_utils.dart';
import '../../utils/moderation_copy.dart';
import '../community_avatar.dart';
import '../sensitive_content.dart';
import '../user_avatar.dart';
import 'notification_post_card.dart';

const _cardPadding = 12.0;
const _rowHorizontalPadding = 16.0;
const _headerAvatarSize = 32.0;
const _authorAvatarSize = 24.0;
const _headerGap = 10.0;
const _sectionGap = 12.0;
const _authorGap = 8.0;
const _excerptGap = 6.0;
const _bubbleIndent = 16.0;
const _bubbleBorderWidth = 2.0;
const _bubblePadding = 12.0;
const _bubbleVerticalPadding = 8.0;
const _bubbleRadius = 8.0;
const _quoteBorderWidth = 2.0;
const _quotePadding = 12.0;

const _reasonStyle = TextStyle(
  color: AppColors.textPrimary,
  fontSize: 14,
  fontWeight: FontWeight.w500,
);
const _communityStyle = TextStyle(color: AppColors.textSecondary, fontSize: 12);
const _timeStyle = TextStyle(color: AppColors.textSecondary, fontSize: 12);
const _authorStyle = TextStyle(
  color: AppColors.textPrimary,
  fontSize: 14,
  fontWeight: FontWeight.w500,
);
const _handleStyle = TextStyle(color: AppColors.textSecondary, fontSize: 12);
const _excerptStyle = TextStyle(color: AppColors.textPrimary, fontSize: 14);
const _quoteStyle = TextStyle(color: AppColors.textSecondary, fontSize: 14);
const _placeholderStyle = TextStyle(
  color: AppColors.textSecondary,
  fontSize: 14,
  fontStyle: FontStyle.italic,
);

class NotificationReplyCard extends StatelessWidget {
  const NotificationReplyCard({
    super.key,
    required this.notification,
    required this.onTap,
    this.currentTime,
    this.sensitiveContentRevealed = false,
    required this.onSensitiveContentToggle,
  });

  final NotificationView notification;
  final VoidCallback onTap;
  final DateTime? currentTime;
  final bool sensitiveContentRevealed;
  final VoidCallback onSensitiveContentToggle;

  @override
  Widget build(BuildContext context) {
    final rootPost = notification.rootPost;
    final subject = notification.subject;
    final record = notification.record;
    final author = notification.author;
    final rootIsLive = rootPost.status == null;
    final reason = rootIsLive
        ? switch (notification.reason) {
            NotificationReason.postReply => 'Reply to your post',
            NotificationReason.commentReply => 'Reply to your comment',
            NotificationReason.mention => 'Mentioned you',
            NotificationReason.upvote => null,
          }
        : null;
    final community = rootIsLive ? rootPost.community : null;
    final communityHandle = community == null
        ? null
        : CommunityHandleUtils.resolveDisplayHandle(
                name: community.name,
                origin: community.origin,
                handle: community.handle,
              )?.toString() ??
              community.name;
    final createdAt = record?.createdAt;
    final parsedTime = createdAt == null ? null : DateTime.tryParse(createdAt);
    final time = rootIsLive && parsedTime != null
        ? DateTimeUtils.formatTimeAgo(parsedTime, currentTime: currentTime)
        : null;

    // A reply to the viewer's comment quotes that comment, or its
    // placeholder, in place of the post card. A removed root always shows
    // its placeholder post card instead.
    final quotesYourComment =
        rootIsLive &&
        notification.reason == NotificationReason.commentReply &&
        subject != null &&
        moderationSubjectUriKind(subject.uri) ==
            ModerationSubjectKind.comment &&
        (subject.status != null || subject.preview != null);
    final quoteText = quotesYourComment
        ? subject.placeholderCopy ?? subject.preview
        : null;
    final quoteIsSensitive =
        quotesYourComment && subject.status == null && subject.isSensitive;
    final showsPostCard = !quotesYourComment;
    final cardIsSensitive = showsPostCard && rootIsLive && rootPost.isSensitive;
    final cardThumbnail = showsPostCard && rootIsLive
        ? rootPost.thumbnail
        : null;

    final recordExcerpt = record?.placeholderCopy ?? record?.excerpt;
    final isPostMention =
        notification.reason == NotificationReason.mention &&
        record != null &&
        _isPostUri(record.uri);
    // The title position already shows the root's placeholder. Repeat it in
    // the excerpt only when it is a separate fact: a post mention reads both
    // positions from one post, and the server folds a moderator or admin
    // removal of the root into the comment's own state.
    final rootPlaceholder = rootPost.placeholderCopy;
    final repeatsRootPlaceholder =
        rootPlaceholder != null &&
        record != null &&
        record.placeholderCopy == rootPlaceholder &&
        (record.uri == rootPost.uri ||
            rootPost.status == NotificationReferenceStatus.removedByModerator ||
            rootPost.status ==
                NotificationReferenceStatus.removedByServerAdmin);
    // The backend cuts a post mention's excerpt from its title, so an
    // excerpt the title starts with adds nothing.
    final excerptRepeatsTitle =
        isPostMention &&
        record.status == null &&
        recordExcerpt != null &&
        (rootPost.title?.startsWith(recordExcerpt) ?? false);
    final recordShownExcerpt = repeatsRootPlaceholder || excerptRepeatsTitle
        ? null
        : recordExcerpt;

    // Placeholder copy is not content, so only a live reference's own text is
    // ever concealed.
    final excerptIsSensitive =
        record != null &&
        record.status == null &&
        recordShownExcerpt != null &&
        record.isSensitive;
    final rowIsSensitive =
        rootPost.isSensitive ||
        (subject?.isSensitive ?? false) ||
        (record?.isSensitive ?? false);
    final showsSensitiveBanner =
        rowIsSensitive &&
        (cardThumbnail != null ||
            cardIsSensitive ||
            quoteIsSensitive ||
            excerptIsSensitive);
    final concealed = showsSensitiveBanner && !sensitiveContentRevealed;
    final postCardVisible = showsPostCard && !(concealed && cardIsSensitive);
    final quote = concealed && quoteIsSensitive ? null : quoteText;
    final excerpt = concealed && excerptIsSensitive ? null : recordShownExcerpt;
    // A post mention whose excerpt only repeats the title needs no bubble
    // once the post card names the author.
    final showsBubble =
        !(excerptRepeatsTitle &&
            postCardVisible &&
            rootIsLive &&
            rootPost.author?.handle != null) &&
        (author != null || excerpt != null);
    final authorName = author?.name;

    // The unread dot is drawn only, so the label says it first.
    final label = [
      if (!notification.isRead) 'Unread',
      reason,
      communityHandle,
      if (quotesYourComment) quote else if (postCardVisible) rootPost.title,
      if (!rootIsLive) rootPlaceholder,
      if (showsBubble) authorName,
      if (showsBubble) excerpt,
      time,
    ].whereType<String>().join(', ');

    // The row's label speaks for every part it excludes. The banner stays
    // its own activatable node inside the row's button, so toggling it never
    // opens the row and opening the row never toggles it.
    final hasOwnActions = showsSensitiveBanner;
    return Semantics(
      container: hasOwnActions,
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: !hasOwnActions,
      child: Material(
        color: AppColors.background,
        shape: notificationRowShape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          excludeFromSemantics: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: _rowHorizontalPadding,
              vertical: _cardPadding,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (reason != null) ...[
                  ExcludeSemantics(
                    child: Row(
                      children: [
                        if (community != null) ...[
                          CommunityAvatar(
                            name: community.name,
                            avatarUrl: community.avatar,
                            size: _headerAvatarSize,
                          ),
                          const SizedBox(width: _headerGap),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(reason, style: _reasonStyle),
                              if (communityHandle != null)
                                Text(
                                  communityHandle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _communityStyle,
                                ),
                            ],
                          ),
                        ),
                        if (time != null || !notification.isRead) ...[
                          const SizedBox(width: _headerGap),
                          NotificationTimeLabel(
                            time: time,
                            unread: !notification.isRead,
                            style: _timeStyle,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: _sectionGap),
                ] else if (time != null || !notification.isRead) ...[
                  // A removed or deleted root has no header, so the unread
                  // dot sits alone where the header's time would be.
                  ExcludeSemantics(
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: NotificationTimeLabel(
                        time: time,
                        unread: !notification.isRead,
                        style: _timeStyle,
                      ),
                    ),
                  ),
                  const SizedBox(height: _sectionGap),
                ],
                if (showsSensitiveBanner) ...[
                  SensitiveContentBanner(
                    concealed: concealed,
                    onToggle: onSensitiveContentToggle,
                  ),
                  const SizedBox(height: _sectionGap),
                ],
                if (quote != null) ...[
                  ExcludeSemantics(
                    child: _YourCommentQuote(
                      text: quote,
                      placeholder: subject?.status != null,
                    ),
                  ),
                  const SizedBox(height: _sectionGap),
                ] else if (postCardVisible) ...[
                  ExcludeSemantics(
                    child: notificationPostCard(
                      rootPost,
                      currentTime: currentTime,
                      hideThumbnail: concealed,
                    ),
                  ),
                  const SizedBox(height: _sectionGap),
                ],
                if (showsBubble)
                  ExcludeSemantics(
                    child: _ReplyBubble(
                      author: author,
                      excerpt: excerpt,
                      excerptIsPlaceholder: record?.status != null,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static bool _isPostUri(String uri) {
    if (!uri.startsWith('at://')) {
      return false;
    }
    final collectionStart = uri.indexOf('/', 'at://'.length);
    if (collectionStart < 0) {
      return false;
    }
    final recordStart = uri.indexOf('/', collectionStart + 1);
    if (recordStart < 0) {
      return false;
    }
    final collection = uri.substring(collectionStart + 1, recordStart);
    return collection == 'social.coves.community.postv2' ||
        collection == 'social.coves.community.post';
  }
}

/// The viewer's own comment that was replied to, quoted above the reply.
class _YourCommentQuote extends StatelessWidget {
  const _YourCommentQuote({required this.text, required this.placeholder});

  final String text;
  final bool placeholder;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(left: _quotePadding),
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: AppColors.border, width: _quoteBorderWidth),
        ),
      ),
      child: Text(
        text,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: placeholder ? _placeholderStyle : _quoteStyle,
      ),
    );
  }
}

const _bubbleBorder = Border(
  left: BorderSide(color: AppColors.textMeta, width: _bubbleBorderWidth),
);

/// The reply's author and excerpt.
class _ReplyBubble extends StatelessWidget {
  const _ReplyBubble({
    required this.author,
    required this.excerpt,
    required this.excerptIsPlaceholder,
  });

  final NotificationActor? author;
  final String? excerpt;
  final bool excerptIsPlaceholder;

  @override
  Widget build(BuildContext context) {
    final author = this.author;
    final excerpt = this.excerpt;
    const radius = Radius.circular(_bubbleRadius);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(left: _bubbleIndent),
      padding: const EdgeInsets.symmetric(
        horizontal: _bubblePadding,
        vertical: _bubbleVerticalPadding,
      ),
      decoration: const BoxDecoration(
        color: AppColors.backgroundSecondary,
        border: _bubbleBorder,
        borderRadius: BorderRadius.only(topRight: radius, bottomRight: radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (author != null)
            Row(
              children: [
                UserAvatar(
                  name: author.name,
                  avatarUrl: author.avatar,
                  size: _authorAvatarSize,
                ),
                const SizedBox(width: _authorGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        author.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _authorStyle,
                      ),
                      if (author.handleLine case final handleLine?)
                        Text(
                          handleLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _handleStyle,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          if (excerpt != null) ...[
            if (author != null) const SizedBox(height: _excerptGap),
            Text(
              excerpt,
              style: excerptIsPlaceholder ? _placeholderStyle : _excerptStyle,
            ),
          ],
        ],
      ),
    );
  }
}
