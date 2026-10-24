import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/main.dart';
import 'package:coves_flutter/models/notification.dart';
import 'package:coves_flutter/models/post_get_result.dart';
import 'package:coves_flutter/screens/home/main_shell_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/notifications_shell_harness.dart';
import '../test_helpers/reply_notification_fixture.dart';
import '../test_helpers/sign_in_flow_fakes.dart';

const _postUri = 'at://did:plc:writer/social.coves.community.post/root';
const _firstUri = 'at://did:plc:writer/social.coves.community.comment/first';
const _secondUri = 'at://did:plc:writer/social.coves.community.comment/second';

void main() {
  testWidgets('B9 pushed post route delays the mark until the shell returns', (
    tester,
  ) async {
    useShellViewport(tester, const Size(590, 1200));
    final shell = NotificationsShellHarness(count: 0, pendingPages: true);
    final eula = AcceptedEulaProvider();
    final guidelines = AcceptedGuidelinesProvider();
    final feeds = IdleFeedProvider(shell.auth, apiService: shell.api);
    final router = createRouter(shell.auth, eula, guidelines);
    provideDummy<PostGetResult>(const PostGetNotFound(_postUri));
    when(shell.api.getPost(_postUri))
        .thenAnswer((_) async => const PostGetNotFound(_postUri));
    try {
      await tester.pumpWidget(
        MultiProvider(
          providers: routerShellProviders(
            auth: shell.auth,
            api: shell.api,
            feeds: feeds,
          ),
          child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
        ),
      );
      router.go('/feed');
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump();
      }
      expect(router.state.uri.path, '/feed');
      expect(find.byType(MainShellScreen), findsOneWidget);

      await tester.tap(phoneNavItem('Notifications'));
      await tester.pump();
      expect(shell.pages, hasLength(1));
      unawaited(router.push('/post/${Uri.encodeComponent(_postUri)}'));
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump();
      }
      expect(
        router.state.uri.toString(),
        '/post/at%3A%2F%2Fdid%3Aplc%3Awriter%2Fsocial.coves.community.post%2Froot',
      );

      shell.pages.single.complete(
        NotificationPage.fromJson({
          'notifications': [
            replyNotificationWireFor(recordUri: _firstUri, rootUri: _postUri)
              ..['sortAt'] = '2026-10-08T12:00:00Z',
            replyNotificationWireFor(recordUri: _secondUri, rootUri: _postUri)
              ..['sortAt'] = '2026-10-08T12:05:00Z',
          ],
          'cursor': null,
        }),
      );
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump();
      }
      expect(
        router.state.uri.toString(),
        '/post/at%3A%2F%2Fdid%3Aplc%3Awriter%2Fsocial.coves.community.post%2Froot',
      );
      expect(shell.seenAt, isEmpty);

      router.pop();
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump();
      }
      expect(router.state.uri.path, '/feed');
      expect(
        find.text('at://did:plc:writer/social.coves.community.comment/first'),
        findsOneWidget,
      );
      expect(
        find.text('at://did:plc:writer/social.coves.community.comment/second'),
        findsOneWidget,
      );
      await tester.pump();
      expect(shell.seenAt, ['2026-10-08T12:05:00Z']);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      feeds.dispose();
      guidelines.dispose();
      eula.dispose();
      shell.auth.dispose();
    }
  });
}
