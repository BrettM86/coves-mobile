import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Navigation icons rendered from the Lucide SVG assets in `assets/icons/`.
///
/// Lucide is ISC licensed — see `assets/icons/lucide/LICENSE`.
class AppIcon extends StatelessWidget {
  const AppIcon({
    required this.iconName,
    this.size = 28,
    required this.color,
    super.key,
  });
  final String iconName;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/icons/$iconName.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }

  // Convenience constructors for each icon type
  static Widget homeOutline({required Color color, double size = 24}) =>
      AppIcon(iconName: 'home_outline', color: color, size: size);

  static Widget homeFilled({required Color color, double size = 24}) =>
      AppIcon(iconName: 'home_filled', color: color, size: size);

  static Widget search({required Color color, double size = 24}) =>
      AppIcon(iconName: 'search', color: color, size: size);

  /// Lucide `plus` — the "Create" action
  static Widget create({required Color color, double size = 24}) =>
      AppIcon(iconName: 'create', color: color, size: size);

  /// Lucide `compass`
  static Widget communities({required Color color, double size = 24}) =>
      AppIcon(iconName: 'communities', color: color, size: size);

  static Widget bellOutline({required Color color, double size = 24}) =>
      AppIcon(iconName: 'bell_outline', color: color, size: size);

  static Widget bellFilled({required Color color, double size = 24}) =>
      AppIcon(iconName: 'bell_filled', color: color, size: size);

  static Widget userCircleOutline({required Color color, double size = 24}) =>
      AppIcon(iconName: 'user_circle_outline', color: color, size: size);

  static Widget userCircleFilled({required Color color, double size = 24}) =>
      AppIcon(iconName: 'user_circle_filled', color: color, size: size);

  // Minimal variants used by the bottom nav
  static Widget homeSimple({required Color color, double size = 24}) =>
      AppIcon(iconName: 'home_simple', color: color, size: size);

  static Widget personSimple({required Color color, double size = 24}) =>
      AppIcon(iconName: 'person_simple', color: color, size: size);
}
