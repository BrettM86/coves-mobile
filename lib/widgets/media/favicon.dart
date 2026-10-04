import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../utils/url_display.dart';
import '../../utils/url_policy.dart';

/// The site icon for a link, fetched from Google's favicon service for the
/// host of the link, which is the site a tap opens.
///
/// Shows a generic link glyph instead when a tap cannot open the link
/// ([isAllowedWebUrl] rejects it, even if it has a host, as
/// `ftp://paypal.com/` does), or when the fetch fails, so every link row
/// shows something and no dead link wears a real site's icon.
class Favicon extends StatelessWidget {
  const Favicon(this.url, {this.size = 18, super.key});

  /// The link this icon stands for.
  final String url;

  final double size;

  @override
  Widget build(BuildContext context) {
    final host = isAllowedWebUrl(url) ? domainOf(url) : null;
    if (host == null) {
      return _fallback;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: CachedNetworkImage(
        // The host is record-supplied text, so it is passed as a query
        // parameter for [Uri] to encode rather than interpolated: a value
        // like `evil.com&sz=999` must stay one parameter, not become two.
        imageUrl: Uri.https('www.google.com', '/s2/favicons', {
          'domain': host,
          'sz': '32',
        }).toString(),
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (context, url) => _fallback,
        errorWidget: (context, url, error) => _fallback,
      ),
    );
  }

  Widget get _fallback => Icon(
    Icons.link,
    size: size,
    color: AppColors.textPrimary.withValues(alpha: 0.7),
  );
}
