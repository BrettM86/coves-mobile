import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/community.dart';
import 'package:coves_flutter/models/notification.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/screens/home/main_shell_screen.dart';
import 'package:coves_flutter/screens/home/notifications_screen.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/widgets/icons/lucide_paths.dart';
import 'package:coves_flutter/widgets/notifications/notification_reply_card.dart';
import 'package:coves_flutter/widgets/notifications/notification_upvote_row.dart';
import 'package:coves_flutter/widgets/primary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/lucide_glyph_finder.dart';
import '../test_helpers/notifications_screen_harness.dart';
import '../test_helpers/reply_notification_fixture.dart';
import '../test_helpers/test_mocks.dart';
import '../test_helpers/upvote_notification_fixture.dart';

const _postReplyUri =
    'at://did:plc:writer/social.coves.community.comment/post-reply';
const _mentionUri = 'at://did:plc:writer/social.coves.community.postv2/mention';
const _commentReplyUri =
    'at://did:plc:writer/social.coves.community.comment/comment-reply';
const _otherThread =
    'at://did:plc:me/social.coves.community.postv2/other-thread';

Finder _tab(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      (widget.properties.label?.startsWith(label) ?? false),
);

NotificationPage _page(List<Map<String, dynamic>> rows) =>
    NotificationPage.fromJson({'notifications': rows, 'cursor': null});

Map<String, dynamic> _replyRow() => replyNotificationWireFor(
  recordUri: 'at://did:plc:writer/social.coves.community.comment/reply1',
  rootUri: postUri,
);

