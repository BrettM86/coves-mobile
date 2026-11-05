// Shared harness for CreatePostScreen widget tests.

import 'package:coves_flutter/models/community.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/home/create_post_screen.dart';
import 'package:coves_flutter/services/comments_provider_cache.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/utils/image_preparation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'fake_providers.dart' show postCardProviders;
import 'test_mocks.dart';

/// Signed-in AuthProvider for the composer, with a switchable account.
class FakeAuthProvider extends AuthProvider {
  bool _isAuthenticated = true;
  String? _did = 'did:plc:testuser';
  String? _handle = 'testuser.coves.social';

  @override
  bool get isAuthenticated => _isAuthenticated;

  @override
  String? get did => _did;

  @override
  String? get handle => _handle;

  void setAuthenticated({required bool value, String? did, String? handle}) {
    _isAuthenticated = value;
    _did = did;
    _handle = handle;
    notifyListeners();
  }

  @override
  Future<String?> getAccessToken() async {
    return _isAuthenticated ? 'mock_access_token' : null;
  }

  @override
  Future<bool> refreshToken() async {
    return _isAuthenticated;
  }

  /// What the next [reauthenticate] returns.
  ReauthenticationResult reauthenticateResult = ReauthenticationResult.success;

  /// How many times [reauthenticate] ran.
  int reauthenticateCalls = 0;

  /// Returns [reauthenticateResult]; a success replaces the session for the
  /// same account, so listeners are notified with the DID unchanged.
  @override
  Future<ReauthenticationResult> reauthenticate() async {
    reauthenticateCalls++;
    final result = reauthenticateResult;
    if (result == ReauthenticationResult.success) {
      notifyListeners();
    }
    return result;
  }

  @override
  Future<void> signOut() async {
    _isAuthenticated = false;
    _did = null;
    _handle = null;
    notifyListeners();
  }
}

/// Stubs the community picker's list with the single community "Test Cove"
/// (did:plc:community).
void stubTestCove(MockCovesApiService api) {
  when(
    api.listCommunities(
      limit: anyNamed('limit'),
      cursor: anyNamed('cursor'),
      sort: anyNamed('sort'),
      subscribed: anyNamed('subscribed'),
    ),
  ).thenAnswer(
    (_) async => CommunitiesResponse(
      communities: [
        CommunityView(
          did: 'did:plc:community',
          name: 'testcove',
          displayName: 'Test Cove',
        ),
      ],
    ),
  );
}

/// Opens the community picker and selects the single stubbed community,
/// which is the only way to make the form (and the Post button) valid.
Future<void> selectCommunity(WidgetTester tester) async {
  await tester.tap(find.text('Select a community'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Test Cove'));
  await tester.pumpAndSettle();
}

/// Pumps CreatePostScreen with the providers PostDetailScreen resolves,
/// with the mocked API last so CreatePostScreen submits through it
Future<void> pumpWithPostDetailProviders(
  WidgetTester tester, {
  required AuthProvider auth,
  required CovesApiService api,
  ThemeData? theme,
  ValueChanged<bool>? onDirtyChanged,
  ImagePreparer? imagePreparer,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ...postCardProviders(auth: auth),
        Provider<CovesApiService>.value(value: api),
        Provider<CommentsProviderCache>(
          create: (context) => CommentsProviderCache(
            authProvider: auth,
            voteProvider: context.read<VoteProvider>(),
            commentService: MockCommentService(),
            apiService: api,
          ),
          dispose: (_, cache) => cache.dispose(),
        ),
      ],
      child: MaterialApp(
        theme: theme,
        home: CreatePostScreen(
          onDirtyChanged: onDirtyChanged,
          imagePreparer: imagePreparer,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
