import '../../providers/viewer_authority_provider.dart';
import '../../services/admin_moderation_flow.dart';
import '../../services/moderation_errors.dart';
import 'moderation_action_sheet.dart';

/// The sheet decision for a moderation flow answer that did not succeed,
/// after running the recoveries every admin tool shares.
///
/// Callers handle [ModerationFlowSucceeded], [ModerationFlowNotRemoved] and
/// [ModerationFlowRemovalNoLongerActive] themselves; passing any of them is a
/// programming error.
///
/// - A stale-session answer closes the sheet with nothing shown.
/// - Forbidden revokes [authority] and closes the sheet.
/// - A state conflict goes to [resolveStateConflict] first; the sheet closes
///   when it returns true.
/// - A changed or gone subject runs [reloadSubject], which shows its own
///   message, and closes the sheet.
/// - A failed preflight, an ambiguous failure (locked for an identical
///   retry) or a reload-and-confirm failure keeps the sheet open.
/// - Anything else shows its message and closes the sheet.
Future<ModerationSheetDecision> moderationFailureDecision(
  ModerationFlowResult outcome, {
  required ViewerAuthorityProvider authority,
  required void Function(String message) showMessage,
  required Future<void> Function(ModerationError error) reloadSubject,
  bool Function(ModerationFlowMutationFailed failure)? resolveStateConflict,
}) async {
  final error = switch (outcome) {
    ModerationFlowStaleSession() => null,
    ModerationFlowPreflightFailed(:final error) => error,
    ModerationFlowMutationFailed(:final error) => error,
    ModerationFlowSucceeded() ||
    ModerationFlowNotRemoved() ||
    ModerationFlowRemovalNoLongerActive() => throw ArgumentError.value(
      outcome,
      'outcome',
      'must not succeed',
    ),
  };
  if (error == null) {
    return const ModerationSheetDecision();
  }
  if (error.code == ModerationErrorCode.forbidden) {
    authority.markRevoked();
    showMessage(error.message);
    return const ModerationSheetDecision();
  }
  if (outcome is ModerationFlowMutationFailed &&
      error.code == ModerationErrorCode.stateConflict &&
      (resolveStateConflict?.call(outcome) ?? false)) {
    return const ModerationSheetDecision();
  }
  if (error.code == ModerationErrorCode.contentChanged ||
      error.recovery == ModerationRecovery.reloadSubject) {
    await reloadSubject(error);
    return const ModerationSheetDecision();
  }
  if (outcome is ModerationFlowPreflightFailed) {
    return const ModerationSheetDecision(
      close: false,
      failureMessage: "Couldn't load the current moderation state. Try again.",
    );
  }
  if (error.recovery == ModerationRecovery.ambiguousRetry) {
    return ModerationSheetDecision(
      close: false,
      failureMessage: error.message,
      retryLocked: true,
    );
  }
  if (error.recovery == ModerationRecovery.reloadAndConfirm) {
    return ModerationSheetDecision(close: false, failureMessage: error.message);
  }
  showMessage(error.message);
  return const ModerationSheetDecision();
}
