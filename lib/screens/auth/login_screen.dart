import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
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

  void _showHandleHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A2028),
        title: const Text(
          'What is a handle?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Your handle is your unique identifier '
          'on the atproto network, like '
          'alice.bsky.social. If you don\'t have one '
          'yet, you can create an account at bsky.app.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
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
    } on Exception catch (e) {
      if (mounted) {
        final errorString = e.toString().toLowerCase();
        String userMessage;
        if (errorString.contains('timeout') ||
            errorString.contains('socketexception') ||
            errorString.contains('connection')) {
          userMessage =
              'Network error. Please check your connection and try again.';
        } else if (errorString.contains('404') ||
            errorString.contains('not found')) {
          userMessage =
              'Handle not found. Please verify your handle is correct.';
        } else if (errorString.contains('401') ||
            errorString.contains('403') ||
            errorString.contains('unauthorized')) {
          userMessage = 'Authorization failed. Please try again.';
        } else {
          userMessage = 'Sign in failed. Please try again later.';
          debugPrint('Sign in error: $e');
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userMessage),
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
        backgroundColor: AppColors.background,
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/'),
          ),
        ),
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(context).unfocus(),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 32),

                    // Title
                    const Text(
                      'Enter your atproto handle',
                      style: TextStyle(
                        fontSize: 24,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 12),

                    // Provider logos
                    Center(
                      child: SvgPicture.asset(
                        'assets/icons/atproto/providers_stack.svg',
                        height: 24,
                        errorBuilder: (context, error, stackTrace) {
                          debugPrint(
                            'Failed to load providers_stack.svg: $error',
                          );
                          return const SizedBox(height: 24);
                        },
                      ),
                    ),

                    const SizedBox(height: 32),

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
                          borderSide: const BorderSide(
                            color: Color(0xFF2A3441),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFF2A3441),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppColors.primary,
                            width: 2,
                          ),
                        ),
                        prefixIcon: const Padding(
                          padding: EdgeInsets.only(left: 16, right: 8),
                          child: Text(
                            '@',
                            style: TextStyle(
                              color: Color(0xFF5A6B7F),
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        prefixIconConstraints: const BoxConstraints(),
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
                          return 'Handle must contain a domain '
                              '(e.g., user.bsky.social)';
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
                      'You\'ll be redirected to authorize this app with your '
                      'atproto provider.',
                      style: TextStyle(fontSize: 14, color: Color(0xFF5A6B7F)),
                      textAlign: TextAlign.center,
                    ),

                    const Spacer(),

                    // Help text
                    Center(
                      child: TextButton(
                        onPressed: _showHandleHelpDialog,
                        child: const Text(
                          'What is a handle?',
                          style: TextStyle(
                            color: AppColors.primary,
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
      ),
    );
  }
}
