import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../utils/url_display.dart';

/// The site icon for a link, fetched from Google's favicon service.
///
/// Falls back to a generic link glyph whenever there is no domain to ask
/// about, or the fetch fails — every link row shows something.
class Favicon extends StatelessWidget {
  const Favicon(this.url, {this.domain, this.size = 18, super.key});

  /// The link this icon stands for.
  final String url;

  /// The domain the record declared, preferred over parsing [url] when the
  /// AppView supplied one.
  final String? domain;

  final double size;

  String? get _domain {
    final declared = domain;
    if (declared != null && declared.isNotEmpty) {
      return declared;
    }
    return domainOf(url);
  }

  @override
  Widget build(BuildContext context) {
    final domain = _domain;
    if (domain == null) {
      return _fallback;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: CachedNetworkImage(
        // The domain is record-supplied text, so it is passed as a query
        // parameter for [Uri] to encode rather than interpolated: a value
        // like `evil.com&sz=999` must stay one parameter, not become two.
        imageUrl: Uri.https('www.google.com', '/s2/favicons', {
          'domain': domain,
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
