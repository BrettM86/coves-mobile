import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/bluesky_profile_import.dart';
import '../services/api_exceptions.dart';
import '../services/coves_api_service.dart';
import '../services/own_profile_refresher.dart';
import '../services/profile_cache.dart';
import 'auth_provider.dart';

/// Checks once per signed-in session whether to offer a Bluesky profile
/// import, and holds the offer until it is shown.
class BlueskyProfileImportOfferProvider with ChangeNotifier {
  BlueskyProfileImportOfferProvider({
    required this._apiService,
    required this._authProvider,
    required this._sessionKeyOf,
    required this._profileCache,
  }) {
    _sessionKey = _sessionKeyOf();
    _authProvider.addListener(_onAuthChanged);
    if (_sessionKey != null) {
      unawaited(_fetchOffer());
    }
  }

  final CovesApiService _apiService;
  final AuthProvider _authProvider;
  final Object? Function() _sessionKeyOf;
  final ProfileCache _profileCache;
  Object? _sessionKey;
  int _fetchGeneration = 0;
  bool _isDisposed = false;
  List<BlueskyImportChoice>? _pendingChoices;

  /// The automatic offer waiting to be shown, or null.
  List<BlueskyImportChoice>? get pendingChoices => _pendingChoices;

  /// Clears the offer and tells the server it was declined. Errors are
  /// ignored.
  Future<void> decline() async {
    _setPendingChoices(null);
    try {
      await _apiService.dismissBlueskyProfileImport();
    } on ApiException {
      // Declining stays local; the offer may come back next session.
    }
  }

  /// Imports [fields], clears the offer, then refreshes the own profile.
  /// Import errors propagate; refresh errors are ignored.
  Future<List<BlueskyProfileField>> importFields(
    List<BlueskyProfileField> fields,
  ) async {
    final sessionKey = _sessionKey;
    final imported = await _apiService.importBlueskyProfile(fields);
    if (sessionKey != _sessionKey) {
      return imported;
    }
    _setPendingChoices(null);
    final did = _authProvider.did;
    if (did != null) {
      try {
        await refreshOwnProfile(
          apiService: _apiService,
          cache: _profileCache,
          did: did,
        );
      } on ApiException {
        // The import landed; profile screens catch up on their next load.
      }
    }
    return imported;
  }

  /// Clears the offer without dismissing it, so it is shown only once.
  void markShown() => _setPendingChoices(null);

  void _onAuthChanged() {
    final sessionKey = _sessionKeyOf();
    if (sessionKey == _sessionKey) {
      return;
    }
    _sessionKey = sessionKey;
    _fetchGeneration++;
    _setPendingChoices(null);
    if (sessionKey != null) {
      unawaited(_fetchOffer());
    }
  }

  Future<void> _fetchOffer() async {
    final generation = ++_fetchGeneration;
    try {
      final profileImport = await _apiService.getBlueskyProfileImport();
      if (_isDisposed || generation != _fetchGeneration) {
        return;
      }
      _setPendingChoices(automaticImportChoices(profileImport));
    } on ApiException {
      // The automatic check is silent on errors.
    }
  }

  void _setPendingChoices(List<BlueskyImportChoice>? choices) {
    if (_isDisposed || identical(_pendingChoices, choices)) {
      return;
    }
    _pendingChoices = choices;
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
