// What the post detail app bar's ⋮ entries do: Delete post leaves detail
// only once the server confirms it, signed-out entries ask the viewer to
// sign in, and Subscribe changes the subscription the menu offers next.
import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post_get_result.dart';
import 'package:coves_flutter/screens/home/post_detail_loader.dart';
import 'package:coves_flutter/screens/home/post_detail_screen.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/utils/post_detail_route.dart';
import 'package:coves_flutter/widgets/sign_in_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/post_options_menu_rows.dart';
import '../test_helpers/pump_helpers.dart';

const _feedMarker = 'FEED UNDER DETAIL';
const _postUri = 'at://did:plc:alice/social.coves.community.post/p1';

final Finder _detail = find.byType(PostDetailScreen);

/// Pumps a stub feed route under a GoRouter wired like the app's
/// `/post/:postUri`, then opens [viewer]'s view of the menu post through
/// the production hand-over, so the production [PostDetailLoader] hosts the
/// detail. Comments load empty.
Future<MenuHarness> _pumpDetailOverFeed(
  WidgetTester tester,
  MenuViewer viewer,
) async {
  tester.view.physicalSize = const Size(540, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (_) async => null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  final harness = MenuHarness.create(viewer);
  when(
    harness.api.getComments(
      postUri: anyNamed('postUri'),
      sort: anyNamed('sort'),
      timeframe: anyNamed('timeframe'),
      depth: anyNamed('depth'),
      limit: anyNamed('limit'),
      cursor: anyNamed('cursor'),
      parentRkey: anyNamed('parentRkey'),
    ),
  ).thenAnswer((_) async => CommentsResponse(post: null, comments: const []));
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: Column(
            children: [
              const Text(_feedMarker),
              TextButton(
                onPressed: () => pushPostDetail(
                  context,
                  post: menuPost(viewer),
                  sessionStamp: harness.sessionStamp,
                ),
                child: const Text('Open post'),
              ),
            ],
          ),
        ),
      ),
      GoRoute(
        path: '/post/:postUri',
        builder: (_, state) {
          final loadedPost = state.extra! as PostDetailRouteExtra;
          return PostDetailLoader(
            postUri: loadedPost.post.post.uri,
            loadedPost: loadedPost,
          );
        },
      ),
      GoRoute(
        path: '/profile/:did',
        builder: (_, state) =>
            Scaffold(body: Text('PROFILE ${state.pathParameters['did']}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  // Unmounted before the router and the harness's providers are disposed.
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  await tester.pumpWidget(
    MultiProvider(
      providers: harness.providers,
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    ),
  );
  await pumpFrames(tester);
  await tester.tap(find.text('Open post'));
  await pumpFrames(tester);
  expect(_detail, findsOneWidget);
  expect(find.text(_feedMarker), findsNothing);
  return harness;
}

/// Opens the detail app bar's ⋮ menu.
Future<void> _openDetailMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('More options'));
  await pumpFrames(tester);
}

/// Picks Delete post in the open detail menu, leaving the confirm dialog up.
Future<void> _pickDelete(WidgetTester tester) async {
  await _openDetailMenu(tester);
  expect(find.text('Delete post'), findsOneWidget);
  await tester.tap(find.text('Delete post'));
  await pumpFrames(tester);
  expect(find.text('Delete Post'), findsOneWidget);
}

/// Holds every deletePost on [harness]'s API until the returned completer
/// is answered. A deleted post reads back as not found.
Completer<void> _holdDelete(MenuHarness harness) {
  final deletion = Completer<void>();
  addTearDown(() {
    if (!deletion.isCompleted) {
      deletion.complete();
    }
  });
  when(harness.api.deletePost(uri: anyNamed('uri')))
      .thenAnswer((_) => deletion.future);
  when(harness.api.getPost(_postUri))
      .thenAnswer((_) async => const PostGetNotFound(_postUri));
  return deletion;
}

/// Unmounts the tree and runs out the snackbar timer.
Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 5));
}

