import 'package:flutter/foundation.dart';

import '../models/comment.dart';
import '../models/feed_state.dart';
import '../models/post.dart';
import '../models/user_profile.dart';
import '../services/api_exceptions.dart';
import '../services/coves_api_service.dart';
import 'auth_provider.dart';
import 'vote_provider.dart';

/// User Profile Provider
///
/// Manages state for user profile pages including profile data and
/// author posts feed. Supports viewing both own profile and other users.
///
/// IMPORTANT: Accepts AuthProvider reference to fetch fresh access
/// tokens before each authenticated request (critical for atProto OAuth
/// token rotation).
class UserProfileProvider with ChangeNotifier {
  UserProfileProvider(
    AuthProvider authProvider, {
    CovesApiService? apiService,
    VoteProvider? voteProvider,
  }) : _authProvider = authProvider,
       _voteProvider = voteProvider {
    _apiService =
        apiService ??
        CovesApiService(
          tokenGetter: _authProvider.getAccessToken,
          tokenRefresher: _authProvider.refreshToken,
          signOutHandler: _authProvider.signOut,
        );

    // Listen to auth state changes
    _authProvider.addListener(_onAuthChanged);
  }

  AuthProvider _authProvider;
  final VoteProvider? _voteProvider;

  /// Update auth provider reference (called by ChangeNotifierProxyProvider)
  ///
  /// This ensures token refresh and sign-out handlers stay in sync when
  /// auth state changes propagate through the provider tree.
  void updateAuthProvider(AuthProvider newAuth) {
    if (_authProvider != newAuth) {
      _authProvider.removeListener(_onAuthChanged);
      _authProvider = newAuth;
      _authProvider.addListener(_onAuthChanged);
      // Recreate API service with new auth callbacks
      _apiService.dispose();
      _apiService = CovesApiService(
        tokenGetter: _authProvider.getAccessToken,
        tokenRefresher: _authProvider.refreshToken,
        signOutHandler: _authProvider.signOut,
      );
    }
  }

  late CovesApiService _apiService;

  // Profile state
  UserProfile? _profile;
  bool _isLoadingProfile = false;
  String? _profileError;
  String? _currentProfileDid;

  // Posts feed state (reusing FeedState pattern)
  FeedState _postsState = FeedState.initial();

  // Comments feed state
  CommentsState _commentsState = CommentsState.initial();

  // LRU profile cache keyed by DID (max 50 entries)
  static const int _maxCacheSize = 50;
  final Map<String, UserProfile> _profileCache = {};
  final List<String> _cacheAccessOrder = [];

  /// Add profile to cache with LRU eviction
  void _cacheProfile(UserProfile profile) {
    final did = profile.did;

    // Remove from current position in access order
    _cacheAccessOrder.remove(did);

    // Add to end (most recently used)
    _cacheAccessOrder.add(did);
    _profileCache[did] = profile;

    // Evict oldest entries if over capacity
    while (_cacheAccessOrder.length > _maxCacheSize) {
      final oldestDid = _cacheAccessOrder.removeAt(0);
      _profileCache.remove(oldestDid);
    }
  }

  /// Get profile from cache (updates access order)
  UserProfile? _getCachedProfile(String did) {
    final profile = _profileCache[did];
    if (profile != null) {
      // Update access order (move to end)
      _cacheAccessOrder.remove(did);
      _cacheAccessOrder.add(did);
    }
    return profile;
  }

  // Getters
  UserProfile? get profile => _profile;
  bool get isLoadingProfile => _isLoadingProfile;
  String? get profileError => _profileError;
  String? get currentProfileDid => _currentProfileDid;
  FeedState get postsState => _postsState;
  CommentsState get commentsState => _commentsState;

  /// Check if currently viewing own profile
  bool get isOwnProfile {
    if (_currentProfileDid == null) return false;
    return _currentProfileDid == _authProvider.did;
  }

  /// Handle auth state changes
  void _onAuthChanged() {
    // Clear profile cache on sign-out to prevent stale data
    if (!_authProvider.isAuthenticated) {
      if (kDebugMode) {
        debugPrint('🔒 User signed out - clearing profile cache');
      }
      _profileCache.clear();
      _cacheAccessOrder.clear();
      _profile = null;
      _postsState = FeedState.initial();
      _commentsState = CommentsState.initial();
      _currentProfileDid = null;
      notifyListeners();
    }
  }

