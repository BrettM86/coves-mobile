import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../services/api_exceptions.dart';
import '../services/coves_api_service.dart';
import 'auth_provider.dart';

/// Block Provider
///
/// Manages block state for users and communities with optimistic UI updates.
/// Tracks local block state keyed by DID for instant feedback.
/// Automatically clears state when user signs out.
class BlockProvider with ChangeNotifier {
  BlockProvider({
    required CovesApiService apiService,
    required AuthProvider authProvider,
  }) : _apiService = apiService,
       _authProvider = authProvider {
    _authProvider.addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    _authProvider.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (!_authProvider.isAuthenticated) {
      if (_userBlocks.isNotEmpty || _communityBlocks.isNotEmpty) {
        clear();
        if (kDebugMode) {
          debugPrint('🧹 Cleared block state on sign-out');
        }
      }
    }
  }

  final AuthProvider _authProvider;
  final CovesApiService _apiService;

  // Map of DID -> blocked state
  final Map<String, bool> _userBlocks = {};
  final Map<String, bool> _communityBlocks = {};

  // Map of DID -> in-flight request flag
  final Map<String, bool> _pendingUserBlocks = {};
  final Map<String, bool> _pendingCommunityBlocks = {};

  /// Check if a user is blocked
  bool isUserBlocked(String userDid) => _userBlocks[userDid] ?? false;

  /// Check if a community is blocked
  bool isCommunityBlocked(String communityDid) =>
      _communityBlocks[communityDid] ?? false;

  /// Check if a user block request is pending
  bool isUserBlockPending(String userDid) =>
      _pendingUserBlocks[userDid] ?? false;

  /// Check if a community block request is pending
  bool isCommunityBlockPending(String communityDid) =>
      _pendingCommunityBlocks[communityDid] ?? false;

  /// Toggle user block (block/unblock)
  ///
  /// Returns true if now blocked, false if now unblocked.
  /// Throws ApiException if the request fails.
  Future<bool> toggleUserBlock({required String userDid}) => _toggleBlock(
        did: userDid,
        blocks: _userBlocks,
        pending: _pendingUserBlocks,
        blockFn: () => _apiService.blockUser(actor: userDid),
        unblockFn: () => _apiService.unblockUser(actor: userDid),
      );

  /// Toggle community block (block/unblock)
  ///
  /// Returns true if now blocked, false if now unblocked.
  /// Throws ApiException if the request fails.
  Future<bool> toggleCommunityBlock({required String communityDid}) =>
      _toggleBlock(
        did: communityDid,
        blocks: _communityBlocks,
        pending: _pendingCommunityBlocks,
        blockFn: () => _apiService.blockCommunity(community: communityDid),
        unblockFn: () =>
            _apiService.unblockCommunity(community: communityDid),
      );

  /// Generic toggle block with optimistic updates and rollback.
  Future<bool> _toggleBlock({
    required String did,
    required Map<String, bool> blocks,
    required Map<String, bool> pending,
    required Future<void> Function() blockFn,
    required Future<void> Function() unblockFn,
  }) async {
    if (did.isEmpty || !did.startsWith('did:')) {
      throw ApiException('Invalid DID');
    }

    if (pending[did] ?? false) {
      if (kDebugMode) {
        debugPrint('⚠️ Block request already in progress for $did');
      }
      return blocks[did] ?? false;
    }

    final wasBlocked = blocks[did] ?? false;
    final willBlock = !wasBlocked;

    // Optimistic update + mark as pending before notify
    blocks[did] = willBlock;
    pending[did] = true;
    notifyListeners();

    try {
      if (willBlock) {
        await blockFn();
      } else {
        await unblockFn();
      }
      return willBlock;
    } on ApiException {
      blocks[did] = wasBlocked;
      notifyListeners();
      rethrow;
    } catch (e, stackTrace) {
      blocks[did] = wasBlocked;
      notifyListeners();
      await Sentry.captureException(e, stackTrace: stackTrace);
      throw ApiException(
        'Unexpected error: ${e.toString()}',
        statusCode: 500,
      );
    } finally {
      pending.remove(did);
      notifyListeners();
    }
  }

  /// Initialize user block state from profile data
  void setInitialUserBlockState({
    required String userDid,
    required bool isBlocked,
  }) {
    _userBlocks[userDid] = isBlocked;
  }

  /// Initialize community block state from community data
  void setInitialCommunityBlockState({
    required String communityDid,
    required bool isBlocked,
  }) {
    _communityBlocks[communityDid] = isBlocked;
  }

  /// Clear all block state (e.g., on sign out)
  void clear() {
    _userBlocks.clear();
    _communityBlocks.clear();
    _pendingUserBlocks.clear();
    _pendingCommunityBlocks.clear();
    notifyListeners();
  }
}
