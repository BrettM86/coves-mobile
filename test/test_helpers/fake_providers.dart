import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/community_subscription_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/services/comment_service.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/profile_cache.dart';
import 'package:coves_flutter/services/streamable_service.dart';
import 'package:coves_flutter/services/viewer_state_hydrator.dart';
import 'package:coves_flutter/services/vote_service.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

/// Test doubles for the providers a `PostCard` subtree resolves.
///
/// These deliberately extend the real provider classes rather than
/// standing alone: PostCardActions looks its dependencies up by concrete
/// type (including a `Consumer3<CommunitySubscriptionProvider, AuthProvider,
/// BlockProvider>`), so a lookalike ChangeNotifier registered under its own
/// type throws ProviderNotFoundException at build time.

/// AuthProvider that never touches secure storage or the network.
///
/// Signed out by default. Pass `signedInDid` (and optionally
/// `signedInHandle`) to start signed in; [setSignedInDid] changes the DID
/// with real ChangeNotifier behavior, so observers see the change.
class FakeAuthProvider extends AuthProvider {
  FakeAuthProvider({this._signedInDid, this._signedInHandle});

  String? _signedInDid;
  final String? _signedInHandle;

  @override
  bool get isAuthenticated => _signedInDid != null;

  @override
  bool get isLoading => false;

  @override
  String? get did => _signedInDid;

  @override
  String? get handle => _signedInHandle;

  /// Whether anything is currently listening to this provider.
  bool get isObserved => hasListeners;

  /// Changes the signed-in DID (null means signed out) and notifies.
  void setSignedInDid(String? did) {
    _signedInDid = did;
    notifyListeners();
  }

  /// Notifies without changing the signed-in DID, as a token refresh does.
  void notifyWithoutChange() => notifyListeners();
}

/// VoteProvider wired to a VoteService with no session and no DID, so vote
/// calls resolve locally instead of hitting the API.
class FakeVoteProvider extends VoteProvider {
  FakeVoteProvider(AuthProvider authProvider)
    : super(
        voteService: VoteService(
          sessionGetter: () async => null,
          didGetter: () => null,
        ),
        authProvider: authProvider,
      );
}

/// CommunitySubscriptionProvider whose initial load is a no-op, so no
/// pending timers or network calls leak into a test.
class FakeSubscriptionProvider extends CommunitySubscriptionProvider {
  FakeSubscriptionProvider({
    required super.authProvider,
    CovesApiService? apiService,
  }) : super(apiService: apiService ?? tokenlessApiService());

  @override
  Future<void> loadSubscribedCommunities() async {}
}

/// An API service with no token, for providers that require one but whose
/// requests are never expected to resolve in a widget test.
CovesApiService tokenlessApiService() =>
    CovesApiService(tokenGetter: () async => null);

/// The full provider set a `PostCard` needs to build.
///
/// Pass a `streamableService` to inject a Dio-mocked service; otherwise a
/// real one is supplied that is never exercised.
List<SingleChildWidget> postCardProviders({
  required AuthProvider auth,
  StreamableService? streamableService,
}) {
  return [
    // PostCardActions' delete flow and ReportDialog read the shared API
    // client from the tree, mirroring the app-level wiring in main.dart.
    Provider<CovesApiService>(
      create: (_) => tokenlessApiService(),
      dispose: (_, service) => service.dispose(),
    ),
    ChangeNotifierProvider<AuthProvider>.value(value: auth),
    ChangeNotifierProvider<VoteProvider>(create: (_) => FakeVoteProvider(auth)),
    ChangeNotifierProvider<CommunitySubscriptionProvider>(
      create: (_) => FakeSubscriptionProvider(
        authProvider: auth,
        apiService: tokenlessApiService(),
      ),
    ),
    ChangeNotifierProvider<BlockProvider>(
      create: (_) =>
          BlockProvider(apiService: tokenlessApiService(), authProvider: auth),
    ),
    Provider<StreamableService>.value(
      value: streamableService ?? StreamableService(),
    ),
  ];
}

/// The app-level dependencies a `ProfileScreen` resolves, mirroring the
/// registrations in main.dart.
///
/// Each ProfileScreen builds and owns its own UserProfileProvider from
/// these, so no UserProfileProvider is provided here.
List<SingleChildWidget> profileScreenProviders({
  required AuthProvider auth,
  required CovesApiService apiService,
  required CommentService commentService,
}) {
  return [
    ChangeNotifierProvider<AuthProvider>.value(value: auth),
    Provider<CovesApiService>.value(value: apiService),
    Provider<CommentService>.value(value: commentService),
    ChangeNotifierProvider<VoteProvider>(create: (_) => FakeVoteProvider(auth)),
    ChangeNotifierProvider<CommunitySubscriptionProvider>(
      create: (_) =>
          FakeSubscriptionProvider(authProvider: auth, apiService: apiService),
    ),
    ChangeNotifierProvider<BlockProvider>(
      create: (_) => BlockProvider(apiService: apiService, authProvider: auth),
    ),
    Provider<ViewerStateHydrator>(
      create: (context) => ViewerStateHydrator(
        authProvider: auth,
        voteProvider: context.read<VoteProvider>(),
      ),
    ),
    Provider<StreamableService>.value(value: StreamableService()),
    Provider<ProfileCache>(
      create: (_) => ProfileCache(auth),
      dispose: (_, cache) => cache.dispose(),
    ),
  ];
}
