import 'package:coves_flutter/models/notification.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('NotificationReference.isSensitive follows active nsfw self-labels', () {
    final cases = <(String, Map<String, dynamic>?, bool)>[
      (
        'plain nsfw',
        {
          'values': [
            {'val': 'nsfw'},
          ],
        },
        true,
      ),
      (
        'nsfw with neg false',
        {
          'values': [
            {'val': 'nsfw', 'neg': false},
          ],
        },
        true,
      ),
      (
        'nsfw after another value',
        {
          'values': [
            {'val': 'spoiler'},
            {'val': 'nsfw'},
          ],
        },
        true,
      ),
      (
        'nsfw with neg true',
        {
          'values': [
            {'val': 'nsfw', 'neg': true},
          ],
        },
        false,
      ),
      (
        'nsfw with neg null',
        {
          'values': [
            {'val': 'nsfw', 'neg': null},
          ],
        },
        false,
      ),
      (
        'nsfw with neg string false',
        {
          'values': [
            {'val': 'nsfw', 'neg': 'false'},
          ],
        },
        false,
      ),
      (
        'other values only',
        {
          'values': [
            {'val': 'spoiler'},
          ],
        },
        false,
      ),
      ('no labels key', null, false),
    ];

    for (final (description, labels, expected) in cases) {
      final reference = NotificationReference.fromJson({
        'uri': 'at://did:plc:alice/social.coves.community.postv2/3kpost',
        'cid': 'bafyroot',
        'labels': ?labels,
      });
      expect(reference.isSensitive, expected, reason: description);
    }
  });
}
