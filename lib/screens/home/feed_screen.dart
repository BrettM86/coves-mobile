import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/primary_button.dart';

class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final isAuthenticated = authProvider.isAuthenticated;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0F14),
        foregroundColor: Colors.white,
        title: Text(isAuthenticated ? 'Feed' : 'Explore'),
        automaticallyImplyLeading: !isAuthenticated,
        leading: !isAuthenticated
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go('/'),
              )
            : null,
        actions: isAuthenticated
            ? [
                IconButton(
                  icon: const Icon(Icons.person),
                  onPressed: () {
                    // TODO: Navigate to profile screen
                  },
                ),
              ]
            : null,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.forum,
                size: 64,
                color: Color(0xFFFF6B35),
              ),
              const SizedBox(height: 24),
              Text(
                isAuthenticated ? 'Welcome to Coves!' : 'Explore Coves',
                style: const TextStyle(
                  fontSize: 28,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              if (isAuthenticated && authProvider.did != null) ...[
                Text(
                  'Signed in as:',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  authProvider.did!,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFFB6C2D2),
                    fontFamily: 'monospace',
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 32),
              Text(
                isAuthenticated
                    ? 'Your personalized feed will appear here'
                    : 'Browse communities and discover conversations',
                style: const TextStyle(
                  fontSize: 16,
                  color: Color(0xFFB6C2D2),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              if (isAuthenticated) ...[
                PrimaryButton(
                  title: 'Sign Out',
                  onPressed: () async {
                    await authProvider.signOut();
                    // Explicitly redirect to landing screen after sign out
                    if (context.mounted) {
                      context.go('/');
                    }
                  },
                  variant: ButtonVariant.outline,
                ),
              ] else ...[
                PrimaryButton(
                  title: 'Sign in',
                  onPressed: () => context.go('/login'),
                  variant: ButtonVariant.solid,
                ),
                const SizedBox(height: 12),
                PrimaryButton(
                  title: 'Create account',
                  onPressed: () => context.go('/login'),
                  variant: ButtonVariant.outline,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
