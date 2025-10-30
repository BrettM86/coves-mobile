import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';

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
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.forum, size: 64, color: Color(0xFFFF6B35)),
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
                style: const TextStyle(fontSize: 16, color: Color(0xFFB6C2D2)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
