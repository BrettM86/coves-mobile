import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'config/oauth_config.dart';
import 'constants/app_colors.dart';
import 'models/post.dart';
import 'providers/auth_provider.dart';
import 'providers/comments_provider.dart';
import 'providers/feed_provider.dart';
import 'providers/vote_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/main_shell_screen.dart';
import 'screens/home/post_detail_screen.dart';
import 'screens/landing_screen.dart';
import 'services/comment_service.dart';
import 'services/streamable_service.dart';
import 'services/vote_service.dart';
import 'widgets/loading_error_states.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set system UI overlay style (Android navigation bar)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Color(0xFF0B0F14),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Initialize auth provider
  final authProvider = AuthProvider();
  await authProvider.initialize();

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

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider(
          create:
              (_) => VoteProvider(
                voteService: voteService,
                authProvider: authProvider,
              ),
        ),
        ChangeNotifierProxyProvider2<AuthProvider, VoteProvider, FeedProvider>(
          create:
              (context) => FeedProvider(
                authProvider,
                voteProvider: context.read<VoteProvider>(),
              ),
          update: (context, auth, vote, previous) {
            // Reuse existing provider to maintain state across rebuilds
            return previous ?? FeedProvider(auth, voteProvider: vote);
          },
        ),
        ChangeNotifierProxyProvider2<
          AuthProvider,
          VoteProvider,
          CommentsProvider
        >(
          create:
              (context) => CommentsProvider(
                authProvider,
                voteProvider: context.read<VoteProvider>(),
                commentService: commentService,
              ),
          update: (context, auth, vote, previous) {
            // Reuse existing provider to maintain state across rebuilds
            return previous ??
                CommentsProvider(
                  auth,
                  voteProvider: vote,
                  commentService: commentService,
                );
          },
        ),
        // StreamableService for video embeds
        Provider<StreamableService>(create: (_) => StreamableService()),
      ],
      child: const CovesApp(),
    ),
  );
}

class CovesApp extends StatelessWidget {
  const CovesApp({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    return MaterialApp.router(
      title: 'Coves',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      routerConfig: _createRouter(authProvider),
      restorationScopeId: 'app',
      debugShowCheckedModeBanner: false,
    );
  }
}

// GoRouter configuration factory
GoRouter _createRouter(AuthProvider authProvider) {
  return GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const LandingScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/feed',
        builder: (context, state) => const MainShellScreen(),
      ),
      GoRoute(
        path: '/post/:postUri',
        builder: (context, state) {
          // Extract post from state.extra
          final post = state.extra as FeedViewPost?;

          // If no post provided via extra, show user-friendly error
          if (post == null) {
            if (kDebugMode) {
              print('⚠️ PostDetailScreen: No post provided in route extras');
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

          return PostDetailScreen(post: post);
        },
      ),
    ],
    refreshListenable: authProvider,
    redirect: (context, state) {
      final isAuthenticated = authProvider.isAuthenticated;
      final isLoading = authProvider.isLoading;
      final currentPath = state.uri.path;

      // Don't redirect while loading initial auth state
      if (isLoading) {
        return null;
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
