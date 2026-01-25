import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../models/user_profile.dart';
import '../utils/date_time_utils.dart';

/// Profile header widget displaying banner, avatar, and user info
///
/// Layout matches Bluesky profile design:
/// - Full-width banner image (~150px height)
/// - Circular avatar (80px) overlapping banner at bottom-left
/// - Display name, handle, and bio below
/// - Stats row showing post/comment/community counts
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    required this.profile,
    super.key,
  });

  final UserProfile? profile;

  static const double bannerHeight = 150;

  @override
  Widget build(BuildContext context) {
    // Stack-based layout with banner image behind profile content
    return Stack(
      children: [
        // Banner image (or gradient fallback)
        _buildBannerImage(),
        // Gradient overlay for text readability
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  AppColors.background.withValues(alpha: 0.3),
                  AppColors.background,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
        ),
        // Profile content - UnconstrainedBox allows content to be natural size
        // and clips overflow when SliverAppBar collapses
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.only(top: kToolbarHeight),
            child: UnconstrainedBox(
              clipBehavior: Clip.hardEdge,
              alignment: Alignment.topLeft,
              constrainedAxis: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                // Avatar and name row (side by side)
                _buildAvatarAndNameRow(),
                // Bio
                if (profile?.bio != null && profile!.bio!.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      profile!.bio!,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                // Stats row
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildStatsRow(),
                ),
                // Member since date
                if (profile?.createdAt != null) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          DateTimeUtils.formatJoinedDate(profile!.createdAt!),
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBannerImage() {
    if (profile?.banner != null && profile!.banner!.isNotEmpty) {
      return SizedBox(
        height: bannerHeight,
        width: double.infinity,
        child: CachedNetworkImage(
          imageUrl: profile!.banner!,
          fit: BoxFit.cover,
          // Disable fade animation to prevent scroll jitter
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          placeholder: (context, url) => _buildDefaultBanner(),
          errorWidget: (context, url, error) => _buildDefaultBanner(),
        ),
      );
    }
    return _buildDefaultBanner();
  }

  Widget _buildDefaultBanner() {
    // TODO: Replace with Image.asset('assets/images/default_banner.png')
    // when the user provides the default banner asset
    return Container(
      height: bannerHeight,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.6),
            AppColors.primary.withValues(alpha: 0.3),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarAndNameRow() {
    const avatarSize = 80.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar with drop shadow
          Container(
            width: avatarSize,
            height: avatarSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.background,
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                  spreadRadius: 1,
                ),
              ],
            ),
            child: ClipOval(
              child: _buildAvatar(avatarSize - 6),
            ),
          ),
          const SizedBox(width: 12),
          // Handle and DID column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                // Handle
                Text(
                  profile?.handle != null
                      ? '@${profile!.handle}'
                      : 'Loading...',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                // DID with icon
                if (profile?.did != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.qr_code_2,
                        size: 14,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          profile!.did,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontFamily: 'monospace',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(double size) {
    if (profile?.avatar != null) {
      return CachedNetworkImage(
        imageUrl: profile!.avatar!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // Disable fade animation to prevent scroll jitter
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        // Static placeholder instead of animated spinner to prevent scroll jitter
        placeholder: (context, url) => _buildAvatarLoading(size),
        errorWidget: (context, url, error) => _buildFallbackAvatar(size),
      );
    }
    return _buildFallbackAvatar(size);
  }

  Widget _buildAvatarLoading(double size) {
    // Static placeholder instead of animated spinner to prevent scroll jitter
    return Container(
      width: size,
      height: size,
      color: AppColors.backgroundSecondary,
    );
  }

  Widget _buildFallbackAvatar(double size) {
    return Container(
      width: size,
      height: size,
      color: AppColors.primary,
      child: Icon(Icons.person, size: size * 0.5, color: Colors.white),
    );
  }

  Widget _buildStatsRow() {
    final stats = profile?.stats;

    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        _StatItem(label: 'Posts', value: stats?.postCount ?? 0),
        _StatItem(label: 'Comments', value: stats?.commentCount ?? 0),
        _StatItem(label: 'Memberships', value: stats?.membershipCount ?? 0),
      ],
    );
  }
}

/// Stats item showing label and value
class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.label,
    required this.value,
  });

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final valueText = _formatNumber(value);

    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: valueText,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          TextSpan(
            text: ' $label',
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  String _formatNumber(int value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    }
    return value.toString();
  }
}
