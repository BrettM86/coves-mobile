import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../constants/app_colors.dart';
import '../../models/post.dart';
import '../../services/streamable_service.dart';
import '../../utils/url_launcher.dart';
import '../fullscreen_video_player.dart';
import 'media_surface.dart';
import 'play_chip.dart';

export 'play_chip.dart' show PlayChipStyle;

/// Embed types the AppView uses for a playable external video.
const Set<String> _videoEmbedTypes = {'video', 'video-stream'};

/// What the user is told when a Streamable URL will not resolve to an MP4.
/// One string for both surfaces.
const String _failureCopy = 'Could not load video';

/// A Streamable link rendered as a tappable video poster.
///
/// Tapping resolves the MP4 behind the share URL and pushes the fullscreen
/// player. The resolve is a network round-trip, so the chip shows a spinner
/// and the button reports itself disabled while it is in flight.
///
/// The detail view renders this widget for any video-typed embed, including
/// providers with no in-app playback. Those keep a live play chip too — the
/// tap hands the (validated) link to the external browser instead.
///
/// The feed passes a [frameDecoration] to keep its bordered card; the detail
/// view runs full-bleed with [darken] instead.
class StreamableVideoEmbed extends StatefulWidget {
  const StreamableVideoEmbed({
    required this.embed,
    required this.streamableService,
    this.height = 180,
    this.frameDecoration,
    this.darken = false,
    this.playChipStyle = PlayChipStyle.feed,
    super.key,
  });

  final ExternalEmbed embed;
  final StreamableService streamableService;
  final double height;

  /// Border/radius treatment around the poster, or null for full-bleed.
  final BoxDecoration? frameDecoration;

  /// Whether to lay a scrim over the poster so the chip stays legible.
  final bool darken;

  final PlayChipStyle playChipStyle;

  /// Whether [embed] is a Streamable video this widget can play.
  ///
  /// Case-insensitive on both fields: `embedType` and `provider` are
  /// provider-supplied metadata that reaches us in whatever casing the
  /// AppView recorded. The embed-type match is exact after lowercasing, not
  /// a prefix test.
  static bool isStreamableVideo(ExternalEmbed embed) {
    final embedType = embed.embedType?.toLowerCase();
    if (embedType == null || !_videoEmbedTypes.contains(embedType)) {
      return false;
    }
    // Only Streamable URLs can be resolved to an MP4 in-app.
    return embed.provider?.toLowerCase() == 'streamable';
  }

  @override
  State<StreamableVideoEmbed> createState() => _StreamableVideoEmbedState();
}

class _StreamableVideoEmbedState extends State<StreamableVideoEmbed> {
  bool _isLoading = false;

  Future<void> _play() async {
    // The detail view renders this widget for any video-typed embed, so a
    // non-Streamable provider can reach the tap handler with nothing to
    // resolve in-app. It is still a video link, so hand it to the browser
    // rather than eating the tap. UrlLauncher validates the scheme/host and
    // reports its own failures.
    if (!StreamableVideoEmbed.isStreamableVideo(widget.embed)) {
      await UrlLauncher.launchExternalUrl(widget.embed.uri, context: context);
      return;
    }

    // Capture context-dependent objects before the async gap.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() => _isLoading = true);

    try {
      final videoUrl = await widget.streamableService.getVideoUrl(
        widget.embed.uri,
      );

      if (!mounted) {
        return;
      }

      if (videoUrl == null) {
        _showFailure(messenger);
        return;
      }

      await navigator.push<void>(
        MaterialPageRoute(
          builder: (context) => FullscreenVideoPlayer(videoUrl: videoUrl),
          fullscreenDialog: true,
        ),
      );
    } on Object catch (error, stackTrace) {
      // The service only converts DioExceptions to null; an unexpected
      // response shape surfaces as a TypeError, and anything that escapes
      // here would stop the spinner and tell the user nothing.
      if (kDebugMode) {
        debugPrint('Streamable playback failed: $error\n$stackTrace');
      }
      if (mounted) {
        _showFailure(messenger);
      }
    } finally {
      // A failed resolve is retryable, so the chip always comes back.
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// The one thing the user is told when playback cannot start, whatever the
  /// reason: an unresolvable URL and a malformed response read the same.
  void _showFailure(ScaffoldMessengerState messenger) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          _failureCopy,
          style: GoogleFonts.inter(color: AppColors.textPrimary),
        ),
        backgroundColor: AppColors.backgroundSecondary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final thumb = widget.embed.thumb;

    // With no poster there is nothing to overlay a play chip on, and an
    // empty frame reads as a broken card.
    if (thumb == null) {
      return const SizedBox.shrink();
    }

    Widget poster = CachedNetworkImage(
      imageUrl: thumb,
      width: double.infinity,
      height: widget.height,
      fit: BoxFit.cover,
      // Disable fade animation to prevent scroll jitter from height changes
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholder: (context, url) => _fill(),
      errorWidget: (context, url, error) => _fill(icon: Icons.broken_image),
    );

    final decoration = widget.frameDecoration;
    if (decoration != null) {
      poster = Container(
        decoration: decoration,
        clipBehavior: Clip.antiAlias,
        child: poster,
      );
    }

    return Semantics(
      button: true,
      // Reflect the dropped tap handler while the video is resolving, so
      // assistive tech doesn't advertise a dead button.
      enabled: !_isLoading,
      label: 'Play video',
      child: GestureDetector(
        onTap: _isLoading ? null : _play,
        child: Stack(
          alignment: Alignment.center,
          children: [
            poster,
            if (widget.darken)
              Positioned.fill(
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.3)),
              ),
            PlayChip(style: widget.playChipStyle, loading: _isLoading),
          ],
        ),
      ),
    );
  }

  Widget _fill({IconData? icon}) {
    return SizedBox(
      width: double.infinity,
      height: widget.height,
      child: MediaFill(icon: icon ?? Icons.image_outlined),
    );
  }
}
