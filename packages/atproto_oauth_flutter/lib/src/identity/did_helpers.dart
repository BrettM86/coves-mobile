import 'constants.dart';
import 'identity_resolver_error.dart';

/// Checks if a string is a valid DID.
///
/// A valid DID follows the format: did:method:method-specific-id
/// where method is lowercase alphanumeric and method-specific-id
/// contains only allowed characters.
bool isDid(String input) {
  try {
    assertDid(input);
    return true;
  } catch (e) {
    if (e is IdentityResolverError) {
      return false;
    }
    rethrow;
  }
}

/// Asserts that a string is a valid DID, throwing if not.
void assertDid(String input) {
  if (input.length > maxDidLength) {
    throw InvalidDidError(input, 'DID is too long ($maxDidLength chars max)');
  }

  if (!input.startsWith(didPrefix)) {
    throw InvalidDidError(input, 'DID requires "$didPrefix" prefix');
  }

  final methodEndIndex = input.indexOf(':', didPrefix.length);
  if (methodEndIndex == -1) {
    throw InvalidDidError(input, 'Missing colon after method name');
  }

  _assertDidMethod(input, didPrefix.length, methodEndIndex);
  _assertDidMsid(input, methodEndIndex + 1, input.length);
}

/// Validates DID method name (lowercase alphanumeric).
void _assertDidMethod(String input, int start, int end) {
  if (end == start) {
    throw InvalidDidError(input, 'Empty method name');
  }

  for (int i = start; i < end; i++) {
    final c = input.codeUnitAt(i);
    if (!((c >= 0x61 && c <= 0x7a) || (c >= 0x30 && c <= 0x39))) {
      // Not a-z or 0-9
      throw InvalidDidError(
        input,
        'Invalid character at position $i in DID method name',
      );
    }
  }
}

/// Validates DID method-specific identifier.
void _assertDidMsid(String input, int start, int end) {
  if (end == start) {
    throw InvalidDidError(input, 'DID method-specific id must not be empty');
  }

  for (int i = start; i < end; i++) {
    final c = input.codeUnitAt(i);

    // Check for frequent chars first (a-z, A-Z, 0-9, ., -, _)
    if ((c >= 0x61 && c <= 0x7a) || // a-z
        (c >= 0x41 && c <= 0x5a) || // A-Z
        (c >= 0x30 && c <= 0x39) || // 0-9
        c == 0x2e || // .
        c == 0x2d || // -
        c == 0x5f) {
      // _
      continue;
    }

    // ":"
    if (c == 0x3a) {
      if (i == end - 1) {
        throw InvalidDidError(input, 'DID cannot end with ":"');
      }
      continue;
    }

    // pct-encoded: %HEXDIG HEXDIG
    if (c == 0x25) {
      // %
      if (i + 2 >= end) {
        throw InvalidDidError(
          input,
          'Incomplete pct-encoded character at position $i',
        );
      }

      i++;
      final c1 = input.codeUnitAt(i);
      if (!((c1 >= 0x30 && c1 <= 0x39) || (c1 >= 0x41 && c1 <= 0x46))) {
        // Not 0-9 or A-F
        throw InvalidDidError(
          input,
          'Invalid pct-encoded character at position $i',
        );
      }

      i++;
      final c2 = input.codeUnitAt(i);
      if (!((c2 >= 0x30 && c2 <= 0x39) || (c2 >= 0x41 && c2 <= 0x46))) {
        // Not 0-9 or A-F
        throw InvalidDidError(
          input,
          'Invalid pct-encoded character at position $i',
        );
      }

      continue;
    }

    throw InvalidDidError(
      input,
      'Disallowed character in DID at position $i',
    );
  }
}

/// Extracts the method name from a DID.
///
/// Example: extractDidMethod('did:plc:abc123') returns 'plc'
String extractDidMethod(String did) {
  final methodEndIndex = did.indexOf(':', didPrefix.length);
  return did.substring(didPrefix.length, methodEndIndex);
}

