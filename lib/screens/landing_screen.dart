import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_colors.dart';
import '../widgets/primary_button.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Lil Dude character
                SvgPicture.asset(
                  'assets/logo/lil_dude.svg',
                  width: 120,
                  height: 120,
                  errorBuilder: (context, error, stackTrace) {
                    debugPrint('Failed to load lil_dude.svg: $error');
                    return const SizedBox(width: 120, height: 120);
                  },
                ),
                const SizedBox(height: 16),

                // Coves bubble text
                SvgPicture.asset(
                  'assets/logo/coves_bubble.svg',
                  width: 180,
                  height: 60,
                  errorBuilder: (context, error, stackTrace) {
                    debugPrint('Failed to load coves_bubble.svg: $error');
                    return const SizedBox(width: 180, height: 60);
                  },
                ),

                const SizedBox(height: 48),

                // "Bring your @handle" with logos
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Bring your atproto handle',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF8A96A6),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SvgPicture.asset(
                      'assets/icons/atproto/providers_landing.svg',
                      height: 18,
                      errorBuilder: (context, error, stackTrace) {
                        debugPrint(
                          'Failed to load providers_landing.svg: $error',
                        );
                        return const SizedBox(height: 18);
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Sign in button
                PrimaryButton(
                  title: 'Sign in',
                  onPressed: () {
                    context.go('/login');
                  },
                ),

                const SizedBox(height: 12),

                // Create account button
                PrimaryButton(
                  title: 'Create account',
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Account registration coming soon!'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  variant: ButtonVariant.outline,
                ),

                const SizedBox(height: 20),

                // Explore link
                GestureDetector(
                  onTap: () {
                    context.go('/feed');
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    child: Text(
                      'Explore our communities!',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF8A96A6),
                        fontWeight: FontWeight.w500,
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
    );
  }
}
