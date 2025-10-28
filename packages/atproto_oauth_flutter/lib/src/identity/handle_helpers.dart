import 'identity_resolver_error.dart';

/// Normalizes a handle to lowercase.
String normalizeHandle(String handle) => handle.toLowerCase();

/// Checks if a handle is valid according to atProto spec.
///
/// A valid handle must:
/// - Be between 1 and 253 characters
/// - Match the pattern: subdomain.domain.tld
/// - Each label must start and end with alphanumeric
/// - Labels can contain hyphens but not at boundaries
bool isValidHandle(String handle) {
  if (handle.isEmpty || handle.length >= 254) return false;

  // Pattern: ([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?
  final pattern = RegExp(
    r'^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$',
  );

  return pattern.hasMatch(handle);
}

/// Returns a normalized handle if valid, null otherwise.
String? asNormalizedHandle(String input) {
  final handle = normalizeHandle(input);
  return isValidHandle(handle) ? handle : null;
}

/// Asserts that a handle is valid.
void assertValidHandle(String handle) {
  if (!isValidHandle(handle)) {
    throw InvalidHandleError(handle, 'Invalid handle format');
  }
}
