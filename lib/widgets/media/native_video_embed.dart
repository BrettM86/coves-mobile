import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/post.dart';
import '../fullscreen_video_player.dart';
import 'media_format.dart';
import 'media_surface.dart';
import 'play_chip.dart';

/// Native video embed: poster, play overlay, and an optional duration badge.
///
/// Deliberately separate from the Streamable embed, which takes an
/// [ExternalEmbed], hides itself when there is no thumbnail, and gates
/// playback on resolving a URL first. A native embed always carries a
/// playable URL, and must still render a frame when the AppView gave us no
/// poster.
///
/// [keyPrefix] namespaces the widget keys (`post-` on the feed, `detail-` in
/// the detail view) so each surface stays independently addressable in tests.
class NativeVideoEmbed extends StatelessWidget {
  const NativeVideoEmbed({
    required this.embed,
    required this.keyPrefix,
    this.aspectRatio = 16 / 9,
    this.playChipStyle = PlayChipStyle.feed,
    this.fill = kFeedMediaFill,
    super.key,
  });

  final VideoPostEmbed embed;
  final String keyPrefix;
  final double aspectRatio;
  final PlayChipStyle playChipStyle;
  final MediaFillStyle fill;

  /// Opens the fullscreen player. Pushed synchronously — the URL is already
  /// in hand, so there is nothing to resolve first.
  void _play(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => FullscreenVideoPlayer(videoUrl: embed.video),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final thumbnail = embed.thumbnail;
    final duration = embed.duration;
    final alt = embed.alt;

    Widget surface = AspectRatio(
      aspectRatio: aspectRatio,
      child:
          thumbnail == null
              ? MediaFill(iconColor: fill.iconColor, iconSize: fill.iconSize)
              : CachedNetworkImage(
                imageUrl: thumbnail,
                width: double.infinity,
                fit: BoxFit.cover,
                // Disable fade animation to prevent scroll jitter
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                placeholder:
                    (context, url) => MediaFill(
                      iconColor: fill.iconColor,
                      iconSize: fill.iconSize,
                    ),
                errorWidget:
                    (context, url, error) => MediaFill(
                      icon: Icons.broken_image,
                      iconColor: fill.iconColor,
                      iconSize: fill.iconSize,
                    ),
              ),
    );

    if (alt != null && alt.isNotEmpty) {
      surface = Semantics(image: true, label: alt, child: surface);
    }

    return Semantics(
      // An explicit container: without it this annotation is absorbed into
      // the subtree's node, and the duration badge's text displaces the
      // label. Any future overlay (mute, GIF chip) would do the same.
      container: true,
      explicitChildNodes: true,
      button: true,
      label: 'Play video',
      child: GestureDetector(
        key: Key('$keyPrefix-video-embed'),
        onTap: () => _play(context),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            alignment: Alignment.center,
            children: [
              surface,
              PlayChip(
                key: Key('$keyPrefix-video-play-overlay'),
                style: playChipStyle,
              ),
              if (duration != null)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: MediaBadge(
                    key: Key('$keyPrefix-video-duration-badge'),
                    label: formatVideoDuration(duration),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
