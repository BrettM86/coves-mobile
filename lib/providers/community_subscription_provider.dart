import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../services/api_exceptions.dart';
import '../services/coves_api_service.dart';
import 'auth_provider.dart';

/// Community Subscription Provider
///
/// Manages subscription state for communities with optimistic UI updates.
/// Tracks local subscription state keyed by community DID for instant feedback.
/// Automatically clears state when user signs out.
class CommunitySubscriptionProvider with ChangeNotifier {
  CommunitySubscriptionProvider({
    required AuthProvider authProvider,
  }) : _authProvider = authProvider,
       _apiService = CovesApiService(
         tokenGetter: () async => authProvider.session?.token,
         tokenRefresher: authProvider.refreshToken,
         signOutHandler: authProvider.signOut,
       ) {
    // Listen to auth state changes and clear subscriptions on sign-out
    _authProvider.addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    _authProvider.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (!_authProvider.isAuthenticated) {
      // Clear subscription state when user signs out
      if (_subscriptions.isNotEmpty) {
        clear();
        if (kDebugMode) {
          debugPrint('🧹 Cleared subscription state on sign-out');
        }
      }
    } else if (_subscriptions.isEmpty && !_isLoading) {
      // Load subscriptions when user signs in (prevent duplicate loads)
      loadSubscribedCommunities();
    }
  }

  final AuthProvider _authProvider;
  final CovesApiService _apiService;

  // Map of community DID -> subscribed state
  final Map<String, bool> _subscriptions = {};

  // Map of community DID -> in-flight request flag
  final Map<String, bool> _pendingRequests = {};

  // Loading state for initial subscription load
  bool _isLoading = false;

  // Error state for failed operations
  String? _error;

  /// Check if user is subscribed to a community
  bool isSubscribed(String communityDid) => _subscriptions[communityDid] ?? false;

  /// Check if a request is pending for a community
  bool isPending(String communityDid) => _pendingRequests[communityDid] ?? false;

  /// Check if initial subscription load is in progress
  bool get isLoading => _isLoading;

  /// Get the last error message (null if no error)
  String? get error => _error;

  /// Toggle subscription (subscribe/unsubscribe)
  ///
  /// Uses optimistic updates:
  /// 1. Immediately updates local state
  /// 2. Makes API call
  /// 3. Reverts on error
  ///
  /// Parameters:
  /// - [communityDid]: DID of the community
  ///
  /// Returns:
  /// - true if now subscribed
  /// - false if now unsubscribed
  ///
  /// Throws:
  /// - ApiException if the request fails
  Future<bool> toggleSubscription({required String communityDid}) async {
    // Prevent concurrent requests for the same community
    if (_pendingRequests[communityDid] ?? false) {
      if (kDebugMode) {
        debugPrint('⚠️ Subscription request already in progress for $communityDid');
      }
      return _subscriptions[communityDid] ?? false;
    }

    // Save current state for rollback on error
    final wasSubscribed = _subscriptions[communityDid] ?? false;
    final willSubscribe = !wasSubscribed;

    // Optimistic update
    _subscriptions[communityDid] = willSubscribe;
    notifyListeners();

    // Mark request as pending
    _pendingRequests[communityDid] = true;

    try {
      if (willSubscribe) {
        await _apiService.subscribeToCommunity(community: communityDid);
        if (kDebugMode) {
          debugPrint('✅ Subscribed to community: $communityDid');
        }
      } else {
        await _apiService.unsubscribeFromCommunity(community: communityDid);
        if (kDebugMode) {
          debugPrint('✅ Unsubscribed from community: $communityDid');
        }
      }

      return willSubscribe;
    } on ApiException catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to toggle subscription: ${e.message}');
      }

      // Rollback optimistic update
      _subscriptions[communityDid] = wasSubscribed;
      notifyListeners();

      rethrow;
    } catch (e, stackTrace) {
      // Catch non-ApiException errors (StateError, TypeError, etc.)
      if (kDebugMode) {
        debugPrint('❌ Unexpected error toggling subscription: $e');
      }

      // Rollback optimistic update
      _subscriptions[communityDid] = wasSubscribed;
      notifyListeners();

      // Log to Sentry in production
      await Sentry.captureException(e, stackTrace: stackTrace);

      // Wrap and rethrow as ApiException
      throw ApiException(
        'Unexpected error: ${e.toString()}',
        statusCode: 500,
      );
    } finally {
      _pendingRequests.remove(communityDid);
    }
  }

  /// Initialize subscription state from community data
  ///
  /// Call this when loading communities or posts to populate initial
  /// subscription state from the backend's viewer state.
  ///
  /// Parameters:
  /// - [communityDid]: DID of the community
  /// - [isSubscribed]: Current subscription state from viewer
  void setInitialSubscriptionState({
    required String communityDid,
    required bool isSubscribed,
  }) {
    _subscriptions[communityDid] = isSubscribed;
    // Don't notify listeners - this is just initial state
  }

  /// Load subscribed communities from backend
  ///
  /// Fetches all communities the user is subscribed to and initializes
  /// the subscription state. Called automatically on sign-in.
  Future<void> loadSubscribedCommunities() async {
    if (!_authProvider.isAuthenticated) {
      return;
    }

    // Prevent concurrent loads
    if (_isLoading) {
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      if (kDebugMode) {
        debugPrint('📡 Loading subscribed communities...');
      }

      final response = await _apiService.listCommunities(subscribed: true);

      for (final community in response.communities) {
        _subscriptions[community.did] = true;
      }

      if (kDebugMode) {
        debugPrint(
          '✅ Loaded ${response.communities.length} subscribed communities',
        );
      }
    } on Exception catch (e, stackTrace) {
      // Track error state for callers
      _error = e.toString();

      // Log for debugging in debug mode
      if (kDebugMode) {
        debugPrint('❌ Failed to load subscribed communities: $e');
      }

      // Log to Sentry in production
      await Sentry.captureException(e, stackTrace: stackTrace);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Clear all subscription state (e.g., on sign out)
  void clear() {
    _subscriptions.clear();
    _pendingRequests.clear();
    _error = null;
    _isLoading = false;
    notifyListeners();
  }
}
