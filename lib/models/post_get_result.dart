// Union result models for social.coves.community.post.get
//
// The endpoint returns `{"posts": [...]}` where each entry is one of:
// - #postView (same shape as feed posts' `.post`)
// - #notFoundPost ({uri, notFound: true})
// - #blockedPost ({uri, blocked: true, blockedBy, author?, community?})
//
// The backend does NOT emit a `$type` discriminator on union members;
// discrimination happens via the const booleans `notFound` / `blocked`.
// `$type` strings are still checked defensively in case the backend adds
// them later (standard atproto union encoding).

import 'post.dart';

/// Who caused a post to be hidden from the viewer.
///
/// Open enum over the lexicon's `blockedBy` knownValues
/// ('author' | 'community' | 'moderator'). Unrecognized or missing
/// server values map to [unknown] so the UI never asserts a specific
/// block reason the server didn't send.
enum BlockedBy {
  author,
  community,
  moderator,
  unknown;

  /// Parses the backend's `blockedBy` string.
  ///
  /// Maps 'author' | 'community' | 'moderator' to the matching value;
  /// anything else (including null) maps to [unknown].
  static BlockedBy parse(String? value) {
    return switch (value) {
      'author' => BlockedBy.author,
      'community' => BlockedBy.community,
      'moderator' => BlockedBy.moderator,
      _ => BlockedBy.unknown,
    };
  }
}

/// One entry of a social.coves.community.post.get response.
///
/// Exactly one of the subtypes applies:
/// - [PostGetSuccess]: post found and visible to the viewer
/// - [PostGetNotFound]: post deleted, never indexed, or invalid URI
/// - [PostGetBlocked]: post hidden from the viewer (block/moderation)
sealed class PostGetResult {
  const PostGetResult();

  /// Discriminates the union member and parses it.
  ///
  /// Checks the atproto `$type` discriminator first (defensive; the backend
  /// currently omits it), then falls back to the const booleans
  /// `notFound == true` / `blocked == true`, and finally parses the entry
  /// as a postView.
  factory PostGetResult.fromJson(Map<String, dynamic> json) {
    final type = json[r'$type'] as String?;

    if (type == 'social.coves.community.post.get#notFoundPost' ||
        json['notFound'] == true) {
      return PostGetNotFound(json['uri'] as String);
    }

    if (type == 'social.coves.community.post.get#blockedPost' ||
        json['blocked'] == true) {
      return PostGetBlocked(
        uri: json['uri'] as String,
        blockedBy: BlockedBy.parse(json['blockedBy'] as String?),
      );
    }

    // Unrecognized union member: treat as not found rather than attempting
    // a postView parse that is guaranteed to be wrong
    if (type != null && type != 'social.coves.community.post.get#postView') {
      return PostGetNotFound(json['uri'] as String? ?? '');
    }

    return PostGetSuccess(PostView.fromJson(json));
  }

  /// The AT-URI this result refers to.
  String get uri;
}

/// Post was found and is visible to the viewer.
class PostGetSuccess extends PostGetResult {
  const PostGetSuccess(this.post);

  /// The full post view (same shape as feed posts' `.post`).
  final PostView post;

  @override
  String get uri => post.uri;
}

/// Post was not found (deleted, never indexed, or invalid URI).
class PostGetNotFound extends PostGetResult {
  const PostGetNotFound(this.uri);

  @override
  final String uri;
}

/// Post is hidden from the viewer due to a block or moderation.
class PostGetBlocked extends PostGetResult {
  const PostGetBlocked({required this.uri, required this.blockedBy});

  @override
  final String uri;

  /// What caused the block; [BlockedBy.unknown] when the server omitted
  /// or sent an unrecognized value.
  final BlockedBy blockedBy;
}
