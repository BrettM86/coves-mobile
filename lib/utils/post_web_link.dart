import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

import '../models/comment.dart';
import '../models/post.dart';
import 'web_link_builder.dart';

/// Unpacks a [PostView] into the plain fields [WebLinkBuilder] takes.
extension PostViewWebLink on PostView {
  /// The canonical web URL for this post, or null when [uri] is not a
  /// well-formed at-URI.
  ///
  /// Every surface holding a [PostView] shares this one unpacking so the
  /// identities in the link cannot drift apart between them. The record key
  /// comes from the at-URI, not from [rkey], for the same reason the web
  /// takes it from there: it is the key of the record the URI addresses.
  String? webUrl(WebLinkBuilder linkBuilder) {
    final url = linkBuilder.post(
      postUri: uri,
      authorDid: author.did,
      authorHandle: author.handle,
      communityDid: community.did,
      communityName: community.name,
      communityOrigin: community.origin,
    );
    if (url == null) {
      _reportUnbuildableWebLink('Post', uri);
    }
    return url;
  }
}

/// Unpacks a [CommentView], plus the post it hangs under, into the plain
/// fields [WebLinkBuilder] takes.
extension CommentViewWebLink on CommentView {
  /// The canonical web URL for this comment, or null when either its own
  /// at-URI or [parentPost]'s is not well-formed.
  ///
  /// The post has to come from the surface showing the comment: the permalink
  /// is built under the post's community, which a comment does not carry. A
  /// deleted comment has no author, and the at-URI authority then carries the
  /// identity on its own.
  ///
  /// Also null when [parentPost] is not the post this comment hangs under.
  /// The permalink would then be a working URL addressing the comment under a
  /// post it is not on, which is worse than no link: the surface handed over
  /// the wrong post, and a reader following the link would land somewhere the
  /// comment does not exist.
  String? webUrl(
    WebLinkBuilder linkBuilder, {
    required PostView parentPost,
  }) {
    if (post.uri != parentPost.uri) {
      _reportUnbuildableWebLink('Comment under the wrong parent post', uri);
      return null;
    }
    final url = linkBuilder.comment(
      commentUri: uri,
      commenterDid: author?.did,
      commenterHandle: author?.handle,
      postUri: parentPost.uri,
      postAuthorDid: parentPost.author.did,
      postAuthorHandle: parentPost.author.handle,
      communityDid: parentPost.community.did,
      communityName: parentPost.community.name,
      communityOrigin: parentPost.community.origin,
    );
    if (url == null) {
      _reportUnbuildableWebLink('Comment', uri);
    }
    return url;
  }
}

/// The at-URIs already reported, so a record that cannot be linked is one
/// Sentry event and not one per frame: these getters run on every rebuild of
/// every surface showing the record.
final Set<String> _reportedUnbuildableUris = {};

/// Reports that a record the app is showing has no web link: either the
/// AppView served identities the web's routes cannot address, or a surface
/// handed a comment the wrong parent post — both worth knowing about rather
/// than leaving as a user-visible failure.
///
/// An at-URI is public identifiers only, so it carries no PII. A record whose
/// URI is empty is not yet loaded and says nothing about the data.
void _reportUnbuildableWebLink(String recordKind, String atUri) {
  if (atUri.isEmpty || !_reportedUnbuildableUris.add(atUri)) {
    return;
  }
  unawaited(
    Sentry.captureMessage(
      '$recordKind yields no web link: $atUri',
      level: SentryLevel.warning,
    ),
  );
}
