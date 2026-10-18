import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../providers/auth_provider.dart';
import '../providers/comments_provider.dart';
import '../providers/vote_provider.dart';
import 'comment_service.dart';
import 'coves_api_service.dart';
import 'viewer_state_hydrator.dart';

/// Comments Provider Cache
///
/// Manages cached CommentsProvider instances per post URI using LRU eviction.
/// Inspired by Thunder app's architecture for instant back navigation.
///
/// Key features:
/// - One CommentsProvider per post URI
/// - LRU eviction (default: 15 most recent posts)
/// - Cleanup on sign-in, sign-out and account switch via AuthProvider
///   listener
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
    required this._authProvider,
    required this._voteProvider,
    required this._commentService,
    required this._apiService,
    this._hydrator,
    this.maxSize = 15,
    this._sessionKeyOf,
  }) {
    _signedInDid = _authProvider.did;
    _authProvider.addListener(_syncSignedInDid);
  }

  final AuthProvider _authProvider;
  final VoteProvider _voteProvider;
  final CommentService _commentService;
  final CovesApiService _apiService;

  /// Threaded into every [CommentsProvider] this cache builds — these
  /// providers are created here rather than by the DI list, so this is the
  /// only place the app-wide hydrator can reach them. Null lets each
  /// provider fall back to one built from [_voteProvider].
  final ViewerStateHydrator? _hydrator;

  /// The current viewer session's key, forwarded to every
  /// [CommentsProvider] this cache builds so each can stamp its thread with
  /// the session it was loaded under.
  final Object? Function()? _sessionKeyOf;

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

  /// DID of the signed-in account the cached threads were loaded for, or
  /// null while signed out. A change means the viewer changed.
  String? _signedInDid;

  /// Acquire (get or create) a CommentsProvider for a post.
  ///
  /// This "pins" the provider to avoid LRU eviction while in use.
  /// Call [releaseProvider] when the consumer unmounts.
  ///
  /// If provider exists in cache, moves it to end (LRU touch).
  /// If cache is full, evicts the oldest *unreferenced* provider before
  /// creating a new one. If all providers are currently referenced, the cache
  /// may temporarily exceed [maxSize] to avoid disposing active providers.
  ///
  /// Never returns a provider cached for a previous signed-in DID, even when
  /// called from an auth listener that runs before this cache's own.
  CommentsProvider acquireProvider({
    required String postUri,
    required String postCid,
  }) {
    _syncSignedInDid();
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
      apiService: _apiService,
      voteProvider: _voteProvider,
      commentService: _commentService,
      postUri: postUri,
      postCid: postCid,
      hydrator: _hydrator,
      sessionKeyOf: _sessionKeyOf,
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

  /// Handle auth state changes - clear all when the signed-in DID changes
  /// (sign-in, sign-out or account switch), including pinned providers.
  ///
  /// Cached threads carry the viewer state of the session that loaded them:
  /// a thread cached while signed out has no votes, and one cached while
  /// signed in holds that account's. Either way the post must be fetched
  /// again with the new session. Notifications that keep the same DID, such
  /// as a token refresh, keep the cache.
  ///
  /// Runs as this cache's auth listener and from [acquireProvider]; it
  /// records the DID it cleared for, so the second run for one change keeps
  /// the cache.
  void _syncSignedInDid() {
    final signedInDid = _authProvider.did;

    if (_signedInDid != signedInDid) {
      if (kDebugMode) {
        debugPrint(
          '🔒 Signed-in account changed - clearing '
          '${_cache.length} cached comment providers',
        );
      }
      clearAll();
    }

    _signedInDid = signedInDid;
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
    _authProvider.removeListener(_syncSignedInDid);
    clearAll();
  }
}
