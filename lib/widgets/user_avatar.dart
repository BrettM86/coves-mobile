import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../constants/app_colors.dart';
import '../constants/default_avatars.dart';
import '../utils/default_avatar.dart';
import '../utils/image_decode_size.dart';

/// Shared user/author avatar widget with CachedNetworkImage and fallback.
///
/// The user-side counterpart to `CommunityAvatar`. Always circular.
/// - Loads the real avatar from [avatarUrl] via [CachedNetworkImage].
/// - With no [avatarUrl], an empty one, or a failed load, draws the user's
///   default avatar (PRD_DEFAULT_AVATARS §4.5): a circle in the tint chosen
///   from [did] with the default picture on top. While that picture loads,
///   or if it fails, the tinted circle shows alone.
/// - An empty [did] draws a plain Mist circle with no picture (D13).
/// - Setting [fallbackColor] (the Bluesky embed cards, D12) keeps the
///   initial-on-colour fallback instead and never draws the default.
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
    required this.did,
    required this.size,
    this.avatarUrl,
    this.fallbackColor,
    this.fallbackTextColor,
    this.showLoadingIndicator = false,
    this.cacheManager,
    super.key,
  }) : assert(
         fallbackTextColor == null || fallbackColor != null,
         'fallbackTextColor only applies with fallbackColor',
       );

  /// Display name or handle, used for the Bluesky-mode fallback initial.
  final String name;

  /// The user's DID, used to pick the default avatar (PRD_DEFAULT_AVATARS
  /// §4.2). Empty draws a plain Mist circle.
  final String did;

  /// Width and height of the avatar.
  final double size;

  /// Optional avatar image URL.
  final String? avatarUrl;

  /// Bluesky-mode fallback background colour. When set, the fallback is the
  /// first letter of [name] on this colour, not the default avatar.
  final Color? fallbackColor;

  /// Bluesky-mode fallback initial colour. Defaults to white.
  final Color? fallbackTextColor;

  /// Whether to show a loading spinner while the real avatar loads.
  final bool showLoadingIndicator;

  /// Cache manager handed to every image this widget loads (test seam).
  final BaseCacheManager? cacheManager;

  @override
  Widget build(BuildContext context) {
    if (avatarUrl == null || avatarUrl!.isEmpty) {
      return _buildFallback(context);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 2),
      child: CachedNetworkImage(
        imageUrl: avatarUrl!,
        cacheManager: cacheManager,
        width: size,
        height: size,
        memCacheWidth: decodeWidthFor(context, size),
        fit: BoxFit.cover,
        // Disable fade animation to prevent scroll jitter
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        placeholder: (context, url) =>
            showLoadingIndicator ? _buildLoading() : _buildPlaceholderCircle(),
        errorWidget: (context, url, error) {
          if (kDebugMode) {
            debugPrint('Error loading user avatar for $name: $error');
          }
          return _buildFallback(context);
        },
      ),
    );
  }

  /// What stands in for a missing or failed real avatar.
  Widget _buildFallback(BuildContext context) {
    if (fallbackColor != null) {
      return _buildInitial(fallbackColor!);
    }
    if (did.isEmpty) {
      return _buildCircle(defaultAvatarEmptyDidColor);
    }
    return _buildDefaultAvatar(context, DefaultAvatar.forDid(did));
  }

  /// The circle shown while a real avatar loads without a spinner.
  Widget _buildPlaceholderCircle() {
    if (fallbackColor != null) {
      return _buildInitial(fallbackColor!);
    }
    if (did.isEmpty) {
      return _buildCircle(defaultAvatarEmptyDidColor);
    }
    return _buildCircle(DefaultAvatar.forDid(did).tint);
  }

  Widget _buildDefaultAvatar(BuildContext context, DefaultAvatar avatar) {
    return _buildCircle(
      avatar.tint,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: CachedNetworkImage(
          imageUrl: avatar.url,
          cacheManager: cacheManager,
          width: size,
          height: size,
          memCacheWidth: decodeWidthFor(context, size),
          fit: BoxFit.cover,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          // The tinted circle underneath is the loading and error state.
          placeholder: (context, url) => const SizedBox.shrink(),
          errorWidget: (context, url, error) {
            if (kDebugMode) {
              debugPrint('Error loading default avatar ${avatar.slug}: $error');
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  Widget _buildCircle(Color color, {Widget? child}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: child,
    );
  }

  Widget _buildInitial(Color color) {
    return _buildCircle(
      color,
      child: Center(
        child: Text(
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
