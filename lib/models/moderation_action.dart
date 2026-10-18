import 'moderation.dart';

enum ModerationActionKind { remove, restore, label, retractLabel, unknown }

enum ModerationReason {
  spam,
  harassment,
  doxing,
  illegalContent,
  ruleViolation,
  moderatorDiscretion,
  unknown,
}

extension ModerationReasonWireToken on ModerationReason {
  /// Full lexicon token, or null for [ModerationReason.unknown].
  ///
  /// The single source of the reason/token mapping: parsing derives from it.
  String? get wireToken => switch (this) {
    ModerationReason.spam => 'social.coves.moderation.defs#reasonSpam',
    ModerationReason.harassment =>
      'social.coves.moderation.defs#reasonHarassment',
    ModerationReason.doxing => 'social.coves.moderation.defs#reasonDoxing',
    ModerationReason.illegalContent =>
      'social.coves.moderation.defs#reasonIllegalContent',
    ModerationReason.ruleViolation =>
      'social.coves.moderation.defs#reasonRuleViolation',
    ModerationReason.moderatorDiscretion =>
      'social.coves.moderation.defs#reasonModeratorDiscretion',
    ModerationReason.unknown => null,
  };
}

class ModerationActionRef {
  const ModerationActionRef({required this.serviceDid, required this.actionId});

  final String serviceDid;
  final String actionId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModerationActionRef &&
          serviceDid == other.serviceDid &&
          actionId == other.actionId;

  @override
  int get hashCode => Object.hash(serviceDid, actionId);

  static ModerationActionRef? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) {
      return null;
    }
    final serviceDid = json['serviceDid'];
    final actionId = json['actionId'];
    if (serviceDid is! String ||
        serviceDid.isEmpty ||
        actionId is! String ||
        actionId.isEmpty) {
      return null;
    }
    return ModerationActionRef(serviceDid: serviceDid, actionId: actionId);
  }
}

class ModerationSubjectRef {
  const ModerationSubjectRef({
    required this.uri,
    this.cid,
    this.communityDid,
    this.rootUri,
  });

  final String uri;
  final String? cid;
  final String? communityDid;

  /// The root post of a comment's thread; null when absent or not given.
  final String? rootUri;

  static ModerationSubjectRef? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) {
      return null;
    }
    final uri = json['uri'];
    if (uri is! String || uri.isEmpty) {
      return null;
    }
    final cid = json['cid'];
    final communityDid = json['communityDid'];
    final rootUri = json['rootUri'];
    return ModerationSubjectRef(
      uri: uri,
      cid: cid is String ? cid : null,
      communityDid: communityDid is String ? communityDid : null,
      rootUri: rootUri is String && rootUri.isNotEmpty ? rootUri : null,
    );
  }
}

/// What a moderated record said. A removal captures the text at removal and
/// a restore carries the snapshot of the removal it reverses; in the admin
/// log, a label or retract-label carries the post's current text.
class ModerationContentSnapshot {
  const ModerationContentSnapshot({
    required this.capturedCid,
    this.title,
    this.text,
    this.linkUrl,
  });

  final String? title;
  final String? text;
  final String? linkUrl;
  final String capturedCid;

  /// Null unless [json] is an object with a non-empty string `capturedCid`;
  /// a non-string title, text or linkUrl is dropped on its own.
  static ModerationContentSnapshot? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) {
      return null;
    }
    final capturedCid = json['capturedCid'];
    if (capturedCid is! String || capturedCid.isEmpty) {
      return null;
    }
    final title = json['title'];
    final text = json['text'];
    final linkUrl = json['linkUrl'];
    return ModerationContentSnapshot(
      capturedCid: capturedCid,
      title: title is String ? title : null,
      text: text is String ? text : null,
      linkUrl: linkUrl is String ? linkUrl : null,
    );
  }
}

class ModerationActionView {
  const ModerationActionView({
    required this.ref,
    required this.action,
    required this.createdAt,
    required this.authorityDid,
    required this.scope,
    required this.origin,
    this.actorDid,
    this.subject,
    this.reason,
    this.reverses,
    this.contentSnapshot,
  });

