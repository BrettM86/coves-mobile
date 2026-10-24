import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/community_subscription_provider.dart';
import 'package:coves_flutter/providers/multi_feed_provider.dart';
import 'package:coves_flutter/providers/notification_preferences_change_signal.dart';
import 'package:coves_flutter/providers/notification_preferences_provider.dart';
import 'package:coves_flutter/providers/notifications_list_provider.dart';
import 'package:coves_flutter/providers/unread_notification_count_provider.dart';
import 'package:coves_flutter/providers/viewer_authority_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/services/comment_service.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/post_change_broadcast.dart';
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
          sessionKeyOf: () => null,
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

/// A real [CovesApiService] with no token, for providers that require one.
///
/// Under `testWidgets` the binding's HttpOverrides answers every request
/// with a synthetic 400; under plain `test()` requests go to the closed
/// loopback port of `EnvironmentConfig.test`. Either way a missed mock never
/// reaches production, but only an assertion on the resulting error state
/// fails the test, so tests that exercise a fetch must inject a mocked
/// service.
CovesApiService tokenlessApiService() =>
    CovesApiService(sessionKeyOf: () => null, tokenGetter: () async => null);

/// The full provider set a `PostCard` needs to build.
///
/// The API services supplied are [tokenlessApiService]s. Pass a
/// `streamableService` to inject a Dio-mocked one; otherwise a real
/// [StreamableService] is supplied. It uses `EnvironmentConfig.current`,
/// which on host tests is the closed loopback, so a triggered call fails
/// instead of reaching Streamable.
List<SingleChildWidget> postCardProviders({
  required AuthProvider auth,
  StreamableService? streamableService,
  PostChangeBroadcast? postChangeBroadcast,
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
    // PostCardActions publishes a confirmed delete on the app-wide broadcast.
    Provider<PostChangeBroadcast>.value(
      value: postChangeBroadcast ?? PostChangeBroadcast(),
    ),
  ];
}

/// A `sessionKeyOf` for a provider whose test never changes the session:
/// every page is requested and accepted under this one key.
Object? unchangingSessionKey() => 'unchanging-test-session';

/// The app-wide [ViewerAuthorityProvider] registration a community or
/// profile screen reads, mirroring main.dart.
///
/// Real: for a signed-in [auth] it asks [apiService] for the viewer's
/// authority as soon as it is first read, so a mocked service must stub
/// `getViewerAuthority`.
SingleChildWidget viewerAuthorityRegistration({
  required AuthProvider auth,
  required CovesApiService apiService,
}) {
  return ChangeNotifierProvider<ViewerAuthorityProvider>(
    create: (_) =>
        ViewerAuthorityProvider(apiService: apiService, authProvider: auth),
  );
}

/// The app-wide unread count provider, owned and disposed by the widget tree.
SingleChildWidget unreadNotificationCountRegistration({
  required AuthProvider auth,
  required CovesApiService apiService,
}) {
  return ChangeNotifierProvider<UnreadNotificationCountProvider>(
    create: (_) => UnreadNotificationCountProvider(
      apiService: apiService,
      authProvider: auth,
    ),
  );
}

/// The app-wide notifications list, owned and disposed by the widget tree.
///
/// Stamps pages with the session key of the [ViewerAuthorityProvider]
/// registered above it, as main.dart does.
SingleChildWidget notificationsListRegistration({
  required AuthProvider auth,
  required CovesApiService apiService,
}) {
  return ChangeNotifierProvider<NotificationsListProvider>(
    create: (context) {
      final authority = context.read<ViewerAuthorityProvider>();
      return NotificationsListProvider(
        apiService: apiService,
        authProvider: auth,
        sessionKeyOf: () => authority.sessionKey,
        unreadNotificationCountProvider: context
            .read<UnreadNotificationCountProvider>(),
      );
    },
  );
}

