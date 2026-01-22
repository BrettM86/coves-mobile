import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../constants/app_colors.dart';
import '../widgets/primary_button.dart';

/// Landing screen with Coves beach-inspired dark theme design.
class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Ocean gradient background
          _buildOceanGradient(screenHeight),

          // Main content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 60),

                    // Brand lockup: Mascot + Logo
                    _buildBrandLockup(),

                    const SizedBox(height: 56),

                    // Buttons
                    _buildButtons(context),

                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOceanGradient(double screenHeight) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        height: screenHeight * 0.45,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              AppColors.teal.withValues(alpha: 0.08),
              AppColors.teal.withValues(alpha: 0.15),
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
      ),
    );
  }

  Widget _buildBrandLockup() {
    return Column(
      children: [
        // Mascot
        SvgPicture.asset(
          'assets/logo/lil_dude.svg',
          width: 110,
          height: 110,
          errorBuilder: (context, error, stackTrace) {
            unawaited(
              Sentry.captureException(
                error,
                stackTrace: stackTrace,
                withScope: (scope) {
                  scope.setTag('asset', 'lil_dude.svg');
                  scope.setTag('screen', 'landing');
                },
              ),
            );
            return Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.teal.withValues(alpha: 0.15),
              ),
              child: const Icon(
                Icons.water_drop_rounded,
                size: 48,
                color: AppColors.teal,
              ),
            );
          },
        ),

        const SizedBox(height: 16),

        // Logo text
        SvgPicture.asset(
          'assets/logo/coves_logo_text.svg',
          height: 65,
          errorBuilder: (context, error, stackTrace) {
            unawaited(
              Sentry.captureException(
                error,
                stackTrace: stackTrace,
                withScope: (scope) {
                  scope.setTag('asset', 'coves_logo_text.svg');
                  scope.setTag('screen', 'landing');
                },
              ),
            );
            return Text(
              'Coves',
              style: GoogleFonts.shrikhand(
                fontSize: 48,
                color: AppColors.textPrimary,
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildButtons(BuildContext context) {
    return Column(
      children: [
        // Bring your handle text with provider logos
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Bring your atproto handle',
              style: GoogleFonts.nunito(
                fontSize: 15,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            SvgPicture.asset(
              'assets/icons/atproto/providers_landing.svg',
              height: 18,
              errorBuilder: (context, error, stackTrace) {
                unawaited(
                  Sentry.captureException(
                    error,
                    stackTrace: stackTrace,
                    withScope: (scope) {
                      scope.setTag('asset', 'providers_landing.svg');
                      scope.setTag('screen', 'landing');
                    },
                  ),
                );
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_outlined,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.cloud_outlined,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                  ],
                );
              },
            ),
          ],
        ),

        const SizedBox(height: 20),

        // Sign in button
        PrimaryButton(
          title: 'Sign in',
          onPressed: () => context.push('/login'),
        ),

        const SizedBox(height: 14),

        // Create account button
        PrimaryButton(
          title: 'Create account',
          variant: ButtonVariant.outline,
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Account creation coming soon!',
                  style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w600,
                    color: AppColors.background,
                  ),
                ),
                backgroundColor: AppColors.coral,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 24),

        // Explore link
        GestureDetector(
          onTap: () => context.go('/feed'),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: AppColors.teal.withValues(alpha: 0.1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.explore_outlined,
                  size: 18,
                  color: AppColors.teal,
                ),
                const SizedBox(width: 8),
                Text(
                  'Explore communities',
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    color: AppColors.teal,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
