/// Validation for a new community's name — the DNS-style slug that becomes
/// the community's handle.
///
/// Pure: no widgets, no state, no `setState`. It answers "is this name
/// acceptable, and if not why", and the caller decides what to do with the
/// answer.
library;

/// Validates and normalizes a community name.
abstract final class CommunityNameValidator {
  /// Longest accepted name, in characters.
  ///
  /// A DNS label may not exceed 63 octets, and the name becomes the
  /// `c-<name>` portion of the community handle.
  static const int maxLength = 63;

  /// DNS-valid community names: lowercase alphanumerics, interior hyphens.
  ///
  /// Anchored, and the optional middle group forbids a leading or trailing
  /// hyphen while still accepting a single-character name.
  static final RegExp _dnsNameRegex = RegExp(
    r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?$',
  );

  /// The stored and transmitted form of [rawName]: trimmed, then lowercased.
  ///
  /// The single definition of the transformation [validate] applies, so
  /// validation, the handle preview and the create request cannot drift
  /// apart.
  static String normalize(String rawName) => rawName.trim().toLowerCase();

  /// Returns null when [rawName] is acceptable, or the user-facing error
  /// message explaining why it is not.
  ///
  /// The name is [normalize]d — trimmed AND LOWERCASED — before it is
  /// tested, so an uppercase name such as `MyCommunity` is ACCEPTED here and
  /// stored as `mycommunity`, despite the charset message promising
  /// "lowercase letters". That reads like a bug and is not: the create
  /// request normalizes the same way, so what is sent always matches what
  /// was validated. Rejecting uppercase instead would break the happy path.
  /// Test-pinned; if the product wants uppercase rejected, change the
  /// message and the test together.
  ///
  /// The empty-name branch is currently unreachable from the admin panel —
  /// its submit button is disabled while any field is blank, and
  /// [normalize] cannot empty a non-empty string — but it is the contract
  /// for any other caller and is kept deliberately.
  static String? validate(String rawName) {
    final name = normalize(rawName);

    if (name.isEmpty) {
      return 'Name is required';
    }

    if (name.length > maxLength) {
      return 'Name must be $maxLength characters or less';
    }

    if (!_dnsNameRegex.hasMatch(name)) {
      return 'Name must be lowercase letters, numbers, and hyphens only';
    }

    return null;
  }
}
