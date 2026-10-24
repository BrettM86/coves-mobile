import 'package:cached_network_image/cached_network_image.dart';
import 'package:coves_flutter/models/notification.dart';
import 'package:coves_flutter/widgets/compact_post_card.dart';
import 'package:coves_flutter/widgets/icons/lucide_icon_painter.dart';
import 'package:coves_flutter/widgets/icons/lucide_paths.dart';
import 'package:coves_flutter/widgets/notifications/notification_reply_card.dart';
import 'package:coves_flutter/widgets/notifications/notification_upvote_row.dart';
import 'package:coves_flutter/widgets/sensitive_content.dart';
import 'package:coves_flutter/widgets/user_avatar.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/lucide_glyph_finder.dart';
import '../test_helpers/reply_notification_fixture.dart';
import '../test_helpers/semantics_helpers.dart';
import '../test_helpers/theme_pump.dart';
import '../test_helpers/upvote_notification_fixture.dart';

const _nsfw = <String, dynamic>{
  'values': [
    {'val': 'nsfw'},
  ],
};

const _rootUri = 'at://did:plc:me/social.coves.community.postv2/3kpost';
const _myCommentUri = 'at://did:plc:me/social.coves.community.comment/3kmine';
const _replyUri = 'at://did:plc:bob/social.coves.community.comment/3kreply';

const _replyRoot = <String, dynamic>{
  'uri': _rootUri,
  'cid': 'bafyroot',
  'title': 'Spicy title',
  'thumbnail': 'https://cdn.test/beach-thumb.jpg',
  'thumbnailAlt': 'beach photo',
  'community': {
    'did': 'did:plc:gaming',
    'name': 'gaming',
    'handle': 'c-gaming.coves.social',
  },
};
const _replyRecord = <String, dynamic>{
  'uri': _replyUri,
  'cid': 'bafyrecord',
  'excerpt': 'Spicy reply excerpt',
  'createdAt': '2026-10-01T12:00:00.000Z',
};
const _replyAuthor = <String, dynamic>{
  'did': 'did:plc:bob',
  'handle': 'bob.coves.social',
  'displayName': 'Bob',
};

/// A reply card wire. A `commentReply` subject is the signed-in user's own
/// comment, so it gets its own URI; a `postReply` subject is the root post.
Map<String, dynamic> _replyWire({
  String reason = 'postReply',
  Map<String, dynamic> rootPost = _replyRoot,
  Map<String, dynamic> record = _replyRecord,
  Map<String, dynamic>? subjectLabels,
}) {
  final wire = replyNotificationWire(
    reason: reason,
    rootPost: rootPost,
    record: record,
    author: _replyAuthor,
  );
  wire['subject'] = {
    'uri': reason == 'commentReply' ? _myCommentUri : _rootUri,
    'cid': 'bafysubject',
    'labels': ?subjectLabels,
  };
  return wire;
}

/// An upvote row wire with Alice as the only upvoter. [rootPost] adds the
/// root post's own parts; on a post upvote they mirror the subject's.
Map<String, dynamic> _upvoteWire({
  required Map<String, dynamic> subject,
  Map<String, dynamic>? rootLabels,
  Map<String, dynamic> rootPost = const {},
}) {
  final wire = upvoteWire(upvoters: [aliceUpvoter], count: 1, subject: subject);
  wire['rootPost'] = {
    ...wire['rootPost'] as Map<String, dynamic>,
    ...rootPost,
    'labels': ?rootLabels,
  };
  return wire;
}

Future<void> _pump(WidgetTester tester, Map<String, dynamic> wire) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final notification = NotificationView.tryFromJson(wire);
  expect(notification, isNotNull, reason: 'wire fixture must parse');
  await pumpUnderAppTheme(
    tester,
    notification!.reason == NotificationReason.upvote
        ? NotificationUpvoteRow(
            notification: notification,
            onTap: () {},
            onSensitiveContentToggle: () {},
            currentTime: DateTime.utc(2026, 10, 7, 12),
          )
        : NotificationReplyCard(
            notification: notification,
            onTap: () {},
            onSensitiveContentToggle: () {},
            currentTime: DateTime.utc(2026, 10, 7, 12),
          ),
  );
}

