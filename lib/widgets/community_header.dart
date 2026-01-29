import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../models/community.dart';
import '../utils/community_handle_utils.dart';
import '../utils/display_utils.dart';

/// Community header widget displaying banner, avatar, and community info
///
/// Layout matches the profile header design pattern:
/// - Full-width banner image with gradient overlay
/// - Circular avatar with shadow
/// - Community name, handle, and description
/// - Stats row showing subscriber/member counts
class CommunityHeader extends StatelessWidget {
  const CommunityHeader({
    required this.community,
    super.key,
  });

  final CommunityView? community;

  static const double bannerHeight = 150;

  @override
  Widget build(BuildContext context) {
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;

    return Stack(
      children: [
        // Banner image (or decorative fallback)
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
                  AppColors.background.withValues(alpha: isIOS ? 0.6 : 0.3),
                  AppColors.background,
                ],
                stops: isIOS
                    ? const [0.0, 0.25, 0.55]
                    : const [0.0, 0.5, 1.0],
              ),
            ),
          ),
        ),
        // Community content
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
                  // Avatar and name row
                  _buildAvatarAndNameRow(),
                  // Description
                  if (community?.description != null &&
                      community!.description!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        community!.description!,
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
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBannerImage() {
    // Communities don't have banners yet, so we use a decorative pattern
    // that varies based on community name for visual distinction
    return _buildDefaultBanner();
  }

  Widget _buildDefaultBanner() {
    // Use hash-based color matching the fallback avatar
    final name = community?.name ?? '';
    final baseColor = DisplayUtils.getFallbackColor(name);

    return Container(
      height: bannerHeight,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            baseColor.withValues(alpha: 0.6),
            baseColor.withValues(alpha: 0.3),
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
          // Circular avatar (matches profile style)
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
          // Name and handle column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                // Display name
                Text(
                  community?.displayName ?? community?.name ?? 'Loading...',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                // Handle
                if (community?.handle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    CommunityHandleUtils.formatHandleForDisplay(
                          community!.handle,
                        ) ??
                        '',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.teal,
                      fontWeight: FontWeight.w500,
                    ),
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
    if (community?.avatar != null && community!.avatar!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: community!.avatar!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        placeholder: (context, url) => _buildAvatarLoading(size),
        errorWidget: (context, url, error) {
          if (kDebugMode) {
            debugPrint(
              'Error loading community avatar for ${community?.name}: $error',
            );
          }
          return _buildFallbackAvatar(size);
        },
      );
    }
    return _buildFallbackAvatar(size);
  }

  Widget _buildAvatarLoading(double size) {
    return Container(
      width: size,
      height: size,
      color: AppColors.backgroundSecondary,
    );
  }

  Widget _buildFallbackAvatar(double size) {
    final name = community?.name ?? '';
    final bgColor = DisplayUtils.getFallbackColor(name);

    return Container(
      width: size,
      height: size,
      color: bgColor,
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : 'C',
          style: TextStyle(
            fontSize: size * 0.45,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: -1,
          ),
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        if (community?.subscriberCount != null)
          _StatItem(
            label: 'Subscribers',
            value: community!.subscriberCount!,
          ),
        if (community?.memberCount != null)
          _StatItem(
            label: 'Members',
            value: community!.memberCount!,
          ),
      ],
    );
  }

}

/// Stats item showing label and value (matches profile pattern)
class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.label,
    required this.value,
  });

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final valueText = DisplayUtils.formatCount(value);

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
}

