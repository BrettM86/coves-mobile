import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../utils/display_utils.dart';

/// Shared user/author avatar widget with CachedNetworkImage and fallback.
///
/// The user-side counterpart to `CommunityAvatar`:
/// - Loads the avatar from [avatarUrl] via [CachedNetworkImage]
/// - Falls back to a colored circle with the first letter of [name]
/// - Always circular
///
/// Clipping deliberately uses a [ClipRRect] of radius `size / 2` rather than
/// a `ClipOval`, so this widget contributes no `ClipOval` of its own. Callers
/// that already own one — `ProfileHeader` wraps the avatar in a `ClipOval`
/// for its border ring — stay the only `ClipOval` in the subtree, which is
/// how their tests locate the avatar. The two clips still nest; both are
/// circular and the same size, so the outer one costs nothing.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    required this.name,
    required this.size,
    this.avatarUrl,
    this.fallbackColor,
    this.fallbackTextColor,
    this.fallbackIcon,
    this.showLoadingIndicator = false,
    super.key,
  });

  /// Display name or handle, used for the fallback initial and color.
  final String name;

  /// Width and height of the avatar.
  final double size;

  /// Optional avatar image URL.
  final String? avatarUrl;

  /// Fallback background color. Defaults to the deterministic hash color for
  /// [name] so the same user looks the same everywhere.
  final Color? fallbackColor;

  /// Fallback initial color. Defaults to white.
  final Color? fallbackTextColor;

  /// Rendered instead of the initial when set (e.g. `Icon(Icons.person)`).
  final Widget? fallbackIcon;

  /// Whether to show a loading spinner while the image loads.
  final bool showLoadingIndicator;

  @override
  Widget build(BuildContext context) {
    final fallback = _buildFallback();

    if (avatarUrl == null || avatarUrl!.isEmpty) {
      return fallback;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 2),
      child: CachedNetworkImage(
        imageUrl: avatarUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // Disable fade animation to prevent scroll jitter
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        placeholder: (context, url) =>
            showLoadingIndicator ? _buildLoading() : fallback,
        errorWidget: (context, url, error) {
          if (kDebugMode) {
            debugPrint('Error loading user avatar for $name: $error');
          }
          return fallback;
        },
      ),
    );
  }

  Widget _buildFallback() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fallbackColor ?? DisplayUtils.getFallbackColor(name),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: fallbackIcon ??
            Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                fontSize: size * 0.45,
                fontWeight: FontWeight.bold,
                color: fallbackTextColor ?? Colors.white,
              ),
            ),
      ),
    );
  }

  Widget _buildLoading() {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: AppColors.backgroundSecondary,
        shape: BoxShape.circle,
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
