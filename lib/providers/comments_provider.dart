import 'dart:async' show Completer, Timer, unawaited;

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import '../models/comment.dart';
import '../models/post.dart';
import '../services/api_exceptions.dart';
import '../services/comment_service.dart';
import '../services/coves_api_service.dart';
import 'auth_provider.dart';
import 'vote_provider.dart';

/// Comments Provider
///
/// Manages comment state and fetching logic for a specific post.
/// Each provider instance is bound to a single post (immutable postUri/postCid).
/// Supports sorting (hot/top/new), pagination, vote integration, scroll position,
/// and draft text preservation.
///
/// IMPORTANT: Provider instances are managed by CommentsProviderCache which
/// handles LRU eviction and sign-out cleanup. Do not create directly in widgets.
///
/// IMPORTANT: Accepts AuthProvider reference to fetch fresh access
/// tokens before each authenticated request (critical for atProto OAuth
/// token rotation).
class CommentsProvider with ChangeNotifier {
  CommentsProvider(
    this._authProvider, {
    required String postUri,
    required String postCid,
    CovesApiService? apiService,
    VoteProvider? voteProvider,
    CommentService? commentService,
    List<Duration>? indexingRetryDelays,
  }) : _postUri = postUri,
       _postCid = postCid,
       _voteProvider = voteProvider,
       _commentService = commentService,
       _indexingRetryDelays =
           indexingRetryDelays ?? _defaultIndexingRetryDelays {
    // Use injected service (for testing) or create new one (for production)
    // Pass token getter, refresh handler, and sign out handler to API service
    // for automatic fresh token retrieval and automatic token refresh on 401
    _apiService =
        apiService ??
        CovesApiService(
          tokenGetter: _authProvider.getAccessToken,
          tokenRefresher: _authProvider.refreshToken,
          signOutHandler: _authProvider.signOut,
        );
  }

  /// Maximum comment length in characters (matches backend limit)
  /// Note: This counts Unicode grapheme clusters, so emojis count correctly
  static const int maxCommentLength = 10000;

  /// Default staleness threshold for background refresh
  static const Duration stalenessThreshold = Duration(minutes: 5);

  /// Default backoff schedule while waiting for the AppView to index a
  /// newly created comment (~1-2s firehose lag). Injectable via the
  /// constructor so tests don't need real delays.
  static const List<Duration> _defaultIndexingRetryDelays = [
    Duration(milliseconds: 400),
    Duration(milliseconds: 800),
    Duration(milliseconds: 1200),
  ];

  final AuthProvider _authProvider;
  late final CovesApiService _apiService;
  final VoteProvider? _voteProvider;
  final CommentService? _commentService;
  final List<Duration> _indexingRetryDelays;

  // Post context - immutable per provider instance
  final String _postUri;
  final String _postCid;

  // Comment state
  List<ThreadViewComment> _comments = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _isQuietLoading = false;
  String? _error;
  String? _cursor;
  bool _hasMore = true;

  // Bumped whenever the whole tree is replaced (refresh/sort change/delete).
  // In-flight subtree fetches capture it at start and discard their response
  // if it changed, so a stale subtree is never merged into a newer tree.
  int _treeGeneration = 0;

  // Collapsed thread state - stores URIs of collapsed comments
  final Set<String> _collapsedComments = {};

  // In-flight "load more replies" subtree fetches, keyed by comment URI.
  // Duplicate calls for the same URI get the existing future back so every
  // caller receives the real result instead of null.
  final Map<String, Future<ThreadViewComment?>> _loadingMoreReplies = {};

  // Scroll position state (replaces ScrollStateService for this post)
  double _scrollPosition = 0;

  // Draft reply text - stored per-parent-URI (null key = top-level reply to post)
  // This allows users to have separate drafts for different comments within the same post
  final Map<String?, String> _drafts = {};

  // Staleness tracking for background refresh
  DateTime? _lastRefreshTime;

  // Comment configuration
  String _sort = 'hot';
  String? _timeframe;

  // Flag to track if a refresh should be scheduled after current load
  bool _pendingRefresh = false;

  // Time update mechanism for periodic UI refreshes
  Timer? _timeUpdateTimer;
  final ValueNotifier<DateTime?> _currentTimeNotifier = ValueNotifier(null);

