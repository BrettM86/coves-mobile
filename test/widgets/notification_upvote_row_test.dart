import 'package:cached_network_image/cached_network_image.dart';
import 'package:coves_flutter/constants/app_colors.dart';
import 'package:coves_flutter/models/notification.dart';
import 'package:coves_flutter/utils/removal_copy.dart';
import 'package:coves_flutter/widgets/compact_post_card.dart';
import 'package:coves_flutter/widgets/icons/lucide_icon_painter.dart';
import 'package:coves_flutter/widgets/icons/lucide_paths.dart';
import 'package:coves_flutter/widgets/notifications/notification_upvote_row.dart';
import 'package:coves_flutter/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/lucide_glyph_finder.dart';
import '../test_helpers/theme_pump.dart';
import '../test_helpers/upvote_notification_fixture.dart';

const _title = 'Best budget keyboards?';
const _thumbnailUrl = 'https://cdn.test/keyboard.jpg';
const _thumbnailAlt = 'A keyboard on a desk';
const _commentPreview = 'I use a Keychron K2.';
const _longPreview =
    'This is a detailed review of a compact keyboard with quiet switches, '
    'good battery life, reliable wireless pairing, comfortable keycaps, and '
    'plenty of useful layout options for daily work. It goes on to describe '
    'the typing feel and how it compares with other keyboards on a desk.';

/// A live root post without an author or stats, so the post card adds no
/// avatar or heart of its own to the row.
const _plainRoot = <String, dynamic>{
  'uri': postUri,
  'cid': 'bafyroot',
  'title': _title,
};

/// A live root post with every part the compact post card shows. Its
/// createdAt (7d) differs from the row's sortAt (6d).
const _cardRoot = <String, dynamic>{
  'uri': postUri,
  'cid': 'bafyroot',
  'title': _title,
  'thumbnail': _thumbnailUrl,
  'thumbnailAlt': _thumbnailAlt,
  'author': {'did': 'did:plc:poster', 'handle': 'poster.test'},
  'createdAt': '2026-09-30T12:00:00.000Z',
  'stats': {'score': 12, 'upvotes': 12, 'downvotes': 0, 'commentCount': 3},
};

/// The post subject the server sends alongside [_cardRoot]: the same post.
const _livePostSubject = <String, dynamic>{
  ...postSubject,
  'preview': _title,
  'thumbnail': _thumbnailUrl,
  'thumbnailAlt': _thumbnailAlt,
};