  /// Load profile for a user
  ///
  /// Parameters:
  /// - [actor]: User's DID or handle (required)
  /// - [forceRefresh]: Bypass cache and fetch fresh data
  Future<void> loadProfile(String actor, {bool forceRefresh = false}) async {
    // Check cache first (updates LRU access order)
    final cachedProfile = _getCachedProfile(actor);
    if (cachedProfile != null && !forceRefresh) {
      _profile = cachedProfile;
      _currentProfileDid = cachedProfile.did;
      _profileError = null;
      notifyListeners();
      return;
    }

    if (_isLoadingProfile) return;

    _isLoadingProfile = true;
    _profileError = null;
    _currentProfileDid = actor.startsWith('did:') ? actor : null;
    notifyListeners();

    try {
      final profile = await _apiService.getProfile(actor: actor);

      // Cache by DID with LRU eviction
      _cacheProfile(profile);

      _profile = profile;
      _currentProfileDid = profile.did;
      _isLoadingProfile = false;
      _profileError = null;

      if (kDebugMode) {
        debugPrint('✅ Profile loaded: ${profile.displayNameOrHandle}');
      }
    } on NotFoundException {
      _isLoadingProfile = false;
      _profileError = 'User not found';
      _profile = null;

      if (kDebugMode) {
        debugPrint('❌ Profile not found: $actor');
      }
    } on AuthenticationException {
      _isLoadingProfile = false;
      _profileError = 'Please sign in to view this profile';

      if (kDebugMode) {
        debugPrint('❌ Auth required to load profile: $actor');
      }
    } on NetworkException catch (e) {
      _isLoadingProfile = false;
      _profileError = 'Network error. Check your connection.';

      if (kDebugMode) {
        debugPrint('❌ Network error loading profile: ${e.message}');
      }
    } on ApiException catch (e) {
      _isLoadingProfile = false;
      _profileError = e.message;

      if (kDebugMode) {
        debugPrint('❌ Failed to load profile: ${e.message}');
      }
    } on FormatException catch (e) {
      _isLoadingProfile = false;
      _profileError = 'Invalid data received from server';

      if (kDebugMode) {
        debugPrint('❌ Format error loading profile: $e');
      }
    } on Exception catch (e) {
      // Catch-all for other exceptions
      _isLoadingProfile = false;
      _profileError = 'Failed to load profile. Please try again.';

      if (kDebugMode) {
        debugPrint('❌ Unexpected error loading profile: $e');
      }
    }

    notifyListeners();
  }

  /// Load posts by the current profile's author
  ///
  /// Parameters:
  /// - [refresh]: Reload from beginning instead of paginating
  Future<void> loadPosts({bool refresh = false}) async {
    if (_currentProfileDid == null) {
      // Set error state instead of silently returning
      _postsState = _postsState.copyWith(
        error: 'No profile loaded',
        isLoading: false,
        isLoadingMore: false,
      );
      notifyListeners();
      return;
    }
    if (_postsState.isLoading || _postsState.isLoadingMore) return;

    final currentState = _postsState;

    try {
      if (refresh) {
        _postsState = currentState.copyWith(isLoading: true, error: null);
      } else {
        if (!currentState.hasMore) return;
        _postsState = currentState.copyWith(isLoadingMore: true);
      }
      notifyListeners();

      final response = await _apiService.getAuthorPosts(
        actor: _currentProfileDid!,
        cursor: refresh ? null : currentState.cursor,
      );

      final List<FeedViewPost> newPosts;
      if (refresh) {
        newPosts = response.feed;
      } else {
        newPosts = [...currentState.posts, ...response.feed];
      }

      _postsState = currentState.copyWith(
        posts: newPosts,
        cursor: response.cursor,
        hasMore: response.cursor != null,
        error: null,
        isLoading: false,
        isLoadingMore: false,
        lastRefreshTime:
            refresh ? DateTime.now() : currentState.lastRefreshTime,
      );

      if (kDebugMode) {
        debugPrint('✅ Author posts loaded: ${newPosts.length} posts total');
      }
    } on AuthenticationException {
      _postsState = currentState.copyWith(
        error: 'Please sign in to view posts',
        isLoading: false,
        isLoadingMore: false,
      );

      if (kDebugMode) {
        debugPrint('❌ Auth required to load posts');
      }
    } on NotFoundException {
      // 404 means the actor doesn't exist (not "no posts")
      // Empty posts are returned as an empty array, not 404
      _postsState = currentState.copyWith(
        error: 'User not found',
        isLoading: false,
        isLoadingMore: false,
      );

      if (kDebugMode) {
        debugPrint('❌ Actor not found when loading posts');
      }
    } on NetworkException catch (e) {
      _postsState = currentState.copyWith(
        error: 'Network error. Check your connection.',
        isLoading: false,
        isLoadingMore: false,
      );

      if (kDebugMode) {
        debugPrint('❌ Network error loading posts: ${e.message}');
      }
    } on ApiException catch (e) {
      _postsState = currentState.copyWith(
        error: e.message,
        isLoading: false,
        isLoadingMore: false,
      );

      if (kDebugMode) {
        debugPrint('❌ Failed to load author posts: ${e.message}');
      }
    } on FormatException catch (e) {
      _postsState = currentState.copyWith(
        error: 'Invalid data received from server',
        isLoading: false,
        isLoadingMore: false,
      );

      if (kDebugMode) {
        debugPrint('❌ Format error loading posts: $e');
      }
    } on Exception catch (e) {
      // Catch-all for other exceptions
      _postsState = currentState.copyWith(
        error: 'Failed to load posts. Please try again.',
        isLoading: false,
        isLoadingMore: false,
      );

      if (kDebugMode) {
        debugPrint('❌ Unexpected error loading posts: $e');
      }
    }

    notifyListeners();
  }

