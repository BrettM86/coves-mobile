import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../constants/app_colors.dart';
import '../../constants/bluesky_icons.dart';
import '../../models/bluesky_profile_import.dart';
import '../../utils/bluesky_import_motion.dart';
import '../media/image_error.dart';
import 'import_card_style.dart';

/// Wraps the field region of the choice at [index] (the toggle, its focus
/// and its gestures); identity on the floating drag copy.
typedef ImportFieldWrapper = Widget Function(int index, Widget child);

const _labelFontSize = 13.0;
const _labelGap = 6.0;
const _labelIconSize = 18.0;
const _labelPadding = 12.0;

/// Desaturates a left-out field.
const _grayscale = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0, //
]);

/// The Bluesky profile card: label strip, banner, avatar, name, handle and
/// bio, each row at the fixed height of [geometry].
class BlueskyCardFace extends StatelessWidget {
  const BlueskyCardFace({
    required this.geometry,
    required this.palette,
    required this.choices,
    required this.checked,
    required this.handle,
    this.wrapField,
    this.inkDuration = Duration.zero,
    this.hidesExcludedFields = false,
    super.key,
  });

  final ImportCardGeometry geometry;
  final ImportCardPalette palette;
  final List<BlueskyImportChoice> choices;
  final List<bool> checked;
  final String? handle;
  final ImportFieldWrapper? wrapField;

  /// How long the text takes to change colour at the blend midpoint.
  final Duration inkDuration;

  /// Whether fields left out are blank instead of greyed with an "Off"
  /// pill, as on the copy of the card that travels: only included fields
  /// travel. Each row keeps its height either way.
  final bool hidesExcludedFields;

  int _indexOf(BlueskyProfileField field) =>
      choices.indexWhere((choice) => choice.view.field == field);

