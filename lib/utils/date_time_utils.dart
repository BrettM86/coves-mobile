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

  /// Format datetime as full date/time string like Bluesky
  ///
  /// Example: "12:01PM · Dec 26, 2025"
  ///
  /// [dateTime] is the time to format
  static String formatFullDateTime(DateTime dateTime) {
    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    assert(dateTime.month >= 1 && dateTime.month <= 12, 'Invalid month');
    final month = months[dateTime.month - 1];
    final day = dateTime.day;
    final year = dateTime.year;

    return '$hour12:$minute$period · $month $day, $year';
  }

  /// Format datetime as "Joined Month Year" string
  ///
  /// Example: "Joined January 2025"
  ///
  /// [dateTime] is the account creation date
  static String formatJoinedDate(DateTime dateTime) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    assert(dateTime.month >= 1 && dateTime.month <= 12, 'Invalid month');
    final month = months[dateTime.month - 1];
    return 'Joined $month ${dateTime.year}';
  }
}
