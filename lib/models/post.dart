// Post data models for Coves timeline feed
//
// These models match the backend response structure from:
// /xrpc/social.coves.feed.getTimeline
// /xrpc/social.coves.feed.getDiscover

import 'package:flutter/foundation.dart';

import '../constants/embed_types.dart';
import 'bluesky_post.dart';

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
      facets:
          json['facets'] != null
              ? (json['facets'] as List<dynamic>)
                  .map((f) => PostFacet.fromJson(f as Map<String, dynamic>))
                  .toList()
              : null,
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
  final List<PostFacet>? facets;
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
  });

  factory CommunityRef.fromJson(Map<String, dynamic> json) {
    return CommunityRef(
      did: json['did'] as String,
      name: json['name'] as String,
      handle: json['handle'] as String?,
      avatar: json['avatar'] as String?,
    );
  }
  final String did;
  final String name;
  final String? handle;
  final String? avatar;
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
}

class PostFacet {
  PostFacet({required this.data});

  factory PostFacet.fromJson(Map<String, dynamic> json) {
    return PostFacet(data: json);
  }
  final Map<String, dynamic> data;
}

class FeedReason {
  FeedReason({required this.type, required this.data});

  factory FeedReason.fromJson(Map<String, dynamic> json) {
    return FeedReason(type: json[r'$type'] as String? ?? 'unknown', data: json);
  }
  final String type;
  final Map<String, dynamic> data;
}
