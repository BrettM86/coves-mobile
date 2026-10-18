import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/api_exceptions.dart';
import '../services/coves_api_service.dart';
import 'auth_provider.dart';

enum ViewerAuthorityStatus {
  signedOut,
  loading,
  instanceAdmin,
  notAdmin,
  unavailable,
  revoked,
}

class ViewerAuthorityProvider with ChangeNotifier {
  ViewerAuthorityProvider({
    required this._apiService,
    required this._authProvider,
  }) {
    _signedInDid = _currentDid;
    _sessionKey = _newSessionKey(_signedInDid);
    _authProvider.addListener(_onAuthChanged);
    if (_signedInDid != null) {
      _status = ViewerAuthorityStatus.loading;
      unawaited(_fetchAuthority());
    }
  }

  final CovesApiService _apiService;
  final AuthProvider _authProvider;
  String? _signedInDid;
  ViewerAuthorityStatus _status = ViewerAuthorityStatus.signedOut;
  int _fetchGeneration = 0;
  int _sessionGeneration = 0;
  ({String did, int generation})? _sessionKey;

  /// The key for an account change this provider has not handled yet.
  ({String did, int generation})? _upcomingSessionKey;
  bool _isDisposed = false;

  String? get _currentDid =>
      _authProvider.isAuthenticated ? _authProvider.did : null;

  ViewerAuthorityStatus get status => _status;
  bool get isInstanceAdmin => _status == ViewerAuthorityStatus.instanceAdmin;
  bool get isRevoked => _status == ViewerAuthorityStatus.revoked;

  /// Identifies the signed-in session: null when signed out, kept across
  /// token refreshes and authority reloads, and new on every account change
  /// (including the same account signing in again). Opaque: compare keys
  /// only for equality.
  ///
  /// Always describes the current auth state, even when read by another
  /// auth listener that runs before this provider's own.
  Object? get sessionKey {
    final did = _currentDid;
    return did == _signedInDid ? _sessionKey : _keyForUpcomingSession(did);
  }

  ({String did, int generation})? _newSessionKey(String? did) =>
      did == null ? null : (did: did, generation: ++_sessionGeneration);

  ({String did, int generation})? _keyForUpcomingSession(String? did) {
    if (did == null) {
      return null;
    }
    final upcoming = _upcomingSessionKey;
    if (upcoming != null && upcoming.did == did) {
      return upcoming;
    }
    return _upcomingSessionKey = _newSessionKey(did);
  }

  void markRevoked() {
    if (_isDisposed || _signedInDid == null) {
      return;
    }
    _fetchGeneration++;
    _setStatus(ViewerAuthorityStatus.revoked);
  }

  Future<void> refresh() async {
    if (_isDisposed || _signedInDid == null) {
      return;
    }
    if (!isRevoked) {
      _setStatus(ViewerAuthorityStatus.loading);
    }
    await _fetchAuthority();
  }

  void _onAuthChanged() {
    final did = _currentDid;
    if (did == _signedInDid) {
      // Sign-in and sign-out notify once with isLoading set before the
      // session changes; retrying then would send the outgoing token. A token
      // refresh notifies without isLoading, so 401 recovery still retries.
      if (_authProvider.isLoading) {
        return;
      }
      if (did != null && _status == ViewerAuthorityStatus.unavailable) {
        unawaited(refresh());
      }
      return;
    }

    _fetchGeneration++;
    _signedInDid = did;
    _sessionKey = _keyForUpcomingSession(did);
    _upcomingSessionKey = null;
    final status = did == null
        ? ViewerAuthorityStatus.signedOut
        : ViewerAuthorityStatus.loading;
    // The key changed, so listeners hear about it even when the status
    // stays loading across the switch.
    if (_status == status) {
      notifyListeners();
    } else {
      _setStatus(status);
    }
    if (did != null) {
      unawaited(_fetchAuthority());
    }
  }

  Future<void> _fetchAuthority() async {
    final generation = ++_fetchGeneration;
    try {
      final isAdmin = await _apiService.getViewerAuthority();
      if (_isDisposed || generation != _fetchGeneration) {
        return;
      }
      _setStatus(
        isAdmin
            ? ViewerAuthorityStatus.instanceAdmin
            : ViewerAuthorityStatus.notAdmin,
      );
    } on ApiException {
      if (_isDisposed || generation != _fetchGeneration) {
        return;
      }
      if (!isRevoked) {
        _setStatus(ViewerAuthorityStatus.unavailable);
      }
    }
  }

  void _setStatus(ViewerAuthorityStatus status) {
    if (_status == status) {
      return;
    }
    _status = status;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _fetchGeneration++;
    _authProvider.removeListener(_onAuthChanged);
    super.dispose();
  }
}