void main() {
  setUp(() {
    provideDummy<PostGetResult>(const PostGetNotFound(_postUri));
  });

  group('B5 Delete post from detail', () {
    testWidgets('B5 confirmed and accepted by the server returns to the '
        'route underneath', (tester) async {
      final harness = await _pumpDetailOverFeed(tester, MenuViewer.postAuthor);
      final deletion = _holdDelete(harness);
      await _pickDelete(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await pumpFrames(tester);
      // Premise: while the request is in flight, detail stays.
      expect(_detail, findsOneWidget);
      expect(find.text(_feedMarker), findsNothing);

      deletion.complete();
      await pumpFrames(tester);
      await pumpFrames(tester);

      expect(find.byType(PostDetailLoader), findsNothing);
      expect(find.text('Post Not Found'), findsNothing);
      expect(find.text(_feedMarker), findsOneWidget);
      await _finish(tester);
    });

    testWidgets('B5 accepted after the viewer opened another route over '
        'detail leaves that route on top and shows detail as not found '
        'underneath', (tester) async {
      final harness = await _pumpDetailOverFeed(tester, MenuViewer.postAuthor);
      final deletion = _holdDelete(harness);
      await _pickDelete(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await pumpFrames(tester);
      expect(_detail, findsOneWidget);

      // While the request is in flight, the viewer opens the author's
      // profile on top of detail.
      unawaited(
        GoRouter.of(tester.element(_detail)).push('/profile/did:plc:alice'),
      );
      await pumpFrames(tester);
      expect(find.text('PROFILE did:plc:alice'), findsOneWidget);

      deletion.complete();
      await pumpFrames(tester);
      await pumpFrames(tester);

      expect(find.text('PROFILE did:plc:alice'), findsOneWidget);

      GoRouter.of(tester.element(find.text('PROFILE did:plc:alice'))).pop();
      await pumpFrames(tester);

      expect(find.byType(PostDetailLoader), findsOneWidget);
      expect(find.text('Menu post'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Post Not Found'),
        ),
        findsOneWidget,
      );
      expect(find.text(_feedMarker), findsNothing);
      await _finish(tester);
    });

    testWidgets('B5 cancelled in the confirm dialog keeps detail open', (
      tester,
    ) async {
      final harness = await _pumpDetailOverFeed(tester, MenuViewer.postAuthor);
      _holdDelete(harness);
      await _pickDelete(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await pumpFrames(tester);

      expect(find.text('Delete Post'), findsNothing);
      expect(_detail, findsOneWidget);
      expect(
        find.descendant(of: _detail, matching: find.text('Menu post')),
        findsOneWidget,
      );
      expect(find.text(_feedMarker), findsNothing);
    });

    for (final row in <({String name, Object error})>[
      (
        name: 'a network failure',
        error: NetworkException('Connection refused'),
      ),
      (
        name: 'a server rejection',
        error: ApiException('Internal error', statusCode: 500),
      ),
    ]) {
      testWidgets('B5 failing with ${row.name} keeps detail open', (
        tester,
      ) async {
        final harness = await _pumpDetailOverFeed(
          tester,
          MenuViewer.postAuthor,
        );
        final deletion = _holdDelete(harness);
        await _pickDelete(tester);
        await tester.tap(find.widgetWithText(TextButton, 'Delete'));
        await pumpFrames(tester);

        deletion.completeError(row.error);
        await pumpFrames(tester);
        await pumpFrames(tester);

        expect(_detail, findsOneWidget);
        expect(
          find.descendant(of: _detail, matching: find.text('Menu post')),
          findsOneWidget,
        );
        expect(find.text(_feedMarker), findsNothing);
        await _finish(tester);
      });
    }
  });

  group('B6 signed-out detail menu entries ask to sign in', () {
    for (final row in <({String entry, String message})>[
      (
        entry: 'Subscribe to !Gaming',
        message: 'You need to sign in to subscribe to communities.',
      ),
      (entry: 'Report post', message: 'You need to sign in to report content.'),
      (
        entry: 'Block @alice.coves.social',
        message: 'You need to sign in to block users.',
      ),
      (
        entry: 'Block !Gaming',
        message: 'You need to sign in to block communities.',
      ),
    ]) {
      testWidgets('B6 ${row.entry}', (tester) async {
        await _pumpDetailOverFeed(tester, MenuViewer.signedOut);
        await _openDetailMenu(tester);
        expect(find.text(row.entry), findsOneWidget);

        await tester.tap(find.text(row.entry));
        await pumpFrames(tester);

        expect(find.byType(SignInDialog), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(SignInDialog),
            matching: find.text(row.message),
          ),
          findsOneWidget,
        );
      });
    }
  });

  testWidgets('B7 Subscribe from the detail menu subscribes, so the menu '
      'next offers Unsubscribe', (tester) async {
    final harness = await _pumpDetailOverFeed(
      tester,
      MenuViewer.signedInNotSubscribed,
    );
    when(harness.api.subscribeToCommunity(community: menuCommunityDid))
        .thenAnswer(
          (_) async =>
              'at://did:plc:viewer/social.coves.community.subscription/s1',
        );
    await _openDetailMenu(tester);
    expect(find.text('Subscribe to !Gaming'), findsOneWidget);

    await tester.tap(find.text('Subscribe to !Gaming'));
    await pumpFrames(tester);
    await _openDetailMenu(tester);

    expect(find.text('Unsubscribe from !Gaming'), findsOneWidget);
    expect(find.text('Subscribe to !Gaming'), findsNothing);
    await _finish(tester);
  });
}
