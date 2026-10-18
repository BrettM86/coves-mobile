import 'dart:math';

import '../constants/moderation_constants.dart';
import '../models/moderation_action.dart';
import '../models/moderation_subject_state.dart';
import '../providers/viewer_authority_provider.dart';
import 'api_exceptions.dart';
import 'coves_api_service.dart';
import 'moderation_errors.dart';

enum ModerationSubmissionKind { remove, label, retractLabel, restore }

/// One confirmed moderation request, kept whole so a retry re-sends the
/// exact body and idempotency key.
///
/// Each named constructor sets the fields its [kind] sends; the others stay
/// null.
class ModerationSubmission {
  ModerationSubmission.removal({
    required StrongRef this.subject,
    required this.expectedVersion,
    required this.idempotencyKey,
    required ModerationReason this.reason,
    this.privateNote,
  }) : kind = ModerationSubmissionKind.remove,
       subjectUri = subject.uri,
       actionId = null,
       reviewedSubject = null;

  ModerationSubmission.label({
    required StrongRef this.subject,
    required this.expectedVersion,
    required this.idempotencyKey,
    this.reason,
    this.privateNote,
  }) : kind = ModerationSubmissionKind.label,
       subjectUri = subject.uri,
       actionId = null,
       reviewedSubject = null;

  const ModerationSubmission.labelRetraction({
    required this.subjectUri,
    required String this.actionId,
    required this.expectedVersion,
    required this.idempotencyKey,
    this.reason,
    this.reviewedSubject,
    this.privateNote,
  }) : kind = ModerationSubmissionKind.retractLabel,
       subject = null;

  const ModerationSubmission.restore({
    required this.subjectUri,
    required String this.actionId,
    required this.expectedVersion,
    required this.idempotencyKey,
    required ModerationReason this.reason,
    this.reviewedSubject,
    this.privateNote,
  }) : kind = ModerationSubmissionKind.restore,
       subject = null;

  final ModerationSubmissionKind kind;
  final String subjectUri;
  final StrongRef? subject;
  final String? actionId;
  final String expectedVersion;
  final String idempotencyKey;
  final ModerationReason? reason;
  final String? privateNote;
  final StrongRef? reviewedSubject;
}

sealed class ModerationFlowResult {}

final class ModerationFlowSucceeded extends ModerationFlowResult {
  ModerationFlowSucceeded(this.result);
  final ModerationMutationResult result;
}

final class ModerationFlowPreflightFailed extends ModerationFlowResult {
  ModerationFlowPreflightFailed(this.error);
  final ModerationError error;
}

/// The signed-in session changed while the request was in flight. Its
/// answer belongs to the previous session and must not be shown or applied.
final class ModerationFlowStaleSession extends ModerationFlowResult {}

/// The fresh state has no local removal to restore, so nothing was sent.
final class ModerationFlowNotRemoved extends ModerationFlowResult {}

/// The removal a restore was started from is no longer the subject's local
/// removal (another removal replaced it, or nothing removes the subject), so
/// nothing was sent.
final class ModerationFlowRemovalNoLongerActive extends ModerationFlowResult {}

/// What a restore left the post as, for the message the admin sees.
enum RestoreOutcome {
  restored,
  restoredButDeleted,
  restoredButUnavailable,
  notRemoved,
}

/// Classifies a [AdminModerationFlow.submitRestore] result; null when the
/// restore neither succeeded nor found the post already restored.
///
/// A deleted record outranks an unavailable record.
RestoreOutcome? restoreOutcomeOf(ModerationFlowResult result) {
  return switch (result) {
    ModerationFlowSucceeded(result: ModerationMutationResult(:final state)) =>
      state.recordState == ModerationRecordState.deleted
          ? RestoreOutcome.restoredButDeleted
          : state.recordState == ModerationRecordState.unavailable
          ? RestoreOutcome.restoredButUnavailable
          : RestoreOutcome.restored,
    ModerationFlowNotRemoved() => RestoreOutcome.notRemoved,
    _ => null,
  };
}

final class ModerationFlowMutationFailed extends ModerationFlowResult {
  ModerationFlowMutationFailed(this.error, {this.currentState});
  final ModerationError error;
  final ModerationSubjectState? currentState;
}