  bool _isDisposed = false;

  void _safeNotifyListeners() {
    if (_isDisposed) return;
    notifyListeners();
  }

  // Getters
  String get postUri => _postUri;
  String get postCid => _postCid;
  List<ThreadViewComment> get comments => _comments;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  String? get error => _error;
  bool get hasMore => _hasMore;
  String get sort => _sort;
  String? get timeframe => _timeframe;
  ValueNotifier<DateTime?> get currentTimeNotifier => _currentTimeNotifier;
  Set<String> get collapsedComments => Set.unmodifiable(_collapsedComments);

  /// Comment URIs with an in-flight "load more replies" subtree fetch
  /// (for spinner state in the UI).
  Set<String> get loadingMoreReplies =>
      Set.unmodifiable(_loadingMoreReplies.keys);
  double get scrollPosition => _scrollPosition;
  DateTime? get lastRefreshTime => _lastRefreshTime;

  /// Get draft text for a specific parent URI
  ///
  /// [parentUri] - URI of parent comment (null for top-level post reply)
  /// Returns the draft text, or empty string if no draft exists
  String getDraft({String? parentUri}) => _drafts[parentUri] ?? '';

  /// Legacy getters for backward compatibility
  /// @deprecated Use getDraft(parentUri: ...) instead
  String get draftText => _drafts.values.firstOrNull ?? '';
  String? get draftParentUri => _drafts.keys.firstOrNull;

  /// Check if cached data is stale and should be refreshed in background
  bool get isStale {
    if (_lastRefreshTime == null) {
      return true;
    }
    return DateTime.now().difference(_lastRefreshTime!) > stalenessThreshold;
  }

  /// Save scroll position (called on every scroll event)
  void saveScrollPosition(double position) {
    _scrollPosition = position;
    // No notifyListeners - this is passive state save
  }

  /// Save draft reply text
  ///
  /// [text] - The draft text content
  /// [parentUri] - URI of parent comment (null for top-level post reply)
  ///
  /// Each parent URI gets its own draft, so switching between replies
  /// preserves drafts for each context.
  void saveDraft(String text, {String? parentUri}) {
    if (text.trim().isEmpty) {
      // Remove empty drafts to avoid clutter
      _drafts.remove(parentUri);
    } else {
      _drafts[parentUri] = text;
    }
    // No notifyListeners - this is passive state save
  }

  /// Clear draft text for a specific parent (call after successful submission)
  ///
  /// [parentUri] - URI of parent comment (null for top-level post reply)
  void clearDraft({String? parentUri}) {
    _drafts.remove(parentUri);
  }

  /// Toggle collapsed state for a comment thread
  ///
  /// When collapsed, the comment's replies are hidden from view.
  /// Long-pressing the same comment again will expand the thread.
  void toggleCollapsed(String uri) {
    if (_collapsedComments.contains(uri)) {
      _collapsedComments.remove(uri);
    } else {
      _collapsedComments.add(uri);
    }
    _safeNotifyListeners();
  }

  /// Check if a specific comment is collapsed
  bool isCollapsed(String uri) => _collapsedComments.contains(uri);

