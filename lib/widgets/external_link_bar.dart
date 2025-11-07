import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../models/post.dart';
import '../utils/url_launcher.dart';

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
              _buildFavicon(),
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

  /// Extracts the domain from the embed
  String _extractDomain() {
    // Use domain field if available
    if (embed.domain != null && embed.domain!.isNotEmpty) {
      return embed.domain!;
    }

    // Otherwise parse from URI
    try {
      final uri = Uri.parse(embed.uri);
      if (uri.host.isNotEmpty) {
        return uri.host;
      }
    } on FormatException {
      // Invalid URI, fall through to fallback
    }

    // Fallback to full URI if domain extraction fails
    return embed.uri;
  }

  /// Builds the favicon widget
  Widget _buildFavicon() {
    // Extract domain for favicon URL
    var domain = embed.domain;
    if (domain == null || domain.isEmpty) {
      try {
        final uri = Uri.parse(embed.uri);
        domain = uri.host;
      } on FormatException {
        domain = null;
      }
    }

    if (domain == null || domain.isEmpty) {
      // Fallback to link icon if we can't get the domain
      return Icon(
        Icons.link,
        size: 18,
        color: AppColors.textPrimary.withValues(alpha: 0.7),
      );
    }

    // Use Google's favicon service
    final faviconUrl =
        'https://www.google.com/s2/favicons?domain=$domain&sz=32';

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: CachedNetworkImage(
        imageUrl: faviconUrl,
        width: 18,
        height: 18,
        fit: BoxFit.cover,
        placeholder:
            (context, url) => Icon(
              Icons.link,
              size: 18,
              color: AppColors.textPrimary.withValues(alpha: 0.7),
            ),
        errorWidget:
            (context, url, error) => Icon(
              Icons.link,
              size: 18,
              color: AppColors.textPrimary.withValues(alpha: 0.7),
            ),
      ),
    );
  }
}
