// Liked-item models for /xrpc/social.coves.actor.getLikes, whose feed mixes
// liked posts and liked comments discriminated by "$type".

import 'package:flutter/foundation.dart';

import 'comment.dart';
import 'post.dart';

/// One row of the viewer's likes: a liked post or a liked comment.
sealed class LikedItem {
  const LikedItem();

  /// The liked record's URI: the post's for a liked post, the comment's for
  /// a liked comment.
  String get uri;
}

/// A liked post (`social.coves.actor.getLikes#likedPost`).
final class LikedPost extends LikedItem {
  const LikedPost(this.feedViewPost);

  final FeedViewPost feedViewPost;

  @override
  String get uri => feedViewPost.post.uri;
}

/// A liked comment (`social.coves.actor.getLikes#likedComment`) with the
/// view of the comment's root post.
final class LikedComment extends LikedItem {
  const LikedComment({required this.comment, required this.post});

  final CommentView comment;
  final PostView post;

  @override
  String get uri => comment.uri;
}

/// Which liked items getLikes lists. Omitting the filter means [all].
enum LikesFilter {
  all('all'),
  posts('posts'),
  comments('comments');

  const LikesFilter(this.wireValue);

  /// The getLikes `filter` query value.
  final String wireValue;
}

class LikesResponse {
  LikesResponse({required this.feed, this.cursor});

  /// Parses a getLikes page, skipping any item that is not a map, has an
  /// unknown or missing `$type`, or fails to parse. As with
  /// [TimelineResponse.fromJson], one bad item must never cost the reader
  /// the whole list, so the catch is `on Object`: an unchecked cast deep in
  /// a federated record raises a TypeError, which is an Error.
  factory LikesResponse.fromJson(Map<String, dynamic> json) {
    final feedData = json['feed'];
    final items = <LikedItem>[];

    if (feedData is List) {
      for (final (index, item) in feedData.indexed) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        try {
          final liked = _parseItem(item);
          if (liked != null) {
            items.add(liked);
          }
        } on Object catch (e) {
          if (kDebugMode) {
            debugPrint(
              '⚠️ Skipping malformed likes item $index: ${e.runtimeType}',
            );
          }
        }
      }
    }

    final cursor = json['cursor'];
    return LikesResponse(feed: items, cursor: cursor is String ? cursor : null);
  }

  static const _likedPostType = 'social.coves.actor.getLikes#likedPost';
  static const _likedCommentType = 'social.coves.actor.getLikes#likedComment';

  /// Returns null for an unknown or missing `$type`; throws when a
  /// recognized item is malformed.
  static LikedItem? _parseItem(Map<String, dynamic> item) {
    switch (item[r'$type']) {
      case _likedPostType:
        return LikedPost(FeedViewPost.fromJson(item));
      case _likedCommentType:
        return LikedComment(
          comment: CommentView.fromJson(
            item['comment'] as Map<String, dynamic>,
          ),
          post: PostView.fromJson(item['post'] as Map<String, dynamic>),
        );
      default:
        return null;
    }
  }

  final List<LikedItem> feed;
  final String? cursor;
}

/// The Likes tab's state: a projection of the provider's likes pagination.
class LikesState {
  const LikesState({
    this.items = const [],
    this.cursor,
    this.hasMore = true,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
    this.loadMoreError,
  });

  factory LikesState.initial() => const LikesState();

  final List<LikedItem> items;
  final String? cursor;
  final bool hasMore;
  final bool isLoading;
  final bool isLoadingMore;

  /// First-page error message, if any.
  final String? error;

  /// Pagination error message, if any.
  final String? loadMoreError;
}
