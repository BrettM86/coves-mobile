import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'config/oauth_config.dart';
import 'constants/app_colors.dart';
import 'constants/app_theme.dart';
import 'constants/app_typography.dart';
import 'models/community.dart';
import 'models/post.dart';
import 'providers/auth_provider.dart';
import 'providers/block_provider.dart';
import 'providers/community_subscription_provider.dart';
import 'providers/community_guidelines_provider.dart';
import 'providers/eula_provider.dart';
import 'providers/multi_feed_provider.dart';
import 'providers/user_profile_provider.dart';
import 'providers/vote_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/community_guidelines_screen.dart';
import 'screens/eula_screen.dart';
import 'screens/community/community_feed_screen.dart';
import 'screens/home/main_shell_screen.dart';
import 'screens/home/post_detail_loader.dart';
import 'screens/home/post_detail_screen.dart';
import 'screens/home/profile_screen.dart';
import 'screens/landing_screen.dart';
import 'services/comment_service.dart';
import 'services/comments_provider_cache.dart';
import 'services/coves_api_service.dart';
import 'services/streamable_service.dart';
import 'services/viewer_state_hydrator.dart';
import 'services/vote_service.dart';
import 'widgets/loading_error_states.dart';

Future<void> main() async {
  await SentryFlutter.init(
    (options) {
      // TODO: Replace with your actual Sentry DSN from sentry.io
      options.dsn = const String.fromEnvironment(
        'SENTRY_DSN',
        defaultValue: '',
      );
      options.tracesSampleRate = kDebugMode ? 1.0 : 0.2;
      options.environment = kDebugMode ? 'development' : 'production';
      options.sendDefaultPii = false;
      options.attachScreenshot = true;
      options.attachViewHierarchy = true;
    },
    appRunner: () async {
      WidgetsFlutterBinding.ensureInitialized();

      // The design-system fonts are bundled, so their OFL text ships too.
      AppTypography.registerLicenses();

      // Set system UI overlay style (Android navigation bar)
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          systemNavigationBarColor: AppColors.background,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      );

      runApp(await bootstrapCovesApp());
    },
  );
}