/// Fetches a fresh version for each removal, label, label retraction or
/// restore submission while keeping the subject tied to the post version
/// shown on the card.
///
/// A submission belongs to the session that started it: an answer landing
/// after the session changed returns [ModerationFlowStaleSession] and sends
/// nothing further, and a retained submission from another session is
/// discarded.
class AdminModerationFlow {
  AdminModerationFlow(
    this._apiService, {
    required this._authority,
    String Function()? idempotencyKeyGenerator,
  }) : _idempotencyKeyGenerator = idempotencyKeyGenerator ?? _newKey;

  final CovesApiService _apiService;
  final ViewerAuthorityProvider _authority;
  final String Function() _idempotencyKeyGenerator;
  ModerationSubmission? _retainedSubmission;
  Object? _retainedSessionKey;

  static String _newKey() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  ModerationSubmission? get retainedSubmission =>
      _isCurrentSession(_retainedSessionKey) ? _retainedSubmission : null;

  bool _isCurrentSession(Object? sessionKey) =>
      _authority.sessionKey == sessionKey;

  Future<ModerationFlowResult> submitRemoval({
    required StrongRef subject,
    required ModerationReason reason,
    String? privateNote,
  }) {
    return _submitWithFreshState(
      subject.uri,
      (sessionKey, state) => _send(
        sessionKey,
        ModerationSubmission.removal(
          subject: subject,
          expectedVersion: state.version,
          idempotencyKey: _idempotencyKeyGenerator(),
          reason: reason,
          privateNote: privateNote,
        ),
      ),
    );
  }

  Future<ModerationFlowResult> submitLabel({
    required StrongRef subject,
    ModerationReason? reason,
    String? privateNote,
  }) {
    return _submitWithFreshState(
      subject.uri,
      (sessionKey, state) => _send(
        sessionKey,
        ModerationSubmission.label(
          subject: subject,
          expectedVersion: state.version,
          idempotencyKey: _idempotencyKeyGenerator(),
          reason: reason,
          privateNote: privateNote,
        ),
      ),
    );
  }

  /// Restores the post at [subjectUri] by reversing its local removal.
  ///
  /// Sends nothing when the fresh state has no local removal
  /// ([ModerationFlowNotRemoved]) or reports a present record without its
  /// current version.
  ///
  /// With [expectedRemoval] (a restore started from that removal's log
  /// entry), sends nothing and returns [ModerationFlowRemovalNoLongerActive]
  /// unless the fresh local removal is that same action.
  Future<ModerationFlowResult> submitRestore({
    required String subjectUri,
    required ModerationReason reason,
    String? privateNote,
    ModerationActionRef? expectedRemoval,
  }) {
    return _submitWithFreshState(subjectUri, (sessionKey, state) async {
      final localRemoval = state.localRemoval;
      if (expectedRemoval != null && localRemoval != expectedRemoval) {
        return ModerationFlowRemovalNoLongerActive();
      }
      if (localRemoval == null) {
        return ModerationFlowNotRemoved();
      }
      StrongRef? reviewedSubject;
      if (state.recordState == ModerationRecordState.present) {
        reviewedSubject = state.currentSubject;
        if (reviewedSubject == null) {
          return ModerationFlowPreflightFailed(
            const ModerationError(ModerationErrorCode.unknown),
          );
        }
      }
      return _send(
        sessionKey,
        ModerationSubmission.restore(
          subjectUri: subjectUri,
          actionId: localRemoval.actionId,
          expectedVersion: state.version,
          idempotencyKey: _idempotencyKeyGenerator(),
          reason: reason,
          reviewedSubject: reviewedSubject,
          privateNote: privateNote,
        ),
      );
    });
  }

  /// Retracts the server NSFW label on [subject].
  ///
  /// Sends nothing when the fresh state has no local NSFW label (the post
  /// must be reloaded). When the record is present, [subject] (the version
  /// the caller shows) is sent as the reviewed subject, and an empty
  /// [subject] cid sends nothing ([ModerationErrorCode.invalidSubject]).
  /// A deleted or unavailable record sends no reviewed subject.
  Future<ModerationFlowResult> submitLabelRetraction({
    required StrongRef subject,
    ModerationReason? reason,
    String? privateNote,
  }) {
    return _submitWithFreshState(subject.uri, (sessionKey, state) async {
      final nsfwLabel = state.localLabels
          .where((label) => label.value == nsfwLabelValue)
          .firstOrNull;
      if (nsfwLabel == null) {
        return ModerationFlowPreflightFailed(
          const ModerationError(ModerationErrorCode.decisionNotFound),
        );
      }
      StrongRef? reviewedSubject;
      if (state.recordState == ModerationRecordState.present) {
        if (subject.cid.isEmpty) {
          return ModerationFlowPreflightFailed(
            const ModerationError(ModerationErrorCode.invalidSubject),
          );
        }
        reviewedSubject = subject;
      }
      return _send(
        sessionKey,
        ModerationSubmission.labelRetraction(
          subjectUri: subject.uri,
          actionId: nsfwLabel.action.actionId,
          expectedVersion: state.version,
          idempotencyKey: _idempotencyKeyGenerator(),
          reason: reason,
          reviewedSubject: reviewedSubject,
          privateNote: privateNote,
        ),
      );
    });
  }

