// Post data models for Coves timeline feed
//
// These models match the backend response structure from:
// /xrpc/social.coves.feed.getTimeline
// /xrpc/social.coves.feed.getDiscover

import 'package:flutter/foundation.dart';

import '../constants/embed_types.dart';
import 'bluesky_post.dart';
import 'facet.dart';

export 'facet.dart' show RichTextFacet, parseFacetsFromRecord;

class TimelineResponse {
  TimelineResponse({required this.feed, this.cursor});

  factory TimelineResponse.fromJson(Map<String, dynamic> json) {
    // Handle null feed array from backend
    final feedData = json['feed'];
    final feedList = <FeedViewPost>[];

    if (feedData != null) {
      // Parse feed items, skipping any that fail to parse
      for (final item in feedData as List<dynamic>) {
        try {
          feedList.add(
            FeedViewPost.fromJson(item as Map<String, dynamic>),
          );
        } on Exception catch (e) {
          // Skip malformed posts (e.g., deleted posts with missing data)
          if (kDebugMode) {
            debugPrint('⚠️ Skipping malformed feed item: $e');
          }
        }
      }
    }

    return TimelineResponse(feed: feedList, cursor: json['cursor'] as String?);
  }
  final List<FeedViewPost> feed;
  final String? cursor;
}

class FeedViewPost {
  FeedViewPost({required this.post, this.reason});

  factory FeedViewPost.fromJson(Map<String, dynamic> json) {
    return FeedViewPost(
      post: PostView.fromJson(json['post'] as Map<String, dynamic>),
      reason:
          json['reason'] != null
              ? FeedReason.fromJson(json['reason'] as Map<String, dynamic>)
              : null,
    );
  }
  final PostView post;
  final FeedReason? reason;
}

class ViewerState {
  ViewerState({
    this.vote,
    this.voteUri,
    this.saved = false,
    this.savedUri,
    this.tags,
  });

  factory ViewerState.fromJson(Map<String, dynamic> json) {
    return ViewerState(
      vote: json['vote'] as String?,
      voteUri: json['voteUri'] as String?,
      saved: json['saved'] as bool? ?? false,
      savedUri: json['savedUri'] as String?,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>(),
    );
  }

  /// Vote direction: "up", "down", or null if not voted
  final String? vote;

  /// AT-URI of the vote record
  final String? voteUri;

  /// Whether the post is saved/bookmarked
  final bool saved;

  /// AT-URI of the saved record
  final String? savedUri;

  /// User-applied tags
  final List<String>? tags;
}

class PostView {
  PostView({
    required this.uri,
    required this.cid,
    required this.rkey,
    required this.author,
    required this.community,
    required this.createdAt,
    required this.indexedAt,
    required this.text,
    this.title,
    required this.stats,
    this.embed,
    this.facets,
    this.viewer,
  });

  factory PostView.fromJson(Map<String, dynamic> json) {
    return PostView(
      uri: json['uri'] as String,
      cid: json['cid'] as String,
      rkey: json['rkey'] as String,
      author: AuthorView.fromJson(json['author'] as Map<String, dynamic>),
      community: CommunityRef.fromJson(
        json['community'] as Map<String, dynamic>,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      indexedAt: DateTime.parse(json['indexedAt'] as String),
      text: json['text'] as String? ?? '',
      title: json['title'] as String?,
      stats: PostStats.fromJson(json['stats'] as Map<String, dynamic>),
      embed:
          json['embed'] != null
              ? PostEmbed.fromJson(json['embed'] as Map<String, dynamic>)
              : null,
      // Facets are now in record['facets'] per backend update
      facets: parseFacetsFromRecord(json['record']),
      viewer:
          json['viewer'] != null
              ? ViewerState.fromJson(json['viewer'] as Map<String, dynamic>)
              : null,
    );
  }
  final String uri;
  final String cid;
  final String rkey;
  final AuthorView author;
  final CommunityRef community;
  final DateTime createdAt;
  final DateTime indexedAt;
  final String text;
  final String? title;
  final PostStats stats;
  final PostEmbed? embed;
  final List<RichTextFacet>? facets;
  final ViewerState? viewer;
}

class AuthorView {
  AuthorView({
    required this.did,
    required this.handle,
    this.displayName,
    this.avatar,
  });

  factory AuthorView.fromJson(Map<String, dynamic> json) {
    return AuthorView(
      did: json['did'] as String,
      handle: json['handle'] as String,
      displayName: json['displayName'] as String?,
      avatar: json['avatar'] as String?,
    );
  }
  final String did;
  final String handle;
  final String? displayName;
  final String? avatar;
}

class CommunityRef {
  CommunityRef({
    required this.did,
    required this.name,
    this.handle,
    this.avatar,
    this.viewer,
  });

  factory CommunityRef.fromJson(Map<String, dynamic> json) {
    return CommunityRef(
      did: json['did'] as String,
      name: json['name'] as String,
      handle: json['handle'] as String?,
      avatar: json['avatar'] as String?,
      viewer: json['viewer'] != null
          ? CommunityRefViewerState.fromJson(
              json['viewer'] as Map<String, dynamic>,
            )
          : null,
    );
  }
  final String did;
  final String name;
  final String? handle;
  final String? avatar;

  /// Current user's relationship with this community (if available)
  final CommunityRefViewerState? viewer;
}

/// Viewer state for community ref embedded in posts
class CommunityRefViewerState {
  CommunityRefViewerState({this.subscribed});

