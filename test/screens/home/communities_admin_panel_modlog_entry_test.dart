import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/screens/home/communities_admin_panel.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/pump_helpers.dart';
import '../../test_helpers/test_mocks.dart';

void main() {
  testWidgets('B12 the admin panel menu opens the moderation log', (
    tester,
  ) async {
    final api = MockCovesApiService();
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const CommunitiesAdminPanel()),
        GoRoute(
          path: '/modlog',
          builder: (_, _) => const Scaffold(body: Text('MODLOG DESTINATION')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      Provider<CovesApiService>.value(
        value: api,
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await pumpFrames(tester);

    expect(find.text('Moderation log'), findsOneWidget);
    await tester.tap(find.text('Moderation log'));
    await pumpFrames(tester);
    expect(find.text('MODLOG DESTINATION'), findsOneWidget);
  });
}
