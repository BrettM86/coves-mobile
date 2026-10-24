import 'package:coves_flutter/models/notification.dart';
import 'package:coves_flutter/utils/upvote_notification_copy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/upvote_notification_fixture.dart';

void _expectSentence(
  Map<String, dynamic> wire,
  List<UpvoteSentencePart> expected,
) {
  final notification = NotificationView.tryFromJson(wire);
  expect(notification, isNotNull, reason: 'wire fixture must parse');
  expect(upvoteNotificationSentence(notification!), expected);
}

void main() {
  test('B1 first upvoter and remaining count use singular and plural copy', () {
    for (final (wire, expected) in [
      (
        upvoteWire(upvoters: [aliceUpvoter], count: 13),
        <UpvoteSentencePart>[
          (text: 'Alice', bold: true),
          (text: ' and ', bold: false),
          (text: '12 others', bold: true),
          (text: ' liked your post', bold: false),
        ],
      ),
      (
        upvoteWire(upvoters: [aliceUpvoter, bobUpvoter], count: 5),
        <UpvoteSentencePart>[
          (text: 'Alice', bold: true),
          (text: ' and ', bold: false),
          (text: '4 others', bold: true),
          (text: ' liked your post', bold: false),
        ],
      ),
      (
        upvoteWire(upvoters: [aliceUpvoter], count: 2),
        <UpvoteSentencePart>[
          (text: 'Alice', bold: true),
          (text: ' and ', bold: false),
          (text: '1 other', bold: true),
          (text: ' liked your post', bold: false),
        ],
      ),
      (
        upvoteWire(upvoters: [aliceUpvoter], count: 1),
        <UpvoteSentencePart>[
          (text: 'Alice', bold: true),
          (text: ' liked your post', bold: false),
        ],
      ),
    ]) {
      _expectSentence(wire, expected);
    }
  });

  test('B2 all named upvoters appear when the count is not greater', () {
    for (final (wire, expected) in [
      (
        upvoteWire(upvoters: [aliceUpvoter, bobUpvoter], count: 2),
        <UpvoteSentencePart>[
          (text: 'Alice', bold: true),
          (text: ' and ', bold: false),
          (text: 'bob.test', bold: true),
          (text: ' liked your post', bold: false),
        ],
      ),
      (
        upvoteWire(
          upvoters: [aliceUpvoter, bobUpvoter, carolUpvoter],
          count: 3,
        ),
        <UpvoteSentencePart>[
          (text: 'Alice', bold: true),
          (text: ', ', bold: false),
          (text: 'bob.test', bold: true),
          (text: ' and ', bold: false),
          (text: 'Carol', bold: true),
          (text: ' liked your post', bold: false),
        ],
      ),
      (
        upvoteWire(upvoters: [aliceUpvoter, bobUpvoter], count: 1),
        <UpvoteSentencePart>[
          (text: 'Alice', bold: true),
          (text: ' and ', bold: false),
          (text: 'bob.test', bold: true),
          (text: ' liked your post', bold: false),
        ],
      ),
      (
        upvoteWire(upvoters: [aliceUpvoter, bobUpvoter]),
        <UpvoteSentencePart>[
          (text: 'Alice', bold: true),
          (text: ' and ', bold: false),
          (text: 'bob.test', bold: true),
          (text: ' liked your post', bold: false),
        ],
      ),
    ]) {
      _expectSentence(wire, expected);
    }
  });

  test('B3 bridged-only upvotes use people or person without upvoters', () {
    for (final (wire, expected) in [
      (
        upvoteWire(count: 5),
        <UpvoteSentencePart>[
          (text: '5 people', bold: true),
          (text: ' liked your post', bold: false),
        ],
      ),
      (
        upvoteWire(count: 1),
        <UpvoteSentencePart>[
          (text: '1 person', bold: true),
          (text: ' liked your post', bold: false),
        ],
      ),
    ]) {
      _expectSentence(wire, expected);
    }
  });

  test('B4 comment subjects change every sentence class to your comment', () {
    for (final (wire, expected) in [
      (
        upvoteWire(
          upvoters: [aliceUpvoter],
          count: 13,
          subject: commentSubject,
        ),
        <UpvoteSentencePart>[
          (text: 'Alice', bold: true),
          (text: ' and ', bold: false),
          (text: '12 others', bold: true),
          (text: ' liked your comment', bold: false),
        ],
      ),
      (
        upvoteWire(
          upvoters: [aliceUpvoter, bobUpvoter],
          count: 2,
          subject: commentSubject,
        ),
        <UpvoteSentencePart>[
          (text: 'Alice', bold: true),
          (text: ' and ', bold: false),
          (text: 'bob.test', bold: true),
          (text: ' liked your comment', bold: false),
        ],
      ),
      (
        upvoteWire(count: 5, subject: commentSubject),
        <UpvoteSentencePart>[
          (text: '5 people', bold: true),
          (text: ' liked your comment', bold: false),
        ],
      ),
    ]) {
      _expectSentence(wire, expected);
    }
  });

  test('B5 DID-only upvoter has a safe name and never exposes a DID', () {
    final notification = NotificationView.tryFromJson(
      upvoteWire(upvoters: [didOnlyUpvoter], count: 3),
    );
    expect(notification, isNotNull, reason: 'wire fixture must parse');
    final parts = upvoteNotificationSentence(notification!);
    expect(parts, <UpvoteSentencePart>[
      (text: 'Unknown user', bold: true),
      (text: ' and ', bold: false),
      (text: '2 others', bold: true),
      (text: ' liked your post', bold: false),
    ]);
    expect(parts.map((part) => part.text).join(), isNot(contains('did:')));
  });
}
