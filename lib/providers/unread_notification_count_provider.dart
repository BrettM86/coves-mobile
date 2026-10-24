import 'dart:async';

import 'package:flutter/widgets.dart';

import '../services/api_exceptions.dart';
import '../services/coves_api_service.dart';
import 'auth_provider.dart';

class UnreadNotificationCountProvider
    with ChangeNotifier, WidgetsBindingObserver {
  UnreadNotificationCountProvider({
    required this._apiService,
    required this._authProvider,
  }) {
    _signedInDid = _currentDid;
    _authProvider.addListener(_onAuthChanged);
    WidgetsBinding.instance.addObserver(this);
    if (_signedInDid != null) {
      unawaited(refresh());
      _startPolling();
    }
  }

  final CovesApiService _apiService;
  final AuthProvider _authProvider;
  String? _signedInDid;
  int _count = 0;
  int _fetchGeneration = 0;
  Timer? _pollTimer;
  bool _isDisposed = false;

  String? get _currentDid =>
      _authProvider.isAuthenticated ? _authProvider.did : null;

  bool get _isForeground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  int get count => _count;

  Future<void> refresh() async {
    if (_isDisposed || _signedInDid == null) {
      return;
    }
    final generation = ++_fetchGeneration;
    try {
      final count = await _apiService.getUnreadCount();
      if (_isDisposed || generation != _fetchGeneration || count == _count) {
        return;
      }
      _count = count;
      notifyListeners();
    } on ApiException {
      // Keep the last count when the network or server is unavailable.
    }
  }

  void _onAuthChanged() {
    final did = _currentDid;
    if (did == _signedInDid) {
      return;
    }
    _fetchGeneration++;
    _signedInDid = did;
    _pollTimer?.cancel();
    _pollTimer = null;
    _count = 0;
    notifyListeners();
    if (did != null) {
      unawaited(refresh());
      _startPolling();
    }
  }

  void _startPolling() {
    if (_isDisposed || _signedInDid == null || !_isForeground) {
      return;
    }
    _pollTimer ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(refresh()),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_signedInDid != null) {
        unawaited(refresh());
        _startPolling();
      }
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _fetchGeneration++;
    _pollTimer?.cancel();
    _authProvider.removeListener(_onAuthChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