/// Checks if a string is a valid did:plc identifier.
bool isDidPlc(String input) {
  if (input.length != didPlcLength) return false;
  if (!input.startsWith(didPlcPrefix)) return false;

  // Check that all characters after prefix are base32 [a-z2-7]
  for (int i = didPlcPrefix.length; i < didPlcLength; i++) {
    if (!_isBase32Char(input.codeUnitAt(i))) return false;
  }

  return true;
}

/// Checks if a string is a valid did:web identifier.
bool isDidWeb(String input) {
  if (!input.startsWith(didWebPrefix)) return false;
  if (input.length <= didWebPrefix.length) return false;

  // Check if next char after prefix is ":"
  if (input.codeUnitAt(didWebPrefix.length) == 0x3a) return false;

  try {
    _assertDidMsid(input, didWebPrefix.length, input.length);
    return true;
  } catch (e) {
    return false;
  }
}

/// Checks if a DID uses an atProto-blessed method (plc or web).
bool isAtprotoDid(String input) {
  return isDidPlc(input) || isDidWeb(input);
}

/// Asserts that a string is a valid atProto DID (did:plc or did:web).
///
/// Throws [InvalidDidError] if the DID is not a valid atProto DID.
void assertAtprotoDid(String input) {
  if (!isAtprotoDid(input)) {
    throw InvalidDidError(
      input,
      'DID must use atProto-blessed method (did:plc or did:web)',
    );
  }
}

/// Asserts that a string is a valid did:plc identifier.
void assertDidPlc(String input) {
  if (!input.startsWith(didPlcPrefix)) {
    throw InvalidDidError(input, 'Invalid did:plc prefix');
  }

  if (input.length != didPlcLength) {
    throw InvalidDidError(
      input,
      'did:plc must be $didPlcLength characters long',
    );
  }

  for (int i = didPlcPrefix.length; i < didPlcLength; i++) {
    if (!_isBase32Char(input.codeUnitAt(i))) {
      throw InvalidDidError(input, 'Invalid character at position $i');
    }
  }
}

/// Asserts that a string is a valid did:web identifier.
void assertDidWeb(String input) {
  if (!input.startsWith(didWebPrefix)) {
    throw InvalidDidError(input, 'Invalid did:web prefix');
  }

  if (input.codeUnitAt(didWebPrefix.length) == 0x3a) {
    throw InvalidDidError(input, 'did:web MSID must not start with a colon');
  }

  _assertDidMsid(input, didWebPrefix.length, input.length);
}

/// Checks if a character code is a base32 character [a-z2-7].
bool _isBase32Char(int c) =>
    (c >= 0x61 && c <= 0x7a) || (c >= 0x32 && c <= 0x37);

/// Converts a did:web to an HTTPS URL.
///
/// Example:
/// - did:web:example.com -> https://example.com
/// - did:web:example.com:user:alice -> https://example.com/user/alice
/// - did:web:localhost%3A3000 -> http://localhost:3000
Uri didWebToUrl(String did) {
  assertDidWeb(did);

  final hostIdx = didWebPrefix.length;
  final pathIdx = did.indexOf(':', hostIdx);

  final hostEnc = pathIdx == -1 ? did.substring(hostIdx) : did.substring(hostIdx, pathIdx);
  final host = hostEnc.replaceAll('%3A', ':');
  final path = pathIdx == -1 ? '' : did.substring(pathIdx).replaceAll(':', '/');

  // Use http for localhost, https for everything else
  final proto = host.startsWith('localhost') &&
          (host.length == 9 || host.codeUnitAt(9) == 0x3a) // ':'
      ? 'http'
      : 'https';

  return Uri.parse('$proto://$host$path');
}

/// Converts an HTTPS URL to a did:web identifier.
///
/// Example:
/// - https://example.com -> did:web:example.com
/// - https://example.com/user/alice -> did:web:example.com:user:alice
String urlToDidWeb(Uri url) {
  final port = url.hasPort ? '%3A${url.port}' : '';
  final path = url.path == '/' ? '' : url.path.replaceAll('/', ':');

  return '$didWebPrefix${url.host}$port$path';
}
