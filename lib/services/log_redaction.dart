/// Credential redaction for debug logs.
///
/// Shared by every service that prints request/response data — credentials
/// must never reach the logs, even in debug builds. Covers two shapes:
/// Authorization-header text (`Bearer <token>`) and token-like key/value
/// fields in JSON or Map.toString() output (`access_token: ...`,
/// `"refreshJwt": "..."`). Anything else (e.g. a bare token with no key
/// next to it) is NOT caught — don't log raw bodies from new token-bearing
/// endpoints on the strength of this function alone.
library;

/// Matches a bearer scheme (case-insensitive) followed by any run of
/// non-whitespace characters. Greedy on purpose: a charset-based match
/// would leak the tail of tokens containing characters outside the set.
final RegExp _bearerTokenPattern = RegExp(
  r'Bearer\s+\S+',
  caseSensitive: false,
);

/// Matches token-like fields in JSON bodies (`"access_token": "..."`) and
/// Dart Map.toString() output (`sealed_token: ...`). The key must contain
/// `token` or `jwt`; the value run stops at whitespace, commas, or braces
/// so surrounding structure survives.
final RegExp _tokenFieldPattern = RegExp(
  '(["\']?[a-z_-]*(?:token|jwt)[a-z_-]*["\']?\\s*[:=]\\s*)["\']?[^"\'\\s,}]+["\']?',
  caseSensitive: false,
);

/// Replaces bearer tokens and token-like field values with a placeholder
/// so credentials never appear in logs.
String redactBearerTokens(String line) {
  return line
      .replaceAll(_bearerTokenPattern, 'Bearer [REDACTED]')
      .replaceAllMapped(_tokenFieldPattern, (m) => '${m[1]}[REDACTED]');
}