  /// Fetches [subjectUri]'s current moderation state and hands it to
  /// [submit] while the session that started the submission is still
  /// signed in.
  Future<ModerationFlowResult> _submitWithFreshState(
    String subjectUri,
    Future<ModerationFlowResult> Function(
      Object? sessionKey,
      ModerationSubjectState state,
    )
    submit,
  ) async {
    // A fresh confirmation abandons the previous uncertain request.
    _retainedSubmission = null;
    final sessionKey = _authority.sessionKey;
    ModerationSubjectState state;
    try {
      state = await _apiService.getModerationSubjectState(subjectUri);
    } on ApiException catch (error) {
      if (!_isCurrentSession(sessionKey)) {
        return ModerationFlowStaleSession();
      }
      return ModerationFlowPreflightFailed(
        ModerationError.fromException(error),
      );
    }
    if (!_isCurrentSession(sessionKey)) {
      return ModerationFlowStaleSession();
    }
    return submit(sessionKey, state);
  }

  Future<ModerationFlowResult?> retry() async {
    final submission = retainedSubmission;
    if (submission == null) {
      _retainedSubmission = null;
      return null;
    }
    return _send(_retainedSessionKey, submission);
  }

  Future<ModerationFlowResult> _send(
    Object? sessionKey,
    ModerationSubmission submission,
  ) async {
    try {
      // Each named ModerationSubmission constructor sets the fields its
      // kind reads here.
      final result = await switch (submission.kind) {
        ModerationSubmissionKind.remove => _apiService.removeContent(
          subject: submission.subject!,
          expectedVersion: submission.expectedVersion,
          idempotencyKey: submission.idempotencyKey,
          reason: submission.reason!,
          privateNote: submission.privateNote,
        ),
        ModerationSubmissionKind.label => _apiService.labelContent(
          subject: submission.subject!,
          expectedVersion: submission.expectedVersion,
          idempotencyKey: submission.idempotencyKey,
          reason: submission.reason,
          privateNote: submission.privateNote,
        ),
        ModerationSubmissionKind.retractLabel =>
          _apiService.retractContentLabel(
            actionId: submission.actionId!,
            expectedVersion: submission.expectedVersion,
            idempotencyKey: submission.idempotencyKey,
            reason: submission.reason,
            reviewedSubject: submission.reviewedSubject,
            privateNote: submission.privateNote,
          ),
        ModerationSubmissionKind.restore => _apiService.restoreContent(
          actionId: submission.actionId!,
          expectedVersion: submission.expectedVersion,
          idempotencyKey: submission.idempotencyKey,
          reason: submission.reason!,
          reviewedSubject: submission.reviewedSubject,
          privateNote: submission.privateNote,
        ),
      };
      _retainedSubmission = null;
      if (!_isCurrentSession(sessionKey)) {
        return ModerationFlowStaleSession();
      }
      if (result.outcome == ModerationMutationOutcome.unknown) {
        throw StateError('Unknown ${submission.kind.name} outcome');
      }
      return ModerationFlowSucceeded(result);
    } on ApiException catch (exception) {
      if (!_isCurrentSession(sessionKey)) {
        _retainedSubmission = null;
        return ModerationFlowStaleSession();
      }
      final error = ModerationError.fromException(exception);
      _retainedSubmission = error.recovery == ModerationRecovery.ambiguousRetry
          ? submission
          : null;
      _retainedSessionKey = sessionKey;
      ModerationSubjectState? currentState;
      if (error.code == ModerationErrorCode.stateConflict) {
        try {
          currentState = await _apiService.getModerationSubjectState(
            submission.subjectUri,
          );
        } on ApiException {
          // Keep the original conflict if its follow-up state cannot be loaded.
        }
        if (!_isCurrentSession(sessionKey)) {
          return ModerationFlowStaleSession();
        }
      }
      return ModerationFlowMutationFailed(error, currentState: currentState);
    }
  }
}
