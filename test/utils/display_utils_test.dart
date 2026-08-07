import 'package:coves_flutter/utils/display_utils.dart';
import 'package:flutter_test/flutter_test.dart';

/// Spec for the single canonical count formatter.
///
/// `DisplayUtils.formatCount` is the one implementation the whole UI is
/// expected to render counts through (vote scores, comment counts, member
/// counts). Its contract is uppercase K/M with one decimal place.
void main() {
  group('DisplayUtils.formatCount', () {
    test('renders values below 1000 unchanged', () {
      expect(DisplayUtils.formatCount(0), '0');
      expect(DisplayUtils.formatCount(1), '1');
      expect(DisplayUtils.formatCount(42), '42');
      expect(DisplayUtils.formatCount(999), '999');
    });

    test('renders thousands with an uppercase K', () {
      expect(DisplayUtils.formatCount(1000), '1.0K');
      expect(DisplayUtils.formatCount(1234), '1.2K');
      expect(DisplayUtils.formatCount(1500), '1.5K');
      expect(DisplayUtils.formatCount(5234), '5.2K');
      expect(DisplayUtils.formatCount(10000), '10.0K');
      expect(DisplayUtils.formatCount(42500), '42.5K');
    });

    test('rounds to a single decimal place', () {
      expect(DisplayUtils.formatCount(1567), '1.6K');
      expect(DisplayUtils.formatCount(5678), '5.7K');
      expect(DisplayUtils.formatCount(1470000), '1.5M');
    });

    test('rounds 999999 up into the K tier rather than the M tier', () {
      // Documented rounding artifact: 999.999K renders as "1000.0K" because
      // the tier is chosen before the value is rounded. Kept as-is so the
      // formatter never disagrees with itself across call sites.
      expect(DisplayUtils.formatCount(999999), '1000.0K');
    });

    test('renders millions with an uppercase M', () {
      expect(DisplayUtils.formatCount(1000000), '1.0M');
      expect(DisplayUtils.formatCount(1500000), '1.5M');
      expect(DisplayUtils.formatCount(12300000), '12.3M');
    });

    test('boundaries select the expected tier', () {
      expect(DisplayUtils.formatCount(999), '999');
      expect(DisplayUtils.formatCount(1000), '1.0K');
      expect(DisplayUtils.formatCount(999999), '1000.0K');
      expect(DisplayUtils.formatCount(1000000), '1.0M');
    });

    test('negative counts are rendered raw (characterization)', () {
      // Neither tier threshold matches a negative value, so negatives fall
      // through to `toString()`. Vote scores can legitimately go negative,
      // so this is the shipped behavior, not an accident to preserve
      // silently: -1500 shows as "-1500", never "-1.5K".
      expect(DisplayUtils.formatCount(-1), '-1');
      expect(DisplayUtils.formatCount(-999), '-999');
      expect(DisplayUtils.formatCount(-1500), '-1500');
      expect(DisplayUtils.formatCount(-1500000), '-1500000');
    });
  });
}
