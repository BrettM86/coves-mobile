import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../models/community.dart';
import '../utils/community_handle_utils.dart';
import '../utils/display_utils.dart';
import 'community_avatar.dart';

/// Community header widget displaying banner, avatar, and community info
///
/// Layout matches the profile header design pattern:
/// - Full-width generated gradient banner with geometric pattern overlay
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
        // Decorative banner pattern
        _buildDefaultBanner(),
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

  Widget _buildDefaultBanner() {
    // Use hash-based color matching the fallback avatar
    final name = community?.name ?? '';
    final baseColor = DisplayUtils.getFallbackColor(name);
    // Generate a secondary accent by shifting the hash
    final secondaryColor = DisplayUtils.getFallbackColor('${name}alt');

    return Stack(
      children: [
        // Base gradient with two-tone effect
        Container(
          height: bannerHeight,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                baseColor.withValues(alpha: 0.6),
                secondaryColor.withValues(alpha: 0.3),
                baseColor.withValues(alpha: 0.2),
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        ),
        // Subtle circle pattern overlay for texture
        SizedBox(
          height: bannerHeight,
          width: double.infinity,
          child: CustomPaint(
            painter: _BannerPatternPainter(
              color: Colors.white.withValues(alpha: 0.04),
              seed: name.hashCode,
            ),
          ),
        ),
      ],
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
            child: CommunityAvatar(
              name: community?.name ?? '',
              avatarUrl: community?.avatar,
              size: avatarSize - 6,
              showLoadingIndicator: true,
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

/// Paints a subtle geometric pattern on community banners for differentiation.
///
/// Uses the community name hash as a seed to produce different circle layouts
/// per community, making each banner visually distinct.
class _BannerPatternPainter extends CustomPainter {
  _BannerPatternPainter({required this.color, required this.seed});

  final Color color;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 1 || size.height < 1) {
      return;
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Generate deterministic circle positions from seed
    final rng = seed.abs();
    final circleCount = 5 + (rng % 4);

    for (var i = 0; i < circleCount; i++) {
      final hash = (rng * (i + 1) * 7919) % 10000;
      final x = (hash % size.width.toInt()).toDouble();
      final y = (hash ~/ 3 % size.height.toInt()).toDouble();
      final r = 20.0 + (hash % 60);
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BannerPatternPainter oldDelegate) {
    return oldDelegate.seed != seed || oldDelegate.color != color;
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

