import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../models/post.dart';
import 'icons/lucide_icon_painter.dart';
import 'icons/lucide_paths.dart';
import 'media/media_aspect.dart';
import 'media/media_surface.dart';

/// Keys the post widgets locate these controls by. They stay constant even
/// when a caller passes its own [Key], so both finders work.
const Key _bannerKey = Key('sensitive-content-banner');
const Key _placeholderKey = Key('sensitive-image-placeholder');

/// The reveal control shown on a post the author self-labelled as sensitive.
class SensitiveContentBanner extends StatelessWidget {
  const SensitiveContentBanner({
    required this.concealed,
    required this.onToggle,
    super.key,
  });

  /// Whether the post's content is currently hidden.
  final bool concealed;

  /// Flips the reveal state of the post this banner belongs to.
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    // explicitChildNodes keeps the banner copy from merging into the wrapper:
    // a merged node would announce "NSFW Content Show" instead of the action.
    // Because the copy stays its own node, the tap has to sit on the labelled
    // node itself — a screen reader activates what it announced — and the
    // GestureDetector is excluded so the copy is not a second, unlabelled
    // target.
    return Semantics(
      key: _bannerKey,
      container: true,
      explicitChildNodes: true,
      button: true,
      label: concealed ? 'Show sensitive content' : 'Hide sensitive content',
      onTap: onToggle,
      child: GestureDetector(
        onTap: onToggle,
        excludeFromSemantics: true,
        behavior: HitTestBehavior.opaque,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const LucideGlyph(
                    LucidePaths.info,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'NSFW Content',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    concealed ? 'Show' : 'Hide',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The blurred stand-in shown in place of a concealed image embed.
class SensitiveImagePlaceholder extends StatelessWidget {
  const SensitiveImagePlaceholder({
    required this.image,
    required this.bounds,
    required this.onReveal,
    super.key,
  });

  /// The image being concealed; only its thumb is ever fetched.
  final EmbedImage image;

  /// The display bounds of the surface this placeholder stands in for, so
  /// revealing the image causes no layout jump.
  final MediaRatioBounds bounds;

  /// Reveals the post this placeholder belongs to.
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    // The same clamp the revealed embed applies, so reveal keeps the layout.
    final ratio = clampMediaRatio(
      image.aspectRatio,
      min: bounds.min,
      max: bounds.max,
    );

    // The alt text describes what is being concealed, so it is deliberately
    // not attached anywhere here; ExcludeSemantics stops CachedNetworkImage
    // from contributing a node of its own.
    //
    // As on the banner, explicitChildNodes keeps the overlay copy out of the
    // label, so the tap has to sit on the labelled node and the
    // GestureDetector is excluded from semantics.
    return Semantics(
      key: _placeholderKey,
      container: true,
      explicitChildNodes: true,
      button: true,
      label: 'Show sensitive content',
      onTap: onReveal,
      child: GestureDetector(
        onTap: onReveal,
        excludeFromSemantics: true,
        behavior: HitTestBehavior.opaque,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: AspectRatio(
            aspectRatio: ratio,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ExcludeSemantics(
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
                      // Scaled past the frame so the blur's transparent
                      // fringe falls outside the clip instead of showing as
                      // a soft border. Only the thumb is ever requested:
                      // fetching the fullsize rendering would put the
                      // concealed image in the cache and on the wire.
                      child: Transform.scale(
                        scale: 1.2,
                        child: CachedNetworkImage(
                          imageUrl: image.thumb,
                          fit: BoxFit.cover,
                          fadeInDuration: Duration.zero,
                          fadeOutDuration: Duration.zero,
                          placeholder: (context, url) => const MediaFill(),
                          errorWidget: (context, url, error) =>
                              const MediaFill(),
                        ),
                      ),
                    ),
                  ),
                ),
                Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.background.withValues(alpha: 0.75),
                      border: Border.all(
                        color: AppColors.textPrimary.withValues(alpha: 0.2),
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          LucideGlyph(
                            LucidePaths.info,
                            size: 20,
                            color: AppColors.textPrimary,
                          ),
                          SizedBox(width: 12),
                          Text(
                            'NSFW Content',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Show',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
