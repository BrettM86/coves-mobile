/// Bearer-token redaction for debug logs.
///
/// Shared by every service that prints request/response data — credentials
/// must never reach the logs, even in debug builds.
library;

/// Matches a bearer scheme (case-insensitive) followed by any run of
/// non-whitespace characters. Greedy on purpose: a charset-based match
/// would leak the tail of tokens containing characters outside the set.
final RegExp _bearerTokenPattern = RegExp(r'Bearer\s+\S+', caseSensitive: false);

/// Replaces bearer token values with a placeholder so credentials never
/// appear in logs.
String redactBearerTokens(String line) {
  return line.replaceAll(_bearerTokenPattern, 'Bearer [REDACTED]');
}