/// The app-wide notification preferences owner, owned and disposed by the
/// widget tree.
///
/// Stamps requests with the session key of the [ViewerAuthorityProvider]
/// registered above it, and reports to the [UnreadNotificationCountProvider]
/// and [NotificationPreferencesChangeSignal] registered above it, as
/// main.dart does.
SingleChildWidget notificationPreferencesRegistration({
  required AuthProvider auth,
  required CovesApiService apiService,
}) {
  return ChangeNotifierProvider<NotificationPreferencesProvider>(
    create: (context) {
      final authority = context.read<ViewerAuthorityProvider>();
      return NotificationPreferencesProvider(
        apiService: apiService,
        authProvider: auth,
        sessionKeyOf: () => authority.sessionKey,
        unreadNotificationCountProvider: context
            .read<UnreadNotificationCountProvider>(),
        changeSignal: context.read<NotificationPreferencesChangeSignal>(),
      );
    },
  );
}

/// The app-wide [MultiFeedProvider] registration for a test that pumps a
/// community or profile screen, which also removes a post its author deletes
/// from the home feeds, but never shows those feeds.
///
/// Real, and never loaded, so it makes no requests. It subscribes to the
/// [PostChangeBroadcast] and stamps with the [ViewerAuthorityProvider]
/// registered above it, which the caller provides (the same instances the
/// screen under test reads).
SingleChildWidget unloadedMultiFeedProvider({
  required AuthProvider auth,
  required CovesApiService apiService,
}) {
  return ChangeNotifierProvider<MultiFeedProvider>(
    create: (context) {
      final authority = context.read<ViewerAuthorityProvider>();
      return MultiFeedProvider(
        auth,
        apiService: apiService,
        postChangeBroadcast: context.read<PostChangeBroadcast>(),
        sessionKeyOf: () => authority.sessionKey,
      );
    },
  );
}

/// The app-level dependencies a `ProfileScreen` resolves, mirroring the
/// registrations in main.dart.
///
/// Each ProfileScreen builds and owns its own UserProfileProvider from
/// these, so no UserProfileProvider is provided here. The app-wide
/// [MultiFeedProvider] is a real one that nothing loads unless a home
/// `FeedScreen` is also pumped, so it makes no requests on its own.
///
/// The [ViewerAuthorityProvider] is [viewerAuthority] when given (the caller
/// owns and disposes it), otherwise a real one built on [apiService]; see
/// [viewerAuthorityRegistration]. The home feeds stamp their cards with its
/// session key, as main.dart does.
List<SingleChildWidget> profileScreenProviders({
  required AuthProvider auth,
  required CovesApiService apiService,
  required CommentService commentService,
  PostChangeBroadcast? postChangeBroadcast,
  ViewerAuthorityProvider? viewerAuthority,
  NotificationPreferencesChangeSignal? notificationPreferencesChangeSignal,
}) {
  return [
    ChangeNotifierProvider<AuthProvider>.value(value: auth),
    if (notificationPreferencesChangeSignal != null)
      ChangeNotifierProvider<NotificationPreferencesChangeSignal>.value(
        value: notificationPreferencesChangeSignal,
      )
    else
      ChangeNotifierProvider<NotificationPreferencesChangeSignal>(
        create: (_) => NotificationPreferencesChangeSignal(),
      ),
    Provider<CovesApiService>.value(value: apiService),
    if (viewerAuthority != null)
      ChangeNotifierProvider<ViewerAuthorityProvider>.value(
        value: viewerAuthority,
      )
    else
      viewerAuthorityRegistration(auth: auth, apiService: apiService),
    unreadNotificationCountRegistration(auth: auth, apiService: apiService),
    notificationsListRegistration(auth: auth, apiService: apiService),
    notificationPreferencesRegistration(auth: auth, apiService: apiService),
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
    // One app-wide broadcast, shared by the home feeds and every screen.
    Provider<PostChangeBroadcast>.value(
      value: postChangeBroadcast ?? PostChangeBroadcast(),
    ),
    ChangeNotifierProvider<MultiFeedProvider>(
      create: (context) {
        final authority = context.read<ViewerAuthorityProvider>();
        return MultiFeedProvider(
          auth,
          apiService: apiService,
          postChangeBroadcast: context.read<PostChangeBroadcast>(),
          hydrator: context.read<ViewerStateHydrator>(),
          sessionKeyOf: () => authority.sessionKey,
        );
      },
    ),
    Provider<StreamableService>.value(value: StreamableService()),
    Provider<ProfileCache>(
      create: (_) => ProfileCache(auth),
      dispose: (_, cache) => cache.dispose(),
    ),
  ];
}
