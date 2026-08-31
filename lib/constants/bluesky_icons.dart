import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Icons for embedded Bluesky posts.
///
/// Action glyphs are Lucide (ISC, see `assets/icons/lucide/LICENSE`). The
/// butterfly is a Bluesky trademark used nominatively to identify the source
/// of embedded content and the "Sign in with Bluesky" flow.
class BlueskyIcons {
  BlueskyIcons._();

  /// Reply icon — Lucide `message-circle`
  static const String _replySvg = '''
<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" xmlns="http://www.w3.org/2000/svg">
  <path d="M2.992 16.342a2 2 0 0 1 .094 1.167l-1.065 3.29a1 1 0 0 0 1.236 1.168l3.413-.998a2 2 0 0 1 1.099.092 10 10 0 1 0-4.777-4.719"/>
</svg>
''';

  /// Repost icon — Lucide `repeat-2`
  static const String _repostSvg = '''
<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" xmlns="http://www.w3.org/2000/svg">
  <path d="m2 9 3-3 3 3"/>
  <path d="M13 18H7a2 2 0 0 1-2-2V6"/>
  <path d="m22 15-3 3-3-3"/>
  <path d="M11 6h6a2 2 0 0 1 2 2v10"/>
</svg>
''';

  /// Like icon — Lucide `heart`
  static const String _likeSvg = '''
<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" xmlns="http://www.w3.org/2000/svg">
  <path d="M2 9.5a5.5 5.5 0 0 1 9.591-3.676.56.56 0 0 0 .818 0A5.49 5.49 0 0 1 22 9.5c0 2.29-1.5 4-3 5.5l-5.492 5.313a2 2 0 0 1-3 .019L5 15c-1.5-1.5-3-3.2-3-5.5"/>
</svg>
''';

  /// Bluesky butterfly logo (trademark — nominative use only)
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
