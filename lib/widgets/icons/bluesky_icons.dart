import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Bluesky-style navigation icons using SVG assets
/// These icons match the design from Bluesky's social-app
class BlueSkyIcon extends StatelessWidget {
  final String iconName;
  final double size;
  final Color color;

  const BlueSkyIcon({
    required this.iconName,
    this.size = 28,
    required this.color,
    super.key,
  });

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
  static Widget homeOutline({required Color color, double size = 28}) =>
      BlueSkyIcon(iconName: 'home_outline', color: color, size: size);

  static Widget homeFilled({required Color color, double size = 28}) =>
      BlueSkyIcon(iconName: 'home_filled', color: color, size: size);

  static Widget search({required Color color, double size = 28}) =>
      BlueSkyIcon(iconName: 'search', color: color, size: size);

  static Widget plus({required Color color, double size = 28}) =>
      BlueSkyIcon(iconName: 'plus', color: color, size: size);

  static Widget bellOutline({required Color color, double size = 28}) =>
      BlueSkyIcon(iconName: 'bell_outline', color: color, size: size);

  static Widget bellFilled({required Color color, double size = 28}) =>
      BlueSkyIcon(iconName: 'bell_filled', color: color, size: size);

  static Widget userCircleOutline({required Color color, double size = 28}) =>
      BlueSkyIcon(iconName: 'user_circle_outline', color: color, size: size);

  static Widget userCircleFilled({required Color color, double size = 28}) =>
      BlueSkyIcon(iconName: 'user_circle_filled', color: color, size: size);

  // Simpler versions (inspired by other social apps)
  static Widget homeSimple({required Color color, double size = 28}) =>
      BlueSkyIcon(iconName: 'home_simple', color: color, size: size);

  static Widget personSimple({required Color color, double size = 28}) =>
      BlueSkyIcon(iconName: 'person_simple', color: color, size: size);
}
