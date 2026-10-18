import 'package:coves_flutter/constants/app_colors.dart';
import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/moderation.dart';
import 'package:coves_flutter/models/moderation_action.dart';
import 'package:coves_flutter/widgets/moderation/modlog_entry_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../test_helpers/modlog_fixtures.dart'
    show renderedText, renderedTextContaining;

ModerationActionView actionFixture({
  String actionId = 'a1',
  ModerationActionKind kind = ModerationActionKind.remove,
  ModerationReason? reason,
  ModerationActionRef? reverses,
  ModerationSubjectRef? subject,
  ModerationContentSnapshot? contentSnapshot,
  String? actorDid,
  ModerationScope scope = const ModerationScope(
    kind: ModerationScopeKind.instance,
  ),
}) => ModerationActionView(
  ref: ModerationActionRef(
    serviceDid: 'did:web:coves.social',
    actionId: actionId,
  ),
  action: kind,
  reason: reason,
  reverses: reverses,
  createdAt: DateTime.utc(2026, 10, 2),
  authorityDid: 'did:web:coves.social',
  scope: scope,
  origin: 'local',
  subject: subject,
  contentSnapshot: contentSnapshot,
  actorDid: actorDid,
);

Future<void> pumpTile(
  WidgetTester tester,
  ModerationActionView action, {
  ModerationActionView? reversedAction,
  ModerationContentSnapshot? privateContentSnapshot,
  ModerationSubjectRef? privateSubject,
  String? actorHandle,
  String? privateActorDid,
}) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: ModlogEntryTile(
            action: action,
            reversedAction: reversedAction,
            privateContentSnapshot: privateContentSnapshot,
            privateSubject: privateSubject,
            actorHandle: actorHandle,
            privateActorDid: privateActorDid,
          ),
        ),
      ),
      GoRoute(
        path: '/profile/:did',
        builder: (context, state) =>
            Scaffold(body: Text('PROFILE ${state.pathParameters['did']}')),
      ),
      GoRoute(
        path: '/post/:postUri',
        builder: (context, state) => Scaffold(body: Text('post:${state.uri}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
  );
}

/// The style [label]'s span is drawn with in the rendered headline: its own
/// style merged over every enclosing span's.
TextStyle actorSpanStyle(WidgetTester tester, String label) {
  final headline = tester.widget<RichText>(renderedTextContaining(label));
  TextStyle? found;
  void visit(InlineSpan span, TextStyle inherited) {
    final style = inherited.merge(span.style);
    if (span is TextSpan) {
      if (span.text == label) {
        found = style;
      }
      for (final child in span.children ?? const <InlineSpan>[]) {
        visit(child, style);
      }
    }
  }

  visit(headline.text, const TextStyle());
  expect(found, isNotNull, reason: 'no span drawn as "$label"');
  return found!;
}

void main() {
  testWidgets('B1 labels subjects and leaves non-post subjects on the tile', (
    tester,
  ) async {
    final malformedSubject = ModerationActionView.tryParse({
      'ref': {'serviceDid': 'did:web:coves.social', 'actionId': 'a1'},
      'action': 'remove',
      'createdAt': '2026-10-01T12:00:00.000Z',
      'authorityDid': 'did:web:coves.social',
      'scope': {'kind': 'instance'},
      'origin': 'local',
      'subject': {'cid': 'bafy'},
    })!;
    final cases = [
      (
        'post',
        actionFixture(
          subject: const ModerationSubjectRef(
            uri: 'at://did:plc:author/social.coves.community.post/p1',
          ),
        ),
        'Post',
        false,
      ),
      (
        'comment',
        actionFixture(
          subject: const ModerationSubjectRef(
            uri: 'at://did:plc:author/social.coves.community.comment/c1',
          ),
        ),
        'Comment',
        true,
      ),
      (
        'other collection',
        actionFixture(
          subject: const ModerationSubjectRef(
            uri: 'at://did:plc:a/app.bsky.feed.post/x',
          ),
        ),
        'Item',
        true,
      ),
      (
        'non-AT-URI',
        actionFixture(
          subject: const ModerationSubjectRef(
            uri: 'https://example.com/social.coves.community.post/p1',
          ),
        ),
        'Item',
        true,
      ),
      (
        'missing rkey',
        actionFixture(
          subject: const ModerationSubjectRef(
            uri: 'at://did:plc:author/social.coves.community.post',
          ),
        ),
        'Item',
        true,
      ),
      (
        'extra segment',
        actionFixture(
          subject: const ModerationSubjectRef(
            uri: 'at://did:plc:author/social.coves.community.post/p1/extra',
          ),
        ),
        'Item',
        true,
      ),
      ('absent subject', actionFixture(), 'Content not shown', true),
      ('malformed subject', malformedSubject, 'Content not shown', true),
    ];

    for (final (name, action, label, staysOnTile) in cases) {
      await pumpTile(tester, action);
      final subjectText = find.text(label);
      expect(subjectText, findsOneWidget, reason: name);
      if (staysOnTile) {
        await tester.tap(subjectText, warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Text && (widget.data?.startsWith('post:') ?? false),
          ),
          findsNothing,
          reason: name,
        );
        expect(find.byType(ModlogEntryTile), findsOneWidget, reason: name);
      }
    }
  });

  testWidgets('B2 post subject pushes the encoded post route', (tester) async {
    await pumpTile(
      tester,
      actionFixture(
        subject: const ModerationSubjectRef(
          uri: 'at://did:plc:author/social.coves.community.post/p1',
        ),
      ),
    );

    final post = find.text('Post');
    expect(post, findsOneWidget);
    await tester.tap(post);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'post:/post/at%3A%2F%2Fdid%3Aplc%3Aauthor%2Fsocial.coves.community.post%2Fp1',
      ),
      findsOneWidget,
    );
  });

  testWidgets('B2b post subject reads and sizes as a link', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpTile(
      tester,
      actionFixture(
        subject: const ModerationSubjectRef(
          uri: 'at://did:plc:author/social.coves.community.post/p1',
        ),
      ),
    );

    final post = find.text('Post');
    expect(
      tester.getSemantics(post),
      isSemantics(label: 'Post', isLink: true, hasTapAction: true),
    );
    // androidTapTargetGuideline exempts link nodes, so measure the Post hit
    // area directly as well.
    final hitArea = tester.getSize(
      find.ancestor(of: post, matching: find.byType(InkWell)),
    );
    expect(hitArea.width, greaterThanOrEqualTo(48));
    expect(hitArea.height, greaterThanOrEqualTo(48));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('B2c postv2 subject is a Post link to the encoded post route', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpTile(
      tester,
      actionFixture(
        subject: const ModerationSubjectRef(
          uri: 'at://did:plc:author/social.coves.community.postv2/p1',
        ),
      ),
    );

    final post = find.text('Post');
    expect(post, findsOneWidget);
    expect(
      tester.getSemantics(post),
      isSemantics(label: 'Post', isLink: true, hasTapAction: true),
    );
    final hitArea = tester.getSize(
      find.ancestor(of: post, matching: find.byType(InkWell)),
    );
    expect(hitArea.width, greaterThanOrEqualTo(48));
    expect(hitArea.height, greaterThanOrEqualTo(48));
    handle.dispose();

    await tester.tap(post);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'post:/post/at%3A%2F%2Fdid%3Aplc%3Aauthor%2Fsocial.coves.community.postv2%2Fp1',
      ),
      findsOneWidget,
    );
  });

  testWidgets('B3 labels instance, community and unknown scopes', (
    tester,
  ) async {
    final cases = [
      (
        'instance',
        const ModerationScope(kind: ModerationScopeKind.instance),
        'Server',
      ),
      (
        'community',
        const ModerationScope(
          kind: ModerationScopeKind.community,
          communityDid: 'did:plc:community',
        ),
        'Community',
      ),
      (
        'unknown',
        const ModerationScope(kind: ModerationScopeKind.unknown),
        'Other scope',
      ),
    ];

    for (final (name, scope, label) in cases) {
      await pumpTile(tester, actionFixture(scope: scope));
      expect(find.text(label), findsOneWidget, reason: name);
    }
  });

  testWidgets('Modlog review R1 a row that reverses an earlier action shows '
      'both its scope and what it reverses', (tester) async {
    await pumpTile(
      tester,
      actionFixture(
        actionId: 'restore',
        kind: ModerationActionKind.restore,
        reverses: const ModerationActionRef(
          serviceDid: 'did:web:coves.social',
          actionId: 'removal',
        ),
      ),
      reversedAction: actionFixture(
        actionId: 'removal',
        reason: ModerationReason.spam,
      ),
    );

    expect(renderedText('Reverses removal for Spam'), findsOneWidget);
    expect(renderedText('Server'), findsOneWidget);
  });

  testWidgets('B10 a retract-label row reverses an NSFW label, never a '
      'removal', (tester) async {
    final retraction = actionFixture(
      actionId: 'retract',
      kind: ModerationActionKind.retractLabel,
      reverses: const ModerationActionRef(
        serviceDid: 'did:web:coves.social',
        actionId: 'label',
      ),
    );
    for (final (name, reversedAction) in [
      ('reversed row not loaded', null),
      (
        'reversed label row loaded',
        actionFixture(actionId: 'label', kind: ModerationActionKind.label),
      ),
    ]) {
      await pumpTile(tester, retraction, reversedAction: reversedAction);
      expect(
        find.text('Reverses an earlier NSFW label'),
        findsOneWidget,
        reason: name,
      );
      expect(find.textContaining('removal'), findsNothing, reason: name);
    }
  });

  testWidgets('Modlog redesign B4 the subject box previews the snapshot title, '
      'else its text, else its link, preferring the public snapshot', (
    tester,
  ) async {
    const post = ModerationSubjectRef(
      uri: 'at://did:plc:author/social.coves.community.post/p1',
    );
    const notShown = 'Content not shown';
    final cases =
        <
          ({
            String name,
            ModerationActionView action,
            ModerationContentSnapshot? privateSnapshot,
            List<String> shown,
            List<String> absent,
          })
        >[
          (
            name: 'title',
            action: actionFixture(
              subject: post,
              contentSnapshot: const ModerationContentSnapshot(
                title: 'Free Steam keys',
                text: 'First 50 people only',
                linkUrl: 'https://store.example/keys',
                capturedCid: 'bafy-title',
              ),
            ),
            privateSnapshot: null,
            shown: ['Free Steam keys'],
            absent: ['First 50 people only', 'https://store.example/keys'],
          ),
          (
            name: 'only text',
            action: actionFixture(
              subject: post,
              contentSnapshot: const ModerationContentSnapshot(
                text: 'First 50 people only',
                linkUrl: 'https://store.example/keys',
                capturedCid: 'bafy-text',
              ),
            ),
            privateSnapshot: null,
            shown: ['First 50 people only'],
            absent: ['https://store.example/keys'],
          ),
          (
            name: 'only link',
            action: actionFixture(
              subject: post,
              contentSnapshot: const ModerationContentSnapshot(
                linkUrl: 'https://store.example/keys',
                capturedCid: 'bafy-link',
              ),
            ),
            privateSnapshot: null,
            shown: ['https://store.example/keys'],
            absent: [notShown],
          ),
          (
            name: 'public and private snapshots',
            action: actionFixture(
              subject: post,
              contentSnapshot: const ModerationContentSnapshot(
                title: 'Public title',
                capturedCid: 'bafy-public',
              ),
            ),
            privateSnapshot: const ModerationContentSnapshot(
              title: 'Private title',
              capturedCid: 'bafy-private',
            ),
            shown: ['Public title'],
            absent: ['Private title'],
          ),
          (
            name: 'only private snapshot',
            action: actionFixture(subject: post),
            privateSnapshot: const ModerationContentSnapshot(
              title: 'Private title',
              capturedCid: 'bafy-private',
            ),
            shown: ['Private title'],
            absent: [notShown],
          ),
          (
            name: 'snapshot with only a captured CID',
            action: actionFixture(
              subject: post,
              contentSnapshot: const ModerationContentSnapshot(
                capturedCid: 'bafy-empty',
              ),
            ),
            privateSnapshot: null,
            shown: ['Post'],
            absent: [notShown],
          ),
          (
            name:
                'public snapshot without text, private snapshot with a '
                'title',
            action: actionFixture(
              subject: post,
              contentSnapshot: const ModerationContentSnapshot(
                capturedCid: 'bafy-empty',
              ),
            ),
            privateSnapshot: const ModerationContentSnapshot(
              title: 'Free Steam keys',
              capturedCid: 'bafy-private',
            ),
            shown: ['Free Steam keys'],
            absent: [notShown],
          ),
          (
            name: 'no snapshot',
            action: actionFixture(subject: post),
            privateSnapshot: null,
            shown: ['Post'],
            absent: [notShown],
          ),
          (
            name: 'no subject',
            action: actionFixture(),
            privateSnapshot: null,
            shown: [notShown],
            absent: ['Post'],
          ),
        ];

    for (final row in cases) {
      await pumpTile(
        tester,
        row.action,
        privateContentSnapshot: row.privateSnapshot,
      );
      for (final text in row.shown) {
        expect(
          renderedText(text),
          findsOneWidget,
          reason: '${row.name}: $text',
        );
      }
      for (final text in row.absent) {
        expect(renderedText(text), findsNothing, reason: '${row.name}: $text');
      }
      // A captured CID is bookkeeping, never preview text.
      expect(renderedTextContaining('bafy'), findsNothing, reason: row.name);
      // Withheld content is not shown for many reasons; the copy names none.
      expect(
        renderedTextContaining('for this reason'),
        findsNothing,
        reason: row.name,
      );
    }
  });

  testWidgets('Modlog redesign B4 tapping the snapshot preview opens the '
      'post', (tester) async {
    await pumpTile(
      tester,
      actionFixture(
        subject: const ModerationSubjectRef(
          uri: 'at://did:plc:author/social.coves.community.post/p1',
        ),
        contentSnapshot: const ModerationContentSnapshot(
          title: 'Free Steam keys',
          capturedCid: 'bafy-post',
        ),
      ),
    );

    final preview = renderedText('Free Steam keys');
    expect(preview, findsOneWidget);
    await tester.tap(preview);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'post:/post/at%3A%2F%2Fdid%3Aplc%3Aauthor%2Fsocial.coves.community.post%2Fp1',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Modlog review R6 a public row previewing text only the admin '
      'log holds says the text is hidden from the public log', (tester) async {
    const post = ModerationSubjectRef(
      uri: 'at://did:plc:author/social.coves.community.post/p1',
    );
    const textHidden = 'Text hidden from public log';
    const subjectHidden = 'Hidden from public log';
    final cases =
        <
          ({
            String name,
            ModerationActionView action,
            ModerationContentSnapshot? privateSnapshot,
            ModerationSubjectRef? privateSubject,
            List<String> shown,
            List<String> absent,
          })
        >[
          (
            name: 'public subject, only a private snapshot',
            action: actionFixture(subject: post),
            privateSnapshot: const ModerationContentSnapshot(
              title: 'Leaked address',
              capturedCid: 'bafy-private',
            ),
            privateSubject: null,
            shown: ['Leaked address', textHidden],
            absent: [subjectHidden],
          ),
          (
            name:
                'public snapshot without text, private snapshot with a '
                'title',
            action: actionFixture(
              subject: post,
              contentSnapshot: const ModerationContentSnapshot(
                capturedCid: 'bafy-empty',
              ),
            ),
            privateSnapshot: const ModerationContentSnapshot(
              title: 'Free Steam keys',
              capturedCid: 'bafy-private',
            ),
            privateSubject: null,
            shown: ['Free Steam keys', textHidden],
            absent: [subjectHidden],
          ),
          (
            name: 'public snapshot present',
            action: actionFixture(
              subject: post,
              contentSnapshot: const ModerationContentSnapshot(
                title: 'Public title',
                capturedCid: 'bafy-public',
              ),
            ),
            privateSnapshot: const ModerationContentSnapshot(
              title: 'Private title',
              capturedCid: 'bafy-private',
            ),
            privateSubject: null,
            shown: ['Public title'],
            absent: [textHidden, 'Private title'],
          ),
          (
            name: 'no public subject, private subject and snapshot',
            action: actionFixture(),
            privateSnapshot: const ModerationContentSnapshot(
              title: 'Leaked address',
              capturedCid: 'bafy-private',
            ),
            privateSubject: post,
            shown: [subjectHidden],
            absent: [textHidden],
          ),
          (
            name: 'public subject, no snapshots',
            action: actionFixture(subject: post),
            privateSnapshot: null,
            privateSubject: null,
            shown: ['Post'],
            absent: [textHidden, subjectHidden],
          ),
        ];

    for (final row in cases) {
      await pumpTile(
        tester,
        row.action,
        privateContentSnapshot: row.privateSnapshot,
        privateSubject: row.privateSubject,
      );
      for (final text in row.shown) {
        expect(
          renderedText(text),
          findsOneWidget,
          reason: '${row.name}: $text',
        );
      }
      for (final text in row.absent) {
        expect(renderedText(text), findsNothing, reason: '${row.name}: $text');
      }
    }
  });

  testWidgets('actor label: an @handle takes the feed handle color', (
    tester,
  ) async {
    final cases =
        <
          ({
            String name,
            String? actorDid,
            String? privateActorDid,
            String? actorHandle,
            String label,
            Color color,
          })
        >[
          (
            name: 'known handle',
            actorDid: 'did:plc:alice',
            privateActorDid: null,
            actorHandle: 'alice.coves.social',
            label: '@alice.coves.social',
            color: AppColors.textSecondary,
          ),
          (
            name: 'known handle of the private actor',
            actorDid: null,
            privateActorDid: 'did:plc:admin',
            actorHandle: 'admin.coves.social',
            label: '@admin.coves.social',
            color: AppColors.textSecondary,
          ),
          (
            name: 'no actor DID',
            actorDid: null,
            privateActorDid: null,
            actorHandle: null,
            label: 'Server admin',
            color: AppColors.textPrimary,
          ),
          (
            name: 'unknown handle',
            actorDid: 'did:plc:alice',
            privateActorDid: null,
            actorHandle: null,
            label: 'A moderator',
            color: AppColors.textPrimary,
          ),
        ];

    for (final row in cases) {
      await pumpTile(
        tester,
        actionFixture(actorDid: row.actorDid),
        actorHandle: row.actorHandle,
        privateActorDid: row.privateActorDid,
      );
      final style = actorSpanStyle(tester, row.label);
      expect(style.color, row.color, reason: '${row.name}: color');
      expect(style.fontWeight, FontWeight.w600, reason: '${row.name}: weight');
    }
  });

  testWidgets('tapping a public actor @handle opens their profile', (
    tester,
  ) async {
    await pumpTile(
      tester,
      actionFixture(actorDid: 'did:plc:alice'),
      actorHandle: 'alice.coves.social',
    );

    await tester.tapOnText(find.textRange.ofSubstring('@alice.coves.social'));
    await tester.pumpAndSettle();

    expect(find.text('PROFILE did:plc:alice'), findsOneWidget);
  });

  testWidgets(
    'tapping a private actor @handle opens the private actor profile',
    (tester) async {
      await pumpTile(
        tester,
        actionFixture(actorDid: 'did:plc:public'),
        actorHandle: 'admin.coves.social',
        privateActorDid: 'did:plc:admin',
      );

      await tester.tapOnText(find.textRange.ofSubstring('@admin.coves.social'));
      await tester.pumpAndSettle();

      expect(find.text('PROFILE did:plc:admin'), findsOneWidget);
    },
  );

  testWidgets('Server admin and A moderator do not open a profile', (
    tester,
  ) async {
    final cases = <({String? actorDid, String label})>[
      (actorDid: null, label: 'Server admin'),
      (actorDid: 'did:plc:alice', label: 'A moderator'),
    ];

    for (final row in cases) {
      await pumpTile(tester, actionFixture(actorDid: row.actorDid));

      await tester.tapOnText(find.textRange.ofSubstring(row.label));
      await tester.pumpAndSettle();

      expect(find.textContaining('PROFILE'), findsNothing, reason: row.label);
      expect(renderedTextContaining(row.label), findsOneWidget);
    }
  });
}