Finder _imageWithUrl(String url) => find.byWidgetPredicate(
  (widget) => widget is CachedNetworkImage && widget.imageUrl == url,
);

Finder _heart() => find.byWidgetPredicate(
  (widget) =>
      widget is CustomPaint &&
      widget.painter is LucideIconPainter &&
      identical(
        (widget.painter! as LucideIconPainter).paths,
        LucidePaths.heart,
      ),
);

void _expectReplyHeader(String reasonLine) {
  expect(find.text(reasonLine), findsOneWidget);
  expect(find.text('!gaming@coves.social'), findsOneWidget);
  expect(find.text('6d'), findsOneWidget);
  expect(find.text('Bob'), findsOneWidget);
  expect(find.text('@bob.coves.social'), findsOneWidget);
}

void _expectUpvoteHeader(String title) {
  expect(_heart(), findsOneWidget);
  expect(find.byType(UserAvatar), findsOneWidget);
  expect(
    find.text(title, findRichText: true),
    findsOneWidget,
    reason: 'the title stays visible',
  );
  expect(
    find.text('Alice', findRichText: true),
    findsOneWidget,
    reason: 'the names line stays visible',
  );
  expect(find.text('6d'), findsOneWidget, reason: 'the time stays visible');
}

void main() {
  group('Notification rows conceal sensitive content', () {
    // B2 + B5: any sensitive reference replaces every displayed thumbnail,
    // shows one banner, and keeps the header visible.
    for (final (description, wire, thumbnailUrl, expectHeader) in [
      (
        'postReply card with a sensitive record',
        _replyWire(record: {..._replyRecord, 'labels': _nsfw}),
        'https://cdn.test/beach-thumb.jpg',
        () => _expectReplyHeader('Reply to your post'),
      ),
      (
        'commentReply card with a sensitive subject',
        _replyWire(reason: 'commentReply', subjectLabels: _nsfw),
        'https://cdn.test/beach-thumb.jpg',
        () => _expectReplyHeader('Reply to your comment'),
      ),
      (
        'upvote row on a sensitive post',
        _upvoteWire(
          subject: {
            ...postSubject,
            'preview': 'Spicy preview',
            'thumbnail': 'https://cdn.test/spicy-upvote-thumb.jpg',
            'thumbnailAlt': 'beach photo',
            'labels': _nsfw,
          },
          rootLabels: _nsfw,
          rootPost: {
            'title': 'Spicy preview',
            'thumbnail': 'https://cdn.test/spicy-upvote-thumb.jpg',
            'thumbnailAlt': 'beach photo',
          },
        ),
        'https://cdn.test/spicy-upvote-thumb.jpg',
        () => _expectUpvoteHeader('Liked your post'),
      ),
      (
        'upvote row on an untitled sensitive image post',
        _upvoteWire(
          subject: {
            ...postSubject,
            'thumbnail': 'https://cdn.test/spicy-upvote-thumb.jpg',
            'thumbnailAlt': 'beach photo',
            'labels': _nsfw,
          },
          rootLabels: _nsfw,
          rootPost: {
            'thumbnail': 'https://cdn.test/spicy-upvote-thumb.jpg',
            'thumbnailAlt': 'beach photo',
          },
        ),
        'https://cdn.test/spicy-upvote-thumb.jpg',
        () => _expectUpvoteHeader('Liked your post'),
      ),
    ]) {
      testWidgets('B2 $description hides the thumbnail behind one banner', (
        tester,
      ) async {
        await _pump(tester, wire);

        expectHeader();
        expect(
          _imageWithUrl(thumbnailUrl),
          findsNothing,
          reason: 'a concealed row must not display the thumbnail',
        );
        expect(find.byType(SensitiveContentBanner), findsOneWidget);
      });
    }

    // B3: only the sensitive reference's displayed text is concealed.
    for (final (description, wire, hidden, shown, expectsBanner) in [
      (
        'postReply with a sensitive root post',
        _replyWire(rootPost: {..._replyRoot, 'labels': _nsfw}),
        ['Spicy title'],
        ['Spicy reply excerpt'],
        false,
      ),
      (
        'postReply with a sensitive titled root post and no thumbnail',
        _replyWire(
          rootPost: {..._replyRoot, 'labels': _nsfw}..remove('thumbnail'),
        ),
        ['Spicy title'],
        ['Spicy reply excerpt'],
        true,
      ),
      (
        'postReply with a sensitive record',
        _replyWire(record: {..._replyRecord, 'labels': _nsfw}),
        ['Spicy reply excerpt'],
        ['Spicy title'],
        false,
      ),
      (
        'commentReply with only a sensitive subject',
        _replyWire(reason: 'commentReply', subjectLabels: _nsfw),
        <String>[],
        ['Spicy title', 'Spicy reply excerpt'],
        true,
      ),
      (
        'upvote row on a sensitive comment',
        _upvoteWire(
          subject: {
            ...commentSubject,
            'preview': 'Spicy comment preview',
            'labels': _nsfw,
          },
        ),
        ['Spicy comment preview'],
        <String>[],
        false,
      ),
    ]) {
      testWidgets('B3 $description conceals only the labelled text', (
        tester,
      ) async {
        await _pump(tester, wire);

        for (final text in shown) {
          expect(find.text(text), findsOneWidget, reason: '"$text" stays');
        }
        for (final text in hidden) {
          expect(find.text(text), findsNothing, reason: '"$text" is hidden');
        }
        if (expectsBanner) {
          expect(find.byType(SensitiveContentBanner), findsOneWidget);
        }
      });
    }

    // B4 (guard): a row with nothing displayed to conceal stays unconcealed.
    for (final (description, wire, shown) in [
      (
        'upvote row on a comment under a sensitive root post',
        _upvoteWire(
          subject: {...commentSubject, 'preview': 'Plain comment preview'},
          rootLabels: _nsfw,
        ),
        ['Plain comment preview'],
      ),
      (
        'commentReply with a sensitive subject and no thumbnail',
        _replyWire(
          reason: 'commentReply',
          rootPost: {..._replyRoot}..remove('thumbnail'),
          subjectLabels: _nsfw,
        ),
        ['Spicy title', 'Spicy reply excerpt'],
      ),
    ]) {
      testWidgets('B4 $description shows everything without a banner', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await _pump(tester, wire);

        for (final text in shown) {
          expect(find.text(text), findsOneWidget, reason: '"$text" stays');
        }
        expect(find.byType(SensitiveContentBanner), findsNothing);
        final labels = activatableLabels(
          tester,
          find.byWidgetPredicate(
            (widget) =>
                widget is NotificationUpvoteRow ||
                widget is NotificationReplyCard,
          ),
        );
        expect(labels, hasLength(1), reason: 'the row stays one button node');
        expect(labels.single, contains(shown.first));
        semantics.dispose();
      });
    }
  });

  group('A concealed notification row keeps screen-reader actions apart', () {
    // B8 + B9 run against both row widgets: a reply card whose root post is
    // sensitive, a reply card whose own record is sensitive, and an upvote
    // row on a sensitive post.
    for (final (
          description,
          wire,
          concealedLabel,
          revealedLabel,
          hiddenText,
          thumbnailUrl,
        )
        in [
          (
            'reply card row',
            _replyWire(rootPost: {..._replyRoot, 'labels': _nsfw}),
            'Reply to your post, !gaming@coves.social, Bob, '
                'Spicy reply excerpt, 6d',
            'Reply to your post, !gaming@coves.social, Spicy title, Bob, '
                'Spicy reply excerpt, 6d',
            'Spicy title',
            'https://cdn.test/beach-thumb.jpg',
          ),
          (
            'reply card row with a sensitive reply',
            _replyWire(record: {..._replyRecord, 'labels': _nsfw}),
            'Reply to your post, !gaming@coves.social, Spicy title, Bob, 6d',
            'Reply to your post, !gaming@coves.social, Spicy title, Bob, '
                'Spicy reply excerpt, 6d',
            'Spicy reply excerpt',
            'https://cdn.test/beach-thumb.jpg',
          ),
          (
            'upvote row on a post',
            _upvoteWire(
              subject: {
                ...postSubject,
                'preview': 'Spicy title',
                'thumbnail': 'https://cdn.test/spicy-upvote-thumb.jpg',
                'thumbnailAlt': 'beach photo',
                'labels': _nsfw,
              },
              rootLabels: _nsfw,
              rootPost: {
                'title': 'Spicy title',
                'thumbnail': 'https://cdn.test/spicy-upvote-thumb.jpg',
                'thumbnailAlt': 'beach photo',
              },
            ),
            'Alice liked your post, 6d',
            'Alice liked your post, Spicy title, 6d, beach photo',
            'Spicy title',
            'https://cdn.test/spicy-upvote-thumb.jpg',
          ),
        ]) {
      testWidgets('B8 $description exposes only the row and the banner, '
          'without the concealed text', (tester) async {
        final semantics = tester.ensureSemantics();
        final host = await _pumpRevealHost(tester, wire);

        final activatable = activatableNodes(tester, _rowFinder());
        final labels = [for (final node in activatable) node.label];
        expect(
          labels,
          hasLength(2),
          reason: 'a concealed row is the row button plus the banner',
        );
        expect(labels, contains('Show sensitive content'));

        final rowNode = activatable.singleWhere(
          (node) => node.label != 'Show sensitive content',
        );
        expect(
          rowNode.label,
          equals(concealedLabel),
          reason: 'the row announces its visible parts once each',
        );
        for (final node in allSemanticsNodes(tester, _rowFinder())) {
          expect(
            node.label,
            allOf(isNot(contains(hiddenText)), isNot(contains('beach photo'))),
            reason: 'no node may announce the concealed text or alt',
          );
        }

        activateSemanticsNode(rowNode);
        await tester.pump();

        expect(host.navigated, isTrue, reason: 'the row tap opens the row');
        expect(host.toggled, isFalse, reason: 'the row tap does not reveal');
        expect(find.bySemanticsLabel('Show sensitive content'), findsOneWidget);
        semantics.dispose();
      });

      testWidgets('B9 $description banner toggles the reveal without '
          'opening the row', (tester) async {
        final semantics = tester.ensureSemantics();
        final host = await _pumpRevealHost(tester, wire);

        expect(find.bySemanticsLabel('Show sensitive content'), findsOneWidget);
        activateBySemantics(
          tester,
          find.bySemanticsLabel('Show sensitive content'),
        );
        await tester.pump();

        expect(host.toggled, isTrue, reason: 'the banner tap reveals');
        expect(host.navigated, isFalse, reason: 'the banner tap stays put');
        expect(find.bySemanticsLabel('Hide sensitive content'), findsOneWidget);
        final rowNode = activatableNodes(
          tester,
          _rowFinder(),
        ).singleWhere((node) => node.label != 'Hide sensitive content');
        expect(rowNode.label, equals(revealedLabel));
        expect(find.text(hiddenText), findsOneWidget);
        expect(_imageWithUrl(thumbnailUrl), findsOneWidget);

        activateBySemantics(
          tester,
          find.bySemanticsLabel('Hide sensitive content'),
        );
        await tester.pump();

        expect(find.bySemanticsLabel('Show sensitive content'), findsOneWidget);
        expect(find.text(hiddenText), findsNothing);
        expect(_imageWithUrl(thumbnailUrl), findsNothing);
        expect(host.navigated, isFalse);
        semantics.dispose();
      });

      testWidgets('$description pressing the banner leaves the row '
          'without ink', (tester) async {
        final host = await _pumpRevealHost(tester, wire);
        final rowInk = Material.of(
          tester.element(
            find
                .descendant(of: _rowFinder(), matching: find.byType(InkWell))
                .first,
          ),
        );
        // ignore: avoid_dynamic_calls
        List<Object?> inkFeatures() =>
            ((rowInk as dynamic).debugInkFeatures as List?) ?? const [];

        // Control: pressing the row's time draws the row's ink. Cancelling
        // the press keeps it from opening the row.
        final controlPress = await tester.startGesture(
          tester.getCenter(find.text('6d')),
        );
        await tester.pump(kPressTimeout * 2);
        expect(inkFeatures(), isNotEmpty);
        await controlPress.cancel();
        await tester.pumpAndSettle();
        expect(inkFeatures(), isEmpty);

        final press = await tester.startGesture(
          tester.getCenter(find.text('NSFW Content')),
        );
        await tester.pump(kPressTimeout * 2);

        expect(inkFeatures(), isEmpty);

        await press.up();
        await tester.pump();
        expect(host.toggled, isTrue);
        expect(host.navigated, isFalse);
      });
    }
  });

  group('Concealment covers the post card and the comment quote', () {
    // R5a: a sensitive root's whole post card hides while concealed.
    testWidgets('R5 a concealed sensitive root hides its whole post card', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pumpRevealHost(
          tester,
          _replyWire(
            rootPost: {..._replyRoot, ..._rootCardParts, 'labels': _nsfw},
          ),
        );

        expect(find.byType(SensitiveContentBanner), findsOneWidget);
        expect(find.byType(CompactPostCard), findsNothing);
        expect(find.text('@poster.test'), findsNothing);
        expect(find.text('Spicy title'), findsNothing);
        expect(find.text('Spicy reply excerpt'), findsOneWidget);

        await _reveal(tester);

        expect(find.byType(CompactPostCard), findsOneWidget);
        expect(_inCard(find.text('Spicy title')), findsOneWidget);
        expect(_inCard(find.text('@poster.test')), findsOneWidget);
        expect(
          _inCard(_imageWithUrl('https://cdn.test/beach-thumb.jpg')),
          findsOneWidget,
        );
      } finally {
        semantics.dispose();
      }
    });

    // R5b: a non-sensitive root keeps its card, with the text tile.
    testWidgets('R5 a concealed sensitive reply keeps a plain root card with '
        'its text tile', (tester) async {
      await _pump(
        tester,
        _replyWire(
          rootPost: {..._replyRoot, ..._rootCardParts},
          record: {..._replyRecord, 'labels': _nsfw},
        ),
      );

      expect(find.byType(SensitiveContentBanner), findsOneWidget);
      expect(find.byType(CompactPostCard), findsOneWidget);
      expect(_inCard(find.text('Spicy title')), findsOneWidget);
      expect(_inCard(find.text('@poster.test')), findsOneWidget);
      expect(_imageWithUrl('https://cdn.test/beach-thumb.jpg'), findsNothing);
      expect(
        findLucideGlyph(
          LucidePaths.fileText,
          within: find.byType(CompactPostCard),
        ),
        findsOneWidget,
      );
      expect(find.text('Spicy reply excerpt'), findsNothing);
    });

    // R5c: the viewer's sensitive comment is something to hide.
    testWidgets('R5 a quote of your sensitive comment hides behind the '
        'banner', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final wire = _replyWire(
          reason: 'commentReply',
          rootPost: {..._replyRoot}..remove('thumbnail'),
          subjectLabels: _nsfw,
        );
        (wire['subject'] as Map<String, dynamic>)['preview'] =
            'Spicy comment of mine';
        await _pumpRevealHost(tester, wire);

        expect(find.byType(SensitiveContentBanner), findsOneWidget);
        expect(find.text('Spicy comment of mine'), findsNothing);
        expect(find.byType(CompactPostCard), findsNothing);
        expect(find.text('Spicy reply excerpt'), findsOneWidget);

        await _reveal(tester);

        expect(find.text('Spicy comment of mine'), findsOneWidget);
        expect(find.byType(CompactPostCard), findsNothing);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('R5 a concealed upvote on a sensitive post hides its post '
        'card', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pumpRevealHost(
          tester,
          _upvoteWire(
            subject: {
              ...postSubject,
              'preview': 'Spicy title',
              'thumbnail': 'https://cdn.test/spicy-upvote-thumb.jpg',
              'labels': _nsfw,
            },
            rootLabels: _nsfw,
            rootPost: {
              'title': 'Spicy title',
              'thumbnail': 'https://cdn.test/spicy-upvote-thumb.jpg',
            },
          ),
        );

        expect(find.byType(SensitiveContentBanner), findsOneWidget);
        expect(find.byType(CompactPostCard), findsNothing);

        await _reveal(tester);

        expect(find.byType(CompactPostCard), findsOneWidget);
        expect(_inCard(find.text('Spicy title')), findsOneWidget);
        expect(
          _inCard(_imageWithUrl('https://cdn.test/spicy-upvote-thumb.jpg')),
          findsOneWidget,
        );
      } finally {
        semantics.dispose();
      }
    });

    // R4: while the card is concealed it cannot name the author, so a post
    // mention keeps its bubble; revealed, the card names the author.
    testWidgets('R4 a concealed post mention keeps its bubble until the card '
        'shows the author', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        const mentionUri =
            'at://did:plc:bob/social.coves.community.postv2/3kmention';
        await _pumpRevealHost(
          tester,
          replyNotificationWire(
            reason: 'mention',
            rootPost: {
              ..._replyRoot,
              'uri': mentionUri,
              'labels': _nsfw,
              'author': {'did': 'did:plc:bob', 'handle': 'bob.coves.social'},
            },
            record: {
              ..._replyRecord,
              'uri': mentionUri,
              'excerpt': 'Spicy title',
              'labels': _nsfw,
            },
            author: _replyAuthor,
          ),
        );

        expect(find.byType(CompactPostCard), findsNothing);
        expect(find.text('Bob'), findsOneWidget);

        await _reveal(tester);

        expect(find.text('Bob'), findsNothing);
        expect(find.byType(CompactPostCard), findsOneWidget);
        expect(_inCard(find.text('@bob.coves.social')), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    });
  });
}

