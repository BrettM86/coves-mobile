import 'package:coves_flutter/models/notification.dart';
import 'package:coves_flutter/providers/notifications_list_provider.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/notifications_list_provider_harness.dart';
import '../test_helpers/reply_notification_fixture.dart';
import '../test_helpers/upvote_notification_fixture.dart';

String _replyUri(String name) =>
    'at://did:plc:writer/social.coves.community.comment/$name';

Map<String, dynamic> _reply(
  String name, {
  required String sortAt,
  required bool isRead,
}) => replyNotificationWireFor(recordUri: _replyUri(name), rootUri: postUri)
  ..['sortAt'] = sortAt
  ..['isRead'] = isRead;

NotificationPage _page(
  List<Map<String, dynamic>> rows, {
  String? cursor,
  String? seenAt,
}) => NotificationPage.fromJson({
  'notifications': rows,
  'cursor': cursor,
  'seenAt': ?seenAt,
});

/// Each row's isRead, keyed by record uri (replies) or subject uri (upvotes).
Map<String, bool> _readState(NotificationsListProvider provider) => {
  for (final row in provider.controller.items)
    (row.reason == NotificationReason.upvote ? row.subject! : row.record!).uri:
        row.isRead,
};

/// Answers the next `listNotifications` request (page one) with [page].
Future<void> _loadFirstPage(
  NotificationsListProviderHarness harness,
  NotificationPage page,
) async {
  harness.provider.requestFirstPage();
  harness.responses.last.complete(page);
  await settle();
}

