import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../models/notification.dart';
import '../../utils/date_time_utils.dart';
import '../../utils/image_decode_size.dart';
import '../../utils/moderation_copy.dart';
import '../../utils/upvote_notification_copy.dart';
import '../icons/lucide_icon_painter.dart';
import '../icons/lucide_paths.dart';
import '../sensitive_content.dart';
import '../user_avatar.dart';
import 'notification_post_card.dart';

const _rowPadding = 12.0;
const _rowHorizontalPadding = 16.0;
const _sectionGap = 12.0;
const _headerGap = 10.0;
const _avatarSize = 32.0;
const _avatarOverlap = 8.0;
const _avatarRing = 2.0;
const _maxAvatars = 3;
const _heartSize = 14.0;
const _heartGap = 4.0;
const _timeGap = 8.0;
const _quoteRadius = 12.0;
const _quotePadding = EdgeInsets.symmetric(horizontal: 12, vertical: 10);
const _thumbnailGap = 12.0;
const _thumbnailSize = 64.0;
const _thumbnailRadius = 8.0;

const _titleStyle = TextStyle(
  color: AppColors.textPrimary,
  fontSize: 14,
  fontWeight: FontWeight.w500,
);
const _namesStyle = TextStyle(color: AppColors.textSecondary, fontSize: 12);
const _timeStyle = TextStyle(color: AppColors.textSecondary, fontSize: 12);
const _previewStyle = TextStyle(color: AppColors.textSecondary, fontSize: 14);
const _placeholderStyle = TextStyle(
  color: AppColors.textSecondary,
  fontSize: 14,
  fontStyle: FontStyle.italic,
);

