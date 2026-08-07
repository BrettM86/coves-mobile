/// Display helpers for URLs that came out of a record.
///
/// Three surfaces used to carry their own copy of the parse-and-fall-back
/// dance (the two link bars and the detail view's link rows). Both functions
/// here are total: the input is untrusted record data, so a malformed URL
/// yields a fallback rather than an exception.
library;

/// The host of [url], lowercased, or null when it has none — unparseable,
/// relative, or authority-less. Never throws.
String? domainOf(String url) {
  final host = _tryParse(url)?.host;
  if (host == null || host.isEmpty) {
    return null;
  }
  return host.toLowerCase();
}

/// [url] with the scheme, port, query and fragment stripped:
/// `example.com` or `example.com/a/b`.
///
/// Returns [url] unchanged when it has no host, so a bare string still shows
/// the user something. Never throws.
String hostAndPath(String url) {
  final uri = _tryParse(url);
  if (uri == null || uri.host.isEmpty) {
    return url;
  }

  final path = uri.path;
  if (path.isEmpty || path == '/') {
    return uri.host;
  }
  return '${uri.host}$path';
}

/// [Uri.parse] without the throw.
Uri? _tryParse(String url) {
  try {
    return Uri.parse(url);
  } on FormatException {
    return null;
  }
}
