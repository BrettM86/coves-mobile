import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../widgets/logo.dart';
import '../widgets/primary_button.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F14),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                const CovesLogo(useColorVersion: true),

                // App Name
                const Text(
                  'Coves',
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),

                const SizedBox(height: 48),

                // Buttons
                PrimaryButton(
                  title: 'Create account',
                  onPressed: () {
                    context.go('/login');
                  },
                  variant: ButtonVariant.solid,
                ),

                const SizedBox(height: 12),

                PrimaryButton(
                  title: 'Sign in',
                  onPressed: () {
                    context.go('/login');
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