class NotificationUpvoteRow extends StatelessWidget {
  const NotificationUpvoteRow({
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
    final parts = upvoteNotificationSentence(notification);
    final sentence = parts.map((part) => part.text).join();
    // The last part is " liked your post/comment"; the rest name the voters.
    final names = parts.take(parts.length - 1).map((part) => part.text).join();
    final rootPost = notification.rootPost;
    final subject = notification.subject;
    final isCommentUpvote =
        subject != null &&
        moderationSubjectUriKind(subject.uri) == ModerationSubjectKind.comment;
    final title = isCommentUpvote ? 'Liked your comment' : 'Liked your post';
    final subjectPreview = subject?.placeholderCopy ?? subject?.preview;

    // A post upvote shows the root post as a card; a comment upvote quotes
    // the comment, with its thumbnail beside the quote.
    final cardIsSensitive =
        !isCommentUpvote &&
        rootPost.status == null &&
        (rootPost.isSensitive || (subject?.isSensitive ?? false));
    final shownThumbnail = isCommentUpvote
        ? (subject.status == null ? subject.thumbnail : null)
        : (rootPost.status == null ? rootPost.thumbnail : null);
    final thumbnailAlt = isCommentUpvote
        ? subject.thumbnailAlt
        : rootPost.thumbnailAlt ?? subject?.thumbnailAlt;

    // Placeholder copy is not content, so only a live subject's own preview
    // is ever concealed.
    final previewIsSensitive =
        isCommentUpvote &&
        subject.status == null &&
        subjectPreview != null &&
        subject.isSensitive;
    final rowIsSensitive =
        rootPost.isSensitive || (subject?.isSensitive ?? false);
    final showsSensitiveBanner =
        rowIsSensitive &&
        (shownThumbnail != null || previewIsSensitive || cardIsSensitive);
    final concealed = showsSensitiveBanner && !sensitiveContentRevealed;
    final showsCard = !isCommentUpvote && !(concealed && cardIsSensitive);
    final preview = concealed && (previewIsSensitive || cardIsSensitive)
        ? null
        : subjectPreview;
    final thumbnail = concealed ? null : shownThumbnail;
    final parsedTime = DateTime.tryParse(notification.sortAt);
    final time = parsedTime == null
        ? null
        : DateTimeUtils.formatTimeAgo(parsedTime, currentTime: currentTime);
    // The unread dot is drawn only, so the label says it first.
    final label = [
      if (!notification.isRead) 'Unread',
      sentence,
      preview,
      time,
      if (thumbnail != null) thumbnailAlt,
    ].whereType<String>().join(', ');

    final upvoters = notification.recentUpvoters.take(_maxAvatars).toList();
    final quotePreview = isCommentUpvote ? preview : null;

    // A row with a banner keeps the banner as its own activatable node inside
    // the row's button, so revealing never opens the row and opening never
    // reveals. Every other part is excluded: the row's label speaks for it.
    return Semantics(
      container: showsSensitiveBanner,
      button: true,
      excludeSemantics: !showsSensitiveBanner,
      label: label,
      onTap: onTap,
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
              vertical: _rowPadding,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (upvoters.isNotEmpty) ...[
                        _AvatarStack(upvoters: upvoters),
                        const SizedBox(width: _headerGap),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CustomPaint(
                                  size: const Size.square(_heartSize),
                                  painter: LucideIconPainter(
                                    paths: LucidePaths.heart,
                                    color: AppColors.voteLiked,
                                    filled: true,
                                  ),
                                ),
                                const SizedBox(width: _heartGap),
                                Flexible(
                                  child: Text(title, style: _titleStyle),
                                ),
                              ],
                            ),
                            Text(
                              names,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _namesStyle,
                            ),
                          ],
                        ),
                      ),
                      if (time != null || !notification.isRead) ...[
                        const SizedBox(width: _timeGap),
                        NotificationTimeLabel(
                          time: time,
                          unread: !notification.isRead,
                          style: _timeStyle,
                        ),
                      ],
                    ],
                  ),
                ),
                if (showsCard) ...[
                  const SizedBox(height: _sectionGap),
                  ExcludeSemantics(
                    child: notificationPostCard(
                      rootPost,
                      currentTime: currentTime,
                      hideThumbnail: concealed,
                    ),
                  ),
                ] else if (quotePreview != null ||
                    (isCommentUpvote && thumbnail != null)) ...[
                  const SizedBox(height: _sectionGap),
                  ExcludeSemantics(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: quotePreview == null
                              ? const SizedBox.shrink()
                              : _Quote(
                                  text: quotePreview,
                                  placeholder: subject?.status != null,
                                ),
                        ),
                        if (thumbnail != null) ...[
                          const SizedBox(width: _thumbnailGap),
                          _Thumbnail(url: thumbnail),
                        ],
                      ],
                    ),
                  ),
                ],
                if (showsSensitiveBanner) ...[
                  const SizedBox(height: _sectionGap),
                  SensitiveContentBanner(
                    concealed: concealed,
                    onToggle: onSensitiveContentToggle,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Up to three upvoter avatars, overlapping left to right.
class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.upvoters});

  final List<NotificationActor> upvoters;

  @override
  Widget build(BuildContext context) {
    const step = _avatarSize - _avatarOverlap;
    return SizedBox(
      width: _avatarSize + step * (upvoters.length - 1),
      height: _avatarSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final (index, actor) in upvoters.indexed)
            Positioned(
              left: step * index,
              top: 0,
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.background,
                ),
                padding: const EdgeInsets.all(_avatarRing),
                child: UserAvatar(
                  name: actor.name,
                  avatarUrl: actor.avatar,
                  size: _avatarSize - _avatarRing * 2,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Quote extends StatelessWidget {
  const _Quote({required this.text, required this.placeholder});

  final String text;
  final bool placeholder;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: _quotePadding,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(_quoteRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        text,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: placeholder ? _placeholderStyle : _previewStyle,
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_thumbnailRadius),
      child: CachedNetworkImage(
        imageUrl: url,
        width: _thumbnailSize,
        height: _thumbnailSize,
        memCacheWidth: decodeWidthFor(context, _thumbnailSize),
        fit: BoxFit.cover,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        placeholder: (context, url) =>
            const SizedBox.square(dimension: _thumbnailSize),
        errorWidget: (context, url, error) =>
            const SizedBox.square(dimension: _thumbnailSize),
      ),
    );
  }
}
