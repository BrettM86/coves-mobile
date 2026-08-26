import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Utility class for shared display formatting and styling
///
/// Centralizes common display logic to avoid duplication across widgets:
/// - Avatar fallback colors (consistent color generation by name hash)
/// - Number formatting (K/M suffixes for large numbers)
class DisplayUtils {
  DisplayUtils._();

  /// Fallback colors for avatars when no image is available.
  ///
  /// The values live in [AppColors.avatarFallbacks] so the palette stays the
  /// one place a color is defined. This alias has no callers outside this
  /// file - it exists so [getFallbackColor] below reads in terms of what it
  /// is choosing from, and it is kept public because it is part of
  /// `DisplayUtils`' existing surface. Reach for [AppColors.avatarFallbacks]
  /// directly in new code.
  static const fallbackColors = AppColors.avatarFallbacks;

  /// Get a consistent fallback color for a given name
  ///
  /// Indexes [fallbackColors] by `name.hashCode.abs() % length`, so the same
  /// name always returns the same color - as long as the list does not
  /// change. See [AppColors.avatarFallbacks] on why any edit to it repaints
  /// existing accounts.
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