  final ModerationActionRef ref;
  final ModerationActionKind action;
  final DateTime createdAt;
  final String? actorDid;
  final ModerationSubjectRef? subject;
  final ModerationReason? reason;
  final ModerationActionRef? reverses;
  final ModerationContentSnapshot? contentSnapshot;
  final String authorityDid;
  final ModerationScope scope;
  final String origin;

  static ModerationActionView? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) {
      return null;
    }
    final ref = ModerationActionRef.tryParse(json['ref']);
    final action = json['action'];
    final authorityDid = json['authorityDid'];
    final scope = json['scope'];
    final origin = json['origin'];
    final createdAt = json['createdAt'];
    if (ref == null ||
        action is! String ||
        action.isEmpty ||
        authorityDid is! String ||
        authorityDid.isEmpty ||
        scope is! Map<String, dynamic> ||
        scope['kind'] is! String ||
        (scope['kind'] as String).isEmpty ||
        origin is! String ||
        origin.isEmpty ||
        createdAt is! String) {
      return null;
    }
    final date = DateTime.tryParse(createdAt);
    if (date == null) {
      return null;
    }

    final actor = json['actor'];
    final reason = json['reason'];
    return ModerationActionView(
      ref: ref,
      action: switch (action) {
        'remove' => ModerationActionKind.remove,
        'restore' => ModerationActionKind.restore,
        'label' => ModerationActionKind.label,
        'retract-label' => ModerationActionKind.retractLabel,
        _ => ModerationActionKind.unknown,
      },
      createdAt: date,
      actorDid: actor is Map<String, dynamic> && actor['did'] is String
          ? actor['did'] as String
          : null,
      subject: ModerationSubjectRef.tryParse(json['subject']),
      reason: reason == null
          ? null
          : ModerationReason.values.firstWhere(
              (candidate) => candidate.wireToken == reason,
              orElse: () => ModerationReason.unknown,
            ),
      reverses: ModerationActionRef.tryParse(json['reverses']),
      contentSnapshot: ModerationContentSnapshot.tryParse(
        json['contentSnapshot'],
      ),
      authorityDid: authorityDid,
      scope: ModerationScope.fromJson(scope),
      origin: origin,
    );
  }
}

class ModerationActionPage {
  const ModerationActionPage({required this.actions, this.cursor});

  factory ModerationActionPage.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      return const ModerationActionPage(actions: []);
    }
    final entries = json['actions'];
    final cursor = json['cursor'];
    return ModerationActionPage(
      actions: entries is List
          ? List.unmodifiable(
              entries.map(ModerationActionView.tryParse).nonNulls,
            )
          : const [],
      cursor: cursor is String && cursor.isNotEmpty ? cursor : null,
    );
  }

  final List<ModerationActionView> actions;
  final String? cursor;
}

class AdminModerationActionPage {
  const AdminModerationActionPage({required this.actions, this.cursor});

  factory AdminModerationActionPage.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      return const AdminModerationActionPage(actions: []);
    }
    final entries = json['actions'];
    final cursor = json['cursor'];
    return AdminModerationActionPage(
      actions: entries is List
          ? List.unmodifiable(
              entries.map(AdminModerationActionView.tryParse).nonNulls,
            )
          : const [],
      cursor: cursor is String && cursor.isNotEmpty ? cursor : null,
    );
  }

  final List<AdminModerationActionView> actions;
  final String? cursor;
}

class AdminModerationActionView {
  const AdminModerationActionView({
    required this.action,
    this.actorDid,
    this.privateNote,
    this.privateSubject,
    this.contentSnapshot,
  });

  final ModerationActionView action;
  final String? actorDid;
  final String? privateNote;
  final ModerationSubjectRef? privateSubject;

  /// The admin log's snapshot, present also when the public action withholds
  /// it.
  final ModerationContentSnapshot? contentSnapshot;

  static AdminModerationActionView? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) {
      return null;
    }
    final action = ModerationActionView.tryParse(json['action']);
    if (action == null) {
      return null;
    }
    return AdminModerationActionView(
      action: action,
      actorDid: json['actorDid'] is String ? json['actorDid'] as String : null,
      privateNote: json['privateNote'] is String
          ? json['privateNote'] as String
          : null,
      privateSubject: ModerationSubjectRef.tryParse(json['privateSubject']),
      contentSnapshot: ModerationContentSnapshot.tryParse(
        json['contentSnapshot'],
      ),
    );
  }
}
