import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/main.dart';
import 'package:coves_flutter/models/community.dart';
import 'package:coves_flutter/models/notification.dart';
import 'package:coves_flutter/models/notification_preferences.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/post_get_result.dart';
import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/multi_feed_provider.dart';
import 'package:coves_flutter/providers/notification_preferences_change_signal.dart';
import 'package:coves_flutter/providers/unread_notification_count_provider.dart';
import 'package:coves_flutter/screens/home/main_shell_screen.dart';
import 'package:coves_flutter/screens/settings/settings_screen.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'fake_providers.dart';
import 'reply_notification_fixture.dart';
import 'sign_in_flow_fakes.dart';
import 'test_mocks.dart';

void useShellViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Finder phoneNavItem(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      (widget.properties.label?.startsWith(label) ?? false),
);

/// The app-level shell registrations used beneath the production router.
List<SingleChildWidget> routerShellProviders({
  required AuthProvider auth,
  required CovesApiService api,
  required MultiFeedProvider feeds,
  NotificationPreferencesChangeSignal? notificationPreferencesChangeSignal,
}) => [
  ...profileScreenProviders(
    auth: auth,
    apiService: api,
    commentService: MockCommentService(),
    notificationPreferencesChangeSignal: notificationPreferencesChangeSignal,
  ),
  ChangeNotifierProvider<MultiFeedProvider>.value(value: feeds),
];

/// Shared shell dependencies; pending pages are completed explicitly by tests.
class NotificationsShellHarness {
  NotificationsShellHarness({
    required this.count,
    this.pendingPages = false,
    this.notificationPreferencesChangeSignal,
  }) {
    when(api.getUnreadCount()).thenAnswer((_) async => count);
    when(api.getViewerAuthority()).thenAnswer((_) async => false);
    when(api.updateNotificationsSeen(seenAt: anyNamed('seenAt')))
        .thenAnswer((call) async {
          seenAt.add(call.namedArguments[#seenAt] as String);
        });
    when(api.listNotifications(cursor: anyNamed('cursor'))).thenAnswer((call) {
      cursors.add(call.namedArguments[#cursor] as String?);
      requestDids.add(auth.did);
      final response = Completer<NotificationPage>();
      pages.add(response);
      if (!pendingPages) {
        response.complete(
          NotificationPage.fromJson({
            'notifications': <Map<String, dynamic>>[],
            'cursor': null,
          }),
        );
      }
      return response.future;
    });
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
  }

  int count;
  final bool pendingPages;
  final NotificationPreferencesChangeSignal?
  notificationPreferencesChangeSignal;
  final auth = FakeAuthProvider(signedInDid: 'did:plc:alice');
  final api = MockCovesApiService();
  final pages = <Completer<NotificationPage>>[];
  final cursors = <String?>[];

  /// The signed-in DID when each `listNotifications` was sent.
  final requestDids = <String?>[];
  final seenAt = <String>[];

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: profileScreenProviders(
          auth: auth,
          apiService: api,
          commentService: MockCommentService(),
          notificationPreferencesChangeSignal:
              notificationPreferencesChangeSignal,
        ),
        child: MaterialApp(theme: AppTheme.dark, home: const MainShellScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    auth.dispose();
  }
}

const notificationRootUri =
    'at://did:plc:writer/social.coves.community.post/root';

NotificationPage notificationRows(List<(String, String)> rows) =>
    NotificationPage.fromJson({
      'notifications': [
        for (final (suffix, sortAt) in rows)
          replyNotificationWireFor(
            recordUri:
                'at://did:plc:writer/social.coves.community.comment/$suffix',
            rootUri: notificationRootUri,
          )..['sortAt'] = sortAt,
      ],
      'cursor': null,
    });

Future<void> holdRouterFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  for (var frame = 0; frame < 4; frame++) {
    await tester.pump();
  }
}

/// Production router over shared shell dependencies, with controllable pages.
class NotificationsRouterHarness {
  NotificationsRouterHarness({int count = 0, bool signedIn = true})
    : shell = NotificationsShellHarness(count: count, pendingPages: true) {
    if (!signedIn) {
      shell.auth.setSignedInDid(null);
    }
    feeds = IdleFeedProvider(shell.auth, apiService: shell.api);
    router = createRouter(shell.auth, eula, guidelines);
    provideDummy<PostGetResult>(const PostGetNotFound(notificationRootUri));
    when(shell.api.getPost(notificationRootUri))
        .thenAnswer((_) async => const PostGetNotFound(notificationRootUri));
  }

  final NotificationsShellHarness shell;
  final signal = NotificationPreferencesChangeSignal();
  final eula = AcceptedEulaProvider();
  final guidelines = AcceptedGuidelinesProvider();
  late final IdleFeedProvider feeds;
  late final GoRouter router;
  final settingsPuts = <Completer<NotificationPreferences>>[];

  void stubSettings() {
    when(shell.api.getNotificationPreferences()).thenAnswer(
      (_) async => const NotificationPreferences(
        postReply: true,
        commentReply: false,
        mention: true,
        upvote: false,
      ),
    );
    when(
      shell.api.putNotificationPreferences(
        postReply: anyNamed('postReply'),
        commentReply: anyNamed('commentReply'),
        mention: anyNamed('mention'),
        upvote: anyNamed('upvote'),
      ),
    ).thenAnswer((_) {
      final response = Completer<NotificationPreferences>();
      settingsPuts.add(response);
      return response.future;
    });
  }

  Future<void> openSettings(WidgetTester tester) async {
    unawaited(router.push('/settings'));
    await holdRouterFrames(tester);
    expect(router.state.uri.path, '/settings');
    expect(find.byType(SettingsScreen), findsOneWidget);
  }

  UnreadNotificationCountProvider countProvider(WidgetTester tester) => tester
      .element(find.byType(MainShellScreen, skipOffstage: false))
      .read<UnreadNotificationCountProvider>();

  Future<void> mount(WidgetTester tester) async {
    useShellViewport(tester, const Size(590, 1200));
    await tester.pumpWidget(
      MultiProvider(
        providers: routerShellProviders(
          auth: shell.auth,
          api: shell.api,
          feeds: feeds,
          notificationPreferencesChangeSignal: signal,
        ),
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    router.go('/feed');
    await holdRouterFrames(tester);
    expect(router.state.uri.path, '/feed');
    expect(find.byType(MainShellScreen), findsOneWidget);
  }

  Future<void> select(WidgetTester tester, String label) async {
    await tester.tap(phoneNavItem(label));
    await holdRouterFrames(tester);
  }

  Future<void> showPage(
    WidgetTester tester,
    int index,
    List<(String, String)> rows,
  ) async {
    shell.pages[index].complete(notificationRows(rows));
    await holdRouterFrames(tester);
    for (final (suffix, _) in rows) {
      expect(
        find.text('at://did:plc:writer/social.coves.community.comment/$suffix'),
        findsOneWidget,
      );
    }
  }

  Future<void> pushPost(WidgetTester tester) async {
    unawaited(router.push('/post/${Uri.encodeComponent(notificationRootUri)}'));
    await holdRouterFrames(tester);
    expect(
      router.state.uri.toString(),
      '/post/at%3A%2F%2Fdid%3Aplc%3Awriter%2Fsocial.coves.community.post%2Froot',
    );
  }

  Future<void> pop(WidgetTester tester) async {
    router.pop();
    await holdRouterFrames(tester);
    expect(router.state.uri.path, '/feed');
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    feeds.dispose();
    guidelines.dispose();
    eula.dispose();
    shell.auth.dispose();
    signal.dispose();
  }
}
