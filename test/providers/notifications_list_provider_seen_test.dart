import 'dart:async';

import 'package:coves_flutter/models/notification.dart';
import 'package:coves_flutter/providers/notifications_list_provider.dart';
import 'package:coves_flutter/providers/unread_notification_count_provider.dart';
import 'package:coves_flutter/providers/viewer_authority_provider.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/reply_notification_fixture.dart';
import '../test_helpers/test_mocks.dart';
import '../test_helpers/unread_count_refresh_spy.dart';
import '../test_helpers/upvote_notification_fixture.dart';

const _aliceRow = 'at://did:plc:alice/social.coves.community.comment/seen-a';
const _secondRow = 'at://did:plc:alice/social.coves.community.comment/seen-2';
const _thirdRow = 'at://did:plc:alice/social.coves.community.comment/seen-3';
const _fourthRow = 'at://did:plc:alice/social.coves.community.comment/seen-4';
const _bobRow = 'at://did:plc:bob/social.coves.community.comment/seen-b';

Map<String, dynamic> _row(String uri, String sortAt) =>
    replyNotificationWireFor(recordUri: uri, rootUri: postUri)
      ..['sortAt'] = sortAt;

NotificationPage _page(List<Map<String, dynamic>> rows, {String? cursor}) =>
    NotificationPage.fromJson({'notifications': rows, 'cursor': cursor});

List<String> _recordUris(NotificationsListProvider provider) => [
  for (final row in provider.controller.items) row.record!.uri,
];

