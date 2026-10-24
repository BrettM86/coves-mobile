import 'dart:async';

import 'package:coves_flutter/models/notification.dart';
import 'package:coves_flutter/providers/notifications_list_provider.dart';
import 'package:coves_flutter/providers/viewer_authority_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/reply_notification_fixture.dart';
import '../test_helpers/test_mocks.dart';
import '../test_helpers/unread_count_refresh_spy.dart';
import '../test_helpers/upvote_notification_fixture.dart';

const _aliceRow = 'at://did:plc:alice/social.coves.community.comment/alice-row';
const _bobRow = 'at://did:plc:bob/social.coves.community.comment/bob-row';
const _oldAliceRow =
    'at://did:plc:alice/social.coves.community.comment/old-alice-row';
const _newAliceRow =
    'at://did:plc:alice/social.coves.community.comment/new-alice-row';

NotificationPage _page(String recordUri) => NotificationPage.fromJson({
  'notifications': [
    replyNotificationWireFor(recordUri: recordUri, rootUri: postUri),
  ],
  'cursor': null,
});

List<String> _recordUris(NotificationsListProvider provider) => [
  for (final row in provider.controller.items) row.record!.uri,
];

class _Harness {
  _Harness() {
    when(api.listNotifications(cursor: anyNamed('cursor'))).thenAnswer((call) {
      expect(call.namedArguments[#cursor], isNull);
      calledUnderDids.add(auth.did);
      final response = Completer<NotificationPage>();
      responses.add(response);
      return response.future;
    });
    when(api.getViewerAuthority()).thenAnswer((_) async => false);
    authority = ViewerAuthorityProvider(apiService: api, authProvider: auth);
    provider = NotificationsListProvider(
      apiService: api,
      authProvider: auth,
      sessionKeyOf: () => authority.sessionKey,
      unreadNotificationCountProvider: unreadCount,
    );
  }

  final auth = FakeAuthProvider(signedInDid: 'did:plc:alice');
  final api = MockCovesApiService();
  final unreadCount = UnreadCountRefreshSpy();
  late final ViewerAuthorityProvider authority;
  late final NotificationsListProvider provider;
  final responses = <Completer<NotificationPage>>[];
  final calledUnderDids = <String?>[];

  void expectRequests(List<String> dids) {
    expect(calledUnderDids, dids);
  }

  Future<void> land(int request, String recordUri) async {
    responses[request].complete(_page(recordUri));
    await Future<void>.delayed(Duration.zero);
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

  group('NotificationsListProvider account changes', () {
    test('B6 switch before first request stays idle; switch after A loads '
        'clears A immediately and fetches B', () async {
      final harness = _Harness();
      try {
        harness.auth.setSignedInDid('did:plc:bob');
        expect(harness.calledUnderDids, isEmpty);
        harness.auth.setSignedInDid('did:plc:alice');
        expect(harness.calledUnderDids, isEmpty);

        harness.provider.requestFirstPage();
        harness.expectRequests(['did:plc:alice']);
        await harness.land(0, _aliceRow);
        expect(_recordUris(harness.provider), [_aliceRow]);

        harness.auth.setSignedInDid('did:plc:bob');
        expect(harness.provider.controller.items, isEmpty);
        harness.expectRequests(['did:plc:alice', 'did:plc:bob']);
        await harness.land(1, _bobRow);
        expect(_recordUris(harness.provider), [_bobRow]);
      } finally {
        harness.dispose();
      }
    });

    for (final oldResponseAfterBob in [false, true]) {
      test('B6 A in-flight result never publishes when it lands '
          '${oldResponseAfterBob ? 'after' : 'before'} B', () async {
        final harness = _Harness();
        try {
          final snapshots = <List<String>>[];
          harness.provider.addListener(
            () => snapshots.add(_recordUris(harness.provider)),
          );
          harness.provider.requestFirstPage();
          harness.expectRequests(['did:plc:alice']);
          harness.auth.setSignedInDid('did:plc:bob');
          harness.expectRequests(['did:plc:alice', 'did:plc:bob']);
          expect(harness.provider.controller.items, isEmpty);

          if (oldResponseAfterBob) {
            await harness.land(1, _bobRow);
            await harness.land(0, _aliceRow);
          } else {
            await harness.land(0, _aliceRow);
            expect(harness.provider.controller.items, isEmpty);
            await harness.land(1, _bobRow);
          }
          expect(
            snapshots.every((snapshot) => !snapshot.contains(_aliceRow)),
            isTrue,
          );
          expect(snapshots, contains(equals([_bobRow])));
          expect(_recordUris(harness.provider), [_bobRow]);
        } finally {
          harness.dispose();
        }
      });
    }

    test(
      'B6 unchanged DID notification retains rows without fetching',
      () async {
        final harness = _Harness();
        try {
          harness.provider.requestFirstPage();
          harness.expectRequests(['did:plc:alice']);
          await harness.land(0, _aliceRow);
          harness.auth.notifyWithoutChange();
          expect(_recordUris(harness.provider), [_aliceRow]);
          harness.expectRequests(['did:plc:alice']);
        } finally {
          harness.dispose();
        }
      },
    );
  });

  group('NotificationsListProvider sign-out', () {
    test('B7 sign-out clears loaded rows and blocks requests', () async {
      final harness = _Harness();
      try {
        harness.provider.requestFirstPage();
        harness.expectRequests(['did:plc:alice']);
        await harness.land(0, _aliceRow);
        expect(_recordUris(harness.provider), [_aliceRow]);

        harness.auth.setSignedInDid(null);
        expect(harness.provider.controller.items, isEmpty);
        harness.provider.requestFirstPage();
        await Future<void>.delayed(Duration.zero);
        harness.expectRequests(['did:plc:alice']);
      } finally {
        harness.dispose();
      }
    });

    test(
      'B7 in-flight first page after sign-out leaves no rows or error',
      () async {
        final harness = _Harness();
        try {
          harness.provider.requestFirstPage();
          harness.expectRequests(['did:plc:alice']);
          harness.auth.setSignedInDid(null);
          await harness.land(0, _oldAliceRow);
          expect(harness.provider.controller.items, isEmpty);
          expect(harness.provider.controller.error, isNull);
          harness.expectRequests(['did:plc:alice']);
        } finally {
          harness.dispose();
        }
      },
    );

    test('B7 same DID after sign-out gets one fresh page; old A '
        'response cannot replace it', () async {
      final harness = _Harness();
      try {
        harness.provider.requestFirstPage();
        harness.expectRequests(['did:plc:alice']);
        await harness.land(0, _aliceRow);
        expect(_recordUris(harness.provider), [_aliceRow]);

        unawaited(harness.provider.controller.retry());
        harness.expectRequests(['did:plc:alice', 'did:plc:alice']);
        harness.auth.setSignedInDid(null);
        expect(harness.provider.controller.items, isEmpty);
        harness.auth.setSignedInDid('did:plc:alice');
        harness.provider.requestFirstPage();
        harness.expectRequests([
          'did:plc:alice',
          'did:plc:alice',
          'did:plc:alice',
        ]);
        await harness.land(2, _newAliceRow);
        expect(_recordUris(harness.provider), [_newAliceRow]);
        await harness.land(1, _oldAliceRow);
        expect(_recordUris(harness.provider), [_newAliceRow]);
      } finally {
        harness.dispose();
      }
    });
  });
}
