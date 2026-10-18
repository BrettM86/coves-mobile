// Moderation view models for social.coves.moderation.defs
//
// Served on postView.moderation, commentView.moderation and the
// post.get moderatedPost tombstone.
//
// Parsing is tolerant: open enums map unknown values to `unknown`, malformed
// entries are skipped and unknown fields are ignored, so a new or malformed
// moderation shape never drops the post or comment that carries it.

/// Effective removal state (open enum; unrecognized values map to
/// [unknown]).
enum ModerationState { clear, removed, unknown }

enum ModerationCapability { remove, restore, label, retractLabel }

/// Parses the optional viewer capability list, ignoring unknown tokens.
Set<ModerationCapability> parseModerationCapabilities(Object? json) {
  if (json is! List) {
    return const {};
  }
  return Set.unmodifiable(
    json
        .map(
          (token) => switch (token) {
            'remove' => ModerationCapability.remove,
            'restore' => ModerationCapability.restore,
            'label' => ModerationCapability.label,
            'retract-label' => ModerationCapability.retractLabel,
            _ => null,
          },
        )
        .nonNulls,
  );
}

/// Kind of a moderation scope (open enum; unrecognized or missing values
/// map to [unknown]).
enum ModerationScopeKind { instance, community, unknown }

/// Scope in which a moderation decision applies.
class ModerationScope {
  const ModerationScope({required this.kind, this.communityDid});

  factory ModerationScope.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      return const ModerationScope(kind: ModerationScopeKind.unknown);
    }
    return ModerationScope(
      kind: switch (json['kind']) {
        'instance' => ModerationScopeKind.instance,
        'community' => ModerationScopeKind.community,
        _ => ModerationScopeKind.unknown,
      },
      communityDid: json['communityDid'] is String
          ? json['communityDid'] as String
          : null,
    );
  }

  final ModerationScopeKind kind;
  final String? communityDid;
}

/// Authority source contributing to a moderation state or content label.
class ModerationSource {
  const ModerationSource({required this.authorityDid, required this.scope});

  /// Returns null when [json] lacks a string `authorityDid`.
  static ModerationSource? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) {
      return null;
    }
    final authorityDid = json['authorityDid'];
    if (authorityDid is! String) {
      return null;
    }
    return ModerationSource(
      authorityDid: authorityDid,
      scope: ModerationScope.fromJson(json['scope']),
    );
  }

  final String authorityDid;
  final ModerationScope scope;
}

/// Effective public content label and its contributing sources.
class ContentLabelView {
  const ContentLabelView({
    required this.value,
    this.sources = const [],
    this.sourcesTruncated = false,
  });

  /// Returns null when [json] lacks a string `value`.
  static ContentLabelView? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) {
      return null;
    }
    final value = json['value'];
    if (value is! String) {
      return null;
    }
    return ContentLabelView(
      value: value,
      sources: _parseSources(json['sources']),
      sourcesTruncated: json['sourcesTruncated'] == true,
    );
  }

  final String value;
  final List<ModerationSource> sources;
  final bool sourcesTruncated;
}

/// Effective public removal and content-label state for a subject.
class ModerationView {
  const ModerationView({
    required this.state,
    this.sources = const [],
    this.sourcesTruncated = false,
    this.contentLabels = const [],
  });

  factory ModerationView.fromJson(Map<String, dynamic> json) {
    final labels = json['contentLabels'];
    return ModerationView(
      state: switch (json['state']) {
        'clear' => ModerationState.clear,
        'removed' => ModerationState.removed,
        _ => ModerationState.unknown,
      },
      sources: _parseSources(json['sources']),
      sourcesTruncated: json['sourcesTruncated'] == true,
      contentLabels: labels is List
          ? List.unmodifiable(labels.map(ContentLabelView.tryParse).nonNulls)
          : const [],
    );
  }

  /// Parses an optional `moderation` field; null when absent or not an
  /// object.
  static ModerationView? tryParse(Object? json) {
    return json is Map<String, dynamic> ? ModerationView.fromJson(json) : null;
  }

  final ModerationState state;
  final List<ModerationSource> sources;
  final bool sourcesTruncated;
  final List<ContentLabelView> contentLabels;
}

List<ModerationSource> _parseSources(Object? json) {
  if (json is! List) {
    return const [];
  }
  return List.unmodifiable(json.map(ModerationSource.tryParse).nonNulls);
}