Future<void> _pumpRow(
  WidgetTester tester,
  Map<String, dynamic> wire, {
  VoidCallback? onTap,
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final notification = NotificationView.tryFromJson(wire);
  expect(notification, isNotNull, reason: 'wire fixture must parse');
  await pumpUnderAppTheme(
    tester,
    NotificationUpvoteRow(
      notification: notification!,
      onTap: onTap ?? () {},
      onSensitiveContentToggle: () {},
      currentTime: DateTime.utc(2026, 10, 7, 12),
    ),
  );
}

Finder _rich(String text) => find.text(text, findRichText: true);

Finder _inCard(Finder finder) =>
    find.descendant(of: find.byType(CompactPostCard), matching: finder);

Finder _thumbnail() => find.byWidgetPredicate(
  (widget) => widget is CachedNetworkImage && widget.imageUrl == _thumbnailUrl,
);

void main() {
  group('NotificationUpvoteRow', () {
    testWidgets('B4 header shows ordered avatars, a filled heart, the title, '
        'the names line and the time', (tester) async {
      await _pumpRow(
        tester,
        upvoteWire(
          upvoters: [aliceUpvoter, didOnlyUpvoter, carolUpvoter],
          count: 3,
          subject: {...postSubject, 'preview': _title},
          rootPost: _plainRoot,
        ),
      );

      final avatars = tester
          .widgetList<UserAvatar>(find.byType(UserAvatar))
          .toList();
      expect(avatars.map((avatar) => avatar.avatarUrl).toList(), [
        'https://cdn.test/alice.png',
        null,
        'https://cdn.test/carol.png',
      ]);
      expect(avatars.map((avatar) => avatar.name).toList(), [
        'Alice',
        'Unknown user',
        'Carol',
      ]);
      final avatarRects = find
          .byType(UserAvatar)
          .evaluate()
          .map(
            (element) => tester.getRect(
              find.byElementPredicate((candidate) => candidate == element),
            ),
          )
          .toList();
      expect(avatarRects[0].left, lessThan(avatarRects[1].left));
      expect(avatarRects[1].left, lessThan(avatarRects[2].left));

      final heart = findLucideGlyph(LucidePaths.heart);
      expect(heart, findsOneWidget);
      final painter =
          tester.widget<CustomPaint>(heart).painter! as LucideIconPainter;
      expect(painter.filled, isTrue);
      expect(painter.color, AppColors.voteLiked);

      expect(_rich('Liked your post'), findsOneWidget);
      expect(_rich('Alice, Unknown user and Carol'), findsOneWidget);
      expect(
        find.textContaining('liked your', findRichText: true),
        findsNothing,
        reason: 'the old one-line sentence is gone',
      );
      expect(find.textContaining('did:', findRichText: true), findsNothing);
      expect(find.text('6d'), findsOneWidget);
      expect(
        tester.getTopLeft(_rich('Alice, Unknown user and Carol')).dy,
        greaterThan(tester.getTopLeft(_rich('Liked your post')).dy),
        reason: 'the names line sits below the title',
      );
      expect(find.byType(CompactPostCard), findsOneWidget);
      expect(
        tester.getRect(find.byType(CompactPostCard)).top,
        greaterThanOrEqualTo(
          tester.getRect(_rich('Alice, Unknown user and Carol')).bottom,
        ),
        reason: 'the post card is the body below the header',
      );
    });

    for (final (description, wire, names, avatarCount) in [
      (
        'one named upvoter of many',
        upvoteWire(upvoters: [aliceUpvoter], count: 13, rootPost: _plainRoot),
        'Alice and 12 others',
        1,
      ),
      (
        'one named upvoter of two',
        upvoteWire(upvoters: [aliceUpvoter], count: 2, rootPost: _plainRoot),
        'Alice and 1 other',
        1,
      ),
      (
        'bridged-only upvoters',
        upvoteWire(count: 5, rootPost: _plainRoot),
        '5 people',
        0,
      ),
    ]) {
      testWidgets('B4 names line for $description', (tester) async {
        await _pumpRow(tester, wire);

        expect(_rich(names), findsOneWidget);
        expect(_rich('Liked your post'), findsOneWidget);
        expect(find.byType(UserAvatar), findsNWidgets(avatarCount));
        expect(find.text('6d'), findsOneWidget);
      });
    }

    for (final (description, subject, title) in [
      ('post', postSubject, 'Liked your post'),
      ('comment', commentSubject, 'Liked your comment'),
    ]) {
      testWidgets('B4 the title names a $description subject', (tester) async {
        await _pumpRow(
          tester,
          upvoteWire(
            upvoters: [aliceUpvoter],
            count: 1,
            subject: subject,
            rootPost: _plainRoot,
          ),
        );

        expect(_rich(title), findsOneWidget);
        expect(_rich('Alice'), findsOneWidget);
      });
    }

    testWidgets('B4 a post upvote shows the root post as a compact post card', (
      tester,
    ) async {
      await _pumpRow(
        tester,
        upvoteWire(
          upvoters: [aliceUpvoter],
          count: 1,
          subject: _livePostSubject,
          rootPost: _cardRoot,
        ),
      );

      expect(find.byType(CompactPostCard), findsOneWidget);
      expect(_inCard(find.text(_title)), findsOneWidget);
      expect(_inCard(find.text('@poster.test')), findsOneWidget);
      expect(_inCard(find.text('7d')), findsOneWidget);
      expect(_inCard(find.text('12')), findsOneWidget);
      expect(_inCard(find.text('3')), findsOneWidget);
      expect(_inCard(_thumbnail()), findsOneWidget);
      expect(
        find.text(_title),
        findsOneWidget,
        reason: 'the subject preview is not repeated outside the card',
      );
      expect(_thumbnail(), findsOneWidget);
      expect(find.text('6d'), findsOneWidget, reason: 'the row time remains');
    });

    testWidgets('B4 a removed post upvote shows the placeholder post card', (
      tester,
    ) async {
      var taps = 0;
      await _pumpRow(
        tester,
        upvoteWire(
          count: 5,
          subject: {...postSubject, 'status': 'removedByServerAdmin'},
          rootPost: const {
            'uri': postUri,
            'cid': 'bafyroot',
            'status': 'removedByServerAdmin',
          },
        ),
        onTap: () => taps++,
      );

      expect(find.byType(CompactPostCard), findsOneWidget);
      expect(
        _inCard(find.text(RemovalCopy.removedByServerAdmin)),
        findsOneWidget,
      );
      expect(find.text(RemovalCopy.removedByServerAdmin), findsOneWidget);
      expect(_rich('5 people'), findsOneWidget);
      await tester.tap(find.byType(NotificationUpvoteRow));
      expect(taps, 1);
    });

    testWidgets('B4 a comment upvote quotes the preview, not a post card', (
      tester,
    ) async {
      await _pumpRow(
        tester,
        upvoteWire(
          upvoters: [aliceUpvoter],
          count: 1,
          subject: {...commentSubject, 'preview': _longPreview},
          rootPost: _cardRoot,
        ),
      );

      expect(_rich('Liked your comment'), findsOneWidget);
      expect(find.byType(CompactPostCard), findsNothing);
      expect(find.text(_title), findsNothing);
      final preview = _rich(_longPreview);
      expect(preview, findsOneWidget);
      expect(tester.renderObject<RenderParagraph>(preview).maxLines, 3);
      expect(
        tester.getTopLeft(preview).dy,
        greaterThan(tester.getTopLeft(_rich('Alice')).dy),
        reason: 'the quote is the body below the header',
      );

      await _pumpRow(
        tester,
        upvoteWire(
          upvoters: [aliceUpvoter],
          count: 1,
          subject: {...commentSubject, 'status': 'deleted'},
          rootPost: _cardRoot,
        ),
      );

      expect(_rich('Liked your comment'), findsOneWidget);
      expect(find.byType(CompactPostCard), findsNothing);
      expect(find.text(RemovalCopy.deletedByUser), findsOneWidget);
    });

    for (final (description, wire, label) in [
      (
        'live post with thumbnail alt',
        upvoteWire(
          upvoters: [aliceUpvoter],
          count: 13,
          subject: _livePostSubject,
          rootPost: _cardRoot,
        ),
        'Alice and 12 others liked your post, Best budget keyboards?, '
            '6d, A keyboard on a desk',
      ),
      (
        'live comment',
        upvoteWire(
          upvoters: [aliceUpvoter],
          count: 1,
          subject: {...commentSubject, 'preview': _commentPreview},
          rootPost: _cardRoot,
        ),
        'Alice liked your comment, I use a Keychron K2., 6d',
      ),
      (
        'removed subject with bridged-only upvotes',
        upvoteWire(
          count: 5,
          subject: {...postSubject, 'status': 'removedByServerAdmin'},
          rootPost: const {
            'uri': postUri,
            'cid': 'bafyroot',
            'status': 'removedByServerAdmin',
          },
        ),
        '5 people liked your post, ${RemovalCopy.removedByServerAdmin}, 6d',
      ),
      (
        'thumbnail without alt',
        upvoteWire(
          upvoters: [aliceUpvoter],
          count: 1,
          subject: {
            ...postSubject,
            'preview': _title,
            'thumbnail': _thumbnailUrl,
          },
          rootPost: {..._plainRoot, 'thumbnail': _thumbnailUrl},
        ),
        'Alice liked your post, Best budget keyboards?, 6d',
      ),
      (
        'unparsable sortAt',
        {
          ...upvoteWire(
            upvoters: [aliceUpvoter],
            count: 1,
            subject: {...postSubject, 'preview': _title},
            rootPost: _plainRoot,
          ),
          'sortAt': 'not-a-date',
        },
        'Alice liked your post, Best budget keyboards?',
      ),
    ]) {
      testWidgets('B9 $description has one activatable semantics label', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        try {
          var taps = 0;
          await _pumpRow(tester, wire, onTap: () => taps++);

          expect(find.bySemanticsLabel(label), findsOneWidget);
          final node = tester.getSemantics(find.byType(NotificationUpvoteRow));
          expect(
            node,
            isSemantics(
              isButton: true,
              hasTapAction: true,
              label: label,
              children: const [],
            ),
          );
          if (description == 'live post with thumbnail alt') {
            node.owner!.performAction(node.id, SemanticsAction.tap);
            await tester.pump();
            expect(taps, 1);
          }
        } finally {
          semantics.dispose();
        }
      });
    }
  });
}
