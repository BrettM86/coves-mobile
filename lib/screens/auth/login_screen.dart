import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/primary_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _handleController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  @override
  void dispose() {
    _handleController.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await authProvider.signIn(_handleController.text.trim());

      if (mounted) {
        // Navigate to feed on successful login
        context.go('/feed');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sign in failed: ${e.toString()}'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          context.go('/');
        }
      },
      child: Scaffold(
      backgroundColor: const Color(0xFF0B0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0F14),
        foregroundColor: Colors.white,
        title: const Text('Sign In'),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),

                // Title
                const Text(
                  'Enter your handle',
                  style: TextStyle(
                    fontSize: 24,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 8),

                // Subtitle
                const Text(
                  'Sign in with your atProto handle to continue',
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFFB6C2D2),
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 48),

                // Handle input field
                TextFormField(
                  controller: _handleController,
                  enabled: !_isLoading,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'alice.bsky.social',
                    hintStyle: const TextStyle(color: Color(0xFF5A6B7F)),
                    filled: true,
                    fillColor: const Color(0xFF1A2028),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF2A3441)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF2A3441)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFFF6B35), width: 2),
                    ),
                    prefixIcon: const Icon(Icons.person, color: Color(0xFF5A6B7F)),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _handleSignIn(),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your handle';
                    }
                    // Basic handle validation
                    if (!value.contains('.')) {
                      return 'Handle must contain a domain (e.g., user.bsky.social)';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 32),

                // Sign in button
                PrimaryButton(
                  title: _isLoading ? 'Signing in...' : 'Sign In',
                  onPressed: _isLoading ? () {} : _handleSignIn,
                  disabled: _isLoading,
                ),

                const SizedBox(height: 24),

                // Info text
                const Text(
                  'You\'ll be redirected to authorize this app with your atProto provider.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF5A6B7F),
                  ),
                  textAlign: TextAlign.center,
                ),

                const Spacer(),

                // Help text
                Center(
                  child: TextButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: const Color(0xFF1A2028),
                          title: const Text(
                            'What is a handle?',
                            style: TextStyle(color: Colors.white),
                          ),
                          content: const Text(
                            'Your handle is your unique identifier on the atProto network, '
                            'like alice.bsky.social. If you don\'t have one yet, you can create '
                            'an account at bsky.app.',
                            style: TextStyle(color: Color(0xFFB6C2D2)),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Got it'),
                            ),
                          ],
                        ),
                      );
                    },
                    child: const Text(
                      'What is a handle?',
                      style: TextStyle(
                        color: Color(0xFFFF6B35),
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}
