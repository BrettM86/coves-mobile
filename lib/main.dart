import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'config/oauth_config.dart';
import 'providers/auth_provider.dart';
import 'providers/feed_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/main_shell_screen.dart';
import 'screens/landing_screen.dart';

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

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider(create: (_) => FeedProvider(authProvider)),
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
          seedColor: const Color(0xFFFF6B35),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      routerConfig: _createRouter(authProvider),
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
            '⚠️ OAuth callback in errorBuilder - flutter_web_auth_2 should handle it',
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