  @override
  Widget build(BuildContext context) {
    final g = geometry;
    final bannerIndex = _indexOf(BlueskyProfileField.banner);
    final avatarIndex = _indexOf(BlueskyProfileField.avatar);
    final nameIndex = _indexOf(BlueskyProfileField.displayName);
    final bioIndex = _indexOf(BlueskyProfileField.description);
    final bannerBottom = g.labelStrip + g.banner;
    final handle = this.handle;

    Widget field(int index, Widget value, {required _BadgePlace badge}) {
      final included = checked[index];
      final content = _FieldContent(
        included: included,
        hidden: hidesExcludedFields && !included,
        badge: badge,
        palette: palette,
        child: value,
      );
      return wrapField?.call(index, content) ?? content;
    }

    return SizedBox(
      height: g.height,
      child: AnimatedDefaultTextStyle(
        duration: inkDuration,
        style: DefaultTextStyle.of(context).style.copyWith(color: palette.ink),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(ImportCardGeometry.radius),
            border: Border.all(
              color: palette.border,
              width: ImportCardGeometry.border,
            ),
          ),
          child: Padding(
            // Inside the 2px border, so the banner doesn't paint over it.
            padding: const EdgeInsets.all(ImportCardGeometry.border),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                ImportCardGeometry.radius - ImportCardGeometry.border,
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: g.labelStrip,
                    child: ExcludeSemantics(
                      child: _LabelStrip(
                        icon: BlueskyIcons.logo(
                          size: _labelIconSize,
                          color: palette.accent,
                        ),
                        label: 'Bluesky',
                      ),
                    ),
                  ),
                  Positioned(
                    top: g.labelStrip,
                    left: 0,
                    right: 0,
                    height: g.banner,
                    child: bannerIndex < 0
                        ? ColoredBox(color: palette.placeholder)
                        : field(
                            bannerIndex,
                            _ChoiceImage(
                              view: choices[bannerIndex].view,
                              placeholder: palette.placeholder,
                              muted: palette.muted,
                              isAvatar: false,
                            ),
                            badge: _BadgePlace.topRight,
                          ),
                  ),
                  Positioned(
                    top: bannerBottom - g.avatarOverlap,
                    left: ImportCardGeometry.horizontalPadding,
                    width: g.avatar,
                    height: g.avatar,
                    child: _AvatarRing(
                      ringColor: palette.surface,
                      child: avatarIndex < 0
                          ? _DefaultAvatar(
                              background: palette.placeholder,
                              foreground: palette.muted,
                            )
                          : field(
                              avatarIndex,
                              ClipOval(
                                child: _ChoiceImage(
                                  view: choices[avatarIndex].view,
                                  placeholder: palette.placeholder,
                                  muted: palette.muted,
                                  isAvatar: true,
                                ),
                              ),
                              badge: _BadgePlace.bottomRight,
                            ),
                    ),
                  ),
                  if (nameIndex >= 0)
                    Positioned(
                      top: bannerBottom,
                      left: g.textLeft,
                      right: ImportCardGeometry.horizontalPadding,
                      height: g.nameRow,
                      child: field(
                        nameIndex,
                        _SingleLine(
                          choices[nameIndex].view.bluesky ?? '',
                          style: TextStyle(
                            fontSize: g.nameFontSize,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                        badge: _BadgePlace.end,
                      ),
                    ),
                  if (handle != null)
                    Positioned(
                      top: bannerBottom + g.nameRow,
                      left: g.textLeft,
                      right: ImportCardGeometry.horizontalPadding,
                      height: g.handleRow,
                      child: ExcludeSemantics(
                        child: _SingleLine(
                          '@$handle',
                          style: TextStyle(
                            color: palette.muted,
                            fontSize: 14,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ),
                  if (bioIndex >= 0)
                    Positioned(
                      top: bannerBottom + g.nameRow + g.handleRow,
                      left: ImportCardGeometry.horizontalPadding,
                      right: ImportCardGeometry.horizontalPadding,
                      height: g.bioRow,
                      child: field(
                        bioIndex,
                        Padding(
                          padding: EdgeInsets.only(top: g.bioTopPadding),
                          child: Text(
                            bioPreview(choices[bioIndex].view.bluesky ?? ''),
                            maxLines: g.bioLines,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: ImportCardGeometry.bioFontSize,
                              height:
                                  ImportCardGeometry.bioLineHeight /
                                  ImportCardGeometry.bioFontSize,
                            ),
                          ),
                        ),
                        badge: _BadgePlace.endTop,
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

/// The values the Coves card shows once the Bluesky card has landed: the
/// imported fields, and the header's defaults for the rest.
@immutable
class CovesHeaderCopy {
  const CovesHeaderCopy({
    this.bannerUrl,
    this.avatarUrl,
    this.displayName,
    this.handle,
    this.bio,
  });

  final String? bannerUrl;
  final String? avatarUrl;
  final String? displayName;
  final String? handle;
  final String? bio;
}

/// How far each slot of the Coves card has popped in, from 0 to 1.
@immutable
class CovesSlotFill {
  const CovesSlotFill({
    required this.banner,
    required this.avatar,
    required this.name,
    required this.bio,
  });

  static const full = CovesSlotFill(banner: 1, avatar: 1, name: 1, bio: 1);

  final double banner;
  final double avatar;
  final double name;
  final double bio;
}

/// The Coves card: hollow, with placeholders and a dashed outline, until a
/// [header] copy fills its slots.
class CovesCardFace extends StatelessWidget {
  const CovesCardFace({
    required this.geometry,
    required this.palette,
    required this.outlineColor,
    required this.solidness,
    required this.showDropHere,
    this.header,
    this.fill = CovesSlotFill.full,
    this.scalesPopIn = true,
    super.key,
  });

  final ImportCardGeometry geometry;
  final CovesTargetPalette palette;
  final Color outlineColor;

  /// 0 for a dashed outline, 1 for a solid one.
  final double solidness;
  final bool showDropHere;
  final CovesHeaderCopy? header;
  final CovesSlotFill fill;

  /// Whether slot contents scale as they pop in; with reduced motion they
  /// only fade.
  final bool scalesPopIn;

  @override
  Widget build(BuildContext context) {
    final g = geometry;
    final header = this.header;
    final bannerBottom = g.labelStrip + g.banner;
    final placeholder = palette.placeholder;

    Widget bar(double width) => Container(
      width: width,
      height: 10,
      decoration: BoxDecoration(
        color: placeholder,
        borderRadius: BorderRadius.circular(5),
      ),
    );

    Widget popIn(double amount, Widget child) {
      if (amount <= 0) {
        return const SizedBox.shrink();
      }
      return Opacity(
        opacity: amount.clamp(0.0, 1.0),
        child: scalesPopIn
            ? Transform.scale(
                scale: 0.9 + 0.1 * Curves.easeOutBack.transform(amount),
                child: child,
              )
            : child,
      );
    }

    final displayName = header?.displayName ?? header?.handle;
    return SizedBox(
      height: g.height,
      child: CustomPaint(
        foregroundPainter: DashedOutlinePainter(
          color: outlineColor,
          solidness: solidness,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(ImportCardGeometry.radius),
          ),
          child: Padding(
            padding: const EdgeInsets.all(ImportCardGeometry.border),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                ImportCardGeometry.radius - ImportCardGeometry.border,
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: g.labelStrip,
                    child: _LabelStrip(
                      icon: SvgPicture.asset(
                        'assets/logo/lil_dude.svg',
                        width: _labelIconSize,
                        height: _labelIconSize,
                        excludeFromSemantics: true,
                      ),
                      label: 'Coves',
                      color: palette.ink,
                      trailing: showDropHere
                          ? Text(
                              'Drop here',
                              style: TextStyle(
                                color: palette.muted,
                                fontSize: _labelFontSize,
                                fontWeight: FontWeight.w500,
                              ),
                            )
                          : null,
                    ),
                  ),
                  // Placeholders.
                  Positioned(
                    top: g.labelStrip,
                    left: 0,
                    right: 0,
                    height: g.banner,
                    child: ColoredBox(color: placeholder),
                  ),
                  Positioned(
                    top: bannerBottom - g.avatarOverlap,
                    left: ImportCardGeometry.horizontalPadding,
                    width: g.avatar,
                    height: g.avatar,
                    child: _AvatarRing(
                      ringColor: palette.surface,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: placeholder,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: bannerBottom,
                    left: g.textLeft,
                    right: ImportCardGeometry.horizontalPadding,
                    height: g.nameRow + g.handleRow,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [bar(120), const SizedBox(height: 10), bar(80)],
                    ),
                  ),
                  Positioned(
                    top: bannerBottom + g.nameRow + g.handleRow,
                    left: ImportCardGeometry.horizontalPadding,
                    right: ImportCardGeometry.horizontalPadding,
                    height: g.bioRow,
                    child: Padding(
                      padding: EdgeInsets.only(top: g.bioTopPadding + 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FractionallySizedBox(
                            widthFactor: 1,
                            child: bar(double.infinity),
                          ),
                          const SizedBox(height: 10),
                          FractionallySizedBox(
                            widthFactor: 0.6,
                            child: bar(double.infinity),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // The header copy, popping into the slots in turn.
                  if (header != null) ...[
                    Positioned(
                      top: g.labelStrip,
                      left: 0,
                      right: 0,
                      height: g.banner,
                      child: popIn(
                        fill.banner,
                        header.bannerUrl == null
                            ? const _DefaultCovesBanner()
                            : _NetworkImage(
                                url: header.bannerUrl!,
                                placeholder: placeholder,
                              ),
                      ),
                    ),
                    Positioned(
                      top: bannerBottom - g.avatarOverlap,
                      left: ImportCardGeometry.horizontalPadding,
                      width: g.avatar,
                      height: g.avatar,
                      child: popIn(
                        fill.avatar,
                        _AvatarRing(
                          ringColor: palette.surface,
                          child: header.avatarUrl == null
                              ? _DefaultAvatar(
                                  background: placeholder,
                                  foreground: palette.muted,
                                )
                              : ClipOval(
                                  child: _NetworkImage(
                                    url: header.avatarUrl!,
                                    placeholder: placeholder,
                                  ),
                                ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: bannerBottom,
                      left: g.textLeft,
                      right: ImportCardGeometry.horizontalPadding,
                      height: g.nameRow + g.handleRow,
                      child: popIn(
                        fill.name,
                        ColoredBox(
                          color: palette.surface,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                height: g.nameRow,
                                child: _SingleLine(
                                  displayName ?? '',
                                  style: TextStyle(
                                    color: palette.ink,
                                    fontSize: g.nameFontSize,
                                    fontWeight: FontWeight.w700,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                              SizedBox(
                                height: g.handleRow,
                                child: _SingleLine(
                                  header.handle == null
                                      ? ''
                                      : '@${header.handle}',
                                  style: TextStyle(
                                    color: palette.muted,
                                    fontSize: 14,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: bannerBottom + g.nameRow + g.handleRow,
                      left: ImportCardGeometry.horizontalPadding,
                      right: ImportCardGeometry.horizontalPadding,
                      height: g.bioRow,
                      child: popIn(
                        fill.bio,
                        ColoredBox(
                          color: palette.surface,
                          child: Padding(
                            padding: EdgeInsets.only(top: g.bioTopPadding),
                            child: Text(
                              bioPreview(header.bio ?? ''),
                              maxLines: g.bioLines,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.ink,
                                fontSize: ImportCardGeometry.bioFontSize,
                                height:
                                    ImportCardGeometry.bioLineHeight /
                                    ImportCardGeometry.bioFontSize,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LabelStrip extends StatelessWidget {
  const _LabelStrip({
    required this.icon,
    required this.label,
    this.color,
    this.trailing,
  });

  final Widget icon;
  final String label;
  final Color? color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final trailing = this.trailing;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _labelPadding),
      child: Row(
        children: [
          ExcludeSemantics(child: icon),
          const SizedBox(width: _labelGap),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: _labelFontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// A single line of text centred vertically in its row, with an ellipsis.
class _SingleLine extends StatelessWidget {
  const _SingleLine(this.text, {required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}

class _AvatarRing extends StatelessWidget {
  const _AvatarRing({required this.ringColor, required this.child});

  final Color ringColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: ringColor, shape: BoxShape.circle),
      child: Padding(
        padding: const EdgeInsets.all(ImportCardGeometry.avatarRing),
        child: child,
      ),
    );
  }
}

class _DefaultAvatar extends StatelessWidget {
  const _DefaultAvatar({required this.background, required this.foreground});

  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: LayoutBuilder(
        builder: (context, constraints) => Icon(
          Icons.person,
          color: foreground,
          size: constraints.maxWidth * 0.6,
        ),
      ),
    );
  }
}

/// The Coves profile header's banner when none is set.
class _DefaultCovesBanner extends StatelessWidget {
  const _DefaultCovesBanner();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
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
}

class _NetworkImage extends StatelessWidget {
  const _NetworkImage({required this.url, required this.placeholder});

  final String url;
  final Color placeholder;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      cacheManager: ImageCacheScope.of(context),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholder: (context, url) => ColoredBox(color: placeholder),
      errorWidget: (context, url, error) => ColoredBox(color: placeholder),
    );
  }
}

class _ChoiceImage extends StatelessWidget {
  const _ChoiceImage({
    required this.view,
    required this.placeholder,
    required this.muted,
    required this.isAvatar,
  });

  final BlueskyProfileImportFieldView view;
  final Color placeholder;
  final Color muted;
  final bool isAvatar;

  @override
  Widget build(BuildContext context) {
    final imageUrl = view.blueskyImageUrl;
    if (imageUrl == null) {
      return ColoredBox(color: placeholder);
    }
    return CachedNetworkImage(
      imageUrl: imageUrl,
      cacheManager: ImageCacheScope.of(context),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholder: (context, url) => ColoredBox(color: placeholder),
      errorWidget: (context, url, error) => ColoredBox(
        color: placeholder,
        child: Icon(
          isAvatar ? Icons.person : Icons.broken_image_outlined,
          color: muted,
        ),
      ),
    );
  }
}

enum _BadgePlace { end, endTop, topRight, bottomRight }

/// A field's value, greyed out with an "Off" pill while it is left out.
class _FieldContent extends StatelessWidget {
  const _FieldContent({
    required this.included,
    required this.hidden,
    required this.badge,
    required this.palette,
    required this.child,
  });

  final bool included;

  /// Shows nothing in the field's place, keeping its size.
  final bool hidden;
  final _BadgePlace badge;
  final ImportCardPalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (hidden) {
      return const SizedBox.shrink();
    }
    final value = included
        ? child
        : Opacity(
            opacity: 0.4,
            child: ColorFiltered(colorFilter: _grayscale, child: child),
          );
    final pill = _OffPill(palette: palette);
    switch (badge) {
      case _BadgePlace.end:
      case _BadgePlace.endTop:
        return Row(
          crossAxisAlignment: badge == _BadgePlace.end
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Expanded(child: value),
            if (!included)
              Padding(
                padding: EdgeInsets.only(
                  left: 8,
                  top: badge == _BadgePlace.endTop ? 10 : 0,
                ),
                child: pill,
              ),
          ],
        );
      case _BadgePlace.topRight:
      case _BadgePlace.bottomRight:
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            value,
            if (!included)
              Align(
                alignment: badge == _BadgePlace.topRight
                    ? Alignment.topRight
                    : Alignment.bottomRight,
                child: Padding(
                  padding: EdgeInsets.all(
                    badge == _BadgePlace.topRight ? 6 : 0,
                  ),
                  child: pill,
                ),
              ),
          ],
        );
    }
  }
}

class _OffPill extends StatelessWidget {
  const _OffPill({required this.palette});

  final ImportCardPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: palette.ink,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Off',
        style: TextStyle(
          color: palette.surface,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
      ),
    );
  }
}

/// A rounded 2px outline that is dashed at [solidness] 0 and solid at 1, the
/// gaps closing in between.
class DashedOutlinePainter extends CustomPainter {
  const DashedOutlinePainter({required this.color, required this.solidness});

  final Color color;
  final double solidness;

  static const _dash = 6.0;
  static const _gap = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = ImportCardGeometry.border;
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(ImportCardGeometry.border / 2),
          const Radius.circular(
            ImportCardGeometry.radius - ImportCardGeometry.border / 2,
          ),
        ),
      );
    final gap = _gap * (1 - solidness.clamp(0.0, 1.0));
    if (gap < 0.05) {
      canvas.drawPath(outline, paint);
      return;
    }
    for (final metric in outline.computeMetrics()) {
      for (
        var distance = 0.0;
        distance < metric.length;
        distance += _dash + gap
      ) {
        canvas.drawPath(metric.extractPath(distance, distance + _dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(DashedOutlinePainter oldDelegate) =>
      oldDelegate.solidness != solidness || oldDelegate.color != color;
}
