import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/moderation.dart';
import 'package:coves_flutter/models/post_get_result.dart';
import 'package:coves_flutter/screens/home/post_detail_loader.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/fake_providers.dart';

void main() {
  for (final postUri in [
    'at://did:plc:author/social.coves.community.post/p1',
    'at://did:plc:author/social.coves.community.postv2/p1',
  ]) {
    testWidgets('Filters F7 moderated $postUri links to its moderation log', (
      tester,
    ) async {
      Uri? destination;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => PostDetailLoader(
              postUri: postUri,
              fetchPost: (_) async => PostGetModerated(
                uri: postUri,
                moderation: const ModerationView(
                  state: ModerationState.removed,
                  sources: [
                    ModerationSource(
                      authorityDid: 'did:web:coves.social',
                      scope: ModerationScope(
                        kind: ModerationScopeKind.instance,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/modlog',
            builder: (_, state) {
              destination = state.uri;
              return const Scaffold(body: Text('MODLOG DESTINATION'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            // The loader stamps each request with the signed-out session.
            viewerAuthorityRegistration(
              auth: FakeAuthProvider(),
              apiService: CovesApiService(tokenGetter: () async => null),
            ),
          ],
          child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('View moderation log'), findsOneWidget);
      await tester.tap(find.text('View moderation log'));
      await tester.pumpAndSettle();
      expect(find.text('MODLOG DESTINATION'), findsOneWidget);
      expect(destination?.path, '/modlog');
      expect(destination?.queryParameters['subject'], postUri);
    });
  }

  testWidgets('Filters F7 community removal offers only Go Back', (
    tester,
  ) async {
    const postUri = 'at://did:plc:author/social.coves.community.post/p1';
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => PostDetailLoader(
            postUri: postUri,
            fetchPost: (_) async => const PostGetCommunityRemoved(uri: postUri),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          // The loader stamps each request with the signed-out session.
          viewerAuthorityRegistration(
            auth: FakeAuthProvider(),
            apiService: CovesApiService(tokenGetter: () async => null),
          ),
        ],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('View moderation log'), findsNothing);
    expect(find.text('Go Back'), findsOneWidget);
  });
}