/// Loads the next later page and answers it with [page].
Future<void> _loadMore(
  NotificationsListProviderHarness harness,
  NotificationPage page,
) async {
  final more = harness.provider.loadMore();
  harness.responses.last.complete(page);
  await more;
  await settle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('B1 later pages are computed against page one seenAt and keep their '
      'other fields', () async {
    final harness = NotificationsListProviderHarness();
    try {
      await _loadFirstPage(
        harness,
        _page(
          [_reply('p1', sortAt: '2026-10-08T11:00:00.000Z', isRead: true)],
          cursor: 'c1',
          seenAt: '2026-10-08T12:00:00.000Z',
        ),
      );
      await _loadMore(
        harness,
        _page(
          [
            _reply('equal', sortAt: '2026-10-08T12:00:00.000Z', isRead: false),
            upvoteWire(
                subject: commentSubject,
                count: 4,
                upvoters: [aliceUpvoter, bobUpvoter],
              )
              ..['sortAt'] = '2026-10-08T11:30:00.000Z'
              ..['isRead'] = false,
            _reply('later', sortAt: '2026-10-08T12:15:00.000Z', isRead: true),
          ],
          cursor: 'c2',
          seenAt: '2026-10-08T13:00:00.000Z',
        ),
      );
      await _loadMore(
        harness,
        _page([
          _reply('page3', sortAt: '2026-10-08T12:30:00.000Z', isRead: true),
        ]),
      );

      expect(_readState(harness.provider), {
        _replyUri('p1'): true,
        _replyUri('equal'): true,
        commentUri: true,
        _replyUri('later'): false,
        _replyUri('page3'): false,
      });

      final rows = harness.provider.controller.items;
      final equalReply = rows.singleWhere(
        (row) => row.record?.uri == _replyUri('equal'),
      );
      expect(equalReply.author!.did, 'did:plc:writer');
      expect(equalReply.sortAt, '2026-10-08T12:00:00.000Z');
      final upvote = rows.singleWhere(
        (row) => row.reason == NotificationReason.upvote,
      );
      expect(upvote.subject!.uri, commentUri);
      expect(upvote.upvoteCount, 4);
      expect(
        [for (final upvoter in upvote.recentUpvoters) upvoter.did],
        ['did:plc:alice', 'did:plc:bob'],
      );
    } finally {
      harness.dispose();
    }
  });

  test('B2 later-page rows compare against seenAt at full fractional '
      'precision', () async {
    final harness = NotificationsListProviderHarness();
    try {
      await _loadFirstPage(
        harness,
        _page(
          [_reply('p1', sortAt: '2026-10-08T11:00:00.000Z', isRead: true)],
          cursor: 'c1',
          seenAt: '2026-10-08T12:00:00.1234567Z',
        ),
      );
      await _loadMore(
        harness,
        _page([
          _reply('after', sortAt: '2026-10-08T12:00:00.1234568Z', isRead: true),
          _reply(
            'before',
            sortAt: '2026-10-08T12:00:00.1234566Z',
            isRead: false,
          ),
        ]),
      );

      expect(_readState(harness.provider), {
        _replyUri('p1'): true,
        _replyUri('after'): false,
        _replyUri('before'): true,
      });
    } finally {
      harness.dispose();
    }
  });

  test('B3 without a page-one seenAt every later-page row is read', () async {
    final harness = NotificationsListProviderHarness();
    try {
      await _loadFirstPage(
        harness,
        _page([
          _reply('p1', sortAt: '2026-10-08T12:00:00.000Z', isRead: false),
        ], cursor: 'c1'),
      );
      await _loadMore(
        harness,
        _page([
          _reply('newer', sortAt: '2026-10-08T13:00:00.000Z', isRead: false),
          _reply('older', sortAt: '2026-10-07T12:00:00.000Z', isRead: false),
        ], cursor: 'c2'),
      );
      await _loadMore(
        harness,
        _page([
          _reply('newest', sortAt: '2026-10-09T12:00:00.000Z', isRead: false),
        ]),
      );

      expect(_readState(harness.provider), {
        _replyUri('p1'): false,
        _replyUri('newer'): true,
        _replyUri('older'): true,
        _replyUri('newest'): true,
      });
    } finally {
      harness.dispose();
    }
  });

  test('B4 page-one rows keep the server isRead, also after page two '
      'loads', () async {
    final harness = NotificationsListProviderHarness();
    try {
      await _loadFirstPage(
        harness,
        _page(
          [
            _reply('later', sortAt: '2026-10-08T13:00:00.000Z', isRead: true),
            _reply(
              'earlier',
              sortAt: '2026-10-08T11:00:00.000Z',
              isRead: false,
            ),
          ],
          cursor: 'c1',
          seenAt: '2026-10-08T12:00:00.000Z',
        ),
      );
      expect(_readState(harness.provider), {
        _replyUri('later'): true,
        _replyUri('earlier'): false,
      });

      await _loadMore(
        harness,
        _page([_reply('p2', sortAt: '2026-10-08T10:00:00.000Z', isRead: true)]),
      );
      final readState = _readState(harness.provider);
      expect(readState[_replyUri('later')], isTrue);
      expect(readState[_replyUri('earlier')], isFalse);
    } finally {
      harness.dispose();
    }
  });

  test('B5a pull-to-refresh replaces the seenAt later pages use and keeps '
      'the reloaded page-one server isRead', () async {
    final harness = NotificationsListProviderHarness();
    try {
      await _loadFirstPage(
        harness,
        _page(
          [_reply('p1', sortAt: '2026-10-08T11:00:00.000Z', isRead: true)],
          cursor: 'c1',
          seenAt: '2026-10-08T12:00:00.000Z',
        ),
      );
      await _loadMore(
        harness,
        _page([
          _reply('before', sortAt: '2026-10-08T12:30:00.000Z', isRead: true),
        ]),
      );
      expect(_readState(harness.provider)[_replyUri('before')], isFalse);

      // The reloaded page one is not recomputed against the old 12:00
      // boundary: a row after it stays read and a row before it stays unread.
      final refreshed = harness.provider.refresh();
      harness.responses.last.complete(
        _page(
          [
            _reply(
              'readAfterOldBoundary',
              sortAt: '2026-10-08T12:15:00.000Z',
              isRead: true,
            ),
            _reply('p1', sortAt: '2026-10-08T11:00:00.000Z', isRead: false),
          ],
          cursor: 'c1',
          seenAt: '2026-10-08T13:00:00.000Z',
        ),
      );
      expect(await refreshed, isTrue);
      expect(_readState(harness.provider), {
        _replyUri('readAfterOldBoundary'): true,
        _replyUri('p1'): false,
      });

      await _loadMore(
        harness,
        _page([
          _reply('after', sortAt: '2026-10-08T12:30:00.000Z', isRead: false),
        ]),
      );

      expect(_readState(harness.provider), {
        _replyUri('readAfterOldBoundary'): true,
        _replyUri('p1'): false,
        _replyUri('after'): true,
      });
    } finally {
      harness.dispose();
    }
  });

  test(
    'B5b InvalidCursor recovery replaces the seenAt later pages use',
    () async {
      final harness = NotificationsListProviderHarness();
      try {
        await _loadFirstPage(
          harness,
          _page(
            [_reply('p1', sortAt: '2026-10-08T11:00:00.000Z', isRead: true)],
            cursor: 'c1',
            seenAt: '2026-10-08T12:00:00.000Z',
          ),
        );
        final rejectedMore = harness.provider.loadMore();
        harness.responses.last.completeError(
          ApiException('expired', statusCode: 400, errorCode: 'InvalidCursor'),
        );
        await settle();
        harness.responses.last.complete(
          _page(
            [_reply('p1', sortAt: '2026-10-08T11:00:00.000Z', isRead: true)],
            cursor: 'c2',
            seenAt: '2026-10-08T13:00:00.000Z',
          ),
        );
        await rejectedMore;
        await settle();
        expect(harness.provider.controller.loadMoreError, isNull);

        await _loadMore(
          harness,
          _page([
            _reply(
              'between',
              sortAt: '2026-10-08T12:30:00.000Z',
              isRead: false,
            ),
          ]),
        );

        expect(_readState(harness.provider), {
          _replyUri('p1'): true,
          _replyUri('between'): true,
        });
      } finally {
        harness.dispose();
      }
    },
  );

  test('B5c an account switch replaces the seenAt later pages use', () async {
    final cases = <({String? bobSeenAt, Map<String, bool> expected})>[
      (
        bobSeenAt: null,
        expected: {_replyUri('bobP1'): true, _replyUri('oct5'): true},
      ),
      (
        bobSeenAt: '2026-10-09T00:00:00.000Z',
        expected: {
          _replyUri('bobP1'): true,
          _replyUri('oct5'): true,
          _replyUri('oct10'): false,
        },
      ),
    ];
    for (final testCase in cases) {
      final harness = NotificationsListProviderHarness();
      try {
        await _loadFirstPage(
          harness,
          _page(
            [
              _reply(
                'aliceP1',
                sortAt: '2026-09-30T00:00:00.000Z',
                isRead: true,
              ),
            ],
            cursor: 'c1',
            seenAt: '2026-10-01T00:00:00.000Z',
          ),
        );

        harness.auth.setSignedInDid('did:plc:bob');
        harness.responses.last.complete(
          _page(
            [_reply('bobP1', sortAt: '2026-10-04T00:00:00.000Z', isRead: true)],
            cursor: 'cB',
            seenAt: testCase.bobSeenAt,
          ),
        );
        await settle();
        expect(_readState(harness.provider).keys, [_replyUri('bobP1')]);

        await _loadMore(
          harness,
          _page([
            _reply('oct5', sortAt: '2026-10-05T00:00:00.000Z', isRead: false),
            if (testCase.bobSeenAt != null)
              _reply('oct10', sortAt: '2026-10-10T00:00:00.000Z', isRead: true),
          ]),
        );

        expect(
          _readState(harness.provider),
          testCase.expected,
          reason: 'bob seenAt ${testCase.bobSeenAt}',
        );
      } finally {
        harness.dispose();
      }
    }
  });

  test('B5d marking page one seen does not move the later-page '
      'boundary', () async {
    final harness = NotificationsListProviderHarness();
    when(harness.api.updateNotificationsSeen(seenAt: anyNamed('seenAt')))
        .thenAnswer((_) async {});
    try {
      await _loadFirstPage(
        harness,
        _page(
          [
            _reply('noon', sortAt: '2026-10-08T12:00:00.000Z', isRead: false),
            _reply('three', sortAt: '2026-10-08T03:00:00.000Z', isRead: false),
          ],
          cursor: 'c1',
          seenAt: '2026-10-08T00:00:00.000Z',
        ),
      );
      await harness.provider.markPageOneSeen();
      verify(
        harness.api.updateNotificationsSeen(seenAt: '2026-10-08T12:00:00.000Z'),
      );

      await _loadMore(
        harness,
        _page([
          _reply('six', sortAt: '2026-10-08T06:00:00.000Z', isRead: true),
        ]),
      );

      expect(_readState(harness.provider)[_replyUri('six')], isFalse);
    } finally {
      harness.dispose();
    }
  });

  test('B6 a superseded page-one response never sets the seenAt later pages '
      'use', () async {
    final cases =
        <
          ({
            String name,
            Future<void> Function(NotificationsListProviderHarness harness)
            landPageOnes,
            String laterSortAt,
          })
        >[
          (
            name: 'stale page one from the previous account',
            landPageOnes: (harness) async {
              harness.provider.requestFirstPage();
              final alicePageOne = harness.responses[0];

              harness.auth.setSignedInDid('did:plc:bob');
              harness.responses[1].complete(
                _page([
                  _reply(
                    'bobP1',
                    sortAt: '2026-10-04T00:00:00.000Z',
                    isRead: true,
                  ),
                ], cursor: 'cB'),
              );
              await settle();

              alicePageOne.complete(
                _page(
                  [
                    _reply(
                      'aliceP1',
                      sortAt: '2026-09-30T00:00:00.000Z',
                      isRead: true,
                    ),
                  ],
                  cursor: 'cA',
                  seenAt: '2026-10-01T00:00:00.000Z',
                ),
              );
              await settle();
              expect(_readState(harness.provider).keys, [_replyUri('bobP1')]);
            },
            laterSortAt: '2026-10-05T00:00:00.000Z',
          ),
          (
            name: 'older of two overlapping refreshes lands last',
            landPageOnes: (harness) async {
              await _loadFirstPage(
                harness,
                _page(
                  [
                    _reply(
                      'p1',
                      sortAt: '2026-10-06T00:00:00.000Z',
                      isRead: true,
                    ),
                  ],
                  cursor: 'c1',
                  seenAt: '2026-10-07T00:00:00.000Z',
                ),
              );

              final olderRefresh = harness.provider.refresh();
              final olderPageOne = harness.responses[1];
              final newerRefresh = harness.provider.refresh();

              harness.responses[2].complete(
                _page(
                  [
                    _reply(
                      'p1',
                      sortAt: '2026-10-06T00:00:00.000Z',
                      isRead: true,
                    ),
                  ],
                  cursor: 'c2',
                  seenAt: '2026-10-09T00:00:00.000Z',
                ),
              );
              expect(await newerRefresh, isTrue);
              olderPageOne.complete(
                _page(
                  [
                    _reply(
                      'p1',
                      sortAt: '2026-10-06T00:00:00.000Z',
                      isRead: true,
                    ),
                  ],
                  cursor: 'c1',
                  seenAt: '2026-10-08T00:00:00.000Z',
                ),
              );
              expect(await olderRefresh, isFalse);
              await settle();
            },
            laterSortAt: '2026-10-08T12:00:00.000Z',
          ),
        ];

    for (final testCase in cases) {
      final harness = NotificationsListProviderHarness();
      try {
        await testCase.landPageOnes(harness);

        await _loadMore(
          harness,
          _page([_reply('later', sortAt: testCase.laterSortAt, isRead: false)]),
        );

        expect(
          _readState(harness.provider)[_replyUri('later')],
          isTrue,
          reason: testCase.name,
        );
      } finally {
        harness.dispose();
      }
    }
  });

  test('B7 an unparseable later-page sortAt does not stop the page '
      'loading and keeps the server isRead', () async {
    final harness = NotificationsListProviderHarness();
    try {
      await _loadFirstPage(
        harness,
        _page(
          [_reply('p1', sortAt: '2026-10-08T11:00:00.000Z', isRead: true)],
          cursor: 'c1',
          seenAt: '2026-10-08T12:00:00.000Z',
        ),
      );
      await _loadMore(
        harness,
        _page([
          _reply('malformedUnread', sortAt: 'not-a-time', isRead: false),
          _reply('malformedRead', sortAt: 'also-not-a-time', isRead: true),
          _reply('later', sortAt: '2026-10-08T13:00:00.000Z', isRead: true),
          _reply('earlier', sortAt: '2026-10-08T11:30:00.000Z', isRead: false),
        ]),
      );

      expect(harness.provider.controller.loadMoreError, isNull);
      final readState = _readState(harness.provider);
      expect(readState[_replyUri('malformedUnread')], isFalse);
      expect(readState[_replyUri('malformedRead')], isTrue);
      expect(readState[_replyUri('later')], isFalse);
      expect(readState[_replyUri('earlier')], isTrue);
    } finally {
      harness.dispose();
    }
  });
}
