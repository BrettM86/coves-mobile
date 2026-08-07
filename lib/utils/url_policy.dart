// The single canonical http/https allowlist.
//
// Every place that decides whether a user- or network-supplied string may be
// opened, rendered or posted as a web link routes through [isAllowedWebUrl].
// Keep this file free of Flutter imports: the model layer depends on it, and
// models must stay usable without a widget binding.

/// URL schemes the app is willing to treat as web links.
const Set<String> kAllowedWebSchemes = {'http', 'https'};

/// Whether [url] is a web link the app may open, render or publish.
///
/// True iff [url] parses, carries a scheme in [kAllowedWebSchemes]
/// (case-insensitively), and has a non-empty host.
///
/// The host check is load-bearing, not belt-and-braces: `http:foo` and
/// `https:///path` carry an allowed scheme with no authority at all, and a
/// scheme prefix test (`scheme.startsWith('http')`) would wave through
/// `httpx://evil.com`. Never throws, whatever the input.
bool isAllowedWebUrl(String? url) {
  if (url == null || url.isEmpty) {
    return false;
  }

  final parsed = Uri.tryParse(url);
  if (parsed == null) {
    return false;
  }

  // Uri lowercases the scheme while parsing, but compare case-insensitively
  // anyway so 'HTTPS://…' cannot turn on a future refactor.
  return kAllowedWebSchemes.contains(parsed.scheme.toLowerCase()) &&
      parsed.host.isNotEmpty;
}
