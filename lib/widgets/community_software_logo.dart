import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Small logo for the software a community originates from (e.g. Lemmy).
///
/// Renders nothing for software without a known logo.
class CommunitySoftwareLogo extends StatelessWidget {
  const CommunitySoftwareLogo({
    required this.software,
    this.size = 19,
    super.key,
  });

  /// Origin software name as served by the appview (e.g. `lemmy`).
  final String? software;

  /// Logo width and height; about a third larger than the community name font.
  final double size;

  static const _logos = <String, (String, String)>{
    'lemmy': ('assets/icons/lemmy.svg', 'Lemmy'),
    'piefed': ('assets/icons/piefed.svg', 'PieFed'),
  };

  @override
  Widget build(BuildContext context) {
    final logo = _logos[software?.toLowerCase()];
    if (logo == null) {
      return const SizedBox.shrink();
    }
    final (asset, label) = logo;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: SvgPicture.asset(
        asset,
        width: size,
        height: size,
        semanticsLabel: label,
      ),
    );
  }
}
