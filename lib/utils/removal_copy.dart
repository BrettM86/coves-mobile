import '../models/moderation.dart';

/// Placeholder copy naming who deleted or removed a post or comment.
///
/// Shared by the post tombstone and the comment placeholder so both name
/// the same remover for the same moderation state.
abstract final class RemovalCopy {
  static const deletedByUser = '[Deleted by user]';
  static const removedByServerAdmin = '[Removed by server admin]';
  static const removedByCommunityModerator = '[Removed by community moderator]';
  static const removedByModerator = '[Removed by moderator]';

  /// Copy for a removal established by [moderation]: an instance-scoped
  /// source wins over a community-scoped one; with neither (no moderation,
  /// or only unknown scopes) the remover is a generic moderator.
  static String forModeration(ModerationView? moderation) {
    final kinds = moderation?.sources.map((source) => source.scope.kind) ?? [];
    if (kinds.contains(ModerationScopeKind.instance)) {
      return removedByServerAdmin;
    }
    if (kinds.contains(ModerationScopeKind.community)) {
      return removedByCommunityModerator;
    }
    return removedByModerator;
  }

  /// Copy for a comment placeholder. An author deletion wins even when a
  /// moderator removal is also attached. A missing or unrecognized
  /// [deletionReason] names a moderator only when [moderation] says the
  /// comment is removed; otherwise (legacy rows) the author deleted it.
  static String forComment({
    required String? deletionReason,
    required ModerationView? moderation,
  }) {
    return switch (deletionReason) {
      'author' => deletedByUser,
      'moderator' => forModeration(moderation),
      _ when moderation?.state == ModerationState.removed => forModeration(
        moderation,
      ),
      _ => deletedByUser,
    };
  }
}
