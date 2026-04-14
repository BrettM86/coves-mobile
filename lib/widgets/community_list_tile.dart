import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../models/community.dart';
import '../utils/display_utils.dart';
import 'community_avatar.dart';
import 'community_join_button.dart';

/// Reusable community list tile widget.
///
/// Displays a community with avatar, name, stats,
/// and optional trailing widget or inline join button.
/// Used in the discovery and see-all screens.
class CommunityListTile extends StatelessWidget {
  const CommunityListTile({
    required this.community,
    this.onTap,
    this.trailing,
    this.showJoinButton = false,
    super.key,
  });

  final CommunityView community;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool showJoinButton;

  String _buildStatsLine() {
    var line = '';

    if (community.memberCount != null && community.memberCount! > 0) {
      line = '${DisplayUtils.formatCount(community.memberCount!)} members';
      if (community.subscriberCount != null && community.subscriberCount! > 0) {
        final subCount = DisplayUtils.formatCount(community.subscriberCount!);
        line += ' · $subCount subscribers';
      }
    } else if (community.subscriberCount != null &&
        community.subscriberCount! > 0) {
      line =
          '${DisplayUtils.formatCount(community.subscriberCount!)} subscribers';
    }

    return line;
  }

  @override
  Widget build(BuildContext context) {
    final statsLine = _buildStatsLine();
    final hasDescription =
        community.description != null && community.description!.isNotEmpty;

    return Semantics(
      label: '${community.displayName ?? community.name} community',
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          splashColor: AppColors.textMuted.withValues(alpha: 0.1),
          highlightColor: AppColors.textMuted.withValues(alpha: 0.05),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.border, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                CommunityAvatar(
                  name: community.name,
                  avatarUrl: community.avatar,
                  size: 48,
                  shape: CommunityAvatarShape.roundedRect,
                  showLoadingIndicator: true,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        community.displayName ?? community.name,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (statsLine.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          statsLine,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (hasDescription) ...[
                        const SizedBox(height: 3),
                        Text(
                          community.description!,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing!,
                ] else if (showJoinButton) ...[
                  const SizedBox(width: 8),
                  CommunityJoinButton(communityDid: community.did),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
