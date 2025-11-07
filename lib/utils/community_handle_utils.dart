/// Utility functions for community handle formatting and resolution.
///
/// Coves communities use atProto handles in the format:
/// - DNS format: `gaming.community.coves.social`
/// - Display format: `!gaming@coves.social`
class CommunityHandleUtils {
  /// Converts a DNS-style community handle to display format
  ///
  /// Transforms `gaming.community.coves.social` → `!gaming@coves.social`
  /// by removing the `.community.` segment
  ///
  /// Returns null if the handle is null or doesn't contain `.community.`
  static String? formatHandleForDisplay(String? handle) {
    if (handle == null || handle.isEmpty) {
      return null;
    }

    // Expected format: name.community.instance.domain
    // e.g., gaming.community.coves.social
    final parts = handle.split('.');

    // Must have at least 4 parts: [name, community, instance, domain]
    if (parts.length < 4 || parts[1] != 'community') {
      return null;
    }

    // Extract community name (first part)
    final communityName = parts[0];

    // Extract instance domain (everything after .community.)
    final instanceDomain = parts.sublist(2).join('.');

    // Format as !name@instance
    return '!$communityName@$instanceDomain';
  }

  /// Converts a display-style community handle to DNS format
  ///
  /// Transforms `!gaming@coves.social` → `gaming.community.coves.social`
  /// by inserting `.community.` between the name and instance
  ///
  /// Returns null if the handle is null or doesn't match expected format
  static String? formatHandleForDNS(String? displayHandle) {
    if (displayHandle == null || displayHandle.isEmpty) {
      return null;
    }

    // Remove leading ! if present
    final cleaned =
        displayHandle.startsWith('!')
            ? displayHandle.substring(1)
            : displayHandle;

    // Expected format: name@instance.domain
    if (!cleaned.contains('@')) {
      return null;
    }

    final parts = cleaned.split('@');
    if (parts.length != 2) {
      return null;
    }

    final communityName = parts[0];
    final instanceDomain = parts[1];

    // Format as name.community.instance.domain
    return '$communityName.community.$instanceDomain';
  }
}