  /// Start periodic time updates for "time ago" strings
  ///
  /// Updates currentTime every minute to trigger UI rebuilds for
  /// comment timestamps. This ensures "5m ago" updates to "6m ago" without
  /// requiring user interaction.
  ///
  /// Uses ValueNotifier to avoid triggering full provider rebuilds.
  void startTimeUpdates() {
    // Cancel existing timer if any
    _timeUpdateTimer?.cancel();

    // Update current time immediately
    _currentTimeNotifier.value = DateTime.now();

    // Set up periodic updates (every minute)
    _timeUpdateTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _currentTimeNotifier.value = DateTime.now();
    });

    if (kDebugMode) {
      debugPrint('⏰ Started periodic time updates for comment timestamps');
    }
  }

  /// Stop periodic time updates
  void stopTimeUpdates() {
    _timeUpdateTimer?.cancel();
    _timeUpdateTimer = null;
    _currentTimeNotifier.value = null;

    if (kDebugMode) {
      debugPrint('⏰ Stopped periodic time updates');
    }
  }

  /// Load comments for this provider's post
  ///
  /// Parameters:
  /// - [refresh]: Whether to refresh from the beginning (true) or paginate (false)
  /// - [quiet]: When refreshing, don't flip [isLoading] (no full-list loading
  ///   flicker). Used for background retries while waiting for the AppView to
  ///   index a newly created comment.
  Future<void> loadComments({bool refresh = false, bool quiet = false}) async {
    // If already loading, schedule a refresh to happen after current load
    if (_isLoading || _isLoadingMore || _isQuietLoading) {
      if (refresh) {
        _pendingRefresh = true;
        if (kDebugMode) {
          debugPrint(
            '⏳ Load in progress - scheduled refresh for after completion',
          );
        }
      }
      return;
    }

    try {
      if (refresh) {
        if (quiet) {
          // Internal re-entrancy guard only - not exposed via isLoading, so
          // the UI keeps showing the current tree while we refresh behind it.
          _isQuietLoading = true;
        } else {
          _isLoading = true;
        }
        _error = null;
        _pendingRefresh = false; // Clear any pending refresh
      } else {
        _isLoadingMore = true;
      }
      _safeNotifyListeners();

      if (kDebugMode) {
        debugPrint('📡 Fetching comments: sort=$_sort, postUri=$_postUri');
      }

      final response = await _apiService.getComments(
        postUri: _postUri,
        sort: _sort,
        timeframe: _timeframe,
        cursor: refresh ? null : _cursor,
      );

      if (_isDisposed) return;

      // Only update state after successful fetch
      if (refresh) {
        _comments = response.comments;
        _lastRefreshTime = DateTime.now();
        // The whole tree was replaced - invalidate in-flight subtree fetches
        // so they don't merge stale data into the new tree.
        _treeGeneration++;
      } else {
        // Create new list instance to trigger rebuilds
        _comments = [..._comments, ...response.comments];
      }

      _cursor = response.cursor;
      _hasMore = response.cursor != null;
      _error = null;

      if (kDebugMode) {
        debugPrint('✅ Comments loaded: ${_comments.length} comments total');
      }

      // Initialize vote state from viewer data in comments response
      if (_authProvider.isAuthenticated && _voteProvider != null) {
        if (refresh) {
          // On refresh, initialize all comments - server data is truth
          _comments.forEach(_initializeCommentVoteState);
        } else {
          // On pagination, only initialize newly fetched comments to avoid
          // overwriting optimistic vote state on existing comments
          response.comments.forEach(_initializeCommentVoteState);
        }
      }

      // Start time updates when comments are loaded
      if (_comments.isNotEmpty && _timeUpdateTimer == null) {
        startTimeUpdates();
      }
    } on Exception catch (e) {
      if (_isDisposed) return;
      _error = e.toString();
      if (kDebugMode) {
        debugPrint('❌ Failed to fetch comments: $e');
      }
    } finally {
      if (_isDisposed) return;
      _isLoading = false;
      _isLoadingMore = false;
      _isQuietLoading = false;
      _safeNotifyListeners();

      // If a refresh was scheduled during this load, execute it now
      if (_pendingRefresh) {
        if (kDebugMode) {
          debugPrint('🔄 Executing pending refresh');
        }
        _pendingRefresh = false;
        // Schedule refresh without awaiting to avoid blocking
        // This is intentional - we want the refresh to happen asynchronously
        unawaited(loadComments(refresh: true));
      }
    }
  }

  /// Refresh comments (pull-to-refresh)
  ///
  /// Reloads comments from the beginning for the current post.
  Future<void> refreshComments() async {
    await loadComments(refresh: true);
  }

  /// Load more comments (pagination)
  Future<void> loadMoreComments() async {
    if (!_hasMore || _isLoadingMore) {
      return;
    }
    await loadComments();
  }

  /// Load more replies for a specific comment ("Load more replies" button)
  ///
  /// Fetches the subtree rooted at [commentUri] via the getComments
  /// `parentRkey` parameter and merges it into the in-memory comment tree.
  /// This surfaces replies hidden by the per-parent sibling cap or the
  /// nesting-depth cutoff of the original thread fetch. When the node
  /// already has a [ThreadViewComment.repliesCursor] (a previous page was
  /// fetched), the cursor is sent and the new page of direct replies is
  /// appended instead of replacing what's already loaded.
  ///
  /// Returns the merged subtree so callers (e.g. the focused thread screen)
  /// can render it even when the node is no longer present in the top-level
  /// tree. If a fetch for the same comment is already in flight, the
  /// EXISTING future is returned, so every caller gets the real result.
  /// Returns null when the server returned no/mismatched subtree (the
  /// node's hasMore/cursor are cleared on an empty response so the UI stops
  /// offering a load-more that can never succeed), when the response became
  /// stale (tree refreshed or sort changed mid-flight), or when the
  /// provider was disposed.
  ///
  /// Throws [ArgumentError] for a malformed comment URI (programmer error).
  /// Throws ApiException/AuthenticationException on network or auth errors.
  Future<ThreadViewComment?> loadMoreReplies(String commentUri) {
    final inFlight = _loadingMoreReplies[commentUri];
    if (inFlight != null) {
      return inFlight;
    }

    // rkey is the last path segment of the comment AT-URI. Note: Uri.parse
    // cannot handle at:// URIs (the DID's colons look like an invalid port).
    final segments = commentUri.split('/');
    final rkey = segments.length > 1 ? segments.last : '';
    if (rkey.isEmpty) {
      throw ArgumentError.value(
        commentUri,
        'commentUri',
        'malformed comment AT-URI',
      );
    }

    // Register the in-flight future BEFORE starting the work: the fetch can
    // fail synchronously, and _doLoadMoreReplies' cleanup must always run
    // after the map entry exists or the entry would leak forever.
    final completer = Completer<ThreadViewComment?>();
    _loadingMoreReplies[commentUri] = completer.future;
    _safeNotifyListeners();
    completer.complete(_doLoadMoreReplies(commentUri, rkey));
    return completer.future;
  }

  Future<ThreadViewComment?> _doLoadMoreReplies(
    String commentUri,
    String rkey,
  ) async {
    // Capture staleness markers before the fetch: if the tree is wholesale
    // replaced (refresh/delete) or the sort changes while we're in flight,
    // this response no longer belongs to what's on screen.
    final startGeneration = _treeGeneration;
    final startSort = _sort;

    // Pass the stored cursor (if any) so a node with more than one page of
    // direct replies advances through pages instead of refetching page 1.
    final requestCursor = _findNodeByUri(commentUri)?.repliesCursor;

    try {
      final response = await _apiService.getComments(
        postUri: _postUri,
        sort: _sort,
        timeframe: _timeframe,
        parentRkey: rkey,
        cursor: requestCursor,
      );

      if (_isDisposed) {
        return null;
      }

      if (_treeGeneration != startGeneration || _sort != startSort) {
        if (kDebugMode) {
          debugPrint(
            '⚠️ loadMoreReplies: discarding stale subtree for $rkey '
            '(tree refreshed or sort changed mid-flight)',
          );
        }
        return null;
      }

      final existingNode = _findNodeByUri(commentUri);

      if (response.comments.isEmpty) {
        // Nothing to load - clear the node's pagination state so the
        // "load more" affordance disappears instead of spinning forever.
        if (existingNode != null &&
            (existingNode.hasMore || existingNode.repliesCursor != null)) {
          _comments = _replaceNode(
            _comments,
            existingNode.copyWith(hasMore: false, repliesCursor: null),
          );
        }
        return null;
      }

      // Contract guard: the response must contain the subtree rooted at the
      // requested comment as its sole top-level entry.
      final fresh = response.comments.first;
      if (fresh.comment.uri != commentUri) {
        if (kDebugMode) {
          debugPrint(
            '⚠️ loadMoreReplies: response anchored at ${fresh.comment.uri}, '
            'expected $commentUri - discarding',
          );
        }
        return null;
      }

      // Collect URIs already in the tree BEFORE merging so genuinely new
      // comments get initialized while already-visible ones get reconciled
      // (blind re-initialization would clobber optimistic votes).
      final knownUris = <String>{};
      if (existingNode != null) {
        _collectSubtreeUris(existingNode, knownUris);
      }

      // The response cursor paginates this node's direct replies; if
      // present there are more direct replies beyond this page.
      final ThreadViewComment subtree;
      if (requestCursor != null && existingNode != null) {
        // Cursor page: append the new page's direct replies (deduplicated
        // by URI) to the ones already loaded instead of replacing them.
        final existingReplies =
            existingNode.replies ?? const <ThreadViewComment>[];
        final seenUris = existingReplies.map((r) => r.comment.uri).toSet();
        final newPage = (fresh.replies ?? const <ThreadViewComment>[])
            .where((reply) => !seenUris.contains(reply.comment.uri));
        subtree = fresh.copyWith(
          replies: [...existingReplies, ...newPage],
          hasMore: response.cursor != null,
          repliesCursor: response.cursor,
        );
      } else {
        // First page: merge with the existing node (if any) so deeper
        // branches hydrated earlier survive the refetch.
        final merged =
            existingNode == null ? fresh : _mergeSubtree(fresh, existingNode);
        subtree = merged.copyWith(
          hasMore: response.cursor != null,
          repliesCursor: response.cursor,
        );
      }

      final updated = _replaceNode(_comments, subtree);
      if (identical(updated, _comments)) {
        // Node not in the top-level tree (e.g. below the depth cap when
        // called from the focused thread screen) - nothing to merge, but
        // the returned subtree is still useful to the caller.
        if (kDebugMode) {
          debugPrint(
            'ℹ️ loadMoreReplies: $commentUri not in top-level tree - '
            'returning subtree without merging',
          );
        }
      } else {
        _comments = updated;
      }

      // Initialize vote state for new replies; reconcile already-known ones
      // against the fresh server stats just merged in.
      if (_authProvider.isAuthenticated && _voteProvider != null) {
        _initializeVoteStateForNewComments(subtree, knownUris);
      }

      if (kDebugMode) {
        debugPrint(
          '✅ Loaded replies subtree for $rkey '
          '(${subtree.replies?.length ?? 0} direct replies)',
        );
      }

      return subtree;
    } finally {
      if (!_isDisposed) {
        // Map.remove returns the (already-settled) future; nothing to await.
        unawaited(_loadingMoreReplies.remove(commentUri));
        _safeNotifyListeners();
      }
    }
  }

  /// Merges a freshly fetched [fresh] subtree with the [existing] version of
  /// the same node already in the tree.
  ///
  /// Semantics: fresh data wins for node content/stats, but deeper branches
  /// hydrated earlier (via nested load-more) are preserved when they are
  /// absent from the fresh response only because of its depth/sibling
  /// truncation - absence from a truncated response does not mean deletion.
  /// When the fresh listing of a node's replies is complete (no hasMore),
  /// absence DOES mean deletion and the stale children are dropped.
  ThreadViewComment _mergeSubtree(
    ThreadViewComment fresh,
    ThreadViewComment existing,
  ) {
    assert(
      fresh.comment.uri == existing.comment.uri,
      '_mergeSubtree requires nodes with the same URI',
    );

    final freshReplies = fresh.replies;
    final existingReplies = existing.replies;

    // Fresh node hit the response's depth cutoff (no replies loaded) but we
    // already hydrated this branch - keep the existing branch and its
    // pagination state; take the fresh node's content/stats.
    if (freshReplies == null || freshReplies.isEmpty) {
      if (existingReplies == null || existingReplies.isEmpty) {
        return fresh;
      }
      return fresh.copyWith(
        replies: existingReplies,
        hasMore: existing.hasMore,
        repliesCursor: existing.repliesCursor,
      );
    }

    // Merge per-child by URI: children present in both are merged
    // recursively (so grandchildren expansions survive too).
    final existingByUri = <String, ThreadViewComment>{
      for (final reply in existingReplies ?? const <ThreadViewComment>[])
        reply.comment.uri: reply,
    };
    final mergedReplies = <ThreadViewComment>[
      for (final freshChild in freshReplies)
        existingByUri.containsKey(freshChild.comment.uri)
            ? _mergeSubtree(
              freshChild,
              existingByUri.remove(freshChild.comment.uri)!,
            )
            : freshChild,
    ];

    // Children we had before that are missing from a sibling-truncated
    // fresh page are preserved (appended after the fresh ordering).
    if (fresh.hasMore && existingByUri.isNotEmpty) {
      mergedReplies.addAll(existingByUri.values);
    }

    return fresh.copyWith(
      replies: mergedReplies,
      // Per-node reply cursors only come from earlier subtree fetches of
      // that node - the fresh response doesn't carry them, so keep ours.
      repliesCursor: existing.repliesCursor,
    );
  }

  /// Finds the node with [uri] anywhere in the current top-level tree.
  ThreadViewComment? _findNodeByUri(String uri) {
    for (final node in _comments) {
      final found = node.findByUri(uri);
      if (found != null) {
        return found;
      }
    }
    return null;
  }

  /// Collects the URIs of [node] and all its descendants into [uris].
  void _collectSubtreeUris(ThreadViewComment node, Set<String> uris) {
    uris.add(node.comment.uri);
    for (final reply in node.replies ?? const <ThreadViewComment>[]) {
      _collectSubtreeUris(reply, uris);
    }
  }

  /// Initializes vote state for comments in [node]'s subtree that are new,
  /// and reconciles the ones already known (mirrors the pagination pattern
  /// in loadComments: never blindly re-initialize already-visible comments,
  /// which would revert optimistic votes).
  ///
  /// Known comments are reconciled instead of skipped: the subtree merge
  /// adopts fresh server stats for nodes already in the tree, so a stale
  /// optimistic score adjustment would double-count on top of a server
  /// score that already includes the vote. Reconciliation clears the
  /// adjustment only when the server's viewer state confirms it has caught
  /// up, so an unindexed optimistic vote is never clobbered.
  ///
  /// "Known" means in [knownUris] (present in the top-level tree before the
  /// merge) OR already tracked by the VoteProvider. The latter covers
  /// subtrees anchored below the top-level tree's depth cap (the focused
  /// thread screen): there [knownUris] is empty, but a comment the user
  /// just voted on must still be reconciled, not clobbered.
  void _initializeVoteStateForNewComments(
    ThreadViewComment node,
    Set<String> knownUris,
  ) {
    final voteProvider = _voteProvider!;
    final uri = node.comment.uri;
    final viewer = node.comment.viewer;
    final known = knownUris.contains(uri) || voteProvider.hasStateFor(uri);
    if (!known) {
      voteProvider.setInitialVoteState(
        postUri: uri,
        voteDirection: viewer?.vote,
        voteUri: viewer?.voteUri,
      );
    } else {
      voteProvider.reconcileVoteState(
        postUri: uri,
        serverVoteDirection: viewer?.vote,
        serverVoteUri: viewer?.voteUri,
      );
    }
    for (final reply in node.replies ?? const <ThreadViewComment>[]) {
      _initializeVoteStateForNewComments(reply, knownUris);
    }
  }

  /// Returns a copy of [nodes] with the node matching [replacement]'s URI
  /// replaced by [replacement]. Preserves reference identity when the node
  /// is absent (returns [nodes] itself) so callers can detect a missed
  /// merge via `identical`.
  List<ThreadViewComment> _replaceNode(
    List<ThreadViewComment> nodes,
    ThreadViewComment replacement,
  ) {
    var changed = false;
    final mapped = <ThreadViewComment>[];
    for (final node in nodes) {
      final result = node.replaceDescendant(replacement);
      if (!identical(result, node)) {
        changed = true;
      }
      mapped.add(result);
    }
    return changed ? mapped : nodes;
  }

  /// Change sort order
  ///
  /// Updates the sort option and triggers a refresh of comments.
  /// Available options: 'hot', 'top', 'new'
  ///
  /// Returns true if sort change succeeded, false if reload failed.
  /// On failure, reverts to previous sort option.
  Future<bool> setSortOption(String newSort) async {
    if (_sort == newSort) {
      return true;
    }

    final previousSort = _sort;
    _sort = newSort;
    _safeNotifyListeners();

    // Reload comments with new sort
    try {
      await loadComments(refresh: true);
      return true;
    } on Exception catch (e) {
      if (_isDisposed) return false;
      // Revert to previous sort option on failure
      _sort = previousSort;
      _safeNotifyListeners();

      if (kDebugMode) {
        debugPrint('Failed to apply sort option: $e');
      }

      return false;
    }
  }

  /// Vote on a comment
  ///
  /// Delegates to VoteProvider for optimistic updates and API calls.
  /// The VoteProvider handles:
  /// - Optimistic UI updates
  /// - API call to user's PDS
  /// - Rollback on error
  ///
  /// Parameters:
  /// - [commentUri]: AT-URI of the comment
  /// - [commentCid]: Content ID of the comment
  /// - [voteType]: Vote direction ('up' or 'down')
  ///
  /// Returns:
  /// - true if vote was created
  /// - false if vote was removed (toggled off)
  Future<bool> voteOnComment({
    required String commentUri,
    required String commentCid,
    String voteType = 'up',
  }) async {
    if (_voteProvider == null) {
      throw Exception('VoteProvider not available');
    }

    try {
      final result = await _voteProvider.toggleVote(
        postUri: commentUri,
        postCid: commentCid,
        direction: voteType,
      );

      if (kDebugMode) {
        debugPrint('✅ Comment vote ${result ? 'created' : 'removed'}');
      }

      return result;
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to vote on comment: $e');
      }
      rethrow;
    }
  }

  /// Create a comment on the current post or as a reply to another comment
  ///
  /// Parameters:
  /// - [content]: The comment text content
  /// - [parentComment]: Optional parent comment for nested replies.
  ///   If null, this is a top-level reply to the post.
  ///
  /// The reply reference structure:
  /// - Root: Always points to the original post (_postUri, _postCid)
  /// - Parent: Points to the post (top-level) or the parent comment (nested)
  ///
  /// After successful creation, refreshes the comments list.
  ///
  /// Throws:
  /// - ValidationException if content is empty or too long
  /// - ApiException if CommentService is not available or no post is loaded
  /// - ApiException for API errors
  Future<void> createComment({
    required String content,
    List<RichTextFacet>? contentFacets,
    ThreadViewComment? parentComment,
  }) async {
    // Validate content
    final trimmedContent = content.trim();
    if (trimmedContent.isEmpty) {
      throw ValidationException('Comment cannot be empty');
    }

    // Use characters.length for proper Unicode/emoji counting
    final charCount = trimmedContent.characters.length;
    if (charCount > maxCommentLength) {
      throw ValidationException(
        'Comment too long ($charCount characters). '
        'Maximum is $maxCommentLength characters.',
      );
    }

    if (_commentService == null) {
      throw ApiException('CommentService not available');
    }

    // Root is always the original post
    final rootUri = _postUri;
    final rootCid = _postCid;

    // Parent depends on whether this is a top-level or nested reply
    final String parentUri;
    final String parentCid;

    if (parentComment != null) {
      // Nested reply - parent is the comment being replied to
      parentUri = parentComment.comment.uri;
      parentCid = parentComment.comment.cid;
    } else {
      // Top-level reply - parent is the post
      parentUri = rootUri;
      parentCid = rootCid;
    }

    if (kDebugMode) {
      debugPrint('💬 Creating comment');
      debugPrint('   Root: $rootUri');
      debugPrint('   Parent: $parentUri');
      debugPrint('   Is nested: ${parentComment != null}');
    }

    try {
      final response = await _commentService.createComment(
        rootUri: rootUri,
        rootCid: rootCid,
        parentUri: parentUri,
        parentCid: parentCid,
        content: trimmedContent,
        contentFacets: contentFacets,
      );

      if (kDebugMode) {
        debugPrint('✅ Comment created: ${response.uri}');
      }

      // Surface the new comment. The AppView indexes new comments
      // asynchronously (firehose lag ~1-2s), so the first fetch can race
      // indexing and miss the comment we just created — retry briefly with
      // backoff until it shows up. Bounded so a comment that legitimately
      // falls outside the first page (deep pagination) can't loop forever.
      if (parentComment == null ||
          _treeContainsUri(_comments, parentComment.comment.uri)) {
        // Parent is visible in the top-level tree (or this is a top-level
        // reply): a refresh can surface the new comment. Retries use the
        // quiet path so the full list doesn't flicker into a loading state
        // on every attempt.
        await refreshComments();
        var attempt = 0;
        while (!_isDisposed &&
            attempt < _indexingRetryDelays.length &&
            !_treeContainsUri(_comments, response.uri)) {
          await Future<void>.delayed(_indexingRetryDelays[attempt]);
          attempt++;
          if (_isDisposed) {
            break;
          }
          await loadComments(refresh: true, quiet: true);
        }

        // Deep replies can still sit past the per-parent sibling cap or the
        // depth cutoff of the top-level refresh. Pull the parent's subtree
        // so the new reply is merged into the tree at its correct position.
        if (parentComment != null &&
            !_isDisposed &&
            !_treeContainsUri(_comments, response.uri)) {
          try {
            await loadMoreReplies(parentComment.comment.uri);
          } on Exception catch (e) {
            // The comment was created successfully; failing to hydrate the
            // subtree is not fatal — the reply is reachable via load-more.
            if (kDebugMode) {
              debugPrint('⚠️ Failed to hydrate reply subtree: $e');
            }
          }
        }
      } else {
        // The parent is NOT in the top-level tree (below the depth cap):
        // full refreshes can never surface the new reply, so retry the
        // parent's subtree fetch instead, verifying against the RETURNED
        // subtree (the merge into the top-level tree is a no-op here).
        var subtree = await _tryLoadReplySubtree(parentUri);
        var attempt = 0;
        while (!_isDisposed &&
            attempt < _indexingRetryDelays.length &&
            (subtree == null || subtree.findByUri(response.uri) == null)) {
          await Future<void>.delayed(_indexingRetryDelays[attempt]);
          attempt++;
          if (_isDisposed) {
            break;
          }
          subtree = await _tryLoadReplySubtree(parentUri);
        }
      }
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to create comment: $e');
      }
      rethrow;
    }
  }

  /// Whether [nodes] (or any of their nested replies) contain a comment
  /// with the given [uri].
  bool _treeContainsUri(List<ThreadViewComment> nodes, String uri) =>
      nodes.any((node) => node.findByUri(uri) != null);

  /// Fetches the subtree rooted at [parentUri], swallowing fetch errors.
  ///
  /// Used by the post-create verification loop: the comment was already
  /// created successfully, so a failed hydration attempt is not fatal.
  Future<ThreadViewComment?> _tryLoadReplySubtree(String parentUri) async {
    try {
      return await loadMoreReplies(parentUri);
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Failed to hydrate reply subtree: $e');
      }
      return null;
    }
  }

  /// Delete a comment
  ///
  /// Deletes a comment and refreshes the comment list.
  /// Only the comment author can delete their comments.
  ///
  /// Parameters:
  /// - [commentUri]: AT-URI of the comment to delete
  ///
  /// Throws:
  /// - ApiException if CommentService is not available
  /// - AuthenticationException if not authenticated
  /// - ApiException for API errors
  Future<void> deleteComment({required String commentUri}) async {
    if (_commentService == null) {
      throw ApiException('CommentService not available');
    }

    if (kDebugMode) {
      debugPrint('🗑️ Deleting comment: $commentUri');
    }

    try {
      await _commentService.deleteComment(uri: commentUri);

      if (kDebugMode) {
        debugPrint('✅ Comment deleted, refreshing comments');
      }

      // Refresh comments to reflect deletion
      await refreshComments();
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to delete comment: $e');
      }
      rethrow;
    }
  }

  /// Initialize vote state for a comment and its replies recursively
  ///
  /// Extracts viewer vote data from comment and initializes VoteProvider state.
  /// Handles nested replies recursively.
  ///
  /// IMPORTANT: Always calls setInitialVoteState, even when viewer.vote is
  /// null. This ensures that if a user removed their vote on another device,
  /// the local state is cleared on refresh.
  void _initializeCommentVoteState(ThreadViewComment threadComment) {
    final viewer = threadComment.comment.viewer;
    _voteProvider!.setInitialVoteState(
      postUri: threadComment.comment.uri,
      voteDirection: viewer?.vote,
      voteUri: viewer?.voteUri,
    );

    // Recursively initialize vote state for replies
    threadComment.replies?.forEach(_initializeCommentVoteState);
  }

  /// Retry loading after error
  Future<void> retry() async {
    _error = null;
    await loadComments(refresh: true);
  }

  /// Clear error
  void clearError() {
    _error = null;
    _safeNotifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    // Stop time updates and cancel timer (also sets value to null)
    stopTimeUpdates();
    // Dispose API service
    _apiService.dispose();
    // Dispose the ValueNotifier last
    _currentTimeNotifier.dispose();
    super.dispose();
  }
}
