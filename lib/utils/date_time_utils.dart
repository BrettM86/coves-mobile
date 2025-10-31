/// DateTime utility functions
///
/// Provides reusable time formatting and number formatting utilities.
/// All functions accept current time as parameter to enable testing
/// without relying on DateTime.now().
class DateTimeUtils {
  // Private constructor to prevent instantiation
  DateTimeUtils._();

  /// Format time difference as human-readable "ago" string
  ///
  /// Examples:
  /// - Less than 60 minutes: "5m", "45m"
  /// - Less than 24 hours: "2h", "23h"
  /// - Less than 365 days: "5d", "364d"
  /// - 365+ days: "1yr", "2yr"
  ///
  /// [dateTime] is the past time to format
  /// [currentTime] is the reference time (defaults to now for production use)
  static String formatTimeAgo(DateTime dateTime, {DateTime? currentTime}) {
    final now = currentTime ?? DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h';
    } else if (difference.inDays < 365) {
      return '${difference.inDays}d';
    } else {
      final years = (difference.inDays / 365).floor();
      return '${years}yr';
    }
  }

  /// Format large numbers with 'k' suffix for thousands
  ///
  /// Examples:
  /// - 0-999: "0", "42", "999"
  /// - 1000+: "1.0k", "5.2k", "12.5k"
  ///
  /// [count] is the number to format
  static String formatCount(int count) {
    if (count < 1000) {
      return count.toString();
    } else {
      final thousands = count / 1000;
      return '${thousands.toStringAsFixed(1)}k';
    }
  }
}