void main() {
  testWidgets('B2 first visit loads one page, renders ordered rows with '
      'no gaps between them, and preserves them across tab switches', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(540, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final auth = FakeAuthProvider(signedInDid: 'did:plc:alice');
    final api = MockCovesApiService();
    final response = Completer<NotificationPage>();
    final cursors = <String?>[];
    when(api.listNotifications(cursor: anyNamed('cursor'))).thenAnswer((call) {
      cursors.add(call.namedArguments[#cursor] as String?);
      return response.future;
    });
    when(api.getUnreadCount()).thenAnswer((_) async => 0);
    when(api.getViewerAuthority()).thenAnswer((_) async => false);
    when(
      api.getDiscover(
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((_) async => TimelineResponse(feed: const []));
    when(
      api.getTimeline(
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((_) async => TimelineResponse(feed: const []));
    when(
      api.listCommunities(
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
        sort: anyNamed('sort'),
        subscribed: anyNamed('subscribed'),
      ),
    ).thenAnswer((_) async => CommunitiesResponse(communities: const []));
    when(api.getProfile(actor: 'did:plc:alice')).thenAnswer(
      (_) async => UserProfile(did: 'did:plc:alice', handle: 'alice.test'),
    );
    when(
      api.getAuthorPosts(
        actor: 'did:plc:alice',
        filter: anyNamed('filter'),
        community: anyNamed('community'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((_) async => TimelineResponse(feed: const []));

    try {
      await tester.pumpWidget(
        MultiProvider(
          providers: profileScreenProviders(
            auth: auth,
            apiService: api,
            commentService: MockCommentService(),
          ),
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const MainShellScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(cursors, isEmpty);

      await tester.tap(_tab('Notifications'));
      await tester.pump();
      expect(find.text('No notifications yet'), findsNothing);
      await tester.pump();
      expect(cursors, [null]);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(NotificationReplyCard), findsNothing);
      expect(find.byType(NotificationUpvoteRow), findsNothing);

      response.complete(
        NotificationPage.fromJson({
          'notifications': [
            upvoteWire(upvoters: [], count: 1),
            replyNotificationWireFor(
              recordUri: _postReplyUri,
              rootUri: postUri,
            ),
            replyNotificationWireFor(
              reason: 'mention',
              recordUri: _mentionUri,
              rootUri: _otherThread,
            ),
            replyNotificationWireFor(
              reason: 'commentReply',
              recordUri: _commentReplyUri,
              rootUri: postUri,
            ),
          ],
          'cursor': null,
        }),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NotificationUpvoteRow), findsOneWidget);
      expect(find.byType(NotificationReplyCard), findsNWidgets(3));
      expect(
        find.ancestor(
          of: find.byType(NotificationUpvoteRow),
          matching: find.byType(CustomScrollView),
        ),
        findsOneWidget,
      );

      final positions = <(String, double)>[
        for (final element in find.byType(NotificationUpvoteRow).evaluate())
          (
            (element.widget as NotificationUpvoteRow).notification.subject!.uri,
            tester.getRect(find.byElementPredicate((e) => e == element)).top,
          ),
        for (final element in find.byType(NotificationReplyCard).evaluate())
          (
            (element.widget as NotificationReplyCard).notification.record!.uri,
            tester.getRect(find.byElementPredicate((e) => e == element)).top,
          ),
      ]..sort((a, b) => a.$2.compareTo(b.$2));
      expect(positions.map((row) => row.$1).toList(), [
        'at://did:plc:me/social.coves.community.postv2/3kpost',
        'at://did:plc:writer/social.coves.community.comment/post-reply',
        'at://did:plc:writer/social.coves.community.postv2/mention',
        'at://did:plc:writer/social.coves.community.comment/comment-reply',
      ]);
      final cardRects = [
        for (final element in find.byType(NotificationReplyCard).evaluate())
          tester.getRect(find.byElementPredicate((e) => e == element)),
      ]..sort((a, b) => a.top.compareTo(b.top));
      for (var index = 1; index < cardRects.length; index++) {
        expect(cardRects[index].top - cardRects[index - 1].bottom, 0);
      }

      await tester.tap(_tab('Notifications'));
      await tester.pump();
      await tester.tap(_tab('Home'));
      await tester.pump();
      await tester.tap(_tab('Notifications'));
      await tester.pump();
      expect(find.byType(NotificationUpvoteRow), findsOneWidget);
      expect(find.byType(NotificationReplyCard), findsNWidgets(3));
      expect(cursors, [null]);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
    }
  });

  testWidgets(
    'B3 tapping a post reply pushes the root post with comment focus',
    (tester) async {
      final harness = NotificationsScreenHarness();
      try {
        await harness.mount(tester);
        harness.responses.first.complete(_page([_replyRow()]));
        await tester.pumpAndSettle();

        expect(find.byType(NotificationReplyCard), findsOneWidget);
        expect(harness.cursors, [null]);
        await tester.tap(find.byType(NotificationReplyCard));
        await tester.pumpAndSettle();
        expect(
          harness.router.state.uri.toString(),
          '/post/at%3A%2F%2Fdid%3Aplc%3Ame%2Fsocial.coves.community.postv2%2F3kpost?comment=at%3A%2F%2Fdid%3Aplc%3Awriter%2Fsocial.coves.community.comment%2Freply1',
        );
        expect(harness.router.canPop(), isTrue);
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  testWidgets('B3 tapping an upvote pushes the subject post without comment', (
    tester,
  ) async {
    final harness = NotificationsScreenHarness();
    try {
      await harness.mount(tester);
      harness.responses.first.complete(
        _page([upvoteWire(upvoters: [], count: 1)]),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NotificationUpvoteRow), findsOneWidget);
      expect(harness.cursors, [null]);
      await tester.tap(find.byType(NotificationUpvoteRow));
      await tester.pumpAndSettle();
      expect(
        harness.router.state.uri.toString(),
        '/post/at%3A%2F%2Fdid%3Aplc%3Ame%2Fsocial.coves.community.postv2%2F3kpost',
      );
      expect(harness.router.canPop(), isTrue);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('B4 an empty first page shows the empty state without an error', (
    tester,
  ) async {
    final harness = NotificationsScreenHarness();
    try {
      await harness.mount(tester);
      harness.responses.first.complete(_page([]));
      await tester.pumpAndSettle();

      expect(find.text('No notifications yet'), findsOneWidget);
      expect(harness.cursors, [null]);
      expect(find.text('Retry'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('B5 server and network first-page errors retry and render rows', (
    tester,
  ) async {
    for (final (label, error) in [
      ('server', ServerException('Server failure', statusCode: 500)),
      ('network', NetworkException('Network failure')),
    ]) {
      final harness = NotificationsScreenHarness();
      try {
        await harness.mount(tester);
        harness.responses.first.completeError(error);
        await tester.pumpAndSettle();

        expect(
          find.widgetWithText(ElevatedButton, 'Retry'),
          findsOneWidget,
          reason: label,
        );
        expect(find.byType(NotificationReplyCard), findsNothing);
        await tester.tap(find.text('Retry'));
        await tester.pump();
        expect(harness.cursors, [null, null]);
        harness.responses.last.complete(_page([_replyRow()]));
        await tester.pumpAndSettle();

        expect(find.byType(NotificationReplyCard), findsOneWidget);
        expect(find.text('Retry'), findsNothing);
      } finally {
        await harness.dispose(tester);
      }
    }
  });

  testWidgets('B8 sign-out before or after auth failure shows sign-in only', (
    tester,
  ) async {
    for (final signOutBeforeFailure in [false, true]) {
      final harness = NotificationsScreenHarness();
      try {
        await harness.mount(tester);
        if (signOutBeforeFailure) {
          harness.auth.setSignedInDid(null);
          await tester.pump();
        }
        harness.responses.first.completeError(
          AuthenticationException('Session expired'),
        );
        await tester.pumpAndSettle();
        if (!signOutBeforeFailure) {
          // Let the error land while still authenticated before sign-out.
          expect(find.widgetWithText(ElevatedButton, 'Retry'), findsOneWidget);
          harness.auth.setSignedInDid(null);
          await tester.pumpAndSettle();
        }

        expect(find.widgetWithText(PrimaryButton, 'Sign in'), findsOneWidget);
        expect(find.text('Retry'), findsNothing);
        expect(find.byType(NotificationReplyCard), findsNothing);
        expect(find.byType(NotificationUpvoteRow), findsNothing);
        expect(harness.cursors, [null]);
      } finally {
        await harness.dispose(tester);
      }
    }
  });

  testWidgets('signing in again on the mounted tab loads a fresh first page', (
    tester,
  ) async {
    final harness = NotificationsScreenHarness();
    try {
      await harness.mount(tester);
      harness.responses.first.complete(
        _page([upvoteWire(upvoters: [], count: 1)]),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NotificationUpvoteRow), findsOneWidget);

      harness.auth.setSignedInDid(null);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(PrimaryButton, 'Sign in'), findsOneWidget);

      harness.auth.setSignedInDid('did:plc:alice');
      await tester.pump();
      await tester.pump();
      expect(harness.cursors, [null, null]);
      harness.responses.last.complete(_page([_replyRow()]));
      await tester.pumpAndSettle();

      expect(find.byType(NotificationReplyCard), findsOneWidget);
      expect(find.byType(NotificationUpvoteRow), findsNothing);
      expect(find.text('No notifications yet'), findsNothing);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('B9 an auth error while still signed in can be retried', (
    tester,
  ) async {
    final harness = NotificationsScreenHarness();
    try {
      await harness.mount(tester);
      harness.responses.first.completeError(
        AuthenticationException('Refresh unavailable'),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ElevatedButton, 'Retry'), findsOneWidget);
      expect(find.text('Sign in'), findsNothing);
      expect(harness.auth.isAuthenticated, isTrue);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(harness.cursors, [null, null]);
      harness.responses.last.complete(_page([_replyRow()]));
      await tester.pumpAndSettle();

      expect(find.byType(NotificationReplyCard), findsOneWidget);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('B6a the signed-out prompt shows the Lucide bell', (
    tester,
  ) async {
    final harness = NotificationsScreenHarness();
    try {
      await harness.mount(tester);
      harness.auth.setSignedInDid(null);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(PrimaryButton, 'Sign in'), findsOneWidget);

      expectLucideGlyph(
        tester,
        within: find.byType(NotificationsScreen),
        paths: LucidePaths.bell,
        color: const Color(0xFFFF8040),
        size: 64,
      );
      expect(find.byIcon(Icons.notifications_outlined), findsNothing);
    } finally {
      await harness.dispose(tester);
    }
  });
}
