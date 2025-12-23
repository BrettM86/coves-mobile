/// Utility functions for community handle formatting and resolution.
///
/// Coves communities use atProto handles in the format:
/// - DNS format (new): `c-gaming.coves.social`
/// - DNS format (legacy): `gaming.community.coves.social`
/// - Display format: `!gaming@coves.social`
class CommunityHandleUtils {
  /// Converts a DNS-style community handle to display format
  ///
  /// Supports both formats:
  /// - New: `c-gaming.coves.social` → `!gaming@coves.social`
  /// - Legacy: `gaming.community.coves.social` → `!gaming@coves.social`
  ///
  /// Returns null if the handle is null or doesn't match expected formats
  static String? formatHandleForDisplay(String? handle) {
    if (handle == null || handle.isEmpty) {
      return null;
    }

    final parts = handle.split('.');

    // New format: c-name.instance.domain (e.g., c-gaming.coves.social)
    if (parts.length >= 3 && parts[0].startsWith('c-')) {
      final communityName = parts[0].substring(2); // Remove 'c-' prefix
      final instanceDomain = parts.sublist(1).join('.');
      return '!$communityName@$instanceDomain';
    }

    // Legacy format: name.community.instance.domain
    // e.g., gaming.community.coves.social
    if (parts.length >= 4 && parts[1] == 'community') {
      final communityName = parts[0];
      final instanceDomain = parts.sublist(2).join('.');
      return '!$communityName@$instanceDomain';
    }

    // Unknown format - return null
    return null;
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
