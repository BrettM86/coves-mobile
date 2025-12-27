import 'package:coves_flutter/utils/date_time_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DateTimeUtils.formatTimeAgo', () {
    // Fixed reference time for deterministic testing
    final referenceTime = DateTime(2024, 1, 15, 12);

    test('formats minutes correctly', () {
      final pastTime = referenceTime.subtract(const Duration(minutes: 5));
      expect(
        DateTimeUtils.formatTimeAgo(pastTime, currentTime: referenceTime),
        '5m',
      );
    });

    test('formats 0 minutes as 0m', () {
      final pastTime = referenceTime.subtract(const Duration(seconds: 30));
      expect(
        DateTimeUtils.formatTimeAgo(pastTime, currentTime: referenceTime),
        '0m',
      );
    });

    test('formats 59 minutes as minutes', () {
      final pastTime = referenceTime.subtract(const Duration(minutes: 59));
      expect(
        DateTimeUtils.formatTimeAgo(pastTime, currentTime: referenceTime),
        '59m',
      );
    });

    test('formats hours correctly', () {
      final pastTime = referenceTime.subtract(const Duration(hours: 3));
      expect(
        DateTimeUtils.formatTimeAgo(pastTime, currentTime: referenceTime),
        '3h',
      );
    });

    test('formats 23 hours as hours', () {
      final pastTime = referenceTime.subtract(const Duration(hours: 23));
      expect(
        DateTimeUtils.formatTimeAgo(pastTime, currentTime: referenceTime),
        '23h',
      );
    });

    test('formats days correctly', () {
      final pastTime = referenceTime.subtract(const Duration(days: 7));
      expect(
        DateTimeUtils.formatTimeAgo(pastTime, currentTime: referenceTime),
        '7d',
      );
    });

    test('formats 364 days as days', () {
      final pastTime = referenceTime.subtract(const Duration(days: 364));
      expect(
        DateTimeUtils.formatTimeAgo(pastTime, currentTime: referenceTime),
        '364d',
      );
    });

    test('formats years correctly', () {
      final pastTime = referenceTime.subtract(const Duration(days: 365));
      expect(
        DateTimeUtils.formatTimeAgo(pastTime, currentTime: referenceTime),
        '1yr',
      );
    });

    test('formats multiple years correctly', () {
      final pastTime = referenceTime.subtract(const Duration(days: 730));
      expect(
        DateTimeUtils.formatTimeAgo(pastTime, currentTime: referenceTime),
        '2yr',
      );
    });

    test('uses DateTime.now() when currentTime not provided', () {
      final pastTime = DateTime.now().subtract(const Duration(minutes: 5));
      final result = DateTimeUtils.formatTimeAgo(pastTime);

      // Should be "5m" or "4m" depending on timing
      expect(result, matches(r'^\d+m$'));
    });
  });

  group('DateTimeUtils.formatCount', () {
    test('formats numbers less than 1000 as-is', () {
      expect(DateTimeUtils.formatCount(0), '0');
      expect(DateTimeUtils.formatCount(1), '1');
      expect(DateTimeUtils.formatCount(42), '42');
      expect(DateTimeUtils.formatCount(999), '999');
    });

    test('formats 1000 as 1.0k', () {
      expect(DateTimeUtils.formatCount(1000), '1.0k');
    });

    test('formats thousands with one decimal place', () {
      expect(DateTimeUtils.formatCount(1500), '1.5k');
      expect(DateTimeUtils.formatCount(2300), '2.3k');
      expect(DateTimeUtils.formatCount(5678), '5.7k');
    });

    test('formats large numbers correctly', () {
      expect(DateTimeUtils.formatCount(10000), '10.0k');
      expect(DateTimeUtils.formatCount(42500), '42.5k');
      expect(DateTimeUtils.formatCount(999999), '1000.0k');
    });

    test('rounds to one decimal place', () {
      expect(DateTimeUtils.formatCount(1234), '1.2k');
      expect(DateTimeUtils.formatCount(1567), '1.6k');
    });
  });

  group('DateTimeUtils.formatFullDateTime', () {
    test('formats midnight (12:00 AM) correctly', () {
      final midnight = DateTime(2025, 6, 15, 0, 0);
      expect(DateTimeUtils.formatFullDateTime(midnight), '12:00AM · Jun 15, 2025');
    });

    test('formats noon (12:00 PM) correctly', () {
      final noon = DateTime(2025, 6, 15, 12, 0);
      expect(DateTimeUtils.formatFullDateTime(noon), '12:00PM · Jun 15, 2025');
    });

    test('formats 12:01 AM correctly', () {
      final justAfterMidnight = DateTime(2025, 6, 15, 0, 1);
      expect(
        DateTimeUtils.formatFullDateTime(justAfterMidnight),
        '12:01AM · Jun 15, 2025',
      );
    });

    test('formats 12:59 PM correctly', () {
      final lateNoon = DateTime(2025, 6, 15, 12, 59);
      expect(DateTimeUtils.formatFullDateTime(lateNoon), '12:59PM · Jun 15, 2025');
    });

    test('pads single digit minutes correctly', () {
      final singleDigitMinute = DateTime(2025, 3, 10, 9, 5);
      expect(
        DateTimeUtils.formatFullDateTime(singleDigitMinute),
        '9:05AM · Mar 10, 2025',
      );
    });

    test('formats double digit minutes correctly', () {
      final doubleDigitMinute = DateTime(2025, 3, 10, 14, 35);
      expect(
        DateTimeUtils.formatFullDateTime(doubleDigitMinute),
        '2:35PM · Mar 10, 2025',
      );
    });

    test('formats AM hours correctly (1-11)', () {
      // 1 AM
      final oneAm = DateTime(2025, 1, 1, 1, 30);
      expect(DateTimeUtils.formatFullDateTime(oneAm), '1:30AM · Jan 1, 2025');

      // 11 AM
      final elevenAm = DateTime(2025, 1, 1, 11, 45);
      expect(DateTimeUtils.formatFullDateTime(elevenAm), '11:45AM · Jan 1, 2025');
    });

    test('formats PM hours correctly (13-23)', () {
      // 1 PM (13:00)
      final onePm = DateTime(2025, 1, 1, 13, 0);
      expect(DateTimeUtils.formatFullDateTime(onePm), '1:00PM · Jan 1, 2025');

      // 11 PM (23:00)
      final elevenPm = DateTime(2025, 1, 1, 23, 30);
      expect(DateTimeUtils.formatFullDateTime(elevenPm), '11:30PM · Jan 1, 2025');
    });

    test('formats all months correctly', () {
      expect(
        DateTimeUtils.formatFullDateTime(DateTime(2025, 1, 15, 10, 0)),
        '10:00AM · Jan 15, 2025',
      );
      expect(
        DateTimeUtils.formatFullDateTime(DateTime(2025, 2, 15, 10, 0)),
        '10:00AM · Feb 15, 2025',
      );
      expect(
        DateTimeUtils.formatFullDateTime(DateTime(2025, 3, 15, 10, 0)),
        '10:00AM · Mar 15, 2025',
      );
      expect(
        DateTimeUtils.formatFullDateTime(DateTime(2025, 4, 15, 10, 0)),
        '10:00AM · Apr 15, 2025',
      );
      expect(
        DateTimeUtils.formatFullDateTime(DateTime(2025, 5, 15, 10, 0)),
        '10:00AM · May 15, 2025',
      );
      expect(
        DateTimeUtils.formatFullDateTime(DateTime(2025, 6, 15, 10, 0)),
        '10:00AM · Jun 15, 2025',
      );
      expect(
        DateTimeUtils.formatFullDateTime(DateTime(2025, 7, 15, 10, 0)),
        '10:00AM · Jul 15, 2025',
      );
      expect(
        DateTimeUtils.formatFullDateTime(DateTime(2025, 8, 15, 10, 0)),
        '10:00AM · Aug 15, 2025',
      );
      expect(
        DateTimeUtils.formatFullDateTime(DateTime(2025, 9, 15, 10, 0)),
        '10:00AM · Sep 15, 2025',
      );
      expect(
        DateTimeUtils.formatFullDateTime(DateTime(2025, 10, 15, 10, 0)),
        '10:00AM · Oct 15, 2025',
      );
      expect(
        DateTimeUtils.formatFullDateTime(DateTime(2025, 11, 15, 10, 0)),
        '10:00AM · Nov 15, 2025',
      );
      expect(
        DateTimeUtils.formatFullDateTime(DateTime(2025, 12, 15, 10, 0)),
        '10:00AM · Dec 15, 2025',
      );
    });

    test('formats AM/PM boundary at 11:59 AM transitioning to 12:00 PM', () {
      final beforeNoon = DateTime(2025, 6, 15, 11, 59);
      expect(
        DateTimeUtils.formatFullDateTime(beforeNoon),
        '11:59AM · Jun 15, 2025',
      );

      final atNoon = DateTime(2025, 6, 15, 12, 0);
      expect(DateTimeUtils.formatFullDateTime(atNoon), '12:00PM · Jun 15, 2025');
    });

    test('formats PM/AM boundary at 11:59 PM transitioning to 12:00 AM', () {
      final beforeMidnight = DateTime(2025, 6, 15, 23, 59);
      expect(
        DateTimeUtils.formatFullDateTime(beforeMidnight),
        '11:59PM · Jun 15, 2025',
      );

      final atMidnight = DateTime(2025, 6, 16, 0, 0);
      expect(
        DateTimeUtils.formatFullDateTime(atMidnight),
        '12:00AM · Jun 16, 2025',
      );
    });

    test('handles edge case: minute 00', () {
      final zeroMinute = DateTime(2025, 5, 20, 15, 0);
      expect(DateTimeUtils.formatFullDateTime(zeroMinute), '3:00PM · May 20, 2025');
    });

    test('handles single digit days', () {
      final singleDigitDay = DateTime(2025, 8, 5, 14, 30);
      expect(
        DateTimeUtils.formatFullDateTime(singleDigitDay),
        '2:30PM · Aug 5, 2025',
      );
    });

    test('handles different years', () {
      final oldDate = DateTime(2020, 3, 1, 9, 15);
      expect(DateTimeUtils.formatFullDateTime(oldDate), '9:15AM · Mar 1, 2020');

      final futureDate = DateTime(2030, 12, 31, 23, 59);
      expect(
        DateTimeUtils.formatFullDateTime(futureDate),
        '11:59PM · Dec 31, 2030',
      );
    });
  });
}
