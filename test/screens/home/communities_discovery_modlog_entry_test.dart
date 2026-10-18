import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/main.dart';
import 'package:coves_flutter/models/community.dart';
import 'package:coves_flutter/models/moderation_action.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/community_guidelines_provider.dart';
import 'package:coves_flutter/providers/community_subscription_provider.dart';
import 'package:coves_flutter/providers/eula_provider.dart';
import 'package:coves_flutter/screens/home/communities_discovery_screen.dart';
import 'package:coves_flutter/screens/moderation/modlog_screen.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/profile_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/fake_providers.dart';
import '../../test_helpers/pump_helpers.dart';
import '../../test_helpers/test_mocks.dart';

class AcceptedEulaProvider extends EulaProvider {
  @override
  bool get hasAccepted => true;

  @override
  bool get isLoading => false;
}

class AcceptedGuidelinesProvider extends CommunityGuidelinesProvider {
  @override
  bool get hasAccepted => true;

  @override
  bool get isLoading => false;
}

void main() {
  late MockCovesApiService api;

  setUp(() => api = MockCovesApiService());

  testWidgets('B9 signed-out Explore row opens the moderation log', (
    tester,
  ) async {
    when(
      api.listCommunities(
        limit: 8,
        cursor: anyNamed('cursor'),
        sort: anyNamed('sort'),
        subscribed: anyNamed('subscribed'),
      ),
    ).thenAnswer((_) async => CommunitiesResponse(communities: []));
    when(
      api.listCommunities(
        limit: 5,
        cursor: anyNamed('cursor'),
        sort: 'new',
        subscribed: anyNamed('subscribed'),
      ),
    ).thenAnswer((_) async => CommunitiesResponse(communities: []));
    final auth = FakeAuthProvider();
    final subscriptions = FakeSubscriptionProvider(
      authProvider: auth,
      apiService: api,
    );
    addTearDown(subscriptions.dispose);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: CommunitiesDiscoveryScreen()),
        ),
        GoRoute(
          path: '/modlog',
          builder: (_, _) => const Scaffold(body: Text('MODLOG DESTINATION')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<CovesApiService>.value(value: api),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<CommunitySubscriptionProvider>.value(
            value: subscriptions,
          ),
        ],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await pumpFrames(tester);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
    await pumpFrames(tester);
    expect(find.text('Moderation log'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Moderation log'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Moderation log'), findsOneWidget);
    await tester.tap(find.text('Moderation log'));
    await pumpFrames(tester);
    expect(find.text('MODLOG DESTINATION'), findsOneWidget);
  });

  testWidgets('B9 production /modlog route opens ModlogScreen signed out', (
    tester,
  ) async {
    when(
      api.listModerationActions(
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
      ),
    ).thenAnswer((_) async => const ModerationActionPage(actions: []));
    final auth = FakeAuthProvider();
    final cache = ProfileCache(auth);
    addTearDown(cache.dispose);
    final router = createRouter(
      auth,
      AcceptedEulaProvider(),
      AcceptedGuidelinesProvider(),
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<CovesApiService>.value(value: api),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          Provider<ProfileCache>.value(value: cache),
          viewerAuthorityRegistration(auth: auth, apiService: api),
        ],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    router.go('/modlog');
    await pumpFrames(tester);
    expect(find.byType(ModlogScreen), findsOneWidget);
  });
}