  factory CommunityRefViewerState.fromJson(Map<String, dynamic> json) {
    return CommunityRefViewerState(
      subscribed: json['subscribed'] as bool?,
    );
  }

  /// Whether the current user is subscribed to this community
  final bool? subscribed;
}

class PostStats {
  PostStats({
    required this.upvotes,
    required this.downvotes,
    required this.score,
    required this.commentCount,
  });

  factory PostStats.fromJson(Map<String, dynamic> json) {
    return PostStats(
      upvotes: json['upvotes'] as int,
      downvotes: json['downvotes'] as int,
      score: json['score'] as int,
      commentCount: json['commentCount'] as int,
    );
  }
  final int upvotes;
  final int downvotes;
  final int score;
  final int commentCount;
}

class PostEmbed {
  PostEmbed({
    required this.type,
    this.external,
    this.blueskyPost,
    required this.data,
  });

  factory PostEmbed.fromJson(Map<String, dynamic> json) {
    final embedType = json[r'$type'] as String? ?? 'unknown';
    ExternalEmbed? externalEmbed;
    BlueskyPostEmbed? blueskyPostEmbed;

    if (embedType == EmbedTypes.external &&
        json['external'] != null) {
      externalEmbed = ExternalEmbed.fromJson(
        json['external'] as Map<String, dynamic>,
      );
    }

    if (embedType == EmbedTypes.post) {
      blueskyPostEmbed = BlueskyPostEmbed.fromJson(json);
    }

    // Fallback: if no typed embed was parsed but we have a uri field at the
    // top level, treat it as an external link embed. This handles cases where
    // the backend returns simple link embeds without the full $type wrapper.
    if (externalEmbed == null &&
        blueskyPostEmbed == null &&
        json['uri'] != null) {
      if (kDebugMode) {
        debugPrint(
          'PostEmbed fallback: treating unrecognized embed as external link. '
          'Type was: ${json[r'$type']}, keys: ${json.keys.toList()}',
        );
      }
      externalEmbed = ExternalEmbed.fromJson(json);
    }

    return PostEmbed(
      type: embedType,
      external: externalEmbed,
      blueskyPost: blueskyPostEmbed,
      data: json,
    );
  }
  final String type;
  final ExternalEmbed? external;
  final BlueskyPostEmbed? blueskyPost;
  final Map<String, dynamic> data;
}

class ExternalEmbed {
  ExternalEmbed({
    required this.uri,
    this.title,
    this.description,
    this.thumb,
    this.domain,
    this.embedType,
    this.provider,
    this.images,
    this.totalCount,
    this.sources,
  });

  factory ExternalEmbed.fromJson(Map<String, dynamic> json) {
    // Thumb is always a string URL (backend transforms blob refs
    // before sending)

    // Handle images array if present
    List<Map<String, dynamic>>? imagesList;
    if (json['images'] != null && json['images'] is List) {
      imagesList =
          (json['images'] as List).whereType<Map<String, dynamic>>().toList();
    }

    // Handle sources array if present
    List<EmbedSource>? sourcesList;
    if (json['sources'] != null && json['sources'] is List) {
      sourcesList =
          (json['sources'] as List)
              .whereType<Map<String, dynamic>>()
              .map(EmbedSource.fromJson)
              .toList();
    }

    return ExternalEmbed(
      uri: json['uri'] as String,
      title: json['title'] as String?,
      description: json['description'] as String?,
      thumb: json['thumb'] as String?,
      domain: json['domain'] as String?,
      embedType: json['embedType'] as String?,
      provider: json['provider'] as String?,
      images: imagesList,
      totalCount: json['totalCount'] as int?,
      sources: sourcesList,
    );
  }
  final String uri;
  final String? title;
  final String? description;
  final String? thumb;
  final String? domain;
  final String? embedType;
  final String? provider;
  final List<Map<String, dynamic>>? images;
  final int? totalCount;
  final List<EmbedSource>? sources;
}

/// A source link aggregated into a megathread
class EmbedSource {
  EmbedSource({
    required this.uri,
    this.title,
    this.domain,
  });

  factory EmbedSource.fromJson(Map<String, dynamic> json) {
    final uri = json['uri'];
    if (uri == null || uri is! String || uri.isEmpty) {
      throw const FormatException(
        'EmbedSource: Required field "uri" is missing or invalid',
      );
    }

    // Validate URI scheme for security
    final parsedUri = Uri.tryParse(uri);
    if (parsedUri == null ||
        !parsedUri.hasScheme ||
        !['http', 'https'].contains(parsedUri.scheme.toLowerCase())) {
      throw FormatException(
        'EmbedSource: URI has invalid or unsupported scheme: $uri',
      );
    }

    return EmbedSource(
      uri: uri,
      title: json['title'] as String?,
      domain: json['domain'] as String?,
    );
  }

  final String uri;
  final String? title;
  final String? domain;

  @override
  String toString() => 'EmbedSource(uri: $uri, title: $title, domain: $domain)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmbedSource &&
          runtimeType == other.runtimeType &&
          uri == other.uri &&
          title == other.title &&
          domain == other.domain;

  @override
  int get hashCode => Object.hash(uri, title, domain);
}

class FeedReason {
  FeedReason({required this.type, required this.data});

  factory FeedReason.fromJson(Map<String, dynamic> json) {
    return FeedReason(type: json[r'$type'] as String? ?? 'unknown', data: json);
  }
  final String type;
  final Map<String, dynamic> data;
}