/// The root post parts the compact post card shows beyond the title and
/// thumbnail.
const _rootCardParts = <String, dynamic>{
  'author': {'did': 'did:plc:poster', 'handle': 'poster.test'},
  'createdAt': '2026-09-30T12:00:00.000Z',
  'stats': {'score': 12, 'upvotes': 12, 'downvotes': 0, 'commentCount': 3},
};

Finder _inCard(Finder finder) =>
    find.descendant(of: find.byType(CompactPostCard), matching: finder);

/// Activates the banner's Show action, as a screen reader would.
Future<void> _reveal(WidgetTester tester) async {
  activateBySemantics(tester, find.bySemanticsLabel('Show sensitive content'));
  await tester.pump();
}

/// Records what a row's two actions did.
class _RevealHost {
  bool navigated = false;
  bool toggled = false;
}

Finder _rowFinder() => find.byWidgetPredicate(
  (widget) =>
      widget is NotificationUpvoteRow || widget is NotificationReplyCard,
);

/// Pumps the row inside a parent that owns its reveal state, the way the
/// notifications screen does.
Future<_RevealHost> _pumpRevealHost(
  WidgetTester tester,
  Map<String, dynamic> wire,
) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final notification = NotificationView.tryFromJson(wire);
  expect(notification, isNotNull, reason: 'wire fixture must parse');
  final host = _RevealHost();
  var revealed = false;
  await pumpUnderAppTheme(
    tester,
    StatefulBuilder(
      builder: (context, setState) {
        void toggle() => setState(() {
          revealed = !revealed;
          host.toggled = true;
        });
        void open() => host.navigated = true;
        return notification!.reason == NotificationReason.upvote
            ? NotificationUpvoteRow(
                notification: notification,
                onTap: open,
                currentTime: DateTime.utc(2026, 10, 7, 12),
                sensitiveContentRevealed: revealed,
                onSensitiveContentToggle: toggle,
              )
            : NotificationReplyCard(
                notification: notification,
                onTap: open,
                currentTime: DateTime.utc(2026, 10, 7, 12),
                sensitiveContentRevealed: revealed,
                onSensitiveContentToggle: toggle,
              );
      },
    ),
  );
  return host;
}
