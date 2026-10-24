import 'dart:async';

import 'package:coves_flutter/models/notification.dart';
import 'package:coves_flutter/providers/notifications_list_provider.dart';
import 'package:coves_flutter/providers/viewer_authority_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'fake_providers.dart';
import 'reply_notification_fixture.dart';
import 'test_mocks.dart';
import 'unread_count_refresh_spy.dart';
import 'upvote_notification_fixture.dart';

/// Record uri of the single row [NotificationsListProviderHarness.firstPage]
/// loads.
const harnessFirstPageReplyUri =
    'at://did:plc:alice/social.coves.community.comment/r1';

/// Lets pending futures and listener chains run to completion.
Future<void> settle() async {
  for (var turn = 0; turn < 3; turn++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// A [NotificationsListProvider] whose every `listNotifications` call is held
/// on a [Completer] in [responses], with the requests recorded in [requests].
class NotificationsListProviderHarness {
  NotificationsListProviderHarness() {
    when(api.listNotifications(cursor: anyNamed('cursor'))).thenAnswer((call) {
      requests.add((
        cursor: call.namedArguments[#cursor] as String?,
        did: auth.did,
      ));
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
  final requests = <({String? cursor, String? did})>[];
  final responses = <Completer<NotificationPage>>[];

  void expectRequests(List<({String? cursor, String? did})> expected) {
    expect(requests, expected);
  }

  /// Requests page one and answers it with one reply row
  /// ([harnessFirstPageReplyUri]).
  Future<void> firstPage({String? cursor = 'c1'}) async {
    provider.requestFirstPage();
    expectRequests([(cursor: null, did: 'did:plc:alice')]);
    responses[0].complete(
      NotificationPage.fromJson({
        'notifications': [
          replyNotificationWireFor(
            recordUri: harnessFirstPageReplyUri,
            rootUri: postUri,
          ),
        ],
        'cursor': cursor,
      }),
    );
    await settle();
    expect(
      [
        for (final notification in provider.controller.items)
          notification.record!.uri,
      ],
      [harnessFirstPageReplyUri],
    );
  }

  void dispose() {
    provider.dispose();
    unreadCount.dispose();
    authority.dispose();
    auth.dispose();
  }
}
