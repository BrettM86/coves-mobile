import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_colors.dart';
import '../models/user_profile.dart';
import '../utils/date_time_utils.dart';
import '../utils/display_utils.dart';
import 'user_avatar.dart';

/// Collapsing profile header displaying the banner with the avatar and
/// identity row (handle + DID) anchored to the banner's bottom edge.
///
/// All geometry is deterministic: the banner's bottom edge always sits
/// [_bannerOverhang] below the collapsed app bar, and the avatar and
/// identity block are positioned from that edge, so they land in the same
/// place relative to the banner on every screen size and text scale. Bio,
/// stats, and join date live in [ProfileDetails], rendered as normal
/// scroll content below the app bar.
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    required this.profile,
    super.key,
  });

  final UserProfile? profile;

  static const double avatarSize = 80;

  /// How far the banner extends below the toolbar when fully expanded.
  ///
  /// Must be >= [avatarSize] / 2 so the avatar — which straddles the
  /// banner's bottom edge — never rises above the collapsed app bar and
  /// shows through the frosted overlay when the header is collapsed.
  static const double _bannerOverhang = avatarSize / 2;
  static const double _horizontalPadding = 16;
  static const double _bottomPadding = 12;
  static const double _identityTopGap = 6;

  /// Type size for the handle when it fits the identity column outright.
  static const double _handleMaxFontSize = 20;

  /// Floor the handle shrinks to before it gives up and ellipsizes.
  ///
  /// Below this the handle stops reading as the primary identity on the
  /// screen, so a very long handle is truncated rather than shrunk further.
  static const double _handleMinFontSize = 14;

  /// Sliver extent when fully collapsed — mirrors `SliverAppBar.minExtent`
  /// for a primary app bar with no bottom.
  static double collapsedExtentFor(BuildContext context) =>
      MediaQuery.paddingOf(context).top + kToolbarHeight;

  /// Y position of the banner's bottom edge when fully expanded.
  static double bannerBottomFor(BuildContext context) =>
      collapsedExtentFor(context) + _bannerOverhang;

  /// Height of the identity block that hangs below the banner edge:
  /// the avatar's lower half, or the handle + DID column if taller
  /// (e.g. with large accessibility text).
  ///
  /// The handle is measured at [_handleMaxFontSize]; a handle that shrinks
  /// to fit only ever occupies less height than that, so this stays a safe
  /// upper bound and the header's geometry is unaffected by handle length.
  static double _infoHeightFor(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    // Handle line (fontSize 20) + gap + DID line (fontSize 12 + icon).
    final identityBlock =
        _identityTopGap + scaler.scale(26) + 4 + scaler.scale(18);
    return math.max(avatarSize / 2, identityBlock) + _bottomPadding;
  }

  /// Value to pass to [SliverAppBar.expandedHeight].
  ///
  /// Deliberately excludes the status-bar inset: a primary [SliverAppBar]
  /// computes `maxExtent = padding.top + expandedHeight`, so including the
  /// inset here would count it twice and push the banner (and with it the
  /// avatar and DID) further down on devices with taller insets — exactly
  /// the per-device drift this header exists to eliminate.
  static double expandedHeightFor(BuildContext context) =>
      kToolbarHeight + _bannerOverhang + _infoHeightFor(context);

  /// Total sliver extent when fully expanded, including the inset that
  /// [SliverAppBar] adds on top of [expandedHeightFor]. Use this — not
  /// [expandedHeightFor] — as the upper bound when mapping scroll offset
  /// to collapse progress.
  static double maxExtentFor(BuildContext context) =>
      MediaQuery.paddingOf(context).top + expandedHeightFor(context);

  @override
  Widget build(BuildContext context) {
    final minBannerBottom = bannerBottomFor(context);
    final scrimHeight =
        MediaQuery.paddingOf(context).top + kToolbarHeight;
    final infoHeight = _infoHeightFor(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Let the banner absorb overscroll stretch, but never shrink
        // below the toolbar area while the app bar collapses.
        final bannerBottom = math.max(
          minBannerBottom,
          constraints.maxHeight - infoHeight,
        );

        return Stack(
          children: [
            // Banner image (or gradient fallback) — always the bottom layer
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: bannerBottom,
              child: _buildBannerImage(),
            ),
            // Scrim so app bar icons stay legible over any banner
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: scrimHeight,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black45, Colors.transparent],
                  ),
                ),
              ),
            ),
            // Avatar straddling the banner's bottom edge, above the banner
            Positioned(
              top: bannerBottom - avatarSize / 2,
              left: _horizontalPadding,
              child: _buildAvatarCircle(),
            ),
            // Handle and DID beside the avatar, below the banner
            Positioned(
              top: bannerBottom + _identityTopGap,
              left: _horizontalPadding + avatarSize + 12,
              right: _horizontalPadding,
              child: _buildIdentityColumn(context),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBannerImage() {
    if (profile?.banner != null && profile!.banner!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: profile!.banner!,
        fit: BoxFit.cover,
        // Disable fade animation to prevent scroll jitter
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        placeholder: (context, url) => _buildDefaultBanner(),
        errorWidget: (context, url, error) => _buildDefaultBanner(),
      );
    }
    return _buildDefaultBanner();
  }

  Widget _buildDefaultBanner() {
    // TODO: Replace with Image.asset('assets/images/default_banner.png')
    // when the user provides the default banner asset
    return Container(
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

  Widget _buildAvatarCircle() {
    return Container(
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
    );
  }

  Widget _buildIdentityColumn(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HandleText(
          text: profile?.handle != null ? '@${profile!.handle}' : 'Loading...',
        ),
        if (profile?.did != null) ...[
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => _copyDid(context),
            child: Row(
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _copyDid(BuildContext context) {
    Clipboard.setData(ClipboardData(text: profile!.did));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('DID copied to clipboard'),
        duration: Duration(milliseconds: 1500),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildAvatar(double size) {
    return UserAvatar(
      name: profile?.handle ?? '',
      avatarUrl: profile?.avatar,
      size: size,
      fallbackColor: AppColors.primary,
      fallbackIcon: Icon(Icons.person, size: size * 0.5, color: Colors.white),
    );
  }
}

/// The handle line of the identity block, scaled down to fit its column.
///
/// atProto handles are full domains, so their length varies wildly —
/// `@alice.bsky.social` fits the column beside the avatar at full size,
/// while `@somelongname.coves.social` does not. Rather than ellipsizing the
/// user's identity away, the type size steps down from
/// [ProfileHeader._handleMaxFontSize] toward
/// [ProfileHeader._handleMinFontSize] until the whole handle fits on one
/// line. Only a handle still too long at the floor is truncated.
///
/// Stateful purely to memoise the fitted size: this widget rebuilds on every
/// frame while the header collapses, and text measurement is expensive
/// enough that Flutter's own [TextPainter.computeWidth] documents it as
/// something to avoid repeating. None of the measurement inputs change
/// during a collapse, so the cache makes scrolling free.
class _HandleText extends StatefulWidget {
  const _HandleText({required this.text});

  final String text;

  @override
  State<_HandleText> createState() => _HandleTextState();
}

class _HandleTextState extends State<_HandleText> {
  /// Everything the fitted size depends on. A record so equality is
  /// structural — if any input changes, the size is recomputed.
  (String, double, TextStyle, TextScaler, TextDirection)? _cacheKey;
  double _fontSize = ProfileHeader._handleMaxFontSize;

  /// Largest size in [[ProfileHeader._handleMinFontSize],
  /// [ProfileHeader._handleMaxFontSize]] that fits [text] on one line.
  static double _fitFontSize({
    required String text,
    required double available,
    required TextStyle style,
    required TextScaler scaler,
    required TextDirection direction,
  }) {
    // computeWidth disposes the painter it creates; a bare TextPainter here
    // would leak an engine paragraph on every measurement.
    double widthAt(double fontSize) => TextPainter.computeWidth(
          text: TextSpan(
            text: text,
            style: style.copyWith(fontSize: fontSize),
          ),
          maxLines: 1,
          textDirection: direction,
          textScaler: scaler,
        );

    final fullWidth = widthAt(ProfileHeader._handleMaxFontSize);
    if (fullWidth <= available || fullWidth <= 0) {
      return ProfileHeader._handleMaxFontSize;
    }

    // Glyph advances scale nearly linearly with font size, so one ratio
    // lands on (or just past) the right size; the loop then settles the
    // remainder. Non-linear text scaling on some platforms is what makes
    // that verification necessary.
    var fontSize = (ProfileHeader._handleMaxFontSize * available / fullWidth)
        .clamp(
          ProfileHeader._handleMinFontSize,
          ProfileHeader._handleMaxFontSize,
        );
    while (fontSize > ProfileHeader._handleMinFontSize &&
        widthAt(fontSize) > available) {
      fontSize = math.max(ProfileHeader._handleMinFontSize, fontSize - 0.5);
    }
    return fontSize;
  }

  @override
  Widget build(BuildContext context) {
    // Inherit the ambient style so the measurement below uses the same font
    // the Text will actually render with.
    final style = DefaultTextStyle.of(context).style.merge(
          const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        );
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final key = (
          widget.text,
          constraints.maxWidth,
          style,
          scaler,
          direction,
        );
        if (key != _cacheKey) {
          _fontSize = _fitFontSize(
            text: widget.text,
            available: constraints.maxWidth,
            style: style,
            scaler: scaler,
            direction: direction,
          );
          _cacheKey = key;
        }

        return Text(
          widget.text,
          style: style.copyWith(fontSize: _fontSize),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}

/// Bio, stats, and join date shown as normal scroll content below the
/// collapsing [ProfileHeader], so they are never clipped regardless of
/// bio length or device inset.
class ProfileDetails extends StatelessWidget {
  const ProfileDetails({
    required this.profile,
    super.key,
  });

  final UserProfile? profile;

  @override
  Widget build(BuildContext context) {
    final bio = profile?.bio;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (bio != null && bio.isNotEmpty) ...[
            Text(
              bio,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
          ],
          _buildStatsRow(),
          if (profile?.createdAt != null) ...[
            const SizedBox(height: 8),
            Row(
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
          ],
        ],
      ),
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