  /// Load more posts (pagination)
  Future<void> loadMorePosts() async {
    await loadPosts(refresh: false);
  }

  /// Load comments by the current profile's author
  ///
  /// Parameters:
  /// - [refresh]: Reload from beginning instead of paginating
  Future<void> loadComments({bool refresh = false}) async {
    if (_currentProfileDid == null) {
      _commentsState = _commentsState.copyWith(
        error: 'No profile loaded',
        isLoading: false,
        isLoadingMore: false,
      );
      notifyListeners();
      return;
    }
    if (_commentsState.isLoading || _commentsState.isLoadingMore) return;

    final currentState = _commentsState;

    try {
      if (refresh) {
        _commentsState = currentState.copyWith(isLoading: true, error: null);
      } else {
        if (!currentState.hasMore) return;
        _commentsState = currentState.copyWith(isLoadingMore: true);
      }
      notifyListeners();

      final response = await _apiService.getActorComments(
        actor: _currentProfileDid!,
        cursor: refresh ? null : currentState.cursor,
      );

      final List<CommentView> newComments;
      if (refresh) {
        newComments = response.comments;
      } else {
        newComments = [...currentState.comments, ...response.comments];
      }

      _commentsState = currentState.copyWith(
        comments: newComments,
        cursor: response.cursor,
        hasMore: response.cursor != null,
        error: null,
        isLoading: false,
        isLoadingMore: false,
      );

      // Initialize vote state from viewer data in comments response.
      // Ensures server scores are authoritative, prevents double-counting.
      if (_authProvider.isAuthenticated && _voteProvider != null) {
        if (refresh) {
          // On refresh, initialize all comments - server data is truth
          _commentsState.comments.forEach(_initializeCommentVoteState);
        } else {
          // On pagination, only initialize newly fetched comments
          response.comments.forEach(_initializeCommentVoteState);
        }
      } else if (_authProvider.isAuthenticated && _voteProvider == null) {
        if (kDebugMode) {
          debugPrint(
            '⚠️ VoteProvider is null - '
            'cannot initialize comment vote states',
          );
        }
      }

      if (kDebugMode) {
        debugPrint(
          '✅ Author comments loaded: ${newComments.length} comments total',
        );
      }
    } on AuthenticationException {
      _commentsState = currentState.copyWith(
        error: 'Please sign in to view comments',
        isLoading: false,
        isLoadingMore: false,
      );

      if (kDebugMode) {
        debugPrint('❌ Auth required to load comments');
      }
    } on NotFoundException {
      // 404 means the actor doesn't exist (not "no comments")
      // Empty comments are returned as an empty array, not 404
      _commentsState = currentState.copyWith(
        error: 'User not found',
        isLoading: false,
        isLoadingMore: false,
      );

      if (kDebugMode) {
        debugPrint('❌ Actor not found when loading comments');
      }
    } on NetworkException catch (e) {
      _commentsState = currentState.copyWith(
        error: 'Network error. Check your connection.',
        isLoading: false,
        isLoadingMore: false,
      );

      if (kDebugMode) {
        debugPrint('❌ Network error loading comments: ${e.message}');
      }
    } on ApiException catch (e) {
      _commentsState = currentState.copyWith(
        error: e.message,
        isLoading: false,
        isLoadingMore: false,
      );

      if (kDebugMode) {
        debugPrint('❌ Failed to load author comments: ${e.message}');
      }
    } on FormatException catch (e) {
      _commentsState = currentState.copyWith(
        error: 'Invalid data received from server',
        isLoading: false,
        isLoadingMore: false,
      );

      if (kDebugMode) {
        debugPrint('❌ Format error loading comments: $e');
      }
    } on Exception catch (e) {
      _commentsState = currentState.copyWith(
        error: 'Failed to load comments. Please try again.',
        isLoading: false,
        isLoadingMore: false,
      );

      if (kDebugMode) {
        debugPrint('❌ Unexpected error loading comments: $e');
      }
    }

    notifyListeners();
  }

