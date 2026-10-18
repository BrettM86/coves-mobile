import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/moderation_constants.dart';
import '../../models/moderation.dart';
import '../../models/moderation_subject_state.dart';
import '../../models/post.dart';
import '../../models/post_get_result.dart';
import '../../providers/viewer_authority_provider.dart';
import '../../providers/vote_provider.dart';
import '../../services/admin_moderation_flow.dart';
import '../../services/admin_tools_gate.dart';
import '../../services/api_exceptions.dart';
import '../../services/coves_api_service.dart';
import '../../services/moderation_errors.dart';
import '../../services/post_change_broadcast.dart';
import 'moderation_action_sheet.dart';
import 'moderation_failure_decision.dart';

/// The admin moderation tools a post menu can offer, in menu order.
enum PostAdminTool {
  markNsfw(
    ModerationCapability.label,
    'Mark NSFW',
    Icons.visibility_off_outlined,
  ),
  removeNsfwLabel(
    ModerationCapability.retractLabel,
    'Remove NSFW label',
    Icons.visibility_outlined,
  ),
  remove(ModerationCapability.remove, 'Remove post', Icons.delete_outline);

  const PostAdminTool(this.capability, this.label, this.icon);

  /// The server token in `viewer.moderation` that grants this tool.
  final ModerationCapability capability;

  /// The menu item's label.
  final String label;

  /// The menu item's leading icon.
  final IconData icon;

  /// Whether the menu item is drawn in red.
  bool get destructive => this == PostAdminTool.remove;
}

/// The tools a post menu offers, in menu order, for a post whose
/// [capabilities] were loaded under [sessionStamp].
List<PostAdminTool> allowedPostAdminTools({
  required Set<ModerationCapability> capabilities,
  required Object? sessionStamp,
  required ViewerAuthorityProvider authority,
}) => [
  for (final tool in PostAdminTool.values)
    if (adminToolAllowed(
      capability: tool.capability,
      capabilities: capabilities,
      loadedUnderSessionKey: sessionStamp,
      authority: authority,
    ))
      tool,
];

