import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../models/comment.dart';
import '../models/post.dart';
import '../utils/image_layout.dart';
import 'rich_text_renderer.dart';
import 'separated_selection_area.dart';

/// Opens a bottom sheet showing [comment]'s body as selectable text.
///
/// Only the body is shown: no author, timestamp, votes or gallery images.
/// The sheet builds its own renderer, so spoilers start hidden whatever
/// their state in the card.
Future<void> showCommentTextSheet(BuildContext context, CommentView comment) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.backgroundSecondary,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    // Material's default width cap, plus the height cap
    constraints: BoxConstraints(
      maxWidth: 640,
      maxHeight: MediaQuery.sizeOf(context).height * 0.9,
    ),
    builder: (sheetContext) => _CommentTextSheet(comment: comment),
  );
}

class _CommentTextSheet extends StatelessWidget {
  const _CommentTextSheet({required this.comment});

  final CommentView comment;

  @override
  Widget build(BuildContext context) {
    // Comments only ever carry a plain images embed
    final images = imageLayout(
      comment.parsedEmbed is ImagesPostEmbed ? comment.parsedEmbed : null,
      comment.content,
      comment.contentFacets,
    );

    return SafeArea(
      // Full sheet width, however short the body
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            // The scroll view sits inside the region so a selection
            // survives scrolling.
            child: SeparatedSelectionArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: RichTextRenderer(
                  text: comment.content,
                  facets: comment.contentFacets,
                  images: images,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
