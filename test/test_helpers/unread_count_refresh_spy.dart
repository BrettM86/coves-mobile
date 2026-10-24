import 'package:coves_flutter/providers/unread_notification_count_provider.dart';

import 'fake_providers.dart';
import 'test_mocks.dart';

/// No initial fetch or poll: the backing auth provider stays signed out.
class UnreadCountRefreshSpy extends UnreadNotificationCountProvider {
  UnreadCountRefreshSpy() : this._(FakeAuthProvider());

  UnreadCountRefreshSpy._(FakeAuthProvider auth)
    : _auth = auth,
      super(apiService: MockCovesApiService(), authProvider: auth);

  final FakeAuthProvider _auth;

  int refreshCalls = 0;

  @override
  Future<void> refresh() async {
    refreshCalls++;
  }

  @override
  void dispose() {
    super.dispose();
    _auth.dispose();
  }
}
