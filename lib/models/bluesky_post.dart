// Bluesky post data models for embedded posts and external links
//
// These models handle Bluesky post embeds from the backend API

import 'package:flutter/foundation.dart';

import 'post.dart';

/// External link embed from a Bluesky post (link cards with title/description).
class BlueskyExternalEmbed {
  BlueskyExternalEmbed({
    required this.uri,
    this.title,
    this.description,
    this.thumb,
  });

  factory BlueskyExternalEmbed.fromJson(Map<String, dynamic> json) {
    final uri = json['uri'];
    if (uri == null || uri is! String) {
      throw const FormatException(
        'Missing or invalid uri field in BlueskyExternalEmbed',
      );
    }

    return BlueskyExternalEmbed(
      uri: uri,
      title: json['title'] as String?,
      description: json['description'] as String?,
      thumb: json['thumb'] as String?,
    );
  }

  /// URL of the external link
  final String uri;

  /// Page title (from og:title or <title>)
  final String? title;

  /// Page description (from og:description or meta description)
  final String? description;

  /// Thumbnail URL
  final String? thumb;

  /// Extract a nice domain from the URL (e.g., "lemonde.fr" from full URL)
  String get domain {
    final parsed = Uri.tryParse(uri);
    if (parsed == null || parsed.host.isEmpty) {
      return uri;
    }
    var host = parsed.host;
    // Remove www. prefix
    if (host.startsWith('www.')) {
      host = host.substring(4);
    }
    return host;
  }
}

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
    this.embed,
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

    // Parse optional external embed
    BlueskyExternalEmbed? embed;
    if (json['embed'] != null) {
      try {
        embed = BlueskyExternalEmbed.fromJson(
          json['embed'] as Map<String, dynamic>,
        );
      } on FormatException catch (e) {
        if (kDebugMode) {
          debugPrint('BlueskyPostResult: Failed to parse embed: $e');
        }
        // Leave embed as null
      }
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
      embed: embed,
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

  /// External link embed (link card) if present in the post
  final BlueskyExternalEmbed? embed;

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

    // Try to parse resolved post, but handle gracefully if it fails
    // (e.g., deleted posts may have partial data without author)
    BlueskyPostResult? resolved;
    if (json['resolved'] != null) {
      try {
        resolved = BlueskyPostResult.fromJson(
          json['resolved'] as Map<String, dynamic>,
        );
      } on FormatException catch (e) {
        if (kDebugMode) {
          debugPrint(
            'BlueskyPostEmbed: Failed to parse resolved post, '
            'treating as unavailable. Error: $e',
          );
        }
        // Leave resolved as null - UI will show unavailable card
      }
    }

    return BlueskyPostEmbed(uri: uri, cid: cid, resolved: resolved);
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
  ///
  /// Note: We manually parse AT-URIs because Dart's Uri.tryParse() fails on
  /// DIDs containing colons (e.g., did:plc:xxx).
  static String? getPostWebUrl(BlueskyPostResult post, String atUri) {
    // AT-URI format: at://did:plc:xxx/app.bsky.feed.post/rkey
    const prefix = 'at://';

    if (!atUri.startsWith(prefix)) {
      if (kDebugMode) {
        debugPrint('getPostWebUrl: URI does not start with at://: $atUri');
      }
      return null;
    }

    // Remove the at:// prefix and find the path
    final remainder = atUri.substring(prefix.length);

    // Find the first slash after the DID to get the path
    final firstSlash = remainder.indexOf('/');
    if (firstSlash == -1) {
      if (kDebugMode) {
        debugPrint('getPostWebUrl: No path found in URI: $atUri');
      }
      return null;
    }

    // Extract path segments (collection/rkey)
    final path = remainder.substring(firstSlash + 1);
    final pathSegments = path.split('/');

    if (pathSegments.length < 2) {
      if (kDebugMode) {
        debugPrint(
          'getPostWebUrl: Invalid path (expected collection/rkey): $atUri',
        );
      }
      return null;
    }

    // The rkey is the last segment
    final rkey = pathSegments.last;
    return '$_blueskyBaseUrl/profile/${post.author.handle}/post/$rkey';
  }

  /// Build Bluesky profile URL from handle
  static String getProfileUrl(String handle) {
    return '$_blueskyBaseUrl/profile/$handle';
  }
}
