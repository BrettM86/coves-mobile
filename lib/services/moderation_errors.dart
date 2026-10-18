import 'api_exceptions.dart';

enum ModerationErrorCode {
  stateConflict,
  contentChanged,
  idempotencyConflict,
  decisionNotFound,
  invalidDecision,
  subjectNotFound,
  invalidSubject,
  moderationUnavailable,
  forbidden,
  unsupportedReason,
  unsupportedLabel,
  invalidRequest,
  network,
  unknown,
}

enum ModerationRecovery {
  ambiguousRetry,
  reloadAndConfirm,
  showNewVersion,
  reloadSubject,
  revokeAuthority,
  clientBug,
}

class ModerationError {
  const ModerationError(this.code);

  factory ModerationError.fromException(Object error) {
    if (error is ApiException) {
      final recognised = switch (error.errorCode) {
        'StateConflict' => ModerationErrorCode.stateConflict,
        'ContentChanged' => ModerationErrorCode.contentChanged,
        'IdempotencyConflict' => ModerationErrorCode.idempotencyConflict,
        'DecisionNotFound' => ModerationErrorCode.decisionNotFound,
        'InvalidDecision' => ModerationErrorCode.invalidDecision,
        'SubjectNotFound' => ModerationErrorCode.subjectNotFound,
        'InvalidSubject' => ModerationErrorCode.invalidSubject,
        'ModerationUnavailable' => ModerationErrorCode.moderationUnavailable,
        'Forbidden' => ModerationErrorCode.forbidden,
        'UnsupportedReason' => ModerationErrorCode.unsupportedReason,
        'UnsupportedLabel' => ModerationErrorCode.unsupportedLabel,
        'InvalidRequest' => ModerationErrorCode.invalidRequest,
        _ => null,
      };
      if (recognised != null) {
        return ModerationError(recognised);
      }
      // An unrecognised or missing code says nothing about whether the
      // mutation landed, so classify by transport and status: a 5xx (the
      // backend's catch-all InternalServerError included) or an unreachable
      // host is ambiguous and must keep the retained submission.
      if (error is NetworkException || error is FederationException) {
        return const ModerationError(ModerationErrorCode.network);
      }
      if (error is ServerException || (error.statusCode ?? 0) >= 500) {
        return const ModerationError(ModerationErrorCode.moderationUnavailable);
      }
    }
    return const ModerationError(ModerationErrorCode.unknown);
  }

  final ModerationErrorCode code;

  ModerationRecovery get recovery => switch (code) {
    ModerationErrorCode.network || ModerationErrorCode.moderationUnavailable =>
      ModerationRecovery.ambiguousRetry,
    ModerationErrorCode.idempotencyConflict ||
    ModerationErrorCode.stateConflict => ModerationRecovery.reloadAndConfirm,
    ModerationErrorCode.contentChanged => ModerationRecovery.showNewVersion,
    ModerationErrorCode.decisionNotFound ||
    ModerationErrorCode.invalidDecision ||
    ModerationErrorCode.subjectNotFound ||
    ModerationErrorCode.invalidSubject => ModerationRecovery.reloadSubject,
    ModerationErrorCode.forbidden => ModerationRecovery.revokeAuthority,
    _ => ModerationRecovery.clientBug,
  };

  String get message => switch (code) {
    ModerationErrorCode.network || ModerationErrorCode.moderationUnavailable =>
      'Moderation is temporarily unavailable. Try again.',
    ModerationErrorCode.idempotencyConflict =>
      'Something went wrong. Confirm again.',
    ModerationErrorCode.stateConflict =>
      'Someone else acted on this first. Confirm again.',
    ModerationErrorCode.contentChanged =>
      'The author edited this post. Review the new version before acting.',
    ModerationErrorCode.decisionNotFound ||
    ModerationErrorCode.invalidDecision ||
    ModerationErrorCode.subjectNotFound ||
    ModerationErrorCode.invalidSubject =>
      'This item changed. Showing the latest version.',
    ModerationErrorCode.forbidden => 'You no longer have admin access.',
    _ => "Couldn't complete this action.",
  };
}
