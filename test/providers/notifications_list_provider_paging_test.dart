import 'dart:async';

import 'package:coves_flutter/models/notification.dart';
import 'package:coves_flutter/providers/notifications_list_provider.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/notifications_list_provider_harness.dart';
import '../test_helpers/reply_notification_fixture.dart';
import '../test_helpers/upvote_notification_fixture.dart';

const _replyOne = harnessFirstPageReplyUri;
const _replyTwo = 'at://did:plc:alice/social.coves.community.comment/r2';
const _bobReply = 'at://did:plc:bob/social.coves.community.comment/rB';

Map<String, dynamic> _reply(String uri) =>
    replyNotificationWireFor(recordUri: uri, rootUri: postUri);

NotificationPage _page(List<Map<String, dynamic>> rows, {String? cursor}) =>
    NotificationPage.fromJson({'notifications': rows, 'cursor': cursor});

List<String> _recordUris(NotificationsListProvider provider) => [
  for (final notification in provider.controller.items)
    notification.record!.uri,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('B3 InvalidCursor reloads page one once and stops after a second '
      'InvalidCursor', () async {
    final harness = NotificationsListProviderHarness();
    try {
      await harness.firstPage();
      final firstMore = harness.provider.loadMore();
      harness.expectRequests([
        (cursor: null, did: 'did:plc:alice'),
        (cursor: 'c1', did: 'did:plc:alice'),
      ]);
      harness.responses[1].completeError(
        ApiException('expired', statusCode: 400, errorCode: 'InvalidCursor'),
      );
      await settle();
      harness.expectRequests([
        (cursor: null, did: 'did:plc:alice'),
        (cursor: 'c1', did: 'did:plc:alice'),
        (cursor: null, did: 'did:plc:alice'),
      ]);
      harness.responses[2].complete(_page([_reply(_replyTwo)], cursor: 'c2'));
      await firstMore;
      await settle();
      expect(_recordUris(harness.provider), [_replyTwo]);
      expect(harness.provider.controller.loadMoreError, isNull);
      expect(harness.provider.controller.error, isNull);

      final secondMore = harness.provider.loadMore();
      harness.expectRequests([
        (cursor: null, did: 'did:plc:alice'),
        (cursor: 'c1', did: 'did:plc:alice'),
        (cursor: null, did: 'did:plc:alice'),
        (cursor: 'c2', did: 'did:plc:alice'),
      ]);
      harness.responses[3].completeError(
        ApiException(
          'expired again',
          statusCode: 400,
          errorCode: 'InvalidCursor',
        ),
      );
      await settle();
      expect(harness.requests, hasLength(4));
      await secondMore;
      expect(harness.provider.controller.loadMoreError, isNotNull);
      unawaited(harness.provider.loadMore());
      await settle();
      expect(harness.requests, hasLength(4));

      final retry = harness.provider.retryLoadMore();
      harness.expectRequests([
        (cursor: null, did: 'did:plc:alice'),
        (cursor: 'c1', did: 'did:plc:alice'),
        (cursor: null, did: 'did:plc:alice'),
        (cursor: 'c2', did: 'did:plc:alice'),
        (cursor: null, did: 'did:plc:alice'),
      ]);
      harness.responses[4].complete(_page([_reply(_replyOne)], cursor: 'c1'));
      await retry;
      expect(_recordUris(harness.provider), [_replyOne]);
      expect(harness.provider.controller.loadMoreError, isNull);
      expect(harness.provider.controller.error, isNull);
    } finally {
      harness.dispose();
    }
  });

  test(
    'B3 a cursor rejected again after automatic paging does not reload '
    'page one without a gesture, and pull-to-refresh re-arms recovery',
    () async {
      final harness = NotificationsListProviderHarness();
      try {
        await harness.firstPage();
        final firstMore = harness.provider.loadMore();
        harness.expectRequests([
          (cursor: null, did: 'did:plc:alice'),
          (cursor: 'c1', did: 'did:plc:alice'),
        ]);
        harness.responses[1].complete(_page([_reply(_replyTwo)], cursor: 'c2'));
        await firstMore;
        expect(_recordUris(harness.provider), [_replyOne, _replyTwo]);

        final rejectedMore = harness.provider.loadMore();
        harness.expectRequests([
          (cursor: null, did: 'did:plc:alice'),
          (cursor: 'c1', did: 'did:plc:alice'),
          (cursor: 'c2', did: 'did:plc:alice'),
        ]);
        harness.responses[2].completeError(
          ApiException('expired', statusCode: 400, errorCode: 'InvalidCursor'),
        );
        await settle();
        harness.expectRequests([
          (cursor: null, did: 'did:plc:alice'),
          (cursor: 'c1', did: 'did:plc:alice'),
          (cursor: 'c2', did: 'did:plc:alice'),
          (cursor: null, did: 'did:plc:alice'),
        ]);
        harness.responses[3].complete(_page([_reply(_replyOne)], cursor: 'c1'));
        await rejectedMore;
        await settle();
        expect(_recordUris(harness.provider), [_replyOne]);
        expect(harness.provider.controller.loadMoreError, isNull);

        final automaticMore = harness.provider.loadMore();
        harness.expectRequests([
          (cursor: null, did: 'did:plc:alice'),
          (cursor: 'c1', did: 'did:plc:alice'),
          (cursor: 'c2', did: 'did:plc:alice'),
          (cursor: null, did: 'did:plc:alice'),
          (cursor: 'c1', did: 'did:plc:alice'),
        ]);
        harness.responses[4].complete(_page([_reply(_replyTwo)], cursor: 'c2'));
        await automaticMore;
        expect(_recordUris(harness.provider), [_replyOne, _replyTwo]);

        final rejectedAgain = harness.provider.loadMore();
        harness.expectRequests([
          (cursor: null, did: 'did:plc:alice'),
          (cursor: 'c1', did: 'did:plc:alice'),
          (cursor: 'c2', did: 'did:plc:alice'),
          (cursor: null, did: 'did:plc:alice'),
          (cursor: 'c1', did: 'did:plc:alice'),
          (cursor: 'c2', did: 'did:plc:alice'),
        ]);
        harness.responses[5].completeError(
          ApiException(
            'expired again',
            statusCode: 400,
            errorCode: 'InvalidCursor',
          ),
        );
        await settle();
        expect(harness.requests, hasLength(6));
        await rejectedAgain;
        expect(_recordUris(harness.provider), [_replyOne, _replyTwo]);
        expect(harness.provider.controller.loadMoreError, isNotNull);
        expect(harness.provider.controller.error, isNull);
        unawaited(harness.provider.loadMore());
        await settle();
        expect(harness.requests, hasLength(6));

        // Pull-to-refresh is a gesture: it re-arms the one-shot recovery.
        final refreshed = harness.provider.refresh();
        harness.expectRequests([
          (cursor: null, did: 'did:plc:alice'),
          (cursor: 'c1', did: 'did:plc:alice'),
          (cursor: 'c2', did: 'did:plc:alice'),
          (cursor: null, did: 'did:plc:alice'),
          (cursor: 'c1', did: 'did:plc:alice'),
          (cursor: 'c2', did: 'did:plc:alice'),
          (cursor: null, did: 'did:plc:alice'),
        ]);
        harness.responses[6].complete(_page([_reply(_replyOne)], cursor: 'c1'));
        expect(await refreshed, isTrue);
        expect(_recordUris(harness.provider), [_replyOne]);

        final rejectedAfterRefresh = harness.provider.loadMore();
        harness.responses[7].completeError(
          ApiException('expired', statusCode: 400, errorCode: 'InvalidCursor'),
        );
        await settle();
        harness.expectRequests([
          (cursor: null, did: 'did:plc:alice'),
          (cursor: 'c1', did: 'did:plc:alice'),
          (cursor: 'c2', did: 'did:plc:alice'),
          (cursor: null, did: 'did:plc:alice'),
          (cursor: 'c1', did: 'did:plc:alice'),
          (cursor: 'c2', did: 'did:plc:alice'),
          (cursor: null, did: 'did:plc:alice'),
          (cursor: 'c1', did: 'did:plc:alice'),
          (cursor: null, did: 'did:plc:alice'),
        ]);
        harness.responses[8].complete(_page([_reply(_replyTwo)], cursor: 'c2'));
        await rejectedAfterRefresh;
        await settle();
        expect(_recordUris(harness.provider), [_replyTwo]);
        expect(harness.provider.controller.loadMoreError, isNull);

        // Refresh also dropped the pending page-one Retry: a server failure on
        // the next page is retried at its own cursor.
        final failedMore = harness.provider.loadMore();
        harness.responses[9].completeError(ServerException('unavailable'));
        await failedMore;
        expect(harness.provider.controller.loadMoreError, isNotNull);

        final retry = harness.provider.retryLoadMore();
        harness.expectRequests([
          (cursor: null, did: 'did:plc:alice'),
          (cursor: 'c1', did: 'did:plc:alice'),
          (cursor: 'c2', did: 'did:plc:alice'),
          (cursor: null, did: 'did:plc:alice'),
          (cursor: 'c1', did: 'did:plc:alice'),
          (cursor: 'c2', did: 'did:plc:alice'),
          (cursor: null, did: 'did:plc:alice'),
          (cursor: 'c1', did: 'did:plc:alice'),
          (cursor: null, did: 'did:plc:alice'),
          (cursor: 'c2', did: 'did:plc:alice'),
          (cursor: 'c2', did: 'did:plc:alice'),
        ]);
        harness.responses[10].complete(_page([_reply(_replyOne)]));
        await retry;
        expect(_recordUris(harness.provider), [_replyTwo, _replyOne]);
        expect(harness.provider.controller.loadMoreError, isNull);
      } finally {
        harness.dispose();
      }
    },
  );

  test('B3 InvalidRequest on a later page sets a footer error without '
      'recovery', () async {
    final harness = NotificationsListProviderHarness();
    try {
      await harness.firstPage();
      final more = harness.provider.loadMore();
      harness.expectRequests([
        (cursor: null, did: 'did:plc:alice'),
        (cursor: 'c1', did: 'did:plc:alice'),
      ]);
      harness.responses[1].completeError(
        ApiException(
          'bad request',
          statusCode: 400,
          errorCode: 'InvalidRequest',
        ),
      );
      await settle();
      expect(harness.requests, hasLength(2));
      await more;
      expect(_recordUris(harness.provider), [_replyOne]);
      expect(harness.provider.controller.loadMoreError, isNotNull);
      expect(harness.provider.controller.error, isNull);
      expect(harness.requests, hasLength(2));
    } finally {
      harness.dispose();
    }
  });

  test('B3 retry of a server failure recovers InvalidCursor with one '
      'replacement page', () async {
    final harness = NotificationsListProviderHarness();
    try {
      await harness.firstPage();
      final more = harness.provider.loadMore();
      harness.expectRequests([
        (cursor: null, did: 'did:plc:alice'),
        (cursor: 'c1', did: 'did:plc:alice'),
      ]);
      harness.responses[1].completeError(ServerException('unavailable'));
      await settle();
      expect(harness.requests, hasLength(2));
      await more;
      expect(harness.provider.controller.loadMoreError, isNotNull);

      final retry = harness.provider.retryLoadMore();
      harness.expectRequests([
        (cursor: null, did: 'did:plc:alice'),
        (cursor: 'c1', did: 'did:plc:alice'),
        (cursor: 'c1', did: 'did:plc:alice'),
      ]);
      harness.responses[2].completeError(
        ApiException('expired', statusCode: 400, errorCode: 'InvalidCursor'),
      );
      await settle();
      harness.expectRequests([
        (cursor: null, did: 'did:plc:alice'),
        (cursor: 'c1', did: 'did:plc:alice'),
        (cursor: 'c1', did: 'did:plc:alice'),
        (cursor: null, did: 'did:plc:alice'),
      ]);
      harness.responses[3].complete(_page([_reply(_replyTwo)], cursor: 'c2'));
      await retry;
      await settle();
      expect(_recordUris(harness.provider), [_replyTwo]);
      expect(harness.provider.controller.loadMoreError, isNull);
      expect(harness.provider.controller.error, isNull);
      expect(harness.requests, hasLength(4));
    } finally {
      harness.dispose();
    }
  });

  test(
    'B4 failed recovery keeps rows and footer Retry reloads page one once',
    () async {
      final harness = NotificationsListProviderHarness();
      try {
        await harness.firstPage();
        final more = harness.provider.loadMore();
        harness.expectRequests([
          (cursor: null, did: 'did:plc:alice'),
          (cursor: 'c1', did: 'did:plc:alice'),
        ]);
        harness.responses[1].completeError(
          ApiException('expired', statusCode: 400, errorCode: 'InvalidCursor'),
        );
        await settle();
        harness.expectRequests([
          (cursor: null, did: 'did:plc:alice'),
          (cursor: 'c1', did: 'did:plc:alice'),
          (cursor: null, did: 'did:plc:alice'),
        ]);
        harness.responses[2].completeError(ServerException('unavailable'));
        await settle();
        expect(harness.requests, hasLength(3));
        await more;
        expect(_recordUris(harness.provider), [_replyOne]);
        expect(harness.provider.controller.loadMoreError, isNotNull);
        expect(harness.provider.controller.error, isNull);
        unawaited(harness.provider.loadMore());
        await settle();
        expect(harness.requests, hasLength(3));

        final retry = harness.provider.retryLoadMore();
        harness.expectRequests([
          (cursor: null, did: 'did:plc:alice'),
          (cursor: 'c1', did: 'did:plc:alice'),
          (cursor: null, did: 'did:plc:alice'),
          (cursor: null, did: 'did:plc:alice'),
        ]);
        harness.responses[3].complete(_page([_reply(_replyTwo)], cursor: 'c2'));
        await retry;
        expect(_recordUris(harness.provider), [_replyTwo]);
        expect(harness.provider.controller.loadMoreError, isNull);
        expect(harness.provider.controller.error, isNull);

        // The page-one Retry is spent: a server failure on the next page is
        // retried at its own cursor, keeping the rows already loaded.
        final failedMore = harness.provider.loadMore();
        harness.responses[4].completeError(ServerException('unavailable'));
        await failedMore;
        expect(harness.provider.controller.loadMoreError, isNotNull);

        final secondRetry = harness.provider.retryLoadMore();
        harness.expectRequests([
          (cursor: null, did: 'did:plc:alice'),
          (cursor: 'c1', did: 'did:plc:alice'),
          (cursor: null, did: 'did:plc:alice'),
          (cursor: null, did: 'did:plc:alice'),
          (cursor: 'c2', did: 'did:plc:alice'),
          (cursor: 'c2', did: 'did:plc:alice'),
        ]);
        harness.responses[5].complete(_page([_reply(_replyOne)]));
        await secondRetry;
        expect(_recordUris(harness.provider), [_replyTwo, _replyOne]);
        expect(harness.provider.controller.loadMoreError, isNull);
      } finally {
        harness.dispose();
      }
    },
  );

  test('B5 overlapping upvote group keeps its first count and appends '
      'new replies', () async {
    final harness = NotificationsListProviderHarness();
    try {
      harness.provider.requestFirstPage();
      harness.expectRequests([(cursor: null, did: 'did:plc:alice')]);
      harness.responses[0].complete(
        _page([upvoteWire(count: 3), _reply(_replyOne)], cursor: 'c1'),
      );
      await settle();

      final more = harness.provider.loadMore();
      harness.expectRequests([
        (cursor: null, did: 'did:plc:alice'),
        (cursor: 'c1', did: 'did:plc:alice'),
      ]);
      harness.responses[1].complete(
        _page([upvoteWire(count: 9), _reply(_replyTwo)]),
      );
      await more;

      final rows = harness.provider.controller.items;
      expect(rows, hasLength(3));
      expect(
        rows[0].subject!.uri,
        'at://did:plc:me/social.coves.community.postv2/3kpost',
      );
      expect(rows[0].upvoteCount, 3);
      expect(
        rows[1].record!.uri,
        'at://did:plc:alice/social.coves.community.comment/r1',
      );
      expect(
        rows[2].record!.uri,
        'at://did:plc:alice/social.coves.community.comment/r2',
      );
    } finally {
      harness.dispose();
    }
  });

  test('B6 sign-out blocks loadMore, footer Retry and refresh', () async {
    final harness = NotificationsListProviderHarness();
    try {
      await harness.firstPage();
      final more = harness.provider.loadMore();
      harness.expectRequests([
        (cursor: null, did: 'did:plc:alice'),
        (cursor: 'c1', did: 'did:plc:alice'),
      ]);
      harness.responses[1].completeError(ServerException('unavailable'));
      await more;
      expect(harness.provider.controller.loadMoreError, isNotNull);

      harness.auth.setSignedInDid(null);
      unawaited(harness.provider.loadMore());
      unawaited(harness.provider.retryLoadMore());
      unawaited(harness.provider.refresh());
      await settle();
      expect(harness.requests, hasLength(2));
    } finally {
      harness.dispose();
    }
  });

  test(
    'B6 account B page replaces A while A load-more remains pending',
    () async {
      final harness = NotificationsListProviderHarness();
      try {
        await harness.firstPage();
        final oldMore = harness.provider.loadMore();
        harness.expectRequests([
          (cursor: null, did: 'did:plc:alice'),
          (cursor: 'c1', did: 'did:plc:alice'),
        ]);
        harness.auth.setSignedInDid('did:plc:bob');
        harness.expectRequests([
          (cursor: null, did: 'did:plc:alice'),
          (cursor: 'c1', did: 'did:plc:alice'),
          (cursor: null, did: 'did:plc:bob'),
        ]);
        harness.responses[2].complete(_page([_reply(_bobReply)], cursor: 'cB'));
        await settle();
        expect(_recordUris(harness.provider), [_bobReply]);

        harness.responses[1].complete(_page([_reply(_replyTwo)]));
        await oldMore;
        await settle();
        expect(_recordUris(harness.provider), [_bobReply]);
        expect(harness.provider.controller.error, isNull);
        expect(harness.provider.controller.loadMoreError, isNull);
        expect(harness.requests, hasLength(3));
      } finally {
        harness.dispose();
      }
    },
  );

  test(
    'B6 InvalidCursor from A after sign-out cannot start recovery',
    () async {
      final harness = NotificationsListProviderHarness();
      try {
        await harness.firstPage();
        final oldMore = harness.provider.loadMore();
        harness.expectRequests([
          (cursor: null, did: 'did:plc:alice'),
          (cursor: 'c1', did: 'did:plc:alice'),
        ]);
        harness.auth.setSignedInDid(null);
        harness.responses[1].completeError(
          ApiException('expired', statusCode: 400, errorCode: 'InvalidCursor'),
        );
        await settle();
        expect(harness.requests, hasLength(2));
        await oldMore;
        expect(harness.provider.controller.items, isEmpty);
        expect(harness.provider.controller.loadMoreError, isNull);
        expect(harness.provider.controller.error, isNull);
      } finally {
        harness.dispose();
      }
    },
  );
}
