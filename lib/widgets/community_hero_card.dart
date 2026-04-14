import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../models/community.dart';
import '../utils/display_utils.dart';
import 'community_avatar.dart';
import 'community_join_button.dart';

/// Hero display for featured/popular communities.
///
/// Used in the horizontal scrolling "Popular" section.
/// Shows avatar, name, subscriber count, and a compact Join button
/// in a borderless open layout with a left accent bar.
class CommunityHeroCard extends StatelessWidget {
  const CommunityHeroCard({
    required this.community,
    required this.onTap,
    this.showJoinButton = false,
    super.key,
  });

  final CommunityView community;
  final VoidCallback onTap;
  final bool showJoinButton;

  @override
  Widget build(BuildContext context) {
    final name = community.displayName ?? community.name;
    final accentColor = DisplayUtils.getFallbackColor(community.name);
    final subscriberLabel =
        community.subscriberCount != null
            ? '${DisplayUtils.formatCount(community.subscriberCount!)}'
                ' subscribers'
            : null;

    return Semantics(
      label: '$name${subscriberLabel != null ? ", $subscriberLabel" : ""}',
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          splashColor: accentColor.withValues(alpha: 0.15),
          child: SizedBox(
            width: 240,
            child: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left accent bar
                    Container(
                      width: 3,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: accentColor.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              CommunityAvatar(
                                name: community.name,
                                avatarUrl: community.avatar,
                                size: 40,
                                fallbackColorAlpha: 0.8,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        height: 1.2,
                                        letterSpacing: -0.3,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (subscriberLabel != null &&
                                        community.subscriberCount! > 0) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        subscriberLabel,
                                        style: const TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (showJoinButton) ...[
                                const SizedBox(width: 8),
                                CommunityJoinButton(
                                  communityDid: community.did,
                                  style: CommunityJoinButtonStyle.compact,
                                ),
                              ],
                            ],
                          ),
                          if (community.description != null &&
                              community.description!.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              community.description!,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                                height: 1.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
