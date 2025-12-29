import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../models/post.dart';
import '../utils/url_launcher.dart';

/// Source link bar widget for displaying clickable source links
///
/// Shows the domain favicon, domain name, and an external link icon.
/// Visual styling matches ExternalLinkBar for consistency.
/// Taps launch the URL in an external browser with security validation.
class SourceLinkBar extends StatelessWidget {
  const SourceLinkBar({required this.source, super.key});

  final EmbedSource source;

  @override
  Widget build(BuildContext context) {
    final domain = _extractDomain();
    return Semantics(
      button: true,
      label: 'Open source link to $domain in external browser',
      child: InkWell(
        onTap: () async {
          await UrlLauncher.launchExternalUrl(source.uri, context: context);
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

  /// Extracts the domain from the source
  String _extractDomain() {
    // Use domain field if available
    if (source.domain != null && source.domain!.isNotEmpty) {
      return source.domain!;
    }

    // Otherwise parse from URI
    try {
      final uri = Uri.parse(source.uri);
      if (uri.host.isNotEmpty) {
        return uri.host;
      }
    } on FormatException catch (e) {
      if (kDebugMode) {
        debugPrint('SourceLinkBar: Failed to parse URI "${source.uri}": $e');
      }
    }

    // Fallback to full URI if domain extraction fails
    return source.uri;
  }

  /// Builds the favicon widget
  Widget _buildFavicon() {
    // Extract domain for favicon URL
    var domain = source.domain;
    if (domain == null || domain.isEmpty) {
      try {
        final uri = Uri.parse(source.uri);
        domain = uri.host;
      } on FormatException catch (e) {
        if (kDebugMode) {
          debugPrint('SourceLinkBar: Failed to parse URI "${source.uri}": $e');
        }
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
