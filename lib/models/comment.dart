// Comment data models for Coves
//
// These models match the backend response structure from:
// /xrpc/social.coves.community.comment.getComments

import 'post.dart';

class CommentsResponse {
  CommentsResponse({required this.post, this.cursor, required this.comments});

  factory CommentsResponse.fromJson(Map<String, dynamic> json) {
    // Handle null comments array from backend
    final commentsData = json['comments'];
    final List<ThreadViewComment> commentsList;

    if (commentsData == null) {
      // Backend returned null, use empty list
      commentsList = [];
    } else {
      // Parse comment items
      commentsList =
          (commentsData as List<dynamic>)
              .map(
                (item) =>
                    ThreadViewComment.fromJson(item as Map<String, dynamic>),
              )
              .toList();
    }

    return CommentsResponse(
      post: json['post'],
      cursor: json['cursor'] as String?,
      comments: commentsList,
    );
  }

  final dynamic post;
  final String? cursor;
  final List<ThreadViewComment> comments;
}

class ThreadViewComment {
  ThreadViewComment({
    required this.comment,
    this.replies,
    this.hasMore = false,
  });

  factory ThreadViewComment.fromJson(Map<String, dynamic> json) {
    return ThreadViewComment(
      comment: CommentView.fromJson(json['comment'] as Map<String, dynamic>),
      replies:
          json['replies'] != null
              ? (json['replies'] as List<dynamic>)
                  .map(
                    (item) => ThreadViewComment.fromJson(
                      item as Map<String, dynamic>,
                    ),
                  )
                  .toList()
              : null,
      hasMore: json['hasMore'] as bool? ?? false,
    );
  }

  final CommentView comment;
  final List<ThreadViewComment>? replies;
  final bool hasMore;
}

class CommentView {
  CommentView({
    required this.uri,
    required this.cid,
    required this.content,
    this.contentFacets,
    required this.createdAt,
    required this.indexedAt,
    required this.author,
    required this.post,
    this.parent,
    required this.stats,
    this.viewer,
    this.embed,
  });

  factory CommentView.fromJson(Map<String, dynamic> json) {
    return CommentView(
      uri: json['uri'] as String,
      cid: json['cid'] as String,
      content: json['content'] as String,
      contentFacets:
          json['contentFacets'] != null
              ? (json['contentFacets'] as List<dynamic>)
                  .map((f) => PostFacet.fromJson(f as Map<String, dynamic>))
                  .toList()
              : null,
      createdAt: DateTime.parse(json['createdAt'] as String),
      indexedAt: DateTime.parse(json['indexedAt'] as String),
      author: AuthorView.fromJson(json['author'] as Map<String, dynamic>),
      post: CommentRef.fromJson(json['post'] as Map<String, dynamic>),
      parent:
          json['parent'] != null
              ? CommentRef.fromJson(json['parent'] as Map<String, dynamic>)
              : null,
      stats: CommentStats.fromJson(json['stats'] as Map<String, dynamic>),
      viewer:
          json['viewer'] != null
              ? CommentViewerState.fromJson(
                json['viewer'] as Map<String, dynamic>,
              )
              : null,
      embed: json['embed'],
    );
  }

  final String uri;
  final String cid;
  final String content;
  final List<PostFacet>? contentFacets;
  final DateTime createdAt;
  final DateTime indexedAt;
  final AuthorView author;
  final CommentRef post;
  final CommentRef? parent;
  final CommentStats stats;
  final CommentViewerState? viewer;
  final dynamic embed;
}

class CommentRef {
  CommentRef({required this.uri, required this.cid});

  factory CommentRef.fromJson(Map<String, dynamic> json) {
    return CommentRef(uri: json['uri'] as String, cid: json['cid'] as String);
  }

  final String uri;
  final String cid;
}

class CommentStats {
  CommentStats({this.upvotes = 0, this.downvotes = 0, this.score = 0});

  factory CommentStats.fromJson(Map<String, dynamic> json) {
    return CommentStats(
      upvotes: json['upvotes'] as int? ?? 0,
      downvotes: json['downvotes'] as int? ?? 0,
      score: json['score'] as int? ?? 0,
    );
  }

  final int upvotes;
  final int downvotes;
  final int score;
}

class CommentViewerState {
  CommentViewerState({this.vote, this.voteUri});

  factory CommentViewerState.fromJson(Map<String, dynamic> json) {
    return CommentViewerState(
      vote: json['vote'] as String?,
      voteUri: json['voteUri'] as String?,
    );
  }

  /// Vote direction: "up", "down", or null if not voted
  final String? vote;

  /// AT-URI of the vote record (if backend provides it)
  final String? voteUri;
}