  /// Load more comments (pagination)
  Future<void> loadMoreComments() async {
    await loadComments(refresh: false);
  }

  /// Initialize vote state for a comment from viewer data.
  ///
  /// Unlike CommentsProvider._initializeCommentVoteState, this handles
  /// flat CommentView objects (no nested replies) since actor comments
  /// are returned as a flat list.
  ///
  /// If [_voteProvider] is null, this method returns early as a defensive
  /// measure. This also handles the case where the viewer's vote is null
  /// (vote removed on another device) - the vote state is cleared accordingly.
  void _initializeCommentVoteState(CommentView comment) {
    final voteProvider = _voteProvider;
    if (voteProvider == null) return;

    final viewer = comment.viewer;
    voteProvider.setInitialVoteState(
      postUri: comment.uri,
      voteDirection: viewer?.vote,
      voteUri: viewer?.voteUri,
    );
  }

  /// Clear current profile and reset state
  void clearProfile() {
    _profile = null;
    _currentProfileDid = null;
    _postsState = FeedState.initial();
    _commentsState = CommentsState.initial();
    _profileError = null;
    _isLoadingProfile = false;
    notifyListeners();
  }

  /// Set an error message directly (for cases like missing actor)
  void setError(String message) {
    _profileError = message;
    _isLoadingProfile = false;
    notifyListeners();
  }

  /// Retry loading profile after error
  ///
  /// Returns:
  /// - `true` if retry was initiated (profile DID was available)
  /// - `false` if no profile DID is available to retry
  ///
  /// Note: A return of `true` does not mean the profile loaded successfully,
  /// only that the retry attempt was started. Check [profileError] after
  /// the operation completes to determine if it succeeded.
  Future<bool> retryProfile() async {
    if (_currentProfileDid == null) {
      if (kDebugMode) {
        debugPrint('⚠️ retryProfile called but no profile DID available');
      }
      return false;
    }
    await loadProfile(_currentProfileDid!, forceRefresh: true);
    return true;
  }

  /// Retry loading posts after error
  Future<void> retryPosts() async {
    _postsState = _postsState.copyWith(error: null);
    notifyListeners();
    await loadPosts(refresh: true);
  }

  /// Retry loading comments after error
  Future<void> retryComments() async {
    _commentsState = _commentsState.copyWith(error: null);
    notifyListeners();
    await loadComments(refresh: true);
  }

  /// Update the current user's profile
  ///
  /// Only non-null parameters will be sent to the API.
  /// On success, force refreshes the profile from server to get updated URLs.
  ///
  /// Parameters:
  /// - [displayName]: New display name (optional)
  /// - [bio]: New bio text (optional)
  /// - [avatarBytes]: Avatar image bytes (optional)
  /// - [avatarMimeType]: Avatar MIME type (required if avatarBytes provided)
  /// - [bannerBytes]: Banner image bytes (optional)
  /// - [bannerMimeType]: Banner MIME type (required if bannerBytes provided)
  ///
  /// Throws [ApiException] on failure.
  Future<void> updateProfile({
    String? displayName,
    String? bio,
    Uint8List? avatarBytes,
    String? avatarMimeType,
    Uint8List? bannerBytes,
    String? bannerMimeType,
  }) async {
    if (!isOwnProfile || _profile == null) {
      throw ApiException('Can only update own profile');
    }

    if (kDebugMode) {
      debugPrint('📝 Updating profile for: $_currentProfileDid');
    }

    await _apiService.updateProfile(
      displayName: displayName,
      bio: bio,
      avatarBytes: avatarBytes,
      avatarMimeType: avatarMimeType,
      bannerBytes: bannerBytes,
      bannerMimeType: bannerMimeType,
    );

    // Force refresh profile from server to get updated URLs
    await loadProfile(_currentProfileDid!, forceRefresh: true);

    if (kDebugMode) {
      debugPrint('✅ Profile updated and refreshed');
    }
  }

  @override
  void dispose() {
    _authProvider.removeListener(_onAuthChanged);
    _apiService.dispose();
    super.dispose();
  }
}