/// Initializes providers and services and returns the root app widget.
///
/// Extracted from [main] so integration tests can pump the real app without
/// [SentryFlutter.init], whose FlutterError.onError override the test
/// binding rejects. Mirrors the [createRouter] @visibleForTesting pattern.
@visibleForTesting
Future<Widget> bootstrapCovesApp() async {
  // Initialize auth provider
  final authProvider = AuthProvider();
  try {
    await authProvider.initialize();
  } on Exception catch (error, stackTrace) {
    // Log initialization failure but continue - user can retry login
    await Sentry.captureException(
      error,
      stackTrace: stackTrace,
      withScope: (scope) {
        scope.setTag('phase', 'auth_initialization');
      },
    );
  }

  // Initialize EULA acceptance provider
  // Note: initialize() handles errors internally (fail-closed design)
  final eulaProvider = EulaProvider();
  try {
    await eulaProvider.initialize();
  } on Exception catch (error, stackTrace) {
    await Sentry.captureException(
      error,
      stackTrace: stackTrace,
      withScope: (scope) {
        scope.setTag('phase', 'eula_initialization');
      },
    );
  }

  // Initialize community guidelines acceptance provider
  // Note: initialize() handles errors internally (fail-closed design)
  final communityGuidelinesProvider = CommunityGuidelinesProvider();
  try {
    await communityGuidelinesProvider.initialize();
  } on Exception catch (error, stackTrace) {
    await Sentry.captureException(
      error,
      stackTrace: stackTrace,
      withScope: (scope) {
        scope.setTag('phase', 'community_guidelines_initialization');
      },
    );
  }

  // Single app-wide Coves API client (one Dio stack / connection pool).
  // Constructed once here and injected everywhere — providers via
  // constructor, widgets via Provider<CovesApiService>. Never construct
  // ad-hoc instances elsewhere: they would miss future auth wiring and
  // leak their Dio stack. This instance lives for the whole app and is
  // intentionally never disposed; CovesApiService.dispose() exists for
  // test-local instances only.
  final apiService = CovesApiService(
    tokenGetter: authProvider.getAccessToken,
    tokenRefresher: authProvider.refreshToken,
    signOutHandler: authProvider.signOut,
  );

  // Initialize vote service with auth callbacks
  // Votes go through the Coves backend (which proxies to PDS with DPoP)
  // Includes token refresh and sign-out handlers for automatic 401 recovery
  final voteService = VoteService(
    sessionGetter: () async => authProvider.session,
    didGetter: () => authProvider.did,
    tokenRefresher: authProvider.refreshToken,
    signOutHandler: authProvider.signOut,
  );

  // Initialize comment service with auth callbacks
  // Comments go through the Coves backend (which proxies to PDS with DPoP)
  final commentService = CommentService(
    sessionGetter: () async => authProvider.session,
    tokenRefresher: authProvider.refreshToken,
    signOutHandler: authProvider.signOut,
  );

  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: authProvider),
      ChangeNotifierProvider.value(value: eulaProvider),
      ChangeNotifierProvider.value(value: communityGuidelinesProvider),
      ChangeNotifierProvider(
        create:
            (_) => VoteProvider(
              voteService: voteService,
              authProvider: authProvider,
            ),
      ),
      // Expose the shared API client so screens/widgets can context.read it
      Provider<CovesApiService>.value(value: apiService),
      ChangeNotifierProvider(
        create:
            (_) => CommunitySubscriptionProvider(
              authProvider: authProvider,
              apiService: apiService,
            ),
      ),
      ChangeNotifierProvider(
        create:
            (_) => BlockProvider(
              apiService: apiService,
              authProvider: authProvider,
            ),
      ),
      // One hydrator for every fetch path that seeds viewer state (votes,
      // community subscriptions) from a response.
      //
      // Registered AFTER VoteProvider and CommunitySubscriptionProvider
      // because it reads both, and BEFORE the consumers below that read it
      // in their `create`. Safe to capture the notifiers once: both are
      // plain ChangeNotifierProvider(create:) instances, created once and
      // never replaced, and every consumer proxy returns `previous ?? ...`
      // so the `vote` and `subscription` arguments its `update` receives
      // are discarded. (The `auth` argument is NOT discarded everywhere -
      // UserProfileProvider's update forwards it to updateAuthProvider,
      // which rebinds its hydrator.)
      Provider<ViewerStateHydrator>(
        create:
            (context) => ViewerStateHydrator(
              authProvider: authProvider,
              voteProvider: context.read<VoteProvider>(),
              subscriptionProvider:
                  context.read<CommunitySubscriptionProvider>(),
            ),
      ),
      ChangeNotifierProxyProvider3<
        AuthProvider,
        VoteProvider,
        CommunitySubscriptionProvider,
        MultiFeedProvider
      >(
        create:
            (context) => MultiFeedProvider(
              authProvider,
              apiService: apiService,
              hydrator: context.read<ViewerStateHydrator>(),
            ),
        update: (context, auth, vote, subscription, previous) {
          // Reuse existing provider to maintain state across rebuilds
          return previous ??
              MultiFeedProvider(
                auth,
                apiService: apiService,
                hydrator: context.read<ViewerStateHydrator>(),
              );
        },
      ),
      // CommentsProviderCache manages per-post CommentsProvider instances
      // with LRU eviction and sign-out cleanup
      ProxyProvider2<AuthProvider, VoteProvider, CommentsProviderCache>(
        create:
            (context) => CommentsProviderCache(
              authProvider: authProvider,
              voteProvider: context.read<VoteProvider>(),
              commentService: commentService,
              apiService: apiService,
              hydrator: context.read<ViewerStateHydrator>(),
            ),
        update: (context, auth, vote, previous) {
          // Reuse existing cache
          return previous ??
              CommentsProviderCache(
                authProvider: auth,
                voteProvider: vote,
                commentService: commentService,
                apiService: apiService,
                hydrator: context.read<ViewerStateHydrator>(),
              );
        },
        dispose: (_, cache) => cache.dispose(),
      ),
      // StreamableService for video embeds
      Provider<StreamableService>(create: (_) => StreamableService()),
      // UserProfileProvider for profile pages
      ChangeNotifierProxyProvider2<
        AuthProvider,
        VoteProvider,
        UserProfileProvider
      >(
        create:
            (context) => UserProfileProvider(
              authProvider,
              apiService: apiService,
              commentService: commentService,
              // Fully wired, subscriptions included: this surface calls
              // hydrateFeedVotesOnly, so "profile posts never seed
              // subscriptions" is a property of the call, not of a missing
              // provider.
              hydrator: context.read<ViewerStateHydrator>(),
            ),
        update: (context, auth, vote, previous) {
          // The shared apiService/commentService auth callbacks are bound
          // to the bootstrap AuthProvider instance; a different instance
          // flowing through here would leave them stale.
          assert(
            identical(auth, authProvider),
            'AuthProvider instance changed: shared service auth callbacks '
            'are bound to the bootstrap instance',
          );
          // Propagate auth changes to existing provider
          previous?.updateAuthProvider(auth);
          return previous ??
              UserProfileProvider(
                auth,
                apiService: apiService,
                commentService: commentService,
                hydrator: context.read<ViewerStateHydrator>(),
              );
        },
      ),
    ],
    child: const CovesApp(),
  );
}

