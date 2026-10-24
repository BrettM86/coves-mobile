import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../utils/date_time_utils.dart';
import '../utils/display_utils.dart';
import '../utils/image_decode_size.dart';
import 'icons/lucide_icon_painter.dart';
import 'icons/lucide_paths.dart';
import 'user_avatar.dart';

const _cardPadding = 12.0;
const _cardRadius = 12.0;
const _columnGap = 12.0;
const _lineGap = 4.0;
const _metaGap = 6.0;
const _avatarSize = 20.0;
const _mediaSize = 88.0;
const _mediaRadius = 16.0;
const _mediaGlyphSize = 32.0;
const _statGap = 16.0;
const _statIconGap = 4.0;
const _statRunSpacing = 4.0;
const _statIconSize = 16.0;
const _thumbsDownSize = 18.0;
const _statsHeight = 30.0;

const _metaStyle = TextStyle(color: AppColors.textSecondary, fontSize: 12);
const _handleStyle = TextStyle(
  color: AppColors.textSecondary,
  fontSize: 12,
  fontWeight: FontWeight.w500,
);
const _titleStyle = TextStyle(
  color: AppColors.textPrimary,
  fontSize: 16,
  fontWeight: FontWeight.w500,
  height: 1.375,
);
const _placeholderStyle = TextStyle(
  color: AppColors.textSecondary,
  fontSize: 16,
  fontWeight: FontWeight.w500,
  fontStyle: FontStyle.italic,
  height: 1.375,
);
const _statStyle = TextStyle(color: AppColors.textSecondary, fontSize: 14);

/// A post in the compact post look: author and time, a two-line title, score
/// and comment count, and a square media tile. Static: it holds no tap
/// targets, so it can sit inside a tappable row. With a [placeholder] (a
/// removed or deleted post) only that copy and a text tile show. The
/// thumbs-down glyph is decorative and shows no count.
class CompactPostCard extends StatelessWidget {
  const CompactPostCard({
    required this.currentTime,
    this.authorHandle,
    this.authorAvatarUrl,
    this.createdAt,
    this.title,
    this.score,
    this.commentCount,
    this.thumbnailUrl,
    this.thumbnailAlt,
    this.placeholder,
    super.key,
  });

  final String? authorHandle;
  final String? authorAvatarUrl;
  final DateTime? createdAt;
  final DateTime currentTime;
  final String? title;
  final int? score;
  final int? commentCount;
  final String? thumbnailUrl;
  final String? thumbnailAlt;
  final String? placeholder;

  @override
  Widget build(BuildContext context) {
    final placeholder = this.placeholder;
    final live = placeholder == null;
    final handle = live ? authorHandle : null;
    final createdAt = live ? this.createdAt : null;
    final score = live ? this.score : null;
    final commentCount = live ? this.commentCount : null;
    final thumbnailUrl = live ? this.thumbnailUrl : null;
    final title = placeholder ?? this.title;

    return Container(
      padding: const EdgeInsets.all(_cardPadding),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _mediaSize),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (handle != null || createdAt != null) ...[
                        _Meta(
                          handle: handle,
                          avatarUrl: authorAvatarUrl,
                          time: createdAt == null
                              ? null
                              : DateTimeUtils.formatTimeAgo(
                                  createdAt,
                                  currentTime: currentTime,
                                ),
                        ),
                        const SizedBox(height: _lineGap),
                      ],
                      if (title != null)
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: live ? _titleStyle : _placeholderStyle,
                        ),
                    ],
                  ),
                  if (score != null || commentCount != null)
                    Padding(
                      padding: const EdgeInsets.only(top: _lineGap),
                      child: _Stats(score: score, commentCount: commentCount),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: _columnGap),
          _MediaTile(thumbnailUrl: thumbnailUrl, thumbnailAlt: thumbnailAlt),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.handle, required this.avatarUrl, this.time});

  final String? handle;
  final String? avatarUrl;
  final String? time;

  @override
  Widget build(BuildContext context) {
    final handle = this.handle;
    final time = this.time;
    return Row(
      children: [
        if (handle != null) ...[
          UserAvatar(name: handle, size: _avatarSize, avatarUrl: avatarUrl),
          const SizedBox(width: _metaGap),
          Flexible(
            child: Text(
              '@$handle',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _handleStyle,
            ),
          ),
          if (time != null) const SizedBox(width: _metaGap),
        ],
        if (time != null) Text(time, style: _metaStyle),
      ],
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.score, required this.commentCount});

  final int? score;
  final int? commentCount;

  @override
  Widget build(BuildContext context) {
    final score = this.score;
    final commentCount = this.commentCount;
    // Wraps rather than overflows when large counts at a big text scale do
    // not fit on one line.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _statsHeight),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: _statGap,
          runSpacing: _statRunSpacing,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (score != null)
              _Stat(
                paths: LucidePaths.heart,
                count: DisplayUtils.formatCount(score),
              ),
            if (commentCount != null)
              _Stat(
                paths: LucidePaths.messageSquare,
                count: DisplayUtils.formatCount(commentCount),
              ),
            if (score != null)
              const LucideGlyph(
                LucidePaths.thumbsDown,
                size: _thumbsDownSize,
                color: AppColors.textSecondary,
              ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.paths, required this.count});

  final List<String> paths;
  final String count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        LucideGlyph(paths, size: _statIconSize, color: AppColors.textSecondary),
        const SizedBox(width: _statIconGap),
        Flexible(
          child: Text(
            count,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _statStyle,
          ),
        ),
      ],
    );
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({required this.thumbnailUrl, required this.thumbnailAlt});

  final String? thumbnailUrl;
  final String? thumbnailAlt;

  @override
  Widget build(BuildContext context) {
    final thumbnailUrl = this.thumbnailUrl;
    return Container(
      width: _mediaSize,
      height: _mediaSize,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(_mediaRadius),
      ),
      child: thumbnailUrl == null
          ? const _TextTile()
          : Semantics(
              label: thumbnailAlt,
              image: thumbnailAlt != null,
              child: CachedNetworkImage(
                imageUrl: thumbnailUrl,
                width: _mediaSize,
                height: _mediaSize,
                memCacheWidth: decodeWidthFor(context, _mediaSize),
                fit: BoxFit.cover,
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                placeholder: (context, url) =>
                    const SizedBox.square(dimension: _mediaSize),
                errorWidget: (context, url, error) => const _TextTile(),
              ),
            ),
    );
  }
}

class _TextTile extends StatelessWidget {
  const _TextTile();

  @override
  Widget build(BuildContext context) {
    // A photo stands on its own; only the text tile gets a frame, including
    // when it stands in for an image that failed to load.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.backgroundTertiary,
        borderRadius: BorderRadius.circular(_mediaRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: const Center(
        child: LucideGlyph(
          LucidePaths.fileText,
          size: _mediaGlyphSize,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}
