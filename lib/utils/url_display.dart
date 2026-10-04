/// Display helpers for URLs that came out of a record.
///
/// Three surfaces used to carry their own copy of the parse-and-fall-back
/// dance (the two link bars and the detail view's link rows). Every function
/// here is total: the input is untrusted record data, so a malformed URL
/// yields a fallback rather than an exception.
///
/// A link is named by its host only when a tap can open it, that is when
/// [isAllowedWebUrl] accepts it, the same check `UrlLauncher` applies. Uri
/// finds the host `paypal.com` in `ftp://paypal.com/` too, but a tap refuses
/// that link, so it is shown as written rather than as "paypal.com".
library;

import 'url_policy.dart';

/// The host of [url], lowercased, or null when it has none — unparseable,
/// relative, or authority-less. Never throws.
///
/// This says nothing about whether a tap can open [url]: `ftp://paypal.com/`
/// has the host `paypal.com`. Check [isAllowedWebUrl] before showing it.
String? domainOf(String url) {
  final host = _tryParse(url)?.host;
  if (host == null || host.isEmpty) {
    return null;
  }
  return host.toLowerCase();
}

/// The text a link bar shows for [uri]: its host, as [domainOf] gives it,
/// when [isAllowedWebUrl] accepts [uri], because that host is the site a tap
/// opens.
///
/// Any other [uri], with a host or not, is one a tap refuses, so it is shown
/// as its own text, trimmed of surrounding whitespace, or "Invalid link" when
/// it is blank. Never throws.
String linkLabelOf(String uri) {
  final host = isAllowedWebUrl(uri) ? domainOf(uri) : null;
  if (host != null) {
    return host;
  }
  return _unopenableLinkLabel(uri);
}

/// [url] with the scheme, port, query and fragment stripped:
/// `example.com` or `example.com/a/b`, when [isAllowedWebUrl] accepts [url].
///
/// Any other [url] is shown as [linkLabelOf] shows it: trimmed, or "Invalid
/// link" when it is blank. Never throws.
String hostAndPath(String url) {
  final uri = isAllowedWebUrl(url) ? _tryParse(url) : null;
  if (uri == null || uri.host.isEmpty) {
    return _unopenableLinkLabel(url);
  }

  final path = uri.path;
  if (path.isEmpty || path == '/') {
    return uri.host;
  }
  return '${uri.host}$path';
}

/// The label for a link a tap cannot open: [uri] trimmed of surrounding
/// whitespace, or "Invalid link" when nothing is left.
String _unopenableLinkLabel(String uri) {
  final trimmed = uri.trim();
  if (trimmed.isEmpty) {
    return 'Invalid link';
  }
  return trimmed;
}

/// [Uri.parse] without the throw.
Uri? _tryParse(String url) {
  try {
    return Uri.parse(url);
  } on FormatException {
    return null;
  }
}
