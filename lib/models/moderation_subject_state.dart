import 'moderation.dart';
import 'moderation_action.dart';

class StrongRef {
  const StrongRef({required this.uri, required this.cid});

  final String uri;
  final String cid;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StrongRef && uri == other.uri && cid == other.cid;

  @override
  int get hashCode => Object.hash(uri, cid);
}

enum ModerationRecordState { present, deleted, unavailable, unknown }

class LocalLabel {
  const LocalLabel({required this.value, required this.action});

  final String value;
  final ModerationActionRef action;
}

class ModerationSubjectState {
  const ModerationSubjectState({
    required this.subject,
    required this.version,
    required this.moderation,
    required this.recordState,
    this.currentSubject,
    this.localRemoval,
    this.localLabels = const [],
  });

  factory ModerationSubjectState.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    if (version is! String || version.isEmpty) {
      throw const FormatException('Invalid moderation subject version');
    }
    final current = json['currentSubject'];
    final currentUri = current is Map<String, dynamic> ? current['uri'] : null;
    final currentCid = current is Map<String, dynamic> ? current['cid'] : null;
    final labels = json['localLabels'];
    return ModerationSubjectState(
      subject: json['subject'] is String ? json['subject'] as String : '',
      version: version,
      moderation:
          ModerationView.tryParse(json['moderation']) ??
          const ModerationView(state: ModerationState.unknown),
      recordState: switch (json['recordState']) {
        'present' => ModerationRecordState.present,
        'deleted' => ModerationRecordState.deleted,
        'unavailable' => ModerationRecordState.unavailable,
        _ => ModerationRecordState.unknown,
      },
      currentSubject:
          currentUri is String &&
              currentUri.isNotEmpty &&
              currentCid is String &&
              currentCid.isNotEmpty
          ? StrongRef(uri: currentUri, cid: currentCid)
          : null,
      localRemoval: ModerationActionRef.tryParse(json['localRemoval']),
      localLabels: labels is List
          ? List.unmodifiable(
              labels.whereType<Map<String, dynamic>>().map((entry) {
                final value = entry['value'];
                final action = ModerationActionRef.tryParse(entry['action']);
                return value is String && value.isNotEmpty && action != null
                    ? LocalLabel(value: value, action: action)
                    : null;
              }).nonNulls,
            )
          : const [],
    );
  }

  final String subject;
  final String version;
  final ModerationView moderation;
  final ModerationRecordState recordState;
  final StrongRef? currentSubject;
  final ModerationActionRef? localRemoval;
  final List<LocalLabel> localLabels;
}

enum ModerationMutationOutcome { applied, unchanged, unknown }

class ModerationMutationResult {
  const ModerationMutationResult({
    required this.outcome,
    required this.state,
    this.action,
  });

  factory ModerationMutationResult.fromJson(Map<String, dynamic> json) {
    return ModerationMutationResult(
      outcome: switch (json['outcome']) {
        'applied' => ModerationMutationOutcome.applied,
        'unchanged' => ModerationMutationOutcome.unchanged,
        _ => ModerationMutationOutcome.unknown,
      },
      state: ModerationSubjectState.fromJson(
        json['state'] as Map<String, dynamic>,
      ),
      action: AdminModerationActionView.tryParse(json['action']),
    );
  }

  final ModerationMutationOutcome outcome;
  final ModerationSubjectState state;
  final AdminModerationActionView? action;
}
