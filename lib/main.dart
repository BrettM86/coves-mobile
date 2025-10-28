import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:atproto_oauth_flutter/atproto_oauth_flutter.dart';
import 'screens/landing_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/feed_screen.dart';
import 'providers/auth_provider.dart';
import 'config/oauth_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize auth provider
  final authProvider = AuthProvider();
  await authProvider.initialize();

  runApp(
    ChangeNotifierProvider.value(
      value: authProvider,
      child: const CovesApp(),
    ),
  );
}

class CovesApp extends StatelessWidget {
  const CovesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Coves',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF6B35),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}

// GoRouter configuration
final _router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const LandingScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/feed',
      builder: (context, state) => const FeedScreen(),
    ),
  ],
  // No custom redirect - let errorBuilder handle OAuth callbacks
  errorBuilder: (context, state) {
    // Check if this is an OAuth callback
    if (state.uri.scheme == OAuthConfig.customScheme) {
      if (kDebugMode) {
        print('⚠️ OAuth callback in errorBuilder - flutter_web_auth_2 should handle it');
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
