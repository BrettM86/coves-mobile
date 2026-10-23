// Every sign-in gate a signed-out viewer can hit on a post or comment:
// choosing "Sign In" in the SignInDialog opens the /login route, and
// choosing "Cancel" (where the surface acknowledges it) shows the surface's
// snackbar and stays put.
import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/screens/home/post_detail_loader.dart';
import 'package:coves_flutter/utils/post_detail_route.dart';
import 'package:coves_flutter/widgets/comment_card.dart';
import 'package:coves_flutter/widgets/icons/animated_heart_icon.dart';
import 'package:coves_flutter/widgets/post_card.dart';
import 'package:coves_flutter/widgets/sign_in_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/post_options_menu_rows.dart';
import '../test_helpers/pump_helpers.dart';

const _loginMarker = 'LOGIN ROUTE';

/// Where the gate is reached from.
enum _Surface {
  /// The feed card (PostCard) on the root route.
  feedCard,

  /// The post detail screen, pushed over the root route through the
  /// production hand-over; its app bar ⋮ hosts PostOptionsMenu.
  postDetail,

  /// A CommentCard on the root route.
  commentCard,
}

/// Starts the gated action on the surface, leaving the SignInDialog up.
typedef _Trigger = Future<void> Function(WidgetTester tester);

typedef _GateRow = ({
  String name,
  _Surface surface,
  _Trigger trigger,
  String dialogMessage,

  /// The snackbar the surface shows when the viewer cancels, or null when
  /// the surface shows none.
  String? cancelSnackbar,
});

Future<void> _tapUpvote(WidgetTester tester) async {
  await tester.tap(find.byType(AnimatedHeartIcon));
  await pumpFrames(tester);
}

_Trigger _pickMenuEntry(String menuTooltip, String entry) => (tester) async {
  await tester.tap(find.byTooltip(menuTooltip));
  await pumpFrames(tester);
  expect(find.text(entry), findsOneWidget);
  await tester.tap(find.text(entry));
  await pumpFrames(tester);
};

final List<_GateRow> _rows = [
  (
    name: 'post card upvote',
    surface: _Surface.feedCard,
    trigger: _tapUpvote,
    dialogMessage: 'You need to sign in to vote on posts.',
    cancelSnackbar: null,
  ),
  (
    name: 'card menu Subscribe',
    surface: _Surface.feedCard,
    trigger: _pickMenuEntry('Post options', 'Subscribe to !Gaming'),
    dialogMessage: 'You need to sign in to subscribe to communities.',
    cancelSnackbar: 'Sign in required to subscribe',
  ),
  (
    name: 'card menu Report post',
    surface: _Surface.feedCard,
    trigger: _pickMenuEntry('Post options', 'Report post'),
    dialogMessage: 'You need to sign in to report content.',
    cancelSnackbar: 'Sign in required to report content',
  ),
  (
    name: 'detail menu Report post',
    surface: _Surface.postDetail,
    trigger: _pickMenuEntry('More options', 'Report post'),
    dialogMessage: 'You need to sign in to report content.',
    cancelSnackbar: 'Sign in required to report content',
  ),
  (
    name: 'card menu Block user',
    surface: _Surface.feedCard,
    trigger: _pickMenuEntry('Post options', 'Block @alice.coves.social'),
    dialogMessage: 'You need to sign in to block users.',
    cancelSnackbar: 'Sign in required to block users',
  ),
  (
    name: 'card menu Block community',
    surface: _Surface.feedCard,
    trigger: _pickMenuEntry('Post options', 'Block !Gaming'),
    dialogMessage: 'You need to sign in to block communities.',
    cancelSnackbar: 'Sign in required to block communities',
  ),
  (
    name: 'comment upvote',
    surface: _Surface.commentCard,
    trigger: _tapUpvote,
    dialogMessage: 'You need to sign in to vote on comments.',
    cancelSnackbar: null,
  ),
];

final CommentView _comment = CommentView(
  uri: 'at://did:plc:bob/social.coves.community.comment/c1',
  cid: 'cid-c1',
  record: const CommentRecord(content: 'A comment'),
  createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
  indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
  author: AuthorView(did: 'did:plc:bob', handle: 'bob.coves.social'),
  post: CommentRef(
    uri: 'at://did:plc:alice/social.coves.community.post/p1',
    cid: 'cid-p1',
  ),
  stats: const CommentStats(),
);

/// Pumps [surface] for a signed-out viewer under a GoRouter whose /login
/// route renders [_loginMarker].
Future<void> _pumpSignedOut(WidgetTester tester, _Surface surface) async {
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
  final harness = MenuHarness.create(MenuViewer.signedOut);
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
  final post = menuPost(MenuViewer.signedOut);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: switch (surface) {
            _Surface.feedCard => PostCard(
              post: post,
              sessionStamp: harness.sessionStamp,
            ),
            _Surface.postDetail => TextButton(
              onPressed: () => pushPostDetail(
                context,
                post: post,
                sessionStamp: harness.sessionStamp,
              ),
              child: const Text('Open post'),
            ),
            _Surface.commentCard => CommentCard(
              comment: _comment,
              sessionStamp: null,
            ),
          },
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
        path: '/login',
        builder: (_, _) => const Scaffold(body: Text(_loginMarker)),
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
  if (surface == _Surface.postDetail) {
    await tester.tap(find.text('Open post'));
    await pumpFrames(tester);
    expect(find.byType(PostDetailLoader), findsOneWidget);
  }
}

/// Opens [row]'s gate and checks the dialog it shows.
Future<void> _openGate(WidgetTester tester, _GateRow row) async {
  await _pumpSignedOut(tester, row.surface);
  await row.trigger(tester);
  expect(find.byType(SignInDialog), findsOneWidget);
  expect(
    find.descendant(
      of: find.byType(SignInDialog),
      matching: find.text(row.dialogMessage),
    ),
    findsOneWidget,
  );
}

/// Unmounts the tree and runs out any snackbar timer.
Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 5));
}

void main() {
  group('Sign In in the sign-in dialog opens /login', () {
    for (final row in _rows) {
      testWidgets(row.name, (tester) async {
        await _openGate(tester, row);

        await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
        await pumpFrames(tester);

        expect(find.byType(SignInDialog), findsNothing);
        expect(find.text(_loginMarker), findsOneWidget);
        await _finish(tester);
      });
    }
  });

  group('Cancel in the sign-in dialog stays put and says why', () {
    for (final row in _rows.where((row) => row.cancelSnackbar != null)) {
      testWidgets(row.name, (tester) async {
        await _openGate(tester, row);

        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await pumpFrames(tester);

        expect(find.byType(SignInDialog), findsNothing);
        expect(find.text(row.cancelSnackbar!), findsOneWidget);
        expect(find.text(_loginMarker), findsNothing);
        await _finish(tester);
      });
    }

    // A barrier tap (or Android back) closes the dialog with no answer;
    // that counts as Cancel, not Sign In.
    testWidgets('dismissing without a button counts as Cancel', (tester) async {
      final row = _rows.firstWhere((row) => row.cancelSnackbar != null);
      await _openGate(tester, row);

      await tester.tapAt(const Offset(10, 10));
      await pumpFrames(tester);

      expect(find.byType(SignInDialog), findsNothing);
      expect(find.text(row.cancelSnackbar!), findsOneWidget);
      expect(find.text(_loginMarker), findsNothing);
      await _finish(tester);
    });
  });
}
