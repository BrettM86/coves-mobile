import 'dart:async';

import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/community_guidelines_provider.dart';
import 'package:coves_flutter/providers/eula_provider.dart';
import 'package:coves_flutter/providers/multi_feed_provider.dart';
import 'package:coves_flutter/services/post_change_broadcast.dart';

import 'fake_providers.dart';

/// Test doubles for driving a sign-in through the production router
/// (`createRouter` in main.dart).

/// AuthProvider whose sign-in has the real provider's notification shape:
/// it notifies with [isLoading] set while still signed out, waits for the
/// OAuth step the test finishes with [completeOAuth] or [failOAuth], then
/// notifies again with loading cleared.
class GatedSignInAuthProvider extends AuthProvider {
  String? _signedInDid;
  bool _isLoading = false;
  Completer<String>? _pendingOAuth;

  @override
  bool get isAuthenticated => _signedInDid != null;

  @override
  bool get isLoading => _isLoading;

  @override
  String? get did => _signedInDid;

  /// Whether a sign-in is waiting on [completeOAuth] or [failOAuth].
  bool get isAwaitingOAuth =>
      _pendingOAuth != null && !_pendingOAuth!.isCompleted;

  @override
  Future<void> signIn(String handle) async {
    final pendingOAuth = Completer<String>();
    _pendingOAuth = pendingOAuth;
    _isLoading = true;
    notifyListeners();
    try {
      _signedInDid = await pendingOAuth.future;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Finishes the pending OAuth step, signing in as [did].
  void completeOAuth(String did) => _pendingOAuth!.complete(did);

  /// Ends the pending OAuth step with [error], which [signIn] rethrows
  /// while staying signed out, as a cancelled or failed sign-in does.
  void failOAuth(Object error) => _pendingOAuth!.completeError(error);

  /// Changes the signed-in account in place, as an account switch does.
  void switchAccount(String? did) {
    _signedInDid = did;
    notifyListeners();
  }
}

/// EulaProvider with the EULA already accepted, so the router doesn't
/// redirect to /eula.
class AcceptedEulaProvider extends EulaProvider {
  @override
  bool get hasAccepted => true;

  @override
  bool get isLoading => false;
}

/// CommunityGuidelinesProvider with the guidelines already accepted.
class AcceptedGuidelinesProvider extends CommunityGuidelinesProvider {
  @override
  bool get hasAccepted => true;

  @override
  bool get isLoading => false;

  /// Refreshes the router without an auth notification.
  void notifyWithoutChange() => notifyListeners();
}

/// Feed provider that never loads, so /feed renders its empty state.
class IdleFeedProvider extends MultiFeedProvider {
  IdleFeedProvider(super.authProvider, {required super.apiService})
    : super(
        postChangeBroadcast: PostChangeBroadcast(),
        sessionKeyOf: unchangingSessionKey,
      );

  @override
  Future<void> loadFeed(FeedType type, {bool refresh = false}) async {}

  @override
  Future<void> loadMore(FeedType type) async {}

  @override
  Future<void> retry(FeedType type) async {}
}
