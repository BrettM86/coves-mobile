import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../utils/display_utils.dart';

/// Shape variant for the community avatar.
enum CommunityAvatarShape {
  /// Circular avatar (used in chips, hero cards, headers).
  circle,

  /// Rounded rectangle avatar (used in list tiles).
  roundedRect,
}

/// Shared community avatar widget with CachedNetworkImage and fallback.
///
/// Handles the common avatar pattern across community widgets:
/// - Loads avatar from URL via [CachedNetworkImage]
/// - Falls back to a colored container with the first letter of the name
/// - Supports circle and rounded-rectangle shapes
/// - Configurable size, border, and color alpha
class CommunityAvatar extends StatelessWidget {
  const CommunityAvatar({
    required this.name,
    required this.size,
    this.avatarUrl,
    this.shape = CommunityAvatarShape.circle,
    this.borderRadius = 14.0,
    this.fallbackColorAlpha = 1.0,
    this.fallbackBorder,
    this.showLoadingIndicator = false,
    super.key,
  });

  /// Community name, used for fallback initial and color generation.
  final String name;

  /// Width and height of the avatar.
  final double size;

  /// Optional avatar image URL.
  final String? avatarUrl;

  /// Shape of the avatar container.
  final CommunityAvatarShape shape;

  /// Border radius when [shape] is [CommunityAvatarShape.roundedRect].
  final double borderRadius;

  /// Alpha value applied to the fallback background color (0.0 - 1.0).
  final double fallbackColorAlpha;

  /// Optional border on the fallback avatar.
  final BoxBorder? fallbackBorder;

  /// Whether to show a loading spinner while the image loads.
  final bool showLoadingIndicator;

  @override
  Widget build(BuildContext context) {
    final fallback = _buildFallback();

    if (avatarUrl == null || avatarUrl!.isEmpty) {
      return fallback;
    }

    if (shape == CommunityAvatarShape.roundedRect) {
      return CachedNetworkImage(
        imageUrl: avatarUrl!,
        imageBuilder: (context, imageProvider) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            image: DecorationImage(
              image: imageProvider,
              fit: BoxFit.cover,
            ),
          ),
        ),
        placeholder: (context, url) => showLoadingIndicator
            ? _buildLoading()
            : fallback,
        errorWidget: (context, url, error) {
          if (kDebugMode) {
            debugPrint('Error loading community avatar for $name: $error');
          }
          return fallback;
        },
      );
    }

    // Circle shape — use ClipOval
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: avatarUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        placeholder: (context, url) => showLoadingIndicator
            ? _buildLoading()
            : fallback,
        errorWidget: (context, url, error) {
          if (kDebugMode) {
            debugPrint('Error loading community avatar for $name: $error');
          }
          return fallback;
        },
      ),
    );
  }

  Widget _buildFallback() {
    final baseColor = DisplayUtils.getFallbackColor(name);
    final isCircle = shape == CommunityAvatarShape.circle;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: baseColor.withValues(alpha: fallbackColorAlpha),
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isCircle ? null : BorderRadius.circular(borderRadius),
        border: fallbackBorder,
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: size * 0.45,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    final isCircle = shape == CommunityAvatarShape.circle;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isCircle ? null : BorderRadius.circular(borderRadius),
      ),
      child: Center(
        child: SizedBox(
          width: size * 0.33,
          height: size * 0.33,
          child: const CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}
