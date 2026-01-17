import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/primary_button.dart';

/// Login screen with Coves design language.
///
/// Features the warm beach-inspired aesthetic with custom typography
/// and refined input styling.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _handleController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _focusNode = FocusNode();
  bool _isLoading = false;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    setState(() => _isFocused = _focusNode.hasFocus);
  }

  @override
  void dispose() {
    _handleController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _showHandleHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.backgroundSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: AppColors.border,
            width: 1,
          ),
        ),
        title: Text(
          'What is a handle?',
          style: GoogleFonts.nunito(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your handle is your unique identifier on the AT Protocol network.',
              style: GoogleFonts.nunito(
                color: AppColors.textSecondary,
                fontSize: 15,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.teal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.teal.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.alternate_email,
                    color: AppColors.teal,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'alice.bsky.social',
                    style: GoogleFonts.nunito(
                      color: AppColors.teal,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'If you don\'t have one yet, you can create an account at bsky.app.',
              style: GoogleFonts.nunito(
                color: AppColors.textMuted,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.coral,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: Text(
              'Got it',
              style: GoogleFonts.nunito(
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
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
        context.go('/feed');
      }
    } on Exception catch (e, stackTrace) {
      // Log all sign-in errors to Sentry with categorization
      final errorString = e.toString().toLowerCase();
      String userMessage;
      String errorCategory;

      if (errorString.contains('timeout') ||
          errorString.contains('socketexception') ||
          errorString.contains('connection')) {
        userMessage =
            'Network error. Please check your connection and try again.';
        errorCategory = 'network';
      } else if (errorString.contains('404') ||
          errorString.contains('not found')) {
        userMessage =
            'Handle not found. Please verify your handle is correct.';
        errorCategory = 'not_found';
      } else if (errorString.contains('401') ||
          errorString.contains('403') ||
          errorString.contains('unauthorized')) {
        userMessage = 'Authorization failed. Please try again.';
        errorCategory = 'auth_failure';
      } else {
        userMessage = 'Sign in failed. Please try again later.';
        errorCategory = 'unexpected';
      }

      Sentry.captureException(
        e,
        stackTrace: stackTrace,
        withScope: (scope) {
          scope.setTag('error_category', errorCategory);
          scope.setTag('screen', 'login');
          scope.setTag('action', 'sign_in');
          scope.setContexts('sign_in', {
            'handle_provided': _handleController.text.isNotEmpty,
          });
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userMessage,
              style: GoogleFonts.nunito(fontWeight: FontWeight.w500),
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
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
    final screenHeight = MediaQuery.of(context).size.height;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          context.pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            // Ocean gradient background
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: screenHeight * 0.35,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      AppColors.teal.withValues(alpha: 0.06),
                      AppColors.teal.withValues(alpha: 0.12),
                    ],
                  ),
                ),
              ),
            ),

            // Main content
            SafeArea(
              child: Column(
                children: [
                  // App bar
                  _buildAppBar(context),

                  // Scrollable content
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => FocusScope.of(context).unfocus(),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 32),

                              // Title with Shrikhand display font
                              _buildTitle(),

                              const SizedBox(height: 32),

                              // Handle input field
                              _buildHandleInput(),

                              const SizedBox(height: 28),

                              // Sign in button
                              Center(
                                child: PrimaryButton(
                                  title:
                                      _isLoading ? 'Signing in...' : 'Sign in',
                                  onPressed: _isLoading ? () {} : _handleSignIn,
                                  disabled: _isLoading,
                                ),
                              ),

                              const SizedBox(height: 24),

                              // Info text
                              _buildInfoText(),

                              const SizedBox(height: 40),

                              // Help link
                              _buildHelpLink(),

                              const SizedBox(height: 32),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              Icons.arrow_back_rounded,
              color: AppColors.textSecondary,
            ),
            onPressed: () => context.pop(),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.backgroundSecondary,
              padding: const EdgeInsets.all(12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitle() {
    return Column(
      children: [
        // Decorative line
        Container(
          width: 40,
          height: 3,
          decoration: BoxDecoration(
            color: AppColors.coral,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 20),

        Text(
          'Welcome back',
          style: GoogleFonts.shrikhand(
            fontSize: 28,
            color: AppColors.textPrimary,
            height: 1.2,
          ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 12),

        // Provider logos
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Sign in with your atproto identity',
              style: GoogleFonts.nunito(
                fontSize: 15,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        SvgPicture.asset(
          'assets/icons/atproto/providers_stack.svg',
          height: 24,
          errorBuilder: (context, error, stackTrace) {
            Sentry.captureException(
              error,
              stackTrace: stackTrace,
              withScope: (scope) {
                scope.setTag('asset', 'providers_stack.svg');
                scope.setTag('screen', 'login');
              },
            );
            return Text(
              'Bluesky \u2022 ATProto',
              style: GoogleFonts.nunito(
                fontSize: 12,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w500,
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildHandleInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'YOUR HANDLE',
            style: GoogleFonts.nunito(
              fontSize: 11,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),

        // Input field with custom styling
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: AppColors.coral.withValues(alpha: 0.2),
                      blurRadius: 12,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: TextFormField(
            controller: _handleController,
            focusNode: _focusNode,
            enabled: !_isLoading,
            style: GoogleFonts.nunito(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: 'alice.bsky.social',
              hintStyle: GoogleFonts.nunito(
                color: AppColors.textMuted,
                fontSize: 16,
              ),
              filled: true,
              fillColor: AppColors.backgroundTertiary,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 18,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: AppColors.border,
                  width: 2,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: AppColors.border,
                  width: 2,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: AppColors.coral,
                  width: 2,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: AppColors.error,
                  width: 2,
                ),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: AppColors.error,
                  width: 2,
                ),
              ),
              errorStyle: GoogleFonts.nunito(
                color: AppColors.error,
                fontSize: 12,
              ),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 20, right: 4),
                child: Text(
                  '@',
                  style: GoogleFonts.nunito(
                    color: _isFocused ? AppColors.coral : AppColors.textMuted,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
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
              if (!value.contains('.')) {
                return 'Handle must contain a domain (e.g., user.bsky.social)';
              }
              return null;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildInfoText() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.teal.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.teal.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.security_rounded,
            color: AppColors.teal,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'You\'ll be redirected to authorize securely with your atproto provider.',
              style: GoogleFonts.nunito(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpLink() {
    return Center(
      child: GestureDetector(
        onTap: _showHandleHelpDialog,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.help_outline_rounded,
                color: AppColors.coral,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'What is a handle?',
                style: GoogleFonts.nunito(
                  color: AppColors.coral,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
