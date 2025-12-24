import 'package:flutter/material.dart';

import '../constants/bluesky_colors.dart';
import '../utils/date_time_utils.dart';

/// Bluesky action bar widget for displaying engagement counts
///
/// Displays a read-only row of engagement metrics (replies, reposts, likes)
/// with disabled styling to indicate these are view-only from Bluesky.
///
/// All counts are formatted using [DateTimeUtils.formatCount] for readability
/// (e.g., 1200 becomes "1.2k").
class BlueskyActionBar extends StatelessWidget {
  const BlueskyActionBar({
    required this.replyCount,
    required this.repostCount,
    required this.likeCount,
    super.key,
  });

  final int replyCount;
  final int repostCount;
  final int likeCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Reply count
        _buildActionItem(icon: Icons.chat_bubble_outline, count: replyCount),
        const SizedBox(width: 24),

        // Repost count
        _buildActionItem(icon: Icons.repeat, count: repostCount),
        const SizedBox(width: 24),

        // Like count
        _buildActionItem(icon: Icons.favorite_border, count: likeCount),
      ],
    );
  }

  /// Builds a single action item with icon and count
  Widget _buildActionItem({required IconData icon, required int count}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: BlueskyColors.actionDisabled),
        const SizedBox(width: 4),
        Text(
          DateTimeUtils.formatCount(count),
          style: const TextStyle(
            color: BlueskyColors.actionDisabled,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
