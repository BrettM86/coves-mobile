// Union result models for social.coves.community.post.get
//
// The endpoint returns `{"posts": [...]}` where each entry is one of:
// - #postView (same shape as feed posts' `.post`)
// - #notFoundPost ({uri, notFound: true})
// - #blockedPost ({uri, blocked: true, blockedBy, author?, community?})
// - #removedPost ({uri, removed: true, code?}): the community's own removal
// - #moderatedPost ({$type, uri, moderation, authorDid?, community?}):
//   instance-scoped or inherited removal
//
// Only #moderatedPost carries a `$type` discriminator; the other members
// are discriminated via the const booleans `notFound` / `blocked` /
// `removed`. Their `$type` strings are still checked defensively in case
// the backend adds them later (standard atproto union encoding).

import 'package:flutter/foundation.dart';

import 'moderation.dart';
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
/// - [PostGetModerated]: removed by instance-scoped or inherited moderation
/// - [PostGetCommunityRemoved]: removed by its community's moderators
sealed class PostGetResult {
  const PostGetResult();

  /// Discriminates the union member and parses it.
  ///
  /// Checks the atproto `$type` discriminator first, then falls back to the
  /// const booleans `notFound` / `blocked` / `removed`, and finally parses
  /// the entry as a postView.
  factory PostGetResult.fromJson(Map<String, dynamic> json) {
    final type = json[r'$type'] as String?;

    if (type == '$_defs#moderatedPost') {
      final uri = json['uri'] as String;
      var moderation = ModerationView.tryParse(json['moderation']);
      if (moderation == null) {
        if (kDebugMode) {
          debugPrint('moderatedPost $uri has no valid moderation object');
        }
        moderation = const ModerationView(state: ModerationState.unknown);
      }
      return PostGetModerated(
        uri: uri,
        moderation: moderation,
        authorDid: json['authorDid'] is String
            ? json['authorDid'] as String
            : null,
        community: _tryParseCommunity(json['community']),
        viewerModeration: _parseViewerModeration(json['viewer']),
      );
    }

    if (type == '$_defs#notFoundPost' || json['notFound'] == true) {
      return PostGetNotFound(json['uri'] as String);
    }

    if (type == '$_defs#blockedPost' || json['blocked'] == true) {
      return PostGetBlocked(
        uri: json['uri'] as String,
        blockedBy: BlockedBy.parse(json['blockedBy'] as String?),
      );
    }

    if (type == '$_defs#removedPost' || json['removed'] == true) {
      return PostGetCommunityRemoved(
        uri: json['uri'] as String,
        code: json['code'] is String ? json['code'] as String : null,
      );
    }

    // Unrecognized union member: treat as not found rather than attempting
    // a postView parse that is guaranteed to be wrong
    if (type != null && type != '$_defs#postView') {
      return PostGetNotFound(json['uri'] as String? ?? '');
    }

    return PostGetSuccess(PostView.fromJson(json));
  }

  static const _defs = 'social.coves.community.post.defs';

  /// Reads only `viewer.moderation` from a tombstone's narrow viewer state;
  /// every other `viewer` field is ignored.
  static Set<ModerationCapability> _parseViewerModeration(Object? viewer) {
    if (viewer is! Map<String, dynamic>) {
      return const {};
    }
    return parseModerationCapabilities(viewer['moderation']);
  }

  /// Community context is optional on a tombstone: a ref missing its
  /// required fields, or with a wrong-typed optional one, is dropped rather
  /// than failing the removal's parse.
  static CommunityRef? _tryParseCommunity(Object? json) {
    if (json is! Map<String, dynamic> ||
        json['did'] is! String ||
        json['name'] is! String) {
      return null;
    }
    // A failed cast in fromJson is a TypeError; the tombstone outranks its
    // cosmetic community context.
    try {
      return CommunityRef.fromJson(json);
      // ignore: avoid_catching_errors
    } on TypeError catch (error) {
      if (kDebugMode) {
        debugPrint('Dropping malformed tombstone community: $error');
      }
      return null;
    }
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

/// Post was removed by instance-scoped or inherited moderation
/// (`#moderatedPost`). Carries no content.
class PostGetModerated extends PostGetResult {
  const PostGetModerated({
    required this.uri,
    required this.moderation,
    this.authorDid,
    this.community,
    this.viewerModeration = const {},
  });

  @override
  final String uri;

  /// Moderation actions the signed-in viewer may take on the tombstone.
  final Set<ModerationCapability> viewerModeration;

  /// Public moderation state establishing the removal.
  final ModerationView moderation;

  /// DID of the post author, when the server projects it.
  final String? authorDid;

  /// Community context, when the server projects it.
  final CommunityRef? community;
}

/// Post was removed by its community's own moderators (`#removedPost`).
class PostGetCommunityRemoved extends PostGetResult {
  const PostGetCommunityRemoved({required this.uri, this.code});

  @override
  final String uri;

  /// The community's removal decision code (e.g. spam), when sent.
  final String? code;
}