Future<void> _settle() async {
  for (var turn = 0; turn < 3; turn++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _SeenHarness {
  _SeenHarness({bool realCount = false}) {
    when(api.listNotifications(cursor: anyNamed('cursor'))).thenAnswer((call) {
      requests.add((
        cursor: call.namedArguments[#cursor] as String?,
        did: auth.did,
      ));
      final response = Completer<NotificationPage>();
      pages.add(response);
      return response.future;
    });
    when(api.updateNotificationsSeen(seenAt: anyNamed('seenAt'))).thenAnswer((
      call,
    ) {
      sent.add((seenAt: call.namedArguments[#seenAt] as String, did: auth.did));
      final response = Completer<void>();
      updates.add(response);
      return response.future;
    });
    if (realCount) {
      when(api.getUnreadCount()).thenAnswer((_) {
        final response = Completer<int>();
        countResponses.add(response);
        return response.future;
      });
    }
    unreadCount = realCount
        ? UnreadNotificationCountProvider(apiService: api, authProvider: auth)
        : UnreadCountRefreshSpy();
    when(api.getViewerAuthority()).thenAnswer((_) async => false);
    authority = ViewerAuthorityProvider(apiService: api, authProvider: auth);
    provider = NotificationsListProvider(
      apiService: api,
      authProvider: auth,
      sessionKeyOf: () => authority.sessionKey,
      unreadNotificationCountProvider: unreadCount,
      reportError: (error, stack) => reported.add(error),
    );
  }

  final auth = FakeAuthProvider(signedInDid: 'did:plc:alice');
  final api = MockCovesApiService();
  late final UnreadNotificationCountProvider unreadCount;
  late final ViewerAuthorityProvider authority;
  late final NotificationsListProvider provider;
  final requests = <({String? cursor, String? did})>[];
  final pages = <Completer<NotificationPage>>[];
  final sent = <({String seenAt, String? did})>[];
  final updates = <Completer<void>>[];
  final countResponses = <Completer<int>>[];
  final reported = <Object>[];

  Future<void> land(
    int request,
    List<Map<String, dynamic>> rows, {
    String? cursor,
  }) async {
    pages[request].complete(_page(rows, cursor: cursor));
    await _settle();
  }

  void dispose() {
    provider.dispose();
    unreadCount.dispose();
    authority.dispose();
    auth.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'B6 marks the latest page-one instant once and refetches the real count',
    () async {
      final harness = _SeenHarness(realCount: true);
      try {
        expect(harness.countResponses, hasLength(1));
        harness.countResponses[0].complete(3);
        await _settle();
        expect(harness.unreadCount.count, 3);

        harness.provider.requestFirstPage();
        expect(harness.requests, [(cursor: null, did: 'did:plc:alice')]);
        await harness.land(0, [
          _row(_aliceRow, '2026-10-08T12:00:00.5Z'),
          _row(_secondRow, '2026-10-08T08:00:01-04:00'),
          _row(_fourthRow, '2026-10-08T11:59:59Z'),
        ], cursor: 'c1');
        final more = harness.provider.loadMore();
        expect(harness.requests, [
          (cursor: null, did: 'did:plc:alice'),
          (cursor: 'c1', did: 'did:plc:alice'),
        ]);
        await harness.land(1, [_row(_thirdRow, '2026-10-08T12:30:00Z')]);
        await more;

        final marking = harness.provider.markPageOneSeen();
        await _settle();
        expect(harness.sent, [
          (seenAt: '2026-10-08T08:00:01-04:00', did: 'did:plc:alice'),
        ]);
        expect(harness.unreadCount.count, 3);
        harness.updates.single.complete();
        await marking;
        await _settle();
        expect(harness.countResponses, hasLength(2));
        expect(harness.unreadCount.count, 3);
        harness.countResponses[1].complete(0);
        await _settle();
        expect(harness.unreadCount.count, 0);
        unawaited(harness.provider.markPageOneSeen());
        await _settle();
        expect(harness.sent, [
          (seenAt: '2026-10-08T08:00:01-04:00', did: 'did:plc:alice'),
        ]);
        expect(harness.countResponses, hasLength(2));
      } finally {
        harness.dispose();
      }
    },
  );

  for (final (name, error, shouldReport) in [
    ('server failure', ServerException('unavailable'), true),
    ('network failure', NetworkException('offline'), true),
    (
      'AccountNotIndexed',
      ApiException('x', statusCode: 400, errorCode: 'AccountNotIndexed'),
      false,
    ),
  ]) {
    test('B7 $name spends the mark without changing the list', () async {
      final harness = _SeenHarness();
      try {
        harness.provider.requestFirstPage();
        await harness.land(0, [_row(_aliceRow, '2026-10-08T10:00:00Z')]);
        final marking = harness.provider.markPageOneSeen();
        await _settle();
        expect(harness.sent, [
          (seenAt: '2026-10-08T10:00:00Z', did: 'did:plc:alice'),
        ]);
        harness.updates.single.completeError(error);
        await marking;
        await _settle();
        expect(harness.reported, shouldReport ? [same(error)] : isEmpty);
        expect(_recordUris(harness.provider), [_aliceRow]);
        expect(harness.provider.controller.error, isNull);
        expect(harness.provider.controller.loadMoreError, isNull);
        expect((harness.unreadCount as UnreadCountRefreshSpy).refreshCalls, 0);
        unawaited(harness.provider.markPageOneSeen());
        await _settle();
        expect(harness.sent, hasLength(1));
      } finally {
        harness.dispose();
      }
    });
  }

  test('B6 skips an unparseable page-one sortAt', () async {
    final harness = _SeenHarness();
    try {
      harness.provider.requestFirstPage();
      await harness.land(0, [
        _row(_aliceRow, '2026-10-08T10:00:00Z'),
        _row(_secondRow, 'not-a-time'),
      ]);
      expect(_recordUris(harness.provider), [_aliceRow, _secondRow]);
      final marking = harness.provider.markPageOneSeen();
      await _settle();
      expect(harness.sent, [
        (seenAt: '2026-10-08T10:00:00Z', did: 'did:plc:alice'),
      ]);
      harness.updates.single.complete();
      await marking;
      await _settle();
      expect(harness.reported, isEmpty);
      expect((harness.unreadCount as UnreadCountRefreshSpy).refreshCalls, 1);
      unawaited(harness.provider.markPageOneSeen());
      await _settle();
      expect(harness.sent, hasLength(1));
    } finally {
      harness.dispose();
    }
  });

  test('B8 switch after A lands cannot mark A while B is loading', () async {
    final harness = _SeenHarness();
    try {
      harness.provider.requestFirstPage();
      await harness.land(0, [_row(_aliceRow, '2026-10-08T10:00:00Z')]);
      harness.auth.setSignedInDid('did:plc:bob');
      expect(harness.requests, [
        (cursor: null, did: 'did:plc:alice'),
        (cursor: null, did: 'did:plc:bob'),
      ]);
      unawaited(harness.provider.markPageOneSeen());
      await _settle();
      expect(harness.sent, isEmpty);
      await harness.land(1, [_row(_bobRow, '2026-10-08T11:00:00Z')]);
      final marking = harness.provider.markPageOneSeen();
      await _settle();
      expect(harness.sent, [
        (seenAt: '2026-10-08T11:00:00Z', did: 'did:plc:bob'),
      ]);
      harness.updates.single.complete();
      await marking;
    } finally {
      harness.dispose();
    }
  });

  test('B8 late A page cannot be marked before B lands', () async {
    final harness = _SeenHarness();
    try {
      harness.provider.requestFirstPage();
      harness.auth.setSignedInDid('did:plc:bob');
      expect(harness.requests, [
        (cursor: null, did: 'did:plc:alice'),
        (cursor: null, did: 'did:plc:bob'),
      ]);
      await harness.land(0, [_row(_aliceRow, '2026-10-08T10:00:00Z')]);
      unawaited(harness.provider.markPageOneSeen());
      await _settle();
      expect(harness.sent, isEmpty);
      await harness.land(1, [_row(_bobRow, '2026-10-08T11:00:00Z')]);
      final marking = harness.provider.markPageOneSeen();
      await _settle();
      expect(harness.sent, [
        (seenAt: '2026-10-08T11:00:00Z', did: 'did:plc:bob'),
      ]);
      harness.updates.single.complete();
      await marking;
    } finally {
      harness.dispose();
    }
  });

  for (final (name, authChanges) in <(String, List<String?>)>[
    ('account switch', ['did:plc:bob']),
    ('sign-out and back in', [null, 'did:plc:alice']),
  ]) {
    test('B8 $name during updateSeen cannot refetch A count', () async {
      final harness = _SeenHarness(realCount: true);
      try {
        harness.countResponses.single.complete(3);
        await _settle();
        harness.provider.requestFirstPage();
        await harness.land(0, [_row(_aliceRow, '2026-10-08T10:00:00Z')]);
        final marking = harness.provider.markPageOneSeen();
        await _settle();
        expect(harness.sent, [
          (seenAt: '2026-10-08T10:00:00Z', did: 'did:plc:alice'),
        ]);
        for (final did in authChanges) {
          harness.auth.setSignedInDid(did);
          await _settle();
        }
        expect(harness.countResponses, hasLength(2));
        harness.countResponses[1].complete(2);
        await _settle();
        final callsAfterAuthChange = harness.countResponses.length;
        harness.updates.single.complete();
        await marking;
        await _settle();
        expect(harness.countResponses, hasLength(callsAfterAuthChange));
      } finally {
        harness.dispose();
      }
    });
  }

  for (final pendingFirstUpdate in [false, true]) {
    test(
      'B11 refresh re-arms page one with '
      '${pendingFirstUpdate ? 'P1 update pending' : 'P1 update complete'}',
      () async {
        final harness = _SeenHarness();
        try {
          harness.provider.requestFirstPage();
          await harness.land(0, [_row(_aliceRow, '2026-10-08T09:00:00Z')]);
          final firstMark = harness.provider.markPageOneSeen();
          await _settle();
          expect(harness.sent, [
            (seenAt: '2026-10-08T09:00:00Z', did: 'did:plc:alice'),
          ]);
          if (!pendingFirstUpdate) {
            harness.updates[0].complete();
            await firstMark;
          }
          final refresh = harness.provider.refresh();
          expect(harness.requests, [
            (cursor: null, did: 'did:plc:alice'),
            (cursor: null, did: 'did:plc:alice'),
          ]);
          await harness.land(1, [_row(_secondRow, '2026-10-08T09:30:00Z')]);
          expect(await refresh, isTrue);
          final secondMark = harness.provider.markPageOneSeen();
          await _settle();
          expect(harness.sent, [
            (seenAt: '2026-10-08T09:00:00Z', did: 'did:plc:alice'),
            (seenAt: '2026-10-08T09:30:00Z', did: 'did:plc:alice'),
          ]);
          harness.updates[1].complete();
          await secondMark;
          if (pendingFirstUpdate) {
            harness.updates[0].complete();
            await firstMark;
          }
        } finally {
          harness.dispose();
        }
      },
    );
  }

  test('B11 superseded page one cannot replace the mark boundary', () async {
    final harness = _SeenHarness();
    try {
      harness.provider.requestFirstPage();
      final refresh = harness.provider.refresh();
      expect(harness.requests, [
        (cursor: null, did: 'did:plc:alice'),
        (cursor: null, did: 'did:plc:alice'),
      ]);
      await harness.land(1, [_row(_secondRow, '2026-10-08T09:30:00Z')]);
      expect(await refresh, isTrue);
      await harness.land(0, [_row(_aliceRow, '2026-10-08T09:45:00Z')]);
      expect(_recordUris(harness.provider), [_secondRow]);
      final marking = harness.provider.markPageOneSeen();
      await _settle();
      expect(harness.sent, [
        (seenAt: '2026-10-08T09:30:00Z', did: 'did:plc:alice'),
      ]);
      harness.updates.single.complete();
      await marking;
    } finally {
      harness.dispose();
    }
  });

  test('B11 empty page one stays unmarked after page two adds rows', () async {
    final harness = _SeenHarness();
    try {
      harness.provider.requestFirstPage();
      await harness.land(0, [], cursor: 'c1');
      final more = harness.provider.loadMore();
      expect(harness.requests, [
        (cursor: null, did: 'did:plc:alice'),
        (cursor: 'c1', did: 'did:plc:alice'),
      ]);
      await harness.land(1, [_row(_secondRow, '2026-10-08T09:30:00Z')]);
      await more;
      expect(_recordUris(harness.provider), [_secondRow]);
      unawaited(harness.provider.markPageOneSeen());
      await _settle();
      expect(harness.sent, isEmpty);
      expect((harness.unreadCount as UnreadCountRefreshSpy).refreshCalls, 0);
      final refresh = harness.provider.refresh();
      await harness.land(2, [_row(_thirdRow, '2026-10-08T09:45:00Z')]);
      expect(await refresh, isTrue);
      final marking = harness.provider.markPageOneSeen();
      await _settle();
      expect(harness.sent, [
        (seenAt: '2026-10-08T09:45:00Z', did: 'did:plc:alice'),
      ]);
      harness.updates.single.complete();
      await marking;
    } finally {
      harness.dispose();
    }
  });

  // The backend counts unread across every reason (open enum), so the seen
  // boundary is the newest sortAt of every row page one received, including
  // rows the client cannot render.
  for (final (name, dropped) in [
    (
      'unknown-reason',
      _row(_bobRow, '2026-10-08T11:00:00Z')..['reason'] = 'follow',
    ),
    ('missing-record', _row(_bobRow, '2026-10-08T11:00:00Z')..remove('record')),
  ]) {
    test(
      'B12 a newer dropped $name row sets the page-one seen boundary',
      () async {
        final harness = _SeenHarness();
        try {
          harness.provider.requestFirstPage();
          await harness.land(0, [
            dropped,
            _row(_aliceRow, '2026-10-08T10:00:00Z'),
          ]);
          expect(_recordUris(harness.provider), [_aliceRow]);
          final marking = harness.provider.markPageOneSeen();
          await _settle();
          expect(harness.sent, [
            (seenAt: '2026-10-08T11:00:00Z', did: 'did:plc:alice'),
          ]);
          harness.updates.single.complete();
          await marking;
        } finally {
          harness.dispose();
        }
      },
    );
  }

  test('B12 a page one of only unknown-reason rows still marks seen', () async {
    final harness = _SeenHarness();
    try {
      harness.provider.requestFirstPage();
      await harness.land(0, [
        _row(_aliceRow, '2026-10-08T10:00:00Z')..['reason'] = 'follow',
        _row(_bobRow, '2026-10-08T11:00:00Z')..['reason'] = 'follow',
      ]);
      expect(harness.provider.controller.items, isEmpty);
      final marking = harness.provider.markPageOneSeen();
      await _settle();
      expect(harness.sent, [
        (seenAt: '2026-10-08T11:00:00Z', did: 'did:plc:alice'),
      ]);
      harness.updates.single.complete();
      await marking;
      await _settle();
      expect((harness.unreadCount as UnreadCountRefreshSpy).refreshCalls, 1);
    } finally {
      harness.dispose();
    }
  });
}
