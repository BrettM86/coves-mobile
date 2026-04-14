import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../models/community.dart';
import '../utils/display_utils.dart';
import 'community_avatar.dart';

/// Compact community chip for the quick-access horizontal row.
///
/// Shows a circular avatar with the community name below it,
/// similar to story/channel bubbles in messaging apps.
/// Used in the "Your Communities" section for fast navigation.
class CommunityChip extends StatelessWidget {
  const CommunityChip({
    required this.community,
    required this.onTap,
    super.key,
  });

  final CommunityView community;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final baseColor = DisplayUtils.getFallbackColor(community.name);
    final name = community.displayName ?? community.name;

    return Semantics(
      label: '$name community',
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          splashColor: baseColor.withValues(alpha: 0.15),
          child: SizedBox(
            width: 76,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Avatar with colored ring
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: baseColor.withValues(alpha: 0.5),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: baseColor.withValues(alpha: 0.15),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: CommunityAvatar(
                    name: community.name,
                    avatarUrl: community.avatar,
                    size: 52,
                  ),
                ),
                const SizedBox(height: 8),
                // Community name
                Text(
                  name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
