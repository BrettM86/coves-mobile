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
}
