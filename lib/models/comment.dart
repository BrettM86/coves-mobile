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
      // Facets are now in record['facets'] per backend update
      contentFacets: parseFacetsFromRecord(json['record']),
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
  final List<RichTextFacet>? contentFacets;
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

/// Sentinel value for copyWith to distinguish "not provided" from "null"
const _sentinel = Object();

/// State container for a comments list (e.g., actor comments)
///
/// Holds all state for a paginated comments list including loading states,
/// pagination, and errors.
///
/// The [comments] list is immutable - callers cannot modify it externally.
class CommentsState {
  /// Creates a new CommentsState with an immutable comments list.
  CommentsState({
    List<CommentView> comments = const [],
    this.cursor,
    this.hasMore = true,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
  }) : comments = List.unmodifiable(comments);

  /// Create a default empty state
  factory CommentsState.initial() {
    return CommentsState();
  }

  /// Unmodifiable list of comments
  final List<CommentView> comments;

  /// Pagination cursor for next page
  final String? cursor;

  /// Whether more pages are available
  final bool hasMore;

  /// Initial load in progress
  final bool isLoading;

  /// Pagination (load more) in progress
  final bool isLoadingMore;

  /// Error message if any
  final String? error;

  /// Create a copy with modified fields (immutable updates)
  ///
  /// Nullable fields (cursor, error) use a sentinel pattern to distinguish
  /// between "not provided" and "explicitly set to null".
  CommentsState copyWith({
    List<CommentView>? comments,
    Object? cursor = _sentinel,
    bool? hasMore,
    bool? isLoading,
    bool? isLoadingMore,
    Object? error = _sentinel,
  }) {
    return CommentsState(
      comments: comments ?? this.comments,
      cursor: cursor == _sentinel ? this.cursor : cursor as String?,
      hasMore: hasMore ?? this.hasMore,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: error == _sentinel ? this.error : error as String?,
    );
  }
}

/// Response from social.coves.actor.getComments endpoint.
///
/// Returns a flat list of comments by a specific user for their profile page.
/// The endpoint returns an empty array when the user has no comments,
/// and 404 when the user doesn't exist.
class ActorCommentsResponse {
  ActorCommentsResponse({required this.comments, this.cursor});

  /// Parses the JSON response from the API.
  ///
  /// Handles null comments array gracefully by returning an empty list.
  factory ActorCommentsResponse.fromJson(Map<String, dynamic> json) {
    final commentsData = json['comments'];
    final List<CommentView> commentsList;

    if (commentsData == null) {
      commentsList = [];
    } else {
      commentsList =
          (commentsData as List<dynamic>)
              .map((item) => CommentView.fromJson(item as Map<String, dynamic>))
              .toList();
    }

    return ActorCommentsResponse(
      comments: commentsList,
      cursor: json['cursor'] as String?,
    );
  }

  /// List of comments by the actor, ordered newest first.
  final List<CommentView> comments;

  /// Pagination cursor for fetching the next page of comments.
  /// Null when there are no more comments to fetch.
  final String? cursor;
}