/// Opens [tool]'s sheet for [shownPost] and applies the answer on every
/// surface showing the post through [PostChangeBroadcast].
///
/// A removal takes the post off those surfaces. An NSFW change first
/// publishes the shown post with the mutation's moderation state and no
/// admin tools, then the server's own read of the post: capabilities come
/// only from the server. If that read fails, the first post stays.
Future<void> runPostAdminTool(
  BuildContext context, {
  required PostView shownPost,
  required PostAdminTool tool,
}) async {
  final apiService = context.read<CovesApiService>();
  final broadcast = context.read<PostChangeBroadcast>();
  final voteProvider = context.read<VoteProvider>();
  final authority = context.read<ViewerAuthorityProvider>();
  final sessionKey = authority.sessionKey;
  final messenger = ScaffoldMessenger.of(context);
  final subject = StrongRef(uri: shownPost.uri, cid: shownPost.cid);
  final flow = AdminModerationFlow(apiService, authority: authority);
  // Anything that lands after the session changed belongs to the
  // previous account and is neither shown nor applied.
  bool sessionChanged() => authority.sessionKey != sessionKey;
  void showMessage(String message) {
    if (messenger.mounted && !sessionChanged()) {
      messenger.showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
    }
  }

  /// Publishes the server's current post. A post the server no longer
  /// returns leaves every surface when [removeWhenUnavailable].
  Future<void> refreshPost({required bool removeWhenUnavailable}) async {
    final latest = await apiService.getPost(subject.uri);
    if (sessionChanged()) {
      return;
    }
    if (latest is PostGetSuccess) {
      voteProvider.applyServerVoteState(
        postUri: latest.post.uri,
        voteDirection: latest.post.viewer?.vote,
        voteUri: latest.post.viewer?.voteUri,
      );
      broadcast.replacePost(latest.post);
    } else if (removeWhenUnavailable) {
      broadcast.removePost(subject.uri);
    }
  }

  Future<void> publishModeration(ModerationView moderation) async {
    final viewer = shownPost.viewer;
    broadcast.replacePost(
      shownPost.copyWith(
        moderation: moderation,
        viewer: ViewerState(
          vote: viewer?.vote,
          voteUri: viewer?.voteUri,
          saved: viewer?.saved ?? false,
          savedUri: viewer?.savedUri,
          tags: viewer?.tags,
        ),
      ),
    );
    try {
      await refreshPost(removeWhenUnavailable: false);
    } on ApiException {
      // The published post keeps the right blur and offers no admin
      // tools until the next server read.
    }
  }

  Future<ModerationFlowResult> retryOr(
    Future<ModerationFlowResult> Function() submitFresh,
  ) async {
    if (flow.retainedSubmission != null) {
      return (await flow.retry())!;
    }
    return submitFresh();
  }

  Future<ModerationSheetDecision> onResult(ModerationFlowResult outcome) async {
    if (outcome is ModerationFlowSucceeded) {
      final applied =
          outcome.result.outcome == ModerationMutationOutcome.applied;
      switch (tool) {
        case PostAdminTool.remove:
          broadcast.removePost(subject.uri);
          showMessage(applied ? 'Post removed' : 'Post was already removed');
        case PostAdminTool.markNsfw || PostAdminTool.removeNsfwLabel
            when outcome.result.state.moderation.state ==
                ModerationState.removed:
          // A label change can succeed on a removed post; the post still
          // leaves every surface.
          broadcast.removePost(subject.uri);
          showMessage('Someone else already removed this post.');
        case PostAdminTool.markNsfw || PostAdminTool.removeNsfwLabel:
          // Not awaited: the sheet closes on the mutation's answer while
          // the server's read of the post is still out.
          unawaited(publishModeration(outcome.result.state.moderation));
          showMessage(switch ((tool, applied)) {
            (PostAdminTool.markNsfw, true) => 'Marked NSFW',
            (PostAdminTool.markNsfw, false) => 'Post was already NSFW',
            (_, true) => 'NSFW label removed',
            (_, false) => 'Post had no NSFW label',
          });
      }
      return const ModerationSheetDecision();
    }

    return moderationFailureDecision(
      outcome,
      authority: authority,
      showMessage: showMessage,
      resolveStateConflict: (failure) {
        if (failure.currentState?.moderation.state != ModerationState.removed) {
          return false;
        }
        broadcast.removePost(subject.uri);
        showMessage('Someone else already removed this post.');
        return true;
      },
      reloadSubject: (error) async {
        try {
          await refreshPost(removeWhenUnavailable: true);
          showMessage(
            tool == PostAdminTool.removeNsfwLabel &&
                    error.code == ModerationErrorCode.decisionNotFound
                ? 'This post no longer has a server NSFW label.'
                : error.message,
          );
        } on ApiException {
          showMessage("Couldn't complete this action.");
        }
      },
    );
  }

  switch (tool) {
    case PostAdminTool.remove:
      await ModerationActionSheet.show<ModerationFlowResult>(
        context,
        title: 'Remove post',
        confirmLabel: 'Remove',
        reasons: removalReasons,
        failureMessage: "Couldn't remove this post. Try again.",
        authority: authority,
        onSubmit: (reason, privateNote) => retryOr(
          () => flow.submitRemoval(
            subject: subject,
            reason: reason,
            privateNote: privateNote,
          ),
        ),
        onResult: onResult,
      );
    case PostAdminTool.markNsfw:
      await ModerationActionSheet.showOptionalReason<ModerationFlowResult>(
        context,
        title: 'Mark NSFW',
        confirmLabel: 'Mark NSFW',
        reasons: labelReasons,
        failureMessage: "Couldn't mark this post NSFW. Try again.",
        authority: authority,
        onSubmit: (reason, privateNote) => retryOr(
          () => flow.submitLabel(
            subject: subject,
            reason: reason,
            privateNote: privateNote,
          ),
        ),
        onResult: onResult,
      );
    case PostAdminTool.removeNsfwLabel:
      await ModerationActionSheet.showOptionalReason<ModerationFlowResult>(
        context,
        title: 'Remove NSFW label',
        confirmLabel: 'Remove NSFW label',
        reasons: labelReasons,
        failureMessage: "Couldn't remove the NSFW label. Try again.",
        authority: authority,
        onSubmit: (reason, privateNote) => retryOr(
          () => flow.submitLabelRetraction(
            subject: subject,
            reason: reason,
            privateNote: privateNote,
          ),
        ),
        onResult: onResult,
      );
  }
}
