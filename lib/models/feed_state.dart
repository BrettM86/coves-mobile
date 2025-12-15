import 'post.dart';

/// Sentinel value for copyWith to distinguish "not provided" from "null"
const _sentinel = Object();

/// Per-feed state container
///
/// Holds all state for a single feed (Discover or For You) including posts,
/// pagination, loading states, and scroll position.
class FeedState {
  const FeedState({
    this.posts = const [],
    this.cursor,
    this.hasMore = true,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
    this.scrollPosition = 0.0,
    this.lastRefreshTime,
  });

  /// Create a default empty state
  factory FeedState.initial() {
    return const FeedState();
  }

  /// Feed posts
  final List<FeedViewPost> posts;

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

  /// Cached scroll position for this feed
  final double scrollPosition;

  /// Last refresh timestamp for staleness checks
  final DateTime? lastRefreshTime;

  /// Create a copy with modified fields (immutable updates)
  ///
  /// Nullable fields (cursor, error, lastRefreshTime) use a sentinel pattern
  /// to distinguish between "not provided" and "explicitly set to null".
  /// Pass null explicitly to clear these fields.
  FeedState copyWith({
    List<FeedViewPost>? posts,
    Object? cursor = _sentinel,
    bool? hasMore,
    bool? isLoading,
    bool? isLoadingMore,
    Object? error = _sentinel,
    double? scrollPosition,
    Object? lastRefreshTime = _sentinel,
  }) {
    return FeedState(
      posts: posts ?? this.posts,
      cursor: cursor == _sentinel ? this.cursor : cursor as String?,
      hasMore: hasMore ?? this.hasMore,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: error == _sentinel ? this.error : error as String?,
      scrollPosition: scrollPosition ?? this.scrollPosition,
      lastRefreshTime: lastRefreshTime == _sentinel
          ? this.lastRefreshTime
          : lastRefreshTime as DateTime?,
    );
  }
}
