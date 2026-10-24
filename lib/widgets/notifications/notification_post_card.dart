import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../models/notification.dart';
import '../compact_post_card.dart';

const _unreadDotSize = 8.0;
const _unreadDotGap = 6.0;

/// The full-width surface every notification row sits on, divided from the
/// next row by a hairline, as feed posts are.
const ShapeBorder notificationRowShape = Border(
  bottom: BorderSide(color: AppColors.borderWarm, width: 0.5),
);

/// Marks an unread notification row, beside its timestamp.
class NotificationUnreadDot extends StatelessWidget {
  const NotificationUnreadDot({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: _unreadDotSize,
    height: _unreadDotSize,
    decoration: const BoxDecoration(
      color: AppColors.primary,
      shape: BoxShape.circle,
    ),
  );
}

/// A notification row's timestamp, led by [NotificationUnreadDot] while the
/// row is unread.
class NotificationTimeLabel extends StatelessWidget {
  const NotificationTimeLabel({
    required this.time,
    required this.unread,
    required this.style,
    super.key,
  });

  final String? time;
  final bool unread;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final time = this.time;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (unread) const NotificationUnreadDot(),
        if (unread && time != null) const SizedBox(width: _unreadDotGap),
        if (time != null) Text(time, style: style),
      ],
    );
  }
}

/// A notification's root post as a [CompactPostCard]. A removed or deleted
/// root shows its placeholder copy; [hideThumbnail] swaps the thumbnail for
/// the text tile while the row conceals sensitive media.
CompactPostCard notificationPostCard(
  NotificationReference rootPost, {
  required DateTime? currentTime,
  bool hideThumbnail = false,
}) {
  final createdAt = rootPost.createdAt;
  return CompactPostCard(
    currentTime: currentTime ?? DateTime.now(),
    authorHandle: rootPost.author?.handle,
    authorAvatarUrl: rootPost.author?.avatar,
    createdAt: createdAt == null ? null : DateTime.tryParse(createdAt),
    title: rootPost.title,
    score: rootPost.stats?.score,
    commentCount: rootPost.stats?.commentCount,
    thumbnailUrl: hideThumbnail ? null : rootPost.thumbnail,
    thumbnailAlt: rootPost.thumbnailAlt,
    placeholder: rootPost.placeholderCopy,
  );
}
