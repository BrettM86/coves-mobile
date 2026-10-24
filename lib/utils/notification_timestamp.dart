final _notificationTimestampPattern = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})[Tt](\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,9}))?([Zz]|[+-]\d{2}:\d{2})$',
);

/// Whether [value] is a strict RFC 3339 timestamp with a `Z` or numeric
/// offset and a real calendar date and time.
bool isNotificationTimestamp(String value) {
  try {
    _parseNotificationTimestamp(value);
    return true;
  } on FormatException {
    return false;
  }
}

/// Compares RFC 3339 timestamps by instant, retaining nanosecond precision.
int compareNotificationTimestamps(String a, String b) {
  final first = _parseNotificationTimestamp(a);
  final second = _parseNotificationTimestamp(b);
  final seconds = first.seconds.compareTo(second.seconds);
  return seconds != 0
      ? seconds
      : first.nanoseconds.compareTo(second.nanoseconds);
}

({int seconds, int nanoseconds}) _parseNotificationTimestamp(String value) {
  final match = _notificationTimestampPattern.firstMatch(value);
  if (match == null || match.group(0) != value) {
    throw const FormatException('Invalid notification timestamp');
  }

  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final hour = int.parse(match[4]!);
  final minute = int.parse(match[5]!);
  final second = int.parse(match[6]!);
  final wholeSecond = DateTime.utc(year, month, day, hour, minute, second);
  if (wholeSecond.year != year ||
      wholeSecond.month != month ||
      wholeSecond.day != day ||
      wholeSecond.hour != hour ||
      wholeSecond.minute != minute ||
      wholeSecond.second != second) {
    throw const FormatException('Invalid notification timestamp');
  }

  final zone = match[8]!;
  var offsetSeconds = 0;
  if (zone != 'Z' && zone != 'z') {
    final offsetHours = int.parse(zone.substring(1, 3));
    final offsetMinutes = int.parse(zone.substring(4, 6));
    if (offsetHours > 23 || offsetMinutes > 59) {
      throw const FormatException('Invalid notification timestamp');
    }
    offsetSeconds = (offsetHours * 60 + offsetMinutes) * 60;
    if (zone.startsWith('-')) {
      offsetSeconds = -offsetSeconds;
    }
  }

  final fraction = match[7];
  return (
    seconds: wholeSecond.millisecondsSinceEpoch ~/ 1000 - offsetSeconds,
    nanoseconds: fraction == null ? 0 : int.parse(fraction.padRight(9, '0')),
  );
}
