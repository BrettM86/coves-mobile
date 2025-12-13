import 'dart:collection';

import 'package:flutter/foundation.dart';
import '../providers/auth_provider.dart';
import '../providers/comments_provider.dart';
import '../providers/vote_provider.dart';
import 'comment_service.dart';

/// Comments Provider Cache
///
/// Manages cached CommentsProvider instances per post URI using LRU eviction.
/// Inspired by Thunder app's architecture for instant back navigation.
///
/// Key features:
/// - One CommentsProvider per post URI
/// - LRU eviction (default: 15 most recent posts)
/// - Sign-out cleanup via AuthProvider listener
///
/// Usage:
/// ```dart
/// final cache = context.read<CommentsProviderCache>();
/// final provider = cache.getProvider(
///   postUri: post.uri,
///   postCid: post.cid,
/// );
/// ```
class CommentsProviderCache {
  CommentsProviderCache({
    required AuthProvider authProvider,
    required VoteProvider voteProvider,
    required CommentService commentService,
    this.maxSize = 15,
  }) : _authProvider = authProvider,
       _voteProvider = voteProvider,
       _commentService = commentService {
    _wasAuthenticated = _authProvider.isAuthenticated;
    _authProvider.addListener(_onAuthChanged);
  }

  final AuthProvider _authProvider;
  final VoteProvider _voteProvider;
  final CommentService _commentService;

  /// Maximum number of providers to cache
  final int maxSize;

  /// LRU cache - LinkedHashMap maintains insertion order
  /// Most recently accessed items are at the end
  final LinkedHashMap<String, CommentsProvider> _cache = LinkedHashMap();

  /// Reference counts for "in-use" providers.
  ///
  /// Screens that hold onto a provider instance should call [acquireProvider]
  /// and later [releaseProvider] to prevent LRU eviction from disposing a
  /// provider that is still mounted in the navigation stack.
  final Map<String, int> _refCounts = {};

  /// Track auth state for sign-out detection
  bool _wasAuthenticated = false;

  /// Acquire (get or create) a CommentsProvider for a post.
  ///
  /// This "pins" the provider to avoid LRU eviction while in use.
  /// Call [releaseProvider] when the consumer unmounts.
  ///
  /// If provider exists in cache, moves it to end (LRU touch).
  /// If cache is full, evicts the oldest *unreferenced* provider before
  /// creating a new one. If all providers are currently referenced, the cache
  /// may temporarily exceed [maxSize] to avoid disposing active providers.
  CommentsProvider acquireProvider({
    required String postUri,
    required String postCid,
  }) {
    final provider = _getOrCreateProvider(postUri: postUri, postCid: postCid);
    _refCounts[postUri] = (_refCounts[postUri] ?? 0) + 1;
    return provider;
  }

  /// Release a previously acquired provider for a post.
  ///
  /// Once released, the provider becomes eligible for LRU eviction.
  void releaseProvider(String postUri) {
    final current = _refCounts[postUri];
    if (current == null) {
      return;
    }

    if (current <= 1) {
      _refCounts.remove(postUri);
    } else {
      _refCounts[postUri] = current - 1;
    }

    _evictIfNeeded();
  }

  /// Legacy name kept for compatibility: prefer [acquireProvider].
  CommentsProvider getProvider({
    required String postUri,
    required String postCid,
  }) => acquireProvider(postUri: postUri, postCid: postCid);

  CommentsProvider _getOrCreateProvider({
    required String postUri,
    required String postCid,
  }) {
    // Check if already cached
    if (_cache.containsKey(postUri)) {
      // Move to end (most recently used)
      final provider = _cache.remove(postUri)!;
      _cache[postUri] = provider;

      if (kDebugMode) {
        debugPrint('📦 Cache hit: $postUri (${_cache.length}/$maxSize)');
      }

      return provider;
    }

    // Evict unreferenced providers if at capacity.
    if (_cache.length >= maxSize) {
      _evictIfNeeded(includingOne: true);
    }

    // Create new provider
    final provider = CommentsProvider(
      _authProvider,
      voteProvider: _voteProvider,
      commentService: _commentService,
      postUri: postUri,
      postCid: postCid,
    );

    _cache[postUri] = provider;

    if (kDebugMode) {
      debugPrint('📦 Cache miss: $postUri (${_cache.length}/$maxSize)');
      if (_cache.length > maxSize) {
        debugPrint(
          '📌 Cache exceeded maxSize because active providers are pinned',
        );
      }
    }

    return provider;
  }

  void _evictIfNeeded({bool includingOne = false}) {
    final targetSize = includingOne ? maxSize - 1 : maxSize;
    while (_cache.length > targetSize) {
      String? oldestUnreferencedKey;
      for (final key in _cache.keys) {
        if ((_refCounts[key] ?? 0) == 0) {
          oldestUnreferencedKey = key;
          break;
        }
      }

      if (oldestUnreferencedKey == null) {
        break;
      }

      final evicted = _cache.remove(oldestUnreferencedKey);
      evicted?.dispose();

      if (kDebugMode) {
        debugPrint('🗑️ Cache evict: $oldestUnreferencedKey');
      }
    }
  }

  /// Check if provider exists without creating
  bool hasProvider(String postUri) => _cache.containsKey(postUri);

  /// Get existing provider without creating (for checking state)
  CommentsProvider? peekProvider(String postUri) => _cache[postUri];

  /// Remove specific provider (e.g., after post deletion)
  void removeProvider(String postUri) {
    final provider = _cache.remove(postUri);
    _refCounts.remove(postUri);
    provider?.dispose();
  }

  /// Handle auth state changes - clear all on sign-out
  void _onAuthChanged() {
    final isAuthenticated = _authProvider.isAuthenticated;

    // Clear all cached providers on sign-out
    if (_wasAuthenticated && !isAuthenticated) {
      if (kDebugMode) {
        debugPrint('🔒 User signed out - clearing ${_cache.length} cached comment providers');
      }
      clearAll();
    }

    _wasAuthenticated = isAuthenticated;
  }

  /// Clear all cached providers
  void clearAll() {
    for (final provider in _cache.values) {
      provider.dispose();
    }
    _cache.clear();
    _refCounts.clear();
  }

  /// Current cache size
  int get size => _cache.length;

  /// Dispose and cleanup
  void dispose() {
    _authProvider.removeListener(_onAuthChanged);
    clearAll();
  }
}