class CovesApp extends StatelessWidget {
  const CovesApp({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final eulaProvider = Provider.of<EulaProvider>(context, listen: false);
    final guidelinesProvider = Provider.of<CommunityGuidelinesProvider>(
      context,
      listen: false,
    );

    return MaterialApp.router(
      title: 'Coves',
      theme: AppTheme.dark,
      // The app is dark-only by design. `darkTheme` being null would already
      // make the `theme` slot win in every case, so setting both plus an
      // explicit `themeMode` is behavior-preserving - it just stops a later
      // light theme from landing the app in a half-migrated state.
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: createRouter(
        authProvider,
        eulaProvider,
        guidelinesProvider,
      ),
      restorationScopeId: 'app',
      debugShowCheckedModeBanner: false,
    );
  }
}

// GoRouter configuration factory
@visibleForTesting
GoRouter createRouter(
  AuthProvider authProvider,
  EulaProvider eulaProvider,
  CommunityGuidelinesProvider guidelinesProvider,
) {
  return GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const LandingScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/eula',
        builder: (context, state) {
          final viewOnly = state.uri.queryParameters['viewOnly'] == 'true';
          return EulaScreen(viewOnly: viewOnly);
        },
      ),
      GoRoute(
        path: '/community-guidelines',
        builder: (context, state) {
          final viewOnly = state.uri.queryParameters['viewOnly'] == 'true';
          return CommunityGuidelinesScreen(viewOnly: viewOnly);
        },
      ),
      GoRoute(
        path: '/feed',
        builder: (context, state) => const MainShellScreen(),
      ),
      GoRoute(
        path: '/profile/:actor',
        builder: (context, state) {
          final actor = state.pathParameters['actor']!;
          return ProfileScreen(actor: actor);
        },
      ),
      GoRoute(
        path: '/community/:identifier',
        builder: (context, state) {
          final identifier = state.pathParameters['identifier']!;
          final community = state.extra as CommunityView?;
          return CommunityFeedScreen(
            identifier: identifier,
            community: community,
          );
        },
      ),
      GoRoute(
        path: '/post/:postUri',
        builder: (context, state) {
          // Fast path: post passed via state.extra (in-app navigation)
          final post = state.extra as FeedViewPost?;
          if (post != null) {
            return PostDetailScreen(post: post);
          }

          // Cold path: no extra (state restoration, deep links) - load the
          // post by its AT-URI from the path parameter. go_router has
          // already percent-decoded path parameters, so use it as-is.
          final postUri = state.pathParameters['postUri'];
          if (postUri == null || postUri.isEmpty) {
            if (kDebugMode) {
              debugPrint('⚠️ PostDetailScreen: No post URI in route');
            }
            // Show not found screen with option to go back
            return NotFoundError(
              title: 'Post Not Found',
              message:
                  'This post could not be loaded. It may have been '
                  'deleted or the link is invalid.',
              onBackPressed: () {
                // Navigate back to feed
                context.go('/feed');
              },
            );
          }

          if (kDebugMode) {
            debugPrint('🔄 PostDetailScreen: Cold-loading post from URI');
          }
          return PostDetailLoader(postUri: postUri);
        },
      ),
    ],
    refreshListenable: Listenable.merge([
      authProvider,
      eulaProvider,
      guidelinesProvider,
    ]),
    redirect: (context, state) {
      final isAuthenticated = authProvider.isAuthenticated;
      final isAuthLoading = authProvider.isLoading;
      final eulaAccepted = eulaProvider.hasAccepted;
      final isEulaLoading = eulaProvider.isLoading;
      final guidelinesAccepted = guidelinesProvider.hasAccepted;
      final isGuidelinesLoading = guidelinesProvider.isLoading;
      final currentPath = state.uri.path;

      // Don't redirect while loading initial state
      if (isAuthLoading || isEulaLoading || isGuidelinesLoading) {
        return null;
      }

      // EULA must be accepted first before anything else
      if (!eulaAccepted && currentPath != '/eula') {
        return '/eula';
      }

      // Community guidelines must be accepted after EULA
      if (eulaAccepted &&
          !guidelinesAccepted &&
          currentPath != '/community-guidelines' &&
          currentPath != '/eula') {
        return '/community-guidelines';
      }

      // Prevent navigating to acceptance screens in accept mode after already accepting
      final isViewOnly = state.uri.queryParameters['viewOnly'] == 'true';
      if (!isViewOnly) {
        if (eulaAccepted && currentPath == '/eula') {
          // Go straight to community guidelines if not yet accepted
          return guidelinesAccepted ? '/' : '/community-guidelines';
        }
        if (guidelinesAccepted && currentPath == '/community-guidelines') {
          return '/';
        }
      }

      // If authenticated and on landing/login screen, redirect to feed
      if (isAuthenticated && (currentPath == '/' || currentPath == '/login')) {
        if (kDebugMode) {
          print('🔄 User authenticated, redirecting to /feed');
        }
        return '/feed';
      }

      // Allow anonymous users to access /feed for browsing
      // Sign-out redirect is handled explicitly in the sign-out action
      return null;
    },
    errorBuilder: (context, state) {
      // Check if this is an OAuth callback
      if (state.uri.scheme == OAuthConfig.customScheme) {
        if (kDebugMode) {
          print(
            '⚠️ OAuth callback in errorBuilder - '
            'flutter_web_auth_2 should handle it',
          );
          print('   URI: ${state.uri}');
        }
        // Return nothing - just stay on current screen
        // flutter_web_auth_2 will process the callback at native level
        return const SizedBox.shrink();
      }

      // For other errors, show landing page
      if (kDebugMode) {
        print('⚠️ Router error: ${state.uri}');
      }
      return const LandingScreen();
    },
  );
}
