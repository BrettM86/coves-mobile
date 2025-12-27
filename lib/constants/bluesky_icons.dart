import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Bluesky SVG icons matching the official bskyembed styling
class BlueskyIcons {
  BlueskyIcons._();

  /// Reply/comment icon
  static const String _replySvg = '''
<svg viewBox="0 0 16 17" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path fill-rule="evenodd" clip-rule="evenodd" d="M1.3335 4.23242C1.3335 3.12785 2.22893 2.23242 3.3335 2.23242H12.6668C13.7714 2.23242 14.6668 3.12785 14.6668 4.23242V10.8991C14.6668 12.0037 13.7714 12.8991 12.6668 12.8991H8.18482L5.00983 14.8041C4.80387 14.9277 4.54737 14.9309 4.33836 14.8126C4.12936 14.6942 4.00016 14.4726 4.00016 14.2324V12.8991H3.3335C2.22893 12.8991 1.3335 12.0037 1.3335 10.8991V4.23242ZM3.3335 3.56576C2.96531 3.56576 2.66683 3.86423 2.66683 4.23242V10.8991C2.66683 11.2673 2.96531 11.5658 3.3335 11.5658H4.66683C5.03502 11.5658 5.3335 11.8642 5.3335 12.2324V13.055L7.65717 11.6608C7.76078 11.5986 7.87933 11.5658 8.00016 11.5658H12.6668C13.035 11.5658 13.3335 11.2673 13.3335 10.8991V4.23242C13.3335 3.86423 13.035 3.56576 12.6668 3.56576H3.3335Z" fill="currentColor"/>
</svg>
''';

  /// Repost icon
  static const String _repostSvg = '''
<svg viewBox="0 0 16 17" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M3.86204 9.76164C4.12239 9.50134 4.54442 9.50131 4.80475 9.76164C5.06503 10.022 5.06503 10.444 4.80475 10.7044L3.94277 11.5663H11.3334C12.0697 11.5663 12.6667 10.9693 12.6667 10.233V8.89966C12.6667 8.53147 12.9652 8.233 13.3334 8.233C13.7015 8.23305 14.0001 8.53151 14.0001 8.89966V10.233C14.0001 11.7057 12.8061 12.8996 11.3334 12.8997H3.94277L4.80475 13.7616C5.06503 14.022 5.06503 14.444 4.80475 14.7044C4.54442 14.9647 4.12239 14.9646 3.86204 14.7044L2.3334 13.1757C1.8127 12.655 1.8127 11.811 2.3334 11.2903L3.86204 9.76164ZM2.00006 7.56633V6.233C2.00006 4.76024 3.19397 3.56633 4.66673 3.56633H12.0574L11.1954 2.70435C10.935 2.444 10.935 2.02199 11.1954 1.76164C11.4557 1.50134 11.8778 1.50131 12.1381 1.76164L13.6667 3.29029C14.1873 3.81096 14.1873 4.65503 13.6667 5.17571L12.1381 6.70435C11.8778 6.96468 11.4557 6.96465 11.1954 6.70435C10.935 6.444 10.935 6.02199 11.1954 5.76164L12.0574 4.89966H4.66673C3.93035 4.89966 3.3334 5.49662 3.3334 6.233V7.56633C3.3334 7.93449 3.03487 8.23294 2.66673 8.233C2.29854 8.233 2.00006 7.93452 2.00006 7.56633Z" fill="currentColor"/>
</svg>
''';

  /// Like/heart icon
  static const String _likeSvg = '''
<svg viewBox="0 0 16 17" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path fill-rule="evenodd" clip-rule="evenodd" d="M11.1561 3.62664C10.3307 3.44261 9.35086 3.65762 8.47486 4.54615C8.34958 4.67323 8.17857 4.74478 8.00012 4.74478C7.82167 4.74478 7.65066 4.67324 7.52538 4.54616C6.64938 3.65762 5.66955 3.44261 4.84416 3.62664C4.0022 3.81438 3.25812 4.43047 2.89709 5.33069C2.21997 7.01907 2.83524 10.1257 8.00015 13.1315C13.165 10.1257 13.7803 7.01906 13.1032 5.33069C12.7421 4.43047 11.998 3.81437 11.1561 3.62664ZM14.3407 4.83438C15.4101 7.50098 14.0114 11.2942 8.32611 14.4808C8.12362 14.5943 7.87668 14.5943 7.6742 14.4808C1.98891 11.2942 0.590133 7.501 1.65956 4.83439C2.1788 3.53968 3.26862 2.61187 4.55399 2.32527C5.68567 2.07294 6.92237 2.32723 8.00012 3.18278C9.07786 2.32723 10.3146 2.07294 11.4462 2.32526C12.7316 2.61186 13.8214 3.53967 14.3407 4.83438Z" fill="currentColor"/>
</svg>
''';

  /// Bluesky butterfly logo
  static const String _logoSvg = '''
<svg viewBox="0 0 18 16" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M3.79 1.775C5.795 3.289 7.951 6.359 8.743 8.006C9.534 6.359 11.69 3.289 13.695 1.775C15.141 0.683 17.485 -0.163 17.485 2.527C17.485 3.064 17.179 7.039 16.999 7.685C16.375 9.929 14.101 10.501 12.078 10.154C15.614 10.76 16.514 12.765 14.571 14.771C10.2 19.283 8.743 12.357 8.743 12.357C8.743 12.357 7.286 19.283 2.914 14.771C0.971 12.765 1.871 10.76 5.407 10.154C3.384 10.501 1.11 9.929 0.486 7.685C0.306 7.039 0 3.064 0 2.527C0 -0.163 2.344 0.683 3.79 1.775Z" fill="currentColor"/>
</svg>
''';

  /// Build reply icon widget
  static Widget reply({double size = 20, Color? color}) {
    return SvgPicture.string(
      _replySvg.replaceAll('currentColor', _colorToHex(color)),
      width: size,
      height: size,
    );
  }

  /// Build repost icon widget
  static Widget repost({double size = 20, Color? color}) {
    return SvgPicture.string(
      _repostSvg.replaceAll('currentColor', _colorToHex(color)),
      width: size,
      height: size,
    );
  }

  /// Build like icon widget
  static Widget like({double size = 20, Color? color}) {
    return SvgPicture.string(
      _likeSvg.replaceAll('currentColor', _colorToHex(color)),
      width: size,
      height: size,
    );
  }

  /// Build Bluesky logo widget
  static Widget logo({double size = 20, Color? color}) {
    return SvgPicture.string(
      _logoSvg.replaceAll('currentColor', _colorToHex(color)),
      width: size,
      height: size * (16 / 18), // Maintain aspect ratio
    );
  }

  /// Convert Color to hex string for SVG
  static String _colorToHex(Color? color) {
    if (color == null) {
      return '#8B98A5';
    }
    // Color.r/g/b are 0.0-1.0, multiply by 255 to get 0-255 range
    final r = (color.r * 255).round().toRadixString(16).padLeft(2, '0');
    final g = (color.g * 255).round().toRadixString(16).padLeft(2, '0');
    final b = (color.b * 255).round().toRadixString(16).padLeft(2, '0');
    return '#$r$g$b'.toUpperCase();
  }
}
