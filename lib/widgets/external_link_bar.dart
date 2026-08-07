import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../models/post.dart';
import '../utils/url_display.dart';
import '../utils/url_launcher.dart';
import 'media/favicon.dart';

/// External link bar widget for displaying clickable links
///
/// Shows the domain favicon, domain name, and an external link icon.
/// Taps launch the URL in an external browser with security validation.
class ExternalLinkBar extends StatelessWidget {
  const ExternalLinkBar({required this.embed, super.key});

  final ExternalEmbed embed;

  @override
  Widget build(BuildContext context) {
    final domain = _extractDomain();
    return Semantics(
      button: true,
      label: 'Open link to $domain in external browser',
      child: InkWell(
        onTap: () async {
          await UrlLauncher.launchExternalUrl(embed.uri, context: context);
        },
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              // Favicon
              Favicon(embed.uri, domain: embed.domain),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  domain,
                  style: TextStyle(
                    color: AppColors.textPrimary.withValues(alpha: 0.7),
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.open_in_new,
                size: 14,
                color: AppColors.textPrimary.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The domain to show in the bar.
  ///
  /// The record's own `domain` wins when it has one; otherwise the host is
  /// parsed out of the uri, and a uri with no host is shown whole so the row
  /// is never blank.
  String _extractDomain() {
    final declared = embed.domain;
    if (declared != null && declared.isNotEmpty) {
      return declared;
    }
    return domainOf(embed.uri) ?? embed.uri;
  }
}
