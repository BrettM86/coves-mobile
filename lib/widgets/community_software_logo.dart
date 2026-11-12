import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../providers/display_preferences_provider.dart';

/// Small logo for the software a community originates from (e.g. Lemmy).
///
/// Renders nothing for software without a known logo, or when the Show
/// software logos setting is off.
class CommunitySoftwareLogo extends StatelessWidget {
  const CommunitySoftwareLogo({
    required this.software,
    this.size = 19,
    super.key,
  });

  /// Origin software name as served by the appview (e.g. `lemmy`).
  final String? software;

  /// Logo width and height. The default is the community page size; post
  /// cards pass a smaller one.
  final double size;

  static const _logos = <String, (String, String)>{
    'lemmy': ('assets/icons/lemmy.svg', 'Lemmy'),
    'piefed': ('assets/icons/piefed.svg', 'PieFed'),
  };

  @override
  Widget build(BuildContext context) {
    // Absent only in widget tests that pump a subtree without it.
    final showLogos =
        context.watch<DisplayPreferencesProvider?>()?.showSoftwareLogos ?? true;
    final logo = _logos[software?.toLowerCase()];
    if (logo == null || !showLogos) {
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
