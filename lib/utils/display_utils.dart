import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Utility class for shared display formatting and styling
///
/// Centralizes common display logic to avoid duplication across widgets:
/// - Avatar fallback colors (consistent color generation by name hash)
/// - Number formatting (K/M suffixes for large numbers)
class DisplayUtils {
  DisplayUtils._();

  /// Fallback colors for avatars when no image is available
  ///
  /// Used by community avatars, user avatars, and other fallback displays.
  /// Color is deterministically selected based on name hash for consistency.
  static const fallbackColors = [
    AppColors.coral,
    AppColors.teal,
    Color(0xFF9B59B6), // Purple
    Color(0xFF3498DB), // Blue
    Color(0xFF27AE60), // Green
    Color(0xFFE74C3C), // Red
  ];

  /// Get a consistent fallback color for a given name
  ///
  /// Uses hash code to deterministically select a color from [fallbackColors].
  /// The same name will always return the same color.
  static Color getFallbackColor(String name) {
    final colorIndex = name.hashCode.abs() % fallbackColors.length;
    return fallbackColors[colorIndex];
  }

  /// Format a number with K/M suffixes for compact display
  ///
  /// Examples:
  /// - 500 -> "500"
  /// - 1,234 -> "1.2K"
  /// - 1,500,000 -> "1.5M"
  static String formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }
}
