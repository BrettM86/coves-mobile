/// The two halves of a community's `!name@instance` display form.
///
/// Built by [CommunityHandleUtils.resolveDisplayHandle]; callers that render
/// the name and instance in different styles should use [name] and
/// [instance] directly rather than re-splitting [toString].
class CommunityDisplayHandle {
  const CommunityDisplayHandle({required this.name, required this.instance});

  /// Community name without the leading `!` (e.g. `nba`).
  final String name;

  /// Origin instance domain (e.g. `coves.social`, `lemmy.world`).
  final String instance;

  /// `!name` — the community half of the display form.
  String get namePart => '!$name';

  /// `@instance` — the origin half of the display form.
  String get instancePart => '@$instance';

  @override
  String toString() => '$namePart$instancePart';

  @override
  bool operator ==(Object other) =>
      other is CommunityDisplayHandle &&
      other.name == name &&
      other.instance == instance;

  @override
  int get hashCode => Object.hash(name, instance);
}

/// Utility functions for community handle formatting and resolution.
///
/// Communities render as `!name@origin`. The appview serves the origin
/// explicitly via the optional `origin` field on `CommunityRef` /
/// `CommunityView`; until it does, the origin is derived from the atProto
/// DNS handle:
/// - DNS format (new): `c-gaming.coves.social`
/// - DNS format (legacy): `gaming.community.coves.social`
/// - Tidepool-bridged: `comicstrips.lemmy-world.tdpl.io`
class CommunityHandleUtils {
  static const _tidepoolSuffix = ['tdpl', 'io'];

  /// Resolves the structured `!name@instance` display form of a community.
  ///
  /// [origin], when non-empty, is authoritative and pairs directly with
  /// [name]. Otherwise the instance is derived from [handle]:
  /// - `c-<n>.<domain>` → `(n, domain)`
  /// - `<n>.community.<domain>` → `(n, domain)`
  /// - exactly four labels `<n>.<inst>.tdpl.io` → `(n, <inst>.tdpl.io)`.
  ///   This is an honest-but-imperfect fallback: the true origin (e.g.
  ///   `lemmy.world`) is not recoverable from the bridged handle.
  ///
  /// Returns null when neither origin nor a recognised handle is available;
  /// callers should fall back to the raw handle or bare name.
  static CommunityDisplayHandle? resolveDisplayHandle({
    required String name,
    String? origin,
    String? handle,
  }) {
    if (origin != null && origin.isNotEmpty) {
      return CommunityDisplayHandle(name: name, instance: origin);
    }

    if (handle == null || handle.isEmpty) {
      return null;
    }

    final parts = handle.split('.');

    // New format: c-name.instance.domain (e.g., c-gaming.coves.social)
    if (parts.length >= 3 && parts[0].startsWith('c-')) {
      return CommunityDisplayHandle(
        name: parts[0].substring(2),
        instance: parts.sublist(1).join('.'),
      );
    }

    // Legacy format: name.community.instance.domain
    if (parts.length >= 4 && parts[1] == 'community') {
      return CommunityDisplayHandle(
        name: parts[0],
        instance: parts.sublist(2).join('.'),
      );
    }

    // Tidepool bridge: name.instance.tdpl.io (exactly four labels)
    if (parts.length == 4 &&
        parts[2] == _tidepoolSuffix[0] &&
        parts[3] == _tidepoolSuffix[1]) {
      return CommunityDisplayHandle(
        name: parts[0],
        instance: parts.sublist(1).join('.'),
      );
    }

    return null;
  }
}
