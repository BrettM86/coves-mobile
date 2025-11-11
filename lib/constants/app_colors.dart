import 'package:flutter/material.dart';

/// Application color constants
///
/// Centralized color definitions for consistent theming.
/// Using semantic names improves maintainability.
class AppColors {
  // Private constructor to prevent instantiation
  AppColors._();

  /// Primary background color - dark navy
  static const background = Color(0xFF0B0F14);

  /// Primary accent color - orange/coral
  static const primary = Color(0xFFFF6B35);

  /// Secondary text color - light gray/blue
  static const textSecondary = Color(0xFFB6C2D2);

  /// Border color - dark gray
  static const border = Color(0xFF2A2F36);

  /// Secondary background color - slightly lighter than main
  static const backgroundSecondary = Color(0xFF1A1F26);

  /// Loading indicator color - medium gray
  static const loadingIndicator = Color(0xFF484F58);

  /// Off-white color for primary text
  static const textPrimary = Color(0xFFe4e6e7);

  /// Community name color - light blue/cyan
  static const communityName = Color(0xFF7CB9E8);
}
