import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/moderation.dart';
import 'package:coves_flutter/models/moderation_action.dart';
import 'package:coves_flutter/widgets/moderation/modlog_entry_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const commentUri = 'at://did:plc:author/social.coves.community.comment/c1';
const encodingSensitiveCommentUri =
    'at://did:web:example.com%3A8443/social.coves.community.comment/c1';
const postRootUri = 'at://did:plc:author/social.coves.community.post/p1';
const postv2RootUri = 'at://did:plc:author/social.coves.community.postv2/p1';

ModerationActionView actionFixture({ModerationSubjectRef? subject}) =>
    ModerationActionView(
      ref: const ModerationActionRef(
        serviceDid: 'did:web:coves.social',
        actionId: 'a1',
      ),
      action: ModerationActionKind.remove,
      createdAt: DateTime.utc(2026, 10, 2),
      authorityDid: 'did:web:coves.social',
      scope: const ModerationScope(kind: ModerationScopeKind.instance),
      origin: 'local',
      subject: subject,
    );

/// Pumps the tile at '/' with a '/post/:postUri' route that shows the decoded
/// path parameter and `comment` query parameter it was reached with.
Future<GoRouter> pumpTile(
  WidgetTester tester,
  ModerationActionView action, {
  ModerationSubjectRef? privateSubject,
}) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: ModlogEntryTile(action: action, privateSubject: privateSubject),
        ),
      ),
      GoRoute(
        path: '/post/:postUri',
        builder: (context, state) => Scaffold(
          body: Column(
            children: [
              Text('postUri:${state.pathParameters['postUri']}'),
              Text('comment:${state.uri.queryParameters['comment']}'),
            ],
          ),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
  );
  return router;
}

final Finder postRoute = find.byWidgetPredicate(
  (widget) => widget is Text && (widget.data?.startsWith('postUri:') ?? false),
);

/// Taps 'Comment', expects the post route with [root] and [comment], then pops
/// back to the tile to prove the route was pushed rather than replaced.
Future<void> expectCommentOpensThread(
  WidgetTester tester,
  GoRouter router, {
  required String root,
  required String comment,
  required String reason,
}) async {
  await tester.tap(find.text('Comment'));
  await tester.pumpAndSettle();
  expect(find.text('postUri:$root'), findsOneWidget, reason: reason);
  expect(find.text('comment:$comment'), findsOneWidget, reason: reason);

  expect(router.canPop(), isTrue, reason: reason);
  router.pop();
  await tester.pumpAndSettle();
  expect(postRoute, findsNothing, reason: reason);
  expect(find.text('Comment'), findsOneWidget, reason: reason);
}

void main() {
  testWidgets('B2 a comment with a root post opens the root thread focused on '
      'the comment', (tester) async {
    final cases = [
      ('post root', postRootUri, commentUri),
      ('postv2 root', postv2RootUri, commentUri),
      (
        'encoding-sensitive comment URI',
        postRootUri,
        encodingSensitiveCommentUri,
      ),
    ];

    for (final (name, root, comment) in cases) {
      final handle = tester.ensureSemantics();
      final router = await pumpTile(
        tester,
        actionFixture(
          subject: ModerationSubjectRef(uri: comment, rootUri: root),
        ),
      );
      final label = find.text('Comment');
      expect(label, findsOneWidget, reason: name);
      expect(
        tester.getSemantics(label),
        isSemantics(label: 'Comment', isLink: true, hasTapAction: true),
        reason: name,
      );
      handle.dispose();

      await expectCommentOpensThread(
        tester,
        router,
        root: root,
        comment: comment,
        reason: name,
      );
    }
  });

  testWidgets('B3 a comment without a usable root post stays plain text', (
    tester,
  ) async {
    final cases = [
      ('no root', null),
      (
        'comment-collection root',
        'at://did:plc:author/social.coves.community.comment/c0',
      ),
      ('malformed root', 'not-a-uri'),
    ];

    for (final (name, root) in cases) {
      final handle = tester.ensureSemantics();
      await pumpTile(
        tester,
        actionFixture(
          subject: ModerationSubjectRef(uri: commentUri, rootUri: root),
        ),
      );
      final label = find.text('Comment');
      expect(label, findsOneWidget, reason: name);
      expect(
        tester.getSemantics(label),
        isSemantics(isLink: false),
        reason: name,
      );
      handle.dispose();

      await tester.tap(label, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(postRoute, findsNothing, reason: name);
      expect(find.byType(ModlogEntryTile), findsOneWidget, reason: name);
    }
  });

  testWidgets('B4 an admin row takes the root post from the private subject', (
    tester,
  ) async {
    const privateSubject = ModerationSubjectRef(
      uri: commentUri,
      rootUri: postRootUri,
    );
    final cases = [
      (
        'public comment without root',
        actionFixture(subject: const ModerationSubjectRef(uri: commentUri)),
        false,
      ),
      ('public subject hidden', actionFixture(), true),
    ];

    for (final (name, action, hiddenFromPublicLog) in cases) {
      final router = await pumpTile(
        tester,
        action,
        privateSubject: privateSubject,
      );
      if (hiddenFromPublicLog) {
        expect(
          find.text('Hidden from public log'),
          findsOneWidget,
          reason: name,
        );
      }
      await expectCommentOpensThread(
        tester,
        router,
        root: postRootUri,
        comment: commentUri,
        reason: name,
      );
    }
  });
}
