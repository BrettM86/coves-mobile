// Bluesky post data models for embedded posts and external links
//
// These models handle Bluesky post embeds from the backend API

import 'package:flutter/foundation.dart';

import 'post.dart';

class BlueskyPostResult {
  BlueskyPostResult({
    required this.uri,
    required this.cid,
    required this.createdAt,
    required this.author,
    required this.text,
    required this.replyCount,
    required this.repostCount,
    required this.likeCount,
    required this.hasMedia,
    required this.mediaCount,
    this.quotedPost,
    required this.unavailable,
    this.message,
  }) : assert(replyCount >= 0, 'replyCount must be non-negative'),
       assert(repostCount >= 0, 'repostCount must be non-negative'),
       assert(likeCount >= 0, 'likeCount must be non-negative'),
       assert(mediaCount >= 0, 'mediaCount must be non-negative');

  /// Creates a [BlueskyPostResult] from JSON data.
  ///
  /// Throws [FormatException] if required fields are missing or have invalid types.
  /// This includes validation for all required string, int, bool, and DateTime fields.
  factory BlueskyPostResult.fromJson(Map<String, dynamic> json) {
    // Validate required string fields
    final uri = json['uri'];
    if (uri == null || uri is! String) {
      throw const FormatException(
        'Missing or invalid uri field in BlueskyPostResult',
      );
    }

    final cid = json['cid'];
    if (cid == null || cid is! String) {
      throw const FormatException(
        'Missing or invalid cid field in BlueskyPostResult',
      );
    }

    final createdAtStr = json['createdAt'];
    if (createdAtStr == null || createdAtStr is! String) {
      throw const FormatException(
        'Missing or invalid createdAt field in BlueskyPostResult',
      );
    }

    // Parse DateTime with error handling
    final DateTime createdAt;
    try {
      createdAt = DateTime.parse(createdAtStr);
    } on FormatException {
      throw FormatException('Invalid date format for createdAt: $createdAtStr');
    }

    // Validate author field
    final author = json['author'];
    if (author == null || author is! Map<String, dynamic>) {
      throw const FormatException(
        'Missing or invalid author field in BlueskyPostResult',
      );
    }

    final text = json['text'];
    if (text == null || text is! String) {
      throw const FormatException(
        'Missing or invalid text field in BlueskyPostResult',
      );
    }

    // Validate required int fields
    final replyCount = json['replyCount'];
    if (replyCount == null || replyCount is! int) {
      throw const FormatException(
        'Missing or invalid replyCount field in BlueskyPostResult',
      );
    }

    final repostCount = json['repostCount'];
    if (repostCount == null || repostCount is! int) {
      throw const FormatException(
        'Missing or invalid repostCount field in BlueskyPostResult',
      );
    }

    final likeCount = json['likeCount'];
    if (likeCount == null || likeCount is! int) {
      throw const FormatException(
        'Missing or invalid likeCount field in BlueskyPostResult',
      );
    }

    // Validate required bool fields
    final hasMedia = json['hasMedia'];
    if (hasMedia == null || hasMedia is! bool) {
      throw const FormatException(
        'Missing or invalid hasMedia field in BlueskyPostResult',
      );
    }

    final mediaCount = json['mediaCount'];
    if (mediaCount == null || mediaCount is! int) {
      throw const FormatException(
        'Missing or invalid mediaCount field in BlueskyPostResult',
      );
    }

    final unavailable = json['unavailable'];
    if (unavailable == null || unavailable is! bool) {
      throw const FormatException(
        'Missing or invalid unavailable field in BlueskyPostResult',
      );
    }

    return BlueskyPostResult(
      uri: uri,
      cid: cid,
      createdAt: createdAt,
      author: AuthorView.fromJson(author),
      text: text,
      replyCount: replyCount,
      repostCount: repostCount,
      likeCount: likeCount,
      hasMedia: hasMedia,
      mediaCount: mediaCount,
      quotedPost:
          json['quotedPost'] != null
              ? BlueskyPostResult.fromJson(
                json['quotedPost'] as Map<String, dynamic>,
              )
              : null,
      unavailable: unavailable,
      message: json['message'] as String?,
    );
  }

  final String uri;
  final String cid;
  final DateTime createdAt;
  final AuthorView author;
  final String text;
  final int replyCount;
  final int repostCount;
  final int likeCount;
  final bool hasMedia;
  final int mediaCount;
  final BlueskyPostResult? quotedPost;
  final bool unavailable;
  final String? message;

  // NOTE: Missing ==, hashCode overrides (known limitation)
  // Consider using freezed package for value equality in the future
}

class BlueskyPostEmbed {
  BlueskyPostEmbed({required this.uri, required this.cid, this.resolved});

  /// Creates a [BlueskyPostEmbed] from JSON data.
  ///
  /// Throws [FormatException] if the 'post' field is missing or invalid,
  /// or if required fields (uri, cid) within the post object are missing.
  factory BlueskyPostEmbed.fromJson(Map<String, dynamic> json) {
    // Parse the post reference
    final post = json['post'];
    if (post == null || post is! Map<String, dynamic>) {
      throw const FormatException(
        'Missing or invalid post field in BlueskyPostEmbed',
      );
    }

    // Validate required fields in post
    final uri = post['uri'];
    if (uri == null || uri is! String) {
      throw const FormatException(
        'Missing or invalid uri field in BlueskyPostEmbed.post',
      );
    }

    final cid = post['cid'];
    if (cid == null || cid is! String) {
      throw const FormatException(
        'Missing or invalid cid field in BlueskyPostEmbed.post',
      );
    }

    return BlueskyPostEmbed(
      uri: uri,
      cid: cid,
      resolved:
          json['resolved'] != null
              ? BlueskyPostResult.fromJson(
                json['resolved'] as Map<String, dynamic>,
              )
              : null,
    );
  }

  static const _blueskyBaseUrl = 'https://bsky.app';

  /// AT-URI of the embedded post (e.g., "at://did:plc:xxx/app.bsky.feed.post/abc123")
  final String uri;

  /// CID of the embedded post
  final String cid;

  /// Resolved post data (if available from backend)
  final BlueskyPostResult? resolved;

  /// Build Bluesky web URL from AT-URI and author handle
  /// at://did:plc:xxx/app.bsky.feed.post/abc123 -> https://bsky.app/profile/handle/post/abc123
  ///
  /// Returns null if the AT-URI is invalid. Logs debug information when validation fails.
  static String? getPostWebUrl(BlueskyPostResult post, String atUri) {
    final uri = Uri.tryParse(atUri);
    if (uri == null) {
      if (kDebugMode) {
        debugPrint('getPostWebUrl: Failed to parse URI: $atUri');
      }
      return null;
    }
    if (uri.scheme != 'at') {
      if (kDebugMode) {
        debugPrint(
          'getPostWebUrl: Invalid URI scheme (expected "at", got "${uri.scheme}"): $atUri',
        );
      }
      return null;
    }
    if (uri.pathSegments.length < 2) {
      if (kDebugMode) {
        debugPrint(
          'getPostWebUrl: Invalid URI path (expected at least 2 segments, got ${uri.pathSegments.length}): $atUri',
        );
      }
      return null;
    }
    final rkey = uri.pathSegments.last;
    return '$_blueskyBaseUrl/profile/${post.author.handle}/post/$rkey';
  }

  /// Build Bluesky profile URL from handle
  static String getProfileUrl(String handle) {
    return '$_blueskyBaseUrl/profile/$handle';
  }
}
