import 'package:coves_flutter/models/coves_session.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:flutter/foundation.dart';

/// Mock CommentsProvider for testing
class MockCommentsProvider extends ChangeNotifier {
  final String postUri;
  final String postCid;

  MockCommentsProvider({
    required this.postUri,
    required this.postCid,
  });

  final ValueNotifier<DateTime?> currentTimeNotifier = ValueNotifier(null);

  @override
  void dispose() {
    currentTimeNotifier.dispose();
    super.dispose();
  }
}

/// Mock AuthProvider for testing
class MockAuthProvider extends ChangeNotifier {
  bool _isAuthenticated = false;
  bool _isLoading = false;
  String? _error;
  String? _did;
  String? _handle;
  CovesSession? _session;

  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get did => _did;
  String? get handle => _handle;
  CovesSession? get session => _session;

  void setAuthenticated({required bool value, String? did}) {
    _isAuthenticated = value;
    _did = did ?? 'did:plc:testuser';
    notifyListeners();
  }

  Future<void> signIn(String handle) async {
    _isAuthenticated = true;
    _handle = handle;
    _did = 'did:plc:testuser';
    notifyListeners();
  }

  Future<void> signOut() async {
    _isAuthenticated = false;
    _did = null;
    _handle = null;
    _session = null;
    notifyListeners();
  }

  Future<void> initialize() async {
    _isLoading = false;
  }

  Future<String?> getAccessToken() async {
    return _isAuthenticated ? 'mock_access_token' : null;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}

/// Mock VoteProvider for testing
class MockVoteProvider extends ChangeNotifier {
  final Map<String, VoteState> _votes = {};
  final Map<String, int> _scoreAdjustments = {};
  final Map<String, bool> _pendingRequests = {};

  bool isLiked(String postUri) {
    return _votes[postUri]?.direction == 'up' &&
        !(_votes[postUri]?.deleted ?? false);
  }

  int getAdjustedScore(String postUri, int originalScore) {
    final adjustment = _scoreAdjustments[postUri] ?? 0;
    return originalScore + adjustment;
  }

  VoteState? getVoteState(String postUri) => _votes[postUri];

  bool isPending(String postUri) => _pendingRequests[postUri] ?? false;

  Future<bool> toggleVote({
    required String postUri,
    required String postCid,
    String direction = 'up',
  }) async {
    final currentlyLiked = isLiked(postUri);

    if (currentlyLiked) {
      // Removing vote
      _votes[postUri] = VoteState(direction: direction, deleted: true);
      _scoreAdjustments[postUri] = (_scoreAdjustments[postUri] ?? 0) - 1;
    } else {
      // Adding vote
      _votes[postUri] = VoteState(direction: direction, deleted: false);
      _scoreAdjustments[postUri] = (_scoreAdjustments[postUri] ?? 0) + 1;
    }

    notifyListeners();
    return !currentlyLiked;
  }

  void setVoteState({required String postUri, required bool liked}) {
    if (liked) {
      _votes[postUri] = const VoteState(direction: 'up', deleted: false);
    } else {
      _votes.remove(postUri);
    }
    notifyListeners();
  }

  void setInitialVoteState({
    required String postUri,
    String? voteDirection,
    String? voteUri,
  }) {
    if (voteDirection != null) {
      String? rkey;
      if (voteUri != null) {
        final parts = voteUri.split('/');
        if (parts.isNotEmpty) {
          rkey = parts.last;
        }
      }

      _votes[postUri] = VoteState(
        direction: voteDirection,
        uri: voteUri,
        rkey: rkey,
        deleted: false,
      );

      _scoreAdjustments.remove(postUri);
    } else {
      _votes.remove(postUri);
    }
  }

  void clear() {
    _votes.clear();
    _pendingRequests.clear();
    _scoreAdjustments.clear();
    notifyListeners();
  }
}
