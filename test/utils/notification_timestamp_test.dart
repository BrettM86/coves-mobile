import 'package:coves_flutter/utils/notification_timestamp.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('B2 compares nanoseconds and normalized offsets by instant', () {
    for (final (a, b, expectedSign) in [
      ('2026-10-08T12:00:00.1234567Z', '2026-10-08T12:00:00.1234568Z', -1),
      ('2026-10-08T12:00:00.1234568Z', '2026-10-08T12:00:00.1234567Z', 1),
      ('2026-10-08T12:00:00.5Z', '2026-10-08T12:00:00.500000000Z', 0),
      ('2026-10-08T13:00:00.000000001+01:00', '2026-10-08T12:00:00Z', 1),
      ('2026-10-07T23:30:00-01:00', '2026-10-08T00:15:00Z', 1),
      ('2026-10-08T14:00:00+02:00', '2026-10-08T12:00:00Z', 0),
    ]) {
      expect(
        compareNotificationTimestamps(a, b).sign,
        expectedSign,
        reason: '$a compared to $b',
      );
    }
  });

  test('B2 rejects a timestamp that is not RFC 3339', () {
    expect(
      () => compareNotificationTimestamps('not-a-time', '2026-10-08T12:00:00Z'),
      throwsFormatException,
    );
  });
}
