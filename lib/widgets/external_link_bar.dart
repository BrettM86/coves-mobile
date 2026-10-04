import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../models/post.dart';
import '../utils/url_display.dart';
import '../utils/url_launcher.dart';
import '../utils/url_policy.dart';
import 'media/favicon.dart';

/// External link bar widget for displaying clickable links
///
/// When a tap can open the uri ([isAllowedWebUrl]), shows the site's favicon,
/// the uri's host and an external link icon, and a tap opens the uri in an
/// external browser.
///
/// Any other uri gives an inert bar: the generic link glyph and the uri's
/// own trimmed text ("Invalid link" when it is blank), with no external link
/// icon and nothing to tap. A screen reader reads that text as plain text.
class ExternalLinkBar extends StatelessWidget {
  const ExternalLinkBar({required this.embed, super.key});

  final ExternalEmbed embed;

  @override
  Widget build(BuildContext context) {
    final label = linkLabelOf(embed.uri);
    final isOpenable = isAllowedWebUrl(embed.uri);
    final bar = Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // Favicon
          Favicon(embed.uri),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.textPrimary.withValues(alpha: 0.7),
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isOpenable) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.open_in_new,
              size: 14,
              color: AppColors.textPrimary.withValues(alpha: 0.7),
            ),
          ],
        ],
      ),
    );

    if (!isOpenable) {
      return bar;
    }

    return Semantics(
      button: true,
      label: 'Open link to $label in external browser',
      child: InkWell(
        onTap: () async {
          await UrlLauncher.launchExternalUrl(embed.uri, context: context);
        },
        child: bar,
      ),
    );
  }
}
