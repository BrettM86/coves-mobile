import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/main.dart';
import 'package:coves_flutter/models/community.dart';
import 'package:coves_flutter/models/moderation_action.dart';
import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/providers/community_guidelines_provider.dart';
import 'package:coves_flutter/providers/eula_provider.dart';
import 'package:coves_flutter/screens/moderation/modlog_screen.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/profile_cache.dart';
import 'package:coves_flutter/widgets/loading_error_states.dart';
import 'package:coves_flutter/widgets/moderation/modlog_entry_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/fake_providers.dart';
import '../../test_helpers/modlog_fixtures.dart';
import '../../test_helpers/pump_helpers.dart';
import '../../test_helpers/test_mocks.dart';

class _AcceptedEulaProvider extends EulaProvider {
  @override
  bool get hasAccepted => true;

  @override
  bool get isLoading => false;
}

class _AcceptedGuidelinesProvider extends CommunityGuidelinesProvider {
  @override
  bool get hasAccepted => true;

  @override
  bool get isLoading => false;
}

void main() {
  late MockCovesApiService api;
  late FakeAuthProvider auth;
  late ProfileCache cache;

  setUp(() {
    api = MockCovesApiService();
    auth = FakeAuthProvider();
    cache = ProfileCache(auth);
  });
  tearDown(() {
    cache.dispose();
    auth.dispose();
  });

  Future<void> pumpModlog(
    WidgetTester tester, {
    double height = 700,
    String? subject,
    DateTime Function()? clock,
  }) async {
    tester.view.physicalSize = Size(400, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<CovesApiService>.value(value: api),
          Provider<ProfileCache>.value(value: cache),
          viewerAuthorityRegistration(auth: auth, apiService: api),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: ModlogScreen(subject: subject, clock: clock),
        ),
      ),
    );
    await pumpFrames(tester);
  }

  void stubCommunityPicker() {
    when(
      api.listCommunities(
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
        sort: anyNamed('sort'),
        subscribed: anyNamed('subscribed'),
      ),
    ).thenAnswer(
      (_) async => CommunitiesResponse(
        communities: [CommunityView(did: 'did:plc:c', name: 'gardening')],
      ),
    );
  }

  testWidgets('Filters F2 action choices replace rows and retain the action on '
      'later pages', (tester) async {
    final removalPage = Completer<ModerationActionPage>();
    addTearDown(() {
      if (!removalPage.isCompleted) {
        removalPage.complete(const ModerationActionPage(actions: []));
      }
    });
    final calls = <Map<Symbol, dynamic>>[];
    when(
      api.listModerationActions(
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
        action: anyNamed('action'),
        community: anyNamed('community'),
        subject: anyNamed('subject'),
      ),
    ).thenAnswer((invocation) {
      final request = invocation.namedArguments;
      calls.add(request);
      if (request[#action] == 'remove') {
        if (request[#cursor] == 'r2') {
          return Future.value(
            ModerationActionPage(
              actions: [action('did:web:coves.social', 'removal-next')],
            ),
          );
        }
        return removalPage.future;
      }
      if (request[#action] == 'restore') {
        return Future.value(
          ModerationActionPage(
            actions: [
              action(
                'did:web:coves.social',
                'restore-0',
                kind: ModerationActionKind.restore,
              ),
            ],
          ),
        );
      }
      if (calls.length > 1) {
        return Future.value(
          ModerationActionPage(
            actions: [action('did:web:coves.social', 'all-0')],
          ),
        );
      }
      return Future.value(
        ModerationActionPage(
          actions: List.generate(
            25,
            (index) => action('did:web:coves.social', 'initial-$index'),
          ),
          cursor: 'c1',
        ),
      );
    });

    await pumpModlog(tester);
    expect(tile('did:web:coves.social', 'initial-0'), findsOneWidget);
    expect(find.text('All actions'), findsOneWidget);

    await chooseActionFilter(tester, from: 'All actions', to: 'Removals');
    expect(calls, hasLength(2));
    expect((calls.last[#cursor], calls.last[#action]), (null, 'remove'));
    expect(tile('did:web:coves.social', 'initial-0'), findsNothing);
    removalPage.complete(
      ModerationActionPage(
        actions: List.generate(
          25,
          (index) => action('did:web:coves.social', 'removal-$index'),
        ),
        cursor: 'r2',
      ),
    );
    await pumpFrames(tester);
    expect(tile('did:web:coves.social', 'removal-0'), findsOneWidget);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
    await pumpFrames(tester);
    expect(calls, hasLength(3));
    expect((calls.last[#cursor], calls.last[#action]), ('r2', 'remove'));

    await chooseActionFilter(tester, from: 'Removals', to: 'Restores');
    expect(calls, hasLength(4));
    expect((calls.last[#cursor], calls.last[#action]), (null, 'restore'));
    expect(tile('did:web:coves.social', 'removal-next'), findsNothing);
    expect(tile('did:web:coves.social', 'restore-0'), findsOneWidget);

    await chooseActionFilter(tester, from: 'Restores', to: 'All actions');
    expect(calls, hasLength(5));
    expect((calls.last[#cursor], calls.last[#action]), (null, null));
    expect(tile('did:web:coves.social', 'restore-0'), findsNothing);
    expect(tile('did:web:coves.social', 'all-0'), findsOneWidget);
  });

  testWidgets('Filters F4 a new filter supersedes in-flight pages and '
      'InvalidCursor recovery', (tester) async {
    final oldFirstPage = Completer<ModerationActionPage>();
    addTearDown(() {
      if (!oldFirstPage.isCompleted) {
        oldFirstPage.complete(const ModerationActionPage(actions: []));
      }
    });
    final firstPageRequests = <(String?, String?)>[];
    when(
      api.listModerationActions(
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
        action: anyNamed('action'),
        community: anyNamed('community'),
        subject: anyNamed('subject'),
      ),
    ).thenAnswer((invocation) {
      final cursor = invocation.namedArguments[#cursor] as String?;
      final selectedAction = invocation.namedArguments[#action] as String?;
      firstPageRequests.add((cursor, selectedAction));
      if (selectedAction == 'remove') {
        return Future.value(
          ModerationActionPage(
            actions: [action('did:web:coves.social', 'first-filtered-B')],
          ),
        );
      }
      return oldFirstPage.future;
    });

    await pumpModlog(tester);
    expect(firstPageRequests, [(null, null)]);
    await chooseActionFilter(tester, from: 'All actions', to: 'Removals');
    expect(tile('did:web:coves.social', 'first-filtered-B'), findsOneWidget);
    oldFirstPage.complete(
      ModerationActionPage(
        actions: [action('did:web:coves.social', 'first-stale-A')],
      ),
    );
    await pumpFrames(tester);
    expect(tile('did:web:coves.social', 'first-stale-A'), findsNothing);
    expect(tile('did:web:coves.social', 'first-filtered-B'), findsOneWidget);
    expect(firstPageRequests, [(null, null), (null, 'remove')]);

    await tester.pumpWidget(const SizedBox());
    api = MockCovesApiService();
    final oldNextPage = Completer<ModerationActionPage>();
    addTearDown(() {
      if (!oldNextPage.isCompleted) {
        oldNextPage.complete(const ModerationActionPage(actions: []));
      }
    });
    final nextPageRequests = <(String?, String?)>[];
    when(
      api.listModerationActions(
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
        action: anyNamed('action'),
        community: anyNamed('community'),
        subject: anyNamed('subject'),
      ),
    ).thenAnswer((invocation) {
      final cursor = invocation.namedArguments[#cursor] as String?;
      final selectedAction = invocation.namedArguments[#action] as String?;
      nextPageRequests.add((cursor, selectedAction));
      if (selectedAction == 'remove') {
        return Future.value(
          ModerationActionPage(
            actions: [action('did:web:coves.social', 'next-filtered-B')],
          ),
        );
      }
      if (cursor == 'c1') {
        return oldNextPage.future;
      }
      return Future.value(
        ModerationActionPage(
          actions: List.generate(
            25,
            (index) => action('did:web:coves.social', 'next-stale-A-$index'),
          ),
          cursor: 'c1',
        ),
      );
    });

    await pumpModlog(tester);
    expect(tile('did:web:coves.social', 'next-stale-A-0'), findsOneWidget);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
    await pumpFrames(tester);
    expect(nextPageRequests, [(null, null), ('c1', null)]);
    await chooseActionFilter(tester, from: 'All actions', to: 'Removals');
    expect(tile('did:web:coves.social', 'next-filtered-B'), findsOneWidget);
    oldNextPage.completeError(
      ApiException(
        'Invalid cursor',
        statusCode: 400,
        errorCode: 'InvalidCursor',
      ),
    );
    await pumpFrames(tester);
    expect(tile('did:web:coves.social', 'next-filtered-B'), findsOneWidget);
    expect(nextPageRequests, [(null, null), ('c1', null), (null, 'remove')]);
  });

  testWidgets(
    'Filters F3 community picker filters and clear returns to all communities',
    (tester) async {
      stubCommunityPicker();
      final calls = <Map<Symbol, dynamic>>[];
      when(
        api.listModerationActions(
          cursor: anyNamed('cursor'),
          limit: anyNamed('limit'),
          action: anyNamed('action'),
          community: anyNamed('community'),
          subject: anyNamed('subject'),
        ),
      ).thenAnswer((invocation) async {
        calls.add(invocation.namedArguments);
        return ModerationActionPage(
          actions: [
            action(
              'did:web:coves.social',
              calls.last[#community] == null ? 'all' : 'gardening',
            ),
          ],
        );
      });

      await pumpModlog(tester);
      expect(find.text('Community'), findsOneWidget);
      await tester.tap(find.text('Community'));
      await pumpFrames(tester);
      expect(find.text('Filter by community'), findsOneWidget);
      expect(find.text('Post to'), findsNothing);
      await tester.tap(find.text('gardening'));
      await pumpFrames(tester);
      expect(calls, hasLength(2));
      expect(
        (calls.last[#cursor], calls.last[#community]),
        (null, 'did:plc:c'),
      );
      expect(find.text('gardening'), findsOneWidget);
      expect(tile('did:web:coves.social', 'gardening'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear community filter'));
      await pumpFrames(tester);
      expect(calls, hasLength(3));
      expect((calls.last[#cursor], calls.last[#community]), (null, null));
      expect(find.text('Community'), findsOneWidget);
      expect(tile('did:web:coves.social', 'all'), findsOneWidget);
    },
  );

  testWidgets('Filters F9 community chip names each community as !name@origin, '
      'not its self-asserted display name', (tester) async {
    when(
      api.listCommunities(
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
        sort: anyNamed('sort'),
        subscribed: anyNamed('subscribed'),
      ),
    ).thenAnswer(
      (_) async => CommunitiesResponse(
        communities: [
          CommunityView(
            did: 'did:plc:coves-gardening',
            name: 'gardening',
            displayName: 'Gardening',
            origin: 'coves.social',
            description: 'coves row',
          ),
          CommunityView(
            did: 'did:plc:lemmy-gardening',
            name: 'gardening',
            displayName: 'Gardening',
            origin: 'lemmy.world',
            description: 'lemmy row',
          ),
        ],
      ),
    );
    when(
      api.listModerationActions(
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
        action: anyNamed('action'),
        community: anyNamed('community'),
        subject: anyNamed('subject'),
      ),
    ).thenAnswer((_) async => const ModerationActionPage(actions: []));

    await pumpModlog(tester);
    await tester.tap(find.text('Community'));
    await pumpFrames(tester);
    await tester.tap(find.text('coves row'));
    await pumpFrames(tester);
    expect(find.text('!gardening@coves.social'), findsOneWidget);
    expect(find.text('Gardening'), findsNothing);

    await tester.tap(find.text('!gardening@coves.social'));
    await pumpFrames(tester);
    await tester.tap(find.text('lemmy row'));
    await pumpFrames(tester);
    expect(find.text('!gardening@lemmy.world'), findsOneWidget);
    expect(find.text('!gardening@coves.social'), findsNothing);
  });

  testWidgets(
    'Filters F10 a long community name stays on one line and keeps the '
    'clear button reachable on a narrow screen',
    (tester) async {
      final longName = 'a' * 128;
      when(
        api.listCommunities(
          limit: anyNamed('limit'),
          cursor: anyNamed('cursor'),
          sort: anyNamed('sort'),
          subscribed: anyNamed('subscribed'),
        ),
      ).thenAnswer(
        (_) async => CommunitiesResponse(
          communities: [
            CommunityView(
              did: 'did:plc:long',
              name: longName,
              origin: 'coves.social',
              description: 'long row',
            ),
          ],
        ),
      );
      final calls = <Map<Symbol, dynamic>>[];
      when(
        api.listModerationActions(
          cursor: anyNamed('cursor'),
          limit: anyNamed('limit'),
          action: anyNamed('action'),
          community: anyNamed('community'),
          subject: anyNamed('subject'),
        ),
      ).thenAnswer((invocation) async {
        calls.add(invocation.namedArguments);
        return const ModerationActionPage(actions: []);
      });

      await pumpModlog(tester);
      tester.view.physicalSize = const Size(320, 700);
      await pumpFrames(tester);
      await tester.tap(find.text('Community'));
      await pumpFrames(tester);
      await tester.tap(find.text('long row'));
      await pumpFrames(tester);
      expect(tester.takeException(), isNull);
      expect(calls.last[#community], 'did:plc:long');

      final clear = find.byTooltip('Clear community filter');
      expect(clear.hitTestable(), findsOneWidget);
      expect(tester.getRect(clear).right, lessThanOrEqualTo(320));
      await tester.tap(clear);
      await pumpFrames(tester);
      expect(calls.last[#community], isNull);
      expect(find.text('Community'), findsOneWidget);
    },
  );

  testWidgets(
    'Filters F11 an invalid subject link is dropped with a notice and the '
    'full list loads',
    (tester) async {
      final calls = <Map<Symbol, dynamic>>[];
      when(
        api.listModerationActions(
          cursor: anyNamed('cursor'),
          limit: anyNamed('limit'),
          action: anyNamed('action'),
          community: anyNamed('community'),
          subject: anyNamed('subject'),
        ),
      ).thenAnswer((invocation) async {
        calls.add(invocation.namedArguments);
        return ModerationActionPage(
          actions: [action('did:web:coves.social', 'everything')],
        );
      });

      // Each case: the encoded ?subject value, and whether the notice shows.
      // An empty value is the same as no filter, so it shows no notice.
      final cases = <(String, bool)>[
        ('', false),
        ('not-a-uri', true),
        (
          Uri.encodeQueryComponent(
            'at://did:plc:author/social.coves.community.comment/c1',
          ),
          true,
        ),
        (
          Uri.encodeQueryComponent(
            'at://alice.coves.social/social.coves.community.post/p1',
          ),
          true,
        ),
        (
          Uri.encodeQueryComponent('at://did:plc:author/app.bsky.feed.post/p1'),
          true,
        ),
      ];
      for (final (encodedSubject, showsNotice) in cases) {
        calls.clear();
        final router = createRouter(
          auth,
          _AcceptedEulaProvider(),
          _AcceptedGuidelinesProvider(),
        );
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<CovesApiService>.value(value: api),
              Provider<ProfileCache>.value(value: cache),
              viewerAuthorityRegistration(auth: auth, apiService: api),
            ],
            child: MaterialApp.router(
              theme: AppTheme.dark,
              routerConfig: router,
            ),
          ),
        );
        router.go('/modlog?subject=$encodedSubject');
        await pumpFrames(tester);

        expect(calls, hasLength(1), reason: encodedSubject);
        expect(calls.single[#subject], isNull, reason: encodedSubject);
        expect(
          find.text('Showing actions for one post'),
          findsNothing,
          reason: encodedSubject,
        );
        expect(
          find.text("This link isn't valid. Showing all actions."),
          showsNotice ? findsOneWidget : findsNothing,
          reason: encodedSubject,
        );
        expect(
          tile('did:web:coves.social', 'everything'),
          findsOneWidget,
          reason: encodedSubject,
        );
        await tester.pumpWidget(const SizedBox());
        router.dispose();
      }
    },
  );

  testWidgets(
    'Filters F6 empty action, community and subject results use filtered copy',
    (tester) async {
      const postUri = 'at://did:plc:author/social.coves.community.postv2/p1';
      for (final filter in ['action', 'community', 'subject']) {
        if (filter != 'action') {
          await tester.pumpWidget(const SizedBox());
          api = MockCovesApiService();
        }
        stubCommunityPicker();
        final calls = <Map<Symbol, dynamic>>[];
        when(
          api.listModerationActions(
            cursor: anyNamed('cursor'),
            limit: anyNamed('limit'),
            action: anyNamed('action'),
            community: anyNamed('community'),
            subject: anyNamed('subject'),
          ),
        ).thenAnswer((invocation) async {
          final request = invocation.namedArguments;
          calls.add(request);
          return ModerationActionPage(
            actions:
                request[#action] != null ||
                    request[#community] != null ||
                    request[#subject] != null
                ? []
                : [action('did:web:coves.social', 'unfiltered')],
          );
        });

        await pumpModlog(tester, subject: filter == 'subject' ? postUri : null);
        switch (filter) {
          case 'action':
            expect(tile('did:web:coves.social', 'unfiltered'), findsOneWidget);
            await chooseActionFilter(
              tester,
              from: 'All actions',
              to: 'Removals',
            );
            expect(calls.last[#action], 'remove');
          case 'community':
            expect(tile('did:web:coves.social', 'unfiltered'), findsOneWidget);
            expect(find.text('Community'), findsOneWidget);
            await tester.tap(find.text('Community'));
            await pumpFrames(tester);
            await tester.tap(find.text('gardening'));
            await pumpFrames(tester);
            expect(calls.last[#community], 'did:plc:c');
          case 'subject':
            expect(calls.single[#subject], postUri);
        }
        expect(
          find.text('No moderation actions match these filters.'),
          findsOneWidget,
          reason: filter,
        );
        expect(
          find.text('No moderation actions yet.'),
          findsNothing,
          reason: filter,
        );
      }
    },
  );

  testWidgets(
    'Filters F8 action, community and subject compose through clear and '
    'Show all',
    (tester) async {
      const postUri = 'at://did:plc:author/social.coves.community.postv2/p1';
      stubCommunityPicker();
      final calls = <Map<Symbol, dynamic>>[];
      when(
        api.listModerationActions(
          cursor: anyNamed('cursor'),
          limit: anyNamed('limit'),
          action: anyNamed('action'),
          community: anyNamed('community'),
          subject: anyNamed('subject'),
        ),
      ).thenAnswer((invocation) async {
        calls.add(invocation.namedArguments);
        return ModerationActionPage(
          actions: [action('did:web:coves.social', 'row-${calls.length}')],
        );
      });

      await pumpModlog(tester, subject: postUri);
      expect(calls, hasLength(1));
      expect(
        (
          calls.last[#cursor],
          calls.last[#action],
          calls.last[#community],
          calls.last[#subject],
        ),
        (null, null, null, postUri),
      );

      await chooseActionFilter(tester, from: 'All actions', to: 'Removals');
      expect(calls, hasLength(2));
      expect(
        (
          calls.last[#cursor],
          calls.last[#action],
          calls.last[#community],
          calls.last[#subject],
        ),
        (null, 'remove', null, postUri),
      );

      await tester.tap(find.text('Community'));
      await pumpFrames(tester);
      await tester.tap(find.text('gardening'));
      await pumpFrames(tester);
      expect(calls, hasLength(3));
      expect(
        (
          calls.last[#cursor],
          calls.last[#action],
          calls.last[#community],
          calls.last[#subject],
        ),
        (null, 'remove', 'did:plc:c', postUri),
      );

      await tester.tap(find.byTooltip('Clear community filter'));
      await pumpFrames(tester);
      expect(calls, hasLength(4));
      expect(
        (
          calls.last[#cursor],
          calls.last[#action],
          calls.last[#community],
          calls.last[#subject],
        ),
        (null, 'remove', null, postUri),
      );

      await chooseActionFilter(tester, from: 'Removals', to: 'All actions');
      expect(calls, hasLength(5));
      expect(
        (
          calls.last[#cursor],
          calls.last[#action],
          calls.last[#community],
          calls.last[#subject],
        ),
        (null, null, null, postUri),
      );

      await tester.tap(find.text('Show all'));
      await pumpFrames(tester);
      expect(calls, hasLength(6));
      expect(
        (
          calls.last[#cursor],
          calls.last[#action],
          calls.last[#community],
          calls.last[#subject],
        ),
        (null, null, null, null),
      );
    },
  );

  testWidgets('Filters F5 production route shows post actions and Show all '
      'resets the list', (tester) async {
    const postUri = 'at://did:plc:author/social.coves.community.postv2/p1';
    final calls = <Map<Symbol, dynamic>>[];
    when(
      api.listModerationActions(
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
        action: anyNamed('action'),
        community: anyNamed('community'),
        subject: anyNamed('subject'),
      ),
    ).thenAnswer((invocation) async {
      calls.add(invocation.namedArguments);
      return ModerationActionPage(
        actions: [
          action(
            'did:web:coves.social',
            calls.length == 1 ? 'post-only' : 'all-posts',
          ),
        ],
      );
    });
    final router = createRouter(
      auth,
      _AcceptedEulaProvider(),
      _AcceptedGuidelinesProvider(),
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<CovesApiService>.value(value: api),
          Provider<ProfileCache>.value(value: cache),
          viewerAuthorityRegistration(auth: auth, apiService: api),
        ],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    router.go(
      '/modlog?subject=at%3A%2F%2Fdid%3Aplc%3Aauthor%2Fsocial.coves.community.postv2%2Fp1',
    );
    await pumpFrames(tester);
    expect(calls, hasLength(1));
    expect(calls.first[#subject], postUri);
    expect(calls.first[#cursor], isNull);
    expect(calls.first[#action], isNull);
    expect(calls.first[#community], isNull);
    expect(find.text('Showing actions for one post'), findsOneWidget);
    expect(tile('did:web:coves.social', 'post-only'), findsOneWidget);

    await tester.tap(find.text('Show all'));
    await pumpFrames(tester);
    expect(calls, hasLength(2));
    expect(calls.last[#cursor], isNull);
    expect(calls.last[#subject], isNull);
    expect(find.text('Showing actions for one post'), findsNothing);
    expect(tile('did:web:coves.social', 'post-only'), findsNothing);
    expect(tile('did:web:coves.social', 'all-posts'), findsOneWidget);
  });

  testWidgets(
    'Rows B4 resolves actor handles and falls back for failed or absent actors',
    (tester) async {
      final aliceProfile = Completer<UserProfile>();
      when(api.getProfile(actor: 'did:plc:alice'))
          .thenAnswer((_) => aliceProfile.future);
      when(api.getProfile(actor: 'did:plc:broken'))
          .thenAnswer((_) async => throw ApiException('boom', statusCode: 500));
      when(
        api.listModerationActions(
          cursor: anyNamed('cursor'),
          limit: anyNamed('limit'),
        ),
      ).thenAnswer(
        (_) async => ModerationActionPage(
          actions: [
            action('did:web:coves.social', 'alice', actorDid: 'did:plc:alice'),
            action(
              'did:web:coves.social',
              'broken',
              actorDid: 'did:plc:broken',
            ),
            action('did:web:coves.social', 'server'),
          ],
        ),
      );

      await pumpModlog(tester);
      expect(
        find.descendant(
          of: tile('did:web:coves.social', 'alice'),
          matching: renderedText('A moderator removed content'),
        ),
        findsOneWidget,
      );
      aliceProfile.complete(
        UserProfile(did: 'did:plc:alice', handle: 'alice.coves.social'),
      );
      await pumpFrames(tester);
      for (final (actionId, label) in [
        ('alice', '@alice.coves.social removed content'),
        ('broken', 'A moderator removed content'),
        ('server', 'Server admin removed content'),
      ]) {
        expect(
          find.descendant(
            of: tile('did:web:coves.social', actionId),
            matching: renderedText(label),
          ),
          findsOneWidget,
        );
      }
      expect(renderedTextContaining('did:plc:'), findsNothing);
    },
  );

  testWidgets(
    'Rows B4 a programming error in an actor lookup escapes so it reaches '
    'Sentry, and the row names a moderator, never the DID',
    (tester) async {
      when(api.getProfile(actor: 'did:plc:alice'))
          .thenAnswer((_) async => throw StateError('profile bug'));
      when(
        api.listModerationActions(
          cursor: anyNamed('cursor'),
          limit: anyNamed('limit'),
        ),
      ).thenAnswer(
        (_) async => ModerationActionPage(
          actions: [
            action('did:web:coves.social', 'alice', actorDid: 'did:plc:alice'),
          ],
        ),
      );

      // The screen loads in a guarded zone, so the lookup error escaping
      // _resolveActor lands in [uncaught] (as it reaches the app's Sentry
      // zone handler) instead of failing the test outright.
      final uncaught = <Object>[];
      await runZonedGuarded(
        () => pumpModlog(tester),
        (error, stack) => uncaught.add(error),
      );
      await pumpFrames(tester);

      expect(uncaught, [isA<StateError>()]);
      expect(tester.takeException(), isNull);
      expect(renderedTextContaining('did:plc:alice'), findsNothing);
      expect(
        find.descendant(
          of: tile('did:web:coves.social', 'alice'),
          matching: renderedText('A moderator removed content'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Rows B5 shares in-flight actor lookup and reads cached handles',
    (tester) async {
      final aliceProfile = Completer<UserProfile>();
      cache.put(UserProfile(did: 'did:plc:bob', handle: 'bob.coves.social'));
      when(api.getProfile(actor: 'did:plc:alice'))
          .thenAnswer((_) => aliceProfile.future);
      when(
        api.listModerationActions(
          cursor: anyNamed('cursor'),
          limit: anyNamed('limit'),
        ),
      ).thenAnswer(
        (_) async => ModerationActionPage(
          actions: [
            for (var index = 0; index < 3; index++)
              action(
                'did:web:coves.social',
                'alice-$index',
                actorDid: 'did:plc:alice',
              ),
            action('did:web:coves.social', 'bob', actorDid: 'did:plc:bob'),
          ],
        ),
      );

      await pumpModlog(tester, height: 900);
      aliceProfile.complete(
        UserProfile(did: 'did:plc:alice', handle: 'alice.coves.social'),
      );
      await pumpFrames(tester);
      for (var index = 0; index < 3; index++) {
        expect(
          find.descendant(
            of: tile('did:web:coves.social', 'alice-$index'),
            matching: renderedText('@alice.coves.social removed content'),
          ),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(
          of: tile('did:web:coves.social', 'bob'),
          matching: renderedText('@bob.coves.social removed content'),
        ),
        findsOneWidget,
      );
      verify(api.getProfile(actor: 'did:plc:alice')).called(1);
      verifyNever(api.getProfile(actor: 'did:plc:bob'));
    },
  );

  testWidgets(
    'Rows B8 a profile lookup that completes after unmount reports no error',
    (tester) async {
      final aliceProfile = Completer<UserProfile>();
      when(api.getProfile(actor: 'did:plc:alice'))
          .thenAnswer((_) => aliceProfile.future);
      when(
        api.listModerationActions(
          cursor: anyNamed('cursor'),
          limit: anyNamed('limit'),
        ),
      ).thenAnswer(
        (_) async => ModerationActionPage(
          actions: [
            action('did:web:coves.social', 'alice', actorDid: 'did:plc:alice'),
          ],
        ),
      );

      await pumpModlog(tester);
      expect(tile('did:web:coves.social', 'alice'), findsOneWidget);
      verify(api.getProfile(actor: 'did:plc:alice')).called(1);
      await tester.pumpWidget(const SizedBox());
      aliceProfile.complete(
        UserProfile(did: 'did:plc:alice', handle: 'alice.coves.social'),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Rows B6 reverses copy matches the full loaded reference and reason',
    (tester) async {
      when(
        api.listModerationActions(
          cursor: anyNamed('cursor'),
          limit: anyNamed('limit'),
        ),
      ).thenAnswer(
        (_) async => ModerationActionPage(
          actions: [
            action('did:web:coves.social', 'r1', reason: ModerationReason.spam),
            action(
              'did:web:coves.social',
              'r2',
              kind: ModerationActionKind.restore,
              reverses: const ModerationActionRef(
                serviceDid: 'did:web:coves.social',
                actionId: 'r1',
              ),
            ),
            action(
              'did:web:coves.social',
              'r3',
              kind: ModerationActionKind.restore,
              reverses: const ModerationActionRef(
                serviceDid: 'did:web:other.example',
                actionId: 'r1',
              ),
            ),
            action(
              'did:web:coves.social',
              'r4',
              kind: ModerationActionKind.restore,
              reverses: const ModerationActionRef(
                serviceDid: 'did:web:coves.social',
                actionId: 'r-missing',
              ),
            ),
            action('did:web:coves.social', 'r5'),
            action(
              'did:web:coves.social',
              'r6',
              kind: ModerationActionKind.restore,
              reverses: const ModerationActionRef(
                serviceDid: 'did:web:coves.social',
                actionId: 'r5',
              ),
            ),
          ],
        ),
      );

      await pumpModlog(tester, height: 1400);
      for (final (actionId, label) in [
        ('r2', 'Reverses removal for Spam'),
        ('r3', 'Reverses an earlier removal'),
        ('r4', 'Reverses an earlier removal'),
        ('r6', 'Reverses an earlier removal'),
      ]) {
        expect(
          find.descendant(
            of: tile('did:web:coves.social', actionId),
            matching: find.text(label),
          ),
          findsOneWidget,
        );
      }
      for (final actionId in ['r1', 'r5']) {
        for (final label in [
          'Reverses removal for Spam',
          'Reverses an earlier removal',
        ]) {
          expect(
            find.descendant(
              of: tile('did:web:coves.social', actionId),
              matching: find.text(label),
            ),
            findsNothing,
          );
        }
      }
    },
  );

  testWidgets('Rows B7 a later page resolves the earlier restore reference', (
    tester,
  ) async {
    final secondPage = Completer<ModerationActionPage>();
    when(
      api.listModerationActions(
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
      ),
    ).thenAnswer((invocation) {
      if (invocation.namedArguments[#cursor] == 'c1') {
        return secondPage.future;
      }
      return Future.value(
        ModerationActionPage(
          actions: [
            for (var index = 0; index < 24; index++)
              action('did:web:coves.social', 'first-$index'),
            action(
              'did:web:coves.social',
              'r2',
              kind: ModerationActionKind.restore,
              reverses: const ModerationActionRef(
                serviceDid: 'did:web:coves.social',
                actionId: 'r1',
              ),
            ),
          ],
          cursor: 'c1',
        ),
      );
    });

    await pumpModlog(tester);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
    await pumpFrames(tester);
    verify(api.listModerationActions(cursor: 'c1', limit: anyNamed('limit')))
        .called(1);
    final restore = tile('did:web:coves.social', 'r2');
    expect(restore, findsOneWidget);
    expect(
      find.descendant(
        of: restore,
        matching: find.text('Reverses an earlier removal'),
      ),
      findsOneWidget,
    );
    secondPage.complete(
      ModerationActionPage(
        actions: [
          action('did:web:coves.social', 'r1', reason: ModerationReason.spam),
        ],
      ),
    );
    await pumpFrames(tester);
    expect(
      find.descendant(
        of: restore,
        matching: find.text('Reverses removal for Spam'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'B5 renders server order, requests the next cursor and stops after '
    'the last page',
    (tester) async {
      final firstPage = List.generate(
        25,
        (index) => action('did:web:coves.social', 'first-$index'),
      );
      when(
        api.listModerationActions(
          cursor: anyNamed('cursor'),
          limit: anyNamed('limit'),
        ),
      ).thenAnswer(
        (invocation) async => switch (invocation.namedArguments[#cursor]) {
          null => ModerationActionPage(actions: firstPage, cursor: 'c1'),
          'c1' => ModerationActionPage(
            actions: [action('did:web:coves.social', 'second-0')],
          ),
          _ => throw StateError('Unexpected moderation cursor'),
        },
      );

      await pumpModlog(tester);
      expect(tile('did:web:coves.social', 'first-0'), findsOneWidget);
      expect(tile('did:web:coves.social', 'first-1'), findsOneWidget);
      expect(
        tester.getTopLeft(tile('did:web:coves.social', 'first-0')).dy,
        lessThan(tester.getTopLeft(tile('did:web:coves.social', 'first-1')).dy),
      );

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
      await pumpFrames(tester);
      verify(api.listModerationActions(cursor: 'c1', limit: anyNamed('limit')))
          .called(1);
      expect(tile('did:web:coves.social', 'second-0'), findsOneWidget);

      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
      await pumpFrames(tester);
      verifyNever(
        api.listModerationActions(cursor: 'c1', limit: anyNamed('limit')),
      );
      verify(api.listModerationActions(limit: anyNamed('limit'))).called(1);
    },
  );

  testWidgets(
    'B5 keys actions by full service DID and action ID across pages',
    (tester) async {
      when(
        api.listModerationActions(
          cursor: anyNamed('cursor'),
          limit: anyNamed('limit'),
        ),
      ).thenAnswer(
        (invocation) async => switch (invocation.namedArguments[#cursor]) {
          null => ModerationActionPage(
            actions: [
              action('did:web:first.example', 'dup'),
              action('did:web:second.example', 'dup'),
            ],
            cursor: 'c1',
          ),
          'c1' => ModerationActionPage(
            actions: [
              action('did:web:first.example', 'dup'),
              action('did:web:first.example', 'unique'),
            ],
          ),
          _ => throw StateError('Unexpected moderation cursor'),
        },
      );

      await pumpModlog(tester);
      expect(tile('did:web:first.example', 'dup'), findsOneWidget);
      expect(tile('did:web:second.example', 'dup'), findsOneWidget);
      verify(api.listModerationActions(cursor: 'c1', limit: anyNamed('limit')))
          .called(1);
      expect(tile('did:web:first.example', 'unique'), findsOneWidget);
    },
  );

  testWidgets('B5 loads the next cursor for a short page without scrolling', (
    tester,
  ) async {
    when(
      api.listModerationActions(
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
      ),
    ).thenAnswer(
      (invocation) async => switch (invocation.namedArguments[#cursor]) {
        null => ModerationActionPage(
          actions: [
            action('did:web:coves.social', 'short-0'),
            action('did:web:coves.social', 'short-1'),
          ],
          cursor: 'c1',
        ),
        'c1' => ModerationActionPage(
          actions: [action('did:web:coves.social', 'short-2')],
        ),
        _ => throw StateError('Unexpected moderation cursor'),
      },
    );

    await pumpModlog(tester);
    verify(api.listModerationActions(cursor: 'c1', limit: anyNamed('limit')))
        .called(1);
    expect(tile('did:web:coves.social', 'short-2'), findsOneWidget);
  });

  testWidgets(
    'B6 removal, unknown action and reasonless restore show their own copy',
    (tester) async {
      when(
        api.listModerationActions(
          cursor: anyNamed('cursor'),
          limit: anyNamed('limit'),
        ),
      ).thenAnswer(
        (_) async => ModerationActionPage(
          actions: [
            action(
              'did:web:coves.social',
              'removed',
              reason: ModerationReason.spam,
              createdAt: DateTime(2025, 10, 15, 11, 55),
            ),
            action(
              'did:web:coves.social',
              'unknown',
              kind: ModerationActionKind.unknown,
              reason: ModerationReason.unknown,
              subject: const ModerationSubjectRef(
                uri: 'at://did:plc:author/social.coves.community.post/p1',
              ),
            ),
            action(
              'did:web:coves.social',
              'restored',
              kind: ModerationActionKind.restore,
            ),
          ],
        ),
      );

      // A year away from the host clock, so "5m" can only come from the
      // injected clock.
      await pumpModlog(tester, clock: () => DateTime(2025, 10, 15, 12));
      final removed = tile('did:web:coves.social', 'removed');
      final unknown = tile('did:web:coves.social', 'unknown');
      final restored = tile('did:web:coves.social', 'restored');
      expect(
        find.descendant(
          of: removed,
          matching: renderedText('Server admin removed content'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: removed, matching: renderedText('5m')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: removed, matching: find.text('Spam')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: unknown,
          matching: renderedText(
            'Server admin took a moderation action on a post',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: unknown, matching: find.text('Other reason')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: restored,
          matching: renderedText('Server admin restored content'),
        ),
        findsOneWidget,
      );
      for (final label in [
        'Spam',
        'Harassment',
        'Doxing',
        'Illegal content',
        'Rule violation',
        'Moderator discretion',
        'Other reason',
      ]) {
        expect(
          find.descendant(of: restored, matching: find.text(label)),
          findsNothing,
        );
      }
    },
  );

  testWidgets('B6 each known reason has its own label', (tester) async {
    final cases = [
      (ModerationReason.harassment, 'Harassment'),
      (ModerationReason.doxing, 'Doxing'),
      (ModerationReason.illegalContent, 'Illegal content'),
      (ModerationReason.ruleViolation, 'Rule violation'),
      (ModerationReason.moderatorDiscretion, 'Moderator discretion'),
    ];
    when(
      api.listModerationActions(
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
      ),
    ).thenAnswer(
      (_) async => ModerationActionPage(
        actions: [
          for (final (reason, _) in cases)
            action('did:web:coves.social', reason.name, reason: reason),
        ],
      ),
    );

    await pumpModlog(tester, height: 1400);
    for (final (reason, label) in cases) {
      final row = tile('did:web:coves.social', reason.name);
      expect(
        find.descendant(of: row, matching: find.text(label)),
        findsOneWidget,
      );
    }
  });

  testWidgets(
    'B7 first-page failure shows FullScreenError and Retry loads rows',
    (tester) async {
      var calls = 0;
      when(
        api.listModerationActions(
          cursor: anyNamed('cursor'),
          limit: anyNamed('limit'),
        ),
      ).thenAnswer((_) async {
        if (calls++ == 0) {
          throw ServerException('Moderation unavailable', statusCode: 503);
        }
        return ModerationActionPage(
          actions: [action('did:web:coves.social', 'recovered')],
        );
      });

      await pumpModlog(tester);
      expect(find.byType(FullScreenError), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(FullScreenError),
          matching: find.text('Retry'),
        ),
      );
      await pumpFrames(tester);
      expect(tile('did:web:coves.social', 'recovered'), findsOneWidget);
    },
  );

  testWidgets('B7 empty first page shows the modlog empty message', (
    tester,
  ) async {
    when(
      api.listModerationActions(
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
      ),
    ).thenAnswer((_) async => const ModerationActionPage(actions: []));

    await pumpModlog(tester);
    expect(find.text('No moderation actions yet.'), findsOneWidget);
  });

  testWidgets('B8 invalid load-more cursor restarts from a fresh first page', (
    tester,
  ) async {
    var firstPageCalls = 0;
    when(
      api.listModerationActions(
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
      ),
    ).thenAnswer((invocation) async {
      if (invocation.namedArguments[#cursor] == 'c1') {
        throw ApiException(
          'Invalid cursor',
          statusCode: 400,
          errorCode: 'InvalidCursor',
        );
      }
      if (firstPageCalls++ == 0) {
        return ModerationActionPage(
          actions: List.generate(
            25,
            (index) => action('did:web:coves.social', 'old-$index'),
          ),
          cursor: 'c1',
        );
      }
      return ModerationActionPage(
        actions: List.generate(
          25,
          (index) => action('did:web:coves.social', 'fresh-$index'),
        ),
      );
    });

    await pumpModlog(tester);
    expect(tile('did:web:coves.social', 'old-0'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
    await pumpFrames(tester);
    verify(api.listModerationActions(cursor: 'c1', limit: anyNamed('limit')))
        .called(1);
    verify(api.listModerationActions(limit: anyNamed('limit'))).called(2);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 4000));
    await pumpFrames(tester);
    expect(tile('did:web:coves.social', 'fresh-0'), findsOneWidget);
    expect(find.byType(InlineError), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ModlogEntryTile &&
            widget.action.ref.actionId.startsWith('old-'),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'B8 server load-more failure keeps rows and retries the same cursor',
    (tester) async {
      var nextPageCalls = 0;
      when(
        api.listModerationActions(
          cursor: anyNamed('cursor'),
          limit: anyNamed('limit'),
        ),
      ).thenAnswer((invocation) async {
        if (invocation.namedArguments[#cursor] == 'c1') {
          if (nextPageCalls++ == 0) {
            throw ServerException(
              'Moderation unavailable',
              statusCode: 503,
              errorCode: 'ModerationUnavailable',
            );
          }
          return ModerationActionPage(
            actions: [action('did:web:coves.social', 'next-0')],
          );
        }
        return ModerationActionPage(
          actions: List.generate(
            25,
            (index) => action('did:web:coves.social', 'old-$index'),
          ),
          cursor: 'c1',
        );
      });

      await pumpModlog(tester);
      expect(tile('did:web:coves.social', 'old-0'), findsOneWidget);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
      await pumpFrames(tester);
      expect(tile('did:web:coves.social', 'old-24'), findsOneWidget);
      expect(find.byType(InlineError), findsOneWidget);
      final footerRetry = find.descendant(
        of: find.byType(InlineError),
        matching: find.text('Retry'),
      );
      // The error footer is taller than the loading slot; scroll it in.
      await tester.ensureVisible(footerRetry);
      await tester.pump();
      await tester.tap(footerRetry);
      await pumpFrames(tester);
      verify(api.listModerationActions(cursor: 'c1', limit: anyNamed('limit')))
          .called(2);
      verify(api.listModerationActions(limit: anyNamed('limit'))).called(1);
      expect(tile('did:web:coves.social', 'old-24'), findsOneWidget);
    },
  );

  testWidgets(
    'B8 load-more failure leaves a reader above the end where they are',
    (tester) async {
      when(
        api.listModerationActions(
          cursor: anyNamed('cursor'),
          limit: anyNamed('limit'),
        ),
      ).thenAnswer((invocation) async {
        if (invocation.namedArguments[#cursor] == 'c1') {
          throw ServerException('Moderation unavailable', statusCode: 503);
        }
        return ModerationActionPage(
          actions: List.generate(
            25,
            (index) => action('did:web:coves.social', 'old-$index'),
          ),
          cursor: 'c1',
        );
      });

      await pumpModlog(tester);
      final position = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      final readingOffset =
          position.maxScrollExtent - position.viewportDimension;
      expect(readingOffset, greaterThan(0));
      position.jumpTo(readingOffset);
      await pumpFrames(tester);
      verify(api.listModerationActions(cursor: 'c1', limit: anyNamed('limit')))
          .called(1);
      expect(position.pixels, readingOffset);
      position.jumpTo(position.maxScrollExtent);
      await pumpFrames(tester);
      expect(find.byType(InlineError), findsOneWidget);
    },
  );

  // Fake-time latency for mock responses. The scroll trigger's throttle reads
  // the real clock, so each round lets real time pass before the next response
  // lands, the way a network round trip would.
  const responseLatency = Duration(milliseconds: 10);

  Future<void> runRequestRounds(WidgetTester tester, int rounds) async {
    for (var round = 0; round < rounds; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump(responseLatency);
      await tester.pump();
    }
  }

  ApiException invalidCursor() => ApiException(
    'Invalid cursor',
    statusCode: 400,
    errorCode: 'InvalidCursor',
  );

  testWidgets(
    'B8 failed invalid-cursor recovery stops on the full-screen Retry',
    (tester) async {
      var firstPageCalls = 0;
      when(
        api.listModerationActions(
          cursor: anyNamed('cursor'),
          limit: anyNamed('limit'),
        ),
      ).thenAnswer((invocation) async {
        await Future<void>.delayed(responseLatency);
        if (invocation.namedArguments[#cursor] == 'c1') {
          throw invalidCursor();
        }
        if (firstPageCalls++ == 1) {
          throw ServerException('Moderation unavailable', statusCode: 503);
        }
        return ModerationActionPage(
          actions: [action('did:web:coves.social', 'short-0')],
          cursor: 'c1',
        );
      });

      await pumpModlog(tester);
      await runRequestRounds(tester, 8);
      verify(api.listModerationActions(cursor: 'c1', limit: anyNamed('limit')))
          .called(1);
      verify(api.listModerationActions(limit: anyNamed('limit'))).called(2);
      final fullScreenRetry = find.descendant(
        of: find.byType(FullScreenError),
        matching: find.text('Retry'),
      );
      expect(fullScreenRetry, findsOneWidget);

      // Retry starts a new chain: the still-rejected cursor earns one more
      // recovery, then stops on the footer Retry.
      await tester.tap(fullScreenRetry);
      await runRequestRounds(tester, 8);
      verify(api.listModerationActions(limit: anyNamed('limit'))).called(2);
      verify(api.listModerationActions(cursor: 'c1', limit: anyNamed('limit')))
          .called(2);
      expect(
        find.descendant(
          of: find.byType(InlineError),
          matching: find.text('Retry'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'B8 a cursor rejected again after recovery stops on the footer Retry',
    (tester) async {
      when(
        api.listModerationActions(
          cursor: anyNamed('cursor'),
          limit: anyNamed('limit'),
        ),
      ).thenAnswer((invocation) async {
        await Future<void>.delayed(responseLatency);
        if (invocation.namedArguments[#cursor] != null) {
          throw invalidCursor();
        }
        return ModerationActionPage(
          actions: [
            action('did:web:coves.social', 'short-0'),
            action('did:web:coves.social', 'short-1'),
          ],
          cursor: 'c1',
        );
      });
      final footerRetry = find.descendant(
        of: find.byType(InlineError),
        matching: find.text('Retry'),
      );

      await pumpModlog(tester);
      await runRequestRounds(tester, 8);
      verify(api.listModerationActions(cursor: 'c1', limit: anyNamed('limit')))
          .called(2);
      verify(api.listModerationActions(limit: anyNamed('limit'))).called(2);
      expect(footerRetry, findsOneWidget);

      // The footer Retry earns one more recovery, not a loop.
      await tester.tap(footerRetry);
      await runRequestRounds(tester, 8);
      verify(api.listModerationActions(cursor: 'c1', limit: anyNamed('limit')))
          .called(2);
      verify(api.listModerationActions(limit: anyNamed('limit'))).called(1);
      expect(footerRetry, findsOneWidget);
    },
  );

  testWidgets(
    'B8 a successful page earns the next invalid cursor its own recovery',
    (tester) async {
      var firstCursorCalls = 0;
      var secondCursorCalls = 0;
      when(
        api.listModerationActions(
          cursor: anyNamed('cursor'),
          limit: anyNamed('limit'),
        ),
      ).thenAnswer((invocation) async {
        await Future<void>.delayed(responseLatency);
        switch (invocation.namedArguments[#cursor]) {
          case 'c1':
            if (firstCursorCalls++ == 0) {
              throw invalidCursor();
            }
            return ModerationActionPage(
              actions: [action('did:web:coves.social', 'short-1')],
              cursor: 'c2',
            );
          case 'c2':
            if (secondCursorCalls++ == 0) {
              throw invalidCursor();
            }
            return ModerationActionPage(
              actions: [action('did:web:coves.social', 'short-2')],
            );
          default:
            return ModerationActionPage(
              actions: [action('did:web:coves.social', 'short-0')],
              cursor: 'c1',
            );
        }
      });

      await pumpModlog(tester);
      await runRequestRounds(tester, 12);
      verify(api.listModerationActions(limit: anyNamed('limit'))).called(3);
      verify(api.listModerationActions(cursor: 'c1', limit: anyNamed('limit')))
          .called(3);
      verify(api.listModerationActions(cursor: 'c2', limit: anyNamed('limit')))
          .called(2);
      expect(tile('did:web:coves.social', 'short-2'), findsOneWidget);
      expect(find.byType(InlineError), findsNothing);
    },
  );

  testWidgets('B11 the Post link of a row is its own link semantics node', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    when(
      api.listModerationActions(
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
        action: anyNamed('action'),
        community: anyNamed('community'),
        subject: anyNamed('subject'),
      ),
    ).thenAnswer(
      (_) async => ModerationActionPage(
        actions: [
          action(
            'did:web:coves.social',
            'post-row',
            reason: ModerationReason.spam,
            subject: const ModerationSubjectRef(
              uri: 'at://did:plc:author/social.coves.community.postv2/p1',
            ),
          ),
        ],
      ),
    );

    await pumpModlog(tester);
    final post = find.descendant(
      of: tile('did:web:coves.social', 'post-row'),
      matching: find.text('Post'),
    );
    expect(post, findsOneWidget);
    expect(
      tester.getSemantics(post),
      isSemantics(label: 'Post', isLink: true, hasTapAction: true),
    );
    handle.dispose();
  });
}
