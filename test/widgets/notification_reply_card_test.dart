import 'package:cached_network_image/cached_network_image.dart';
import 'package:coves_flutter/models/notification.dart';
import 'package:coves_flutter/utils/removal_copy.dart';
import 'package:coves_flutter/widgets/community_avatar.dart';
import 'package:coves_flutter/widgets/compact_post_card.dart';
import 'package:coves_flutter/widgets/notifications/notification_reply_card.dart';
import 'package:coves_flutter/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/reply_notification_fixture.dart';
import '../test_helpers/semantics_helpers.dart';
import '../test_helpers/theme_pump.dart';

const _title = 'Best budget keyboards?';
const _excerpt = 'I use a Keychron K2.';
const _community = '!gaming@coves.social';
const _rootUri = 'at://did:plc:alice/social.coves.community.postv2/3kpost';
const _replyUri = 'at://did:plc:bob/social.coves.community.comment/3kreply';
const _postMentionUri =
    'at://did:plc:bob/social.coves.community.postv2/3kmention';

const _liveRoot = <String, dynamic>{
  'uri': _rootUri,
  'cid': 'bafyroot',
  'title': _title,
  'thumbnail': 'https://cdn.test/thumb.jpg',
  'community': {
    'did': 'did:plc:gaming',
    'name': 'gaming',
    'handle': 'c-gaming.coves.social',
    'avatar': 'https://cdn.test/gaming.png',
  },
};
const _liveRecord = <String, dynamic>{
  'uri': _replyUri,
  'cid': 'bafyrecord',
  'excerpt': _excerpt,
  'createdAt': '2026-10-01T12:00:00.000Z',
};
const _author = <String, dynamic>{
  'did': 'did:plc:bob',
  'handle': 'bob.coves.social',
  'displayName': 'Bob',
  'avatar': 'https://cdn.test/bob.png',
};

Map<String, dynamic> _row({
  String reason = 'postReply',
  Map<String, dynamic> rootPost = _liveRoot,
  Map<String, dynamic> record = _liveRecord,
  Map<String, dynamic> author = _author,
}) => replyNotificationWire(
  reason: reason,
  rootPost: rootPost,
  record: record,
  author: author,
);

Future<void> _pumpCard(
  WidgetTester tester,
  Map<String, dynamic> wire, {
  VoidCallback? onTap,
  bool revealed = false,
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final notification = NotificationView.tryFromJson(wire);
  expect(notification, isNotNull, reason: 'wire fixture must parse');
  await pumpUnderAppTheme(
    tester,
    NotificationReplyCard(
      notification: notification!,
      onTap: onTap ?? () {},
      onSensitiveContentToggle: () {},
      currentTime: DateTime.utc(2026, 10, 7, 12),
      sensitiveContentRevealed: revealed,
    ),
  );
}

Map<String, dynamic> _statusRoot(String status, {String uri = _rootUri}) => {
  'uri': uri,
  'cid': 'bafyroot',
  'status': status,
};

Map<String, dynamic> _statusRecord(String status, {String uri = _replyUri}) => {
  'uri': uri,
  'cid': 'bafyrecord',
  'status': status,
  'createdAt': '2026-10-01T12:00:00.000Z',
};

/// The top edge of every rendered [Text] widget.
List<double> _textTops(WidgetTester tester) => [
  for (final text in find.byType(Text).evaluate())
    tester.getTopLeft(find.byElementPredicate((element) => element == text)).dy,
];

Finder _thumbnail() => find.byWidgetPredicate(
  (widget) =>
      widget is CachedNetworkImage &&
      widget.imageUrl == 'https://cdn.test/thumb.jpg',
);

/// A live root post with every part the compact post card shows. Its
/// createdAt (7d) differs from the record's (6d), which the header shows.
const _cardRoot = <String, dynamic>{
  ..._liveRoot,
  'author': {'did': 'did:plc:poster', 'handle': 'poster.test'},
  'createdAt': '2026-09-30T12:00:00.000Z',
  'stats': {'score': 12, 'upvotes': 12, 'downvotes': 0, 'commentCount': 3},
};

const _yourCommentUri =
    'at://did:plc:alice/social.coves.community.comment/3kmine';
const _yourComment = 'Mine is a Keychron Q1.';

/// A post by Bob that mentions the viewer, whose card names Bob.
final _authoredMentionRoot = <String, dynamic>{
  ..._liveRoot,
  'uri': _postMentionUri,
  'author': {'did': 'did:plc:bob', 'handle': 'bob.coves.social'},
};

final _longTitle = List.generate(
  141,
  (index) => String.fromCharCode(97 + index % 26),
).join();

/// A reply to the viewer's comment [subject] under [rootPost].
Map<String, dynamic> _commentReply({
  required Map<String, dynamic> subject,
  Map<String, dynamic> rootPost = _cardRoot,
}) => {..._row(reason: 'commentReply', rootPost: rootPost), 'subject': subject};

/// A post that mentions the viewer: the record and the root are one post.
Map<String, dynamic> _postMention({
  required Map<String, dynamic> rootPost,
  required String excerpt,
}) => _row(
  reason: 'mention',
  rootPost: {...rootPost, 'uri': _postMentionUri},
  record: {..._liveRecord, 'uri': _postMentionUri, 'excerpt': excerpt},
);

Finder _inCard(Finder finder) =>
    find.descendant(of: find.byType(CompactPostCard), matching: finder);

void main() {
  group('NotificationReplyCard', () {
    // B1: live header and record time (including missing/invalid timestamps).
    for (final (reason, heading) in [
      ('postReply', 'Reply to your post'),
      ('commentReply', 'Reply to your comment'),
      ('mention', 'Mentioned you'),
    ]) {
      testWidgets('B1 $reason header uses record time', (tester) async {
        await _pumpCard(tester, _row(reason: reason));

        expect(find.byType(CommunityAvatar), findsOneWidget);
        expect(
          tester
              .widget<CommunityAvatar>(find.byType(CommunityAvatar))
              .avatarUrl,
          'https://cdn.test/gaming.png',
        );
        expect(find.text(heading), findsOneWidget);
        expect(find.text(_community), findsOneWidget);
        expect(find.text('6d'), findsOneWidget);
        expect(find.text('1d'), findsNothing);
        final time = tester.getRect(find.text('6d'));
        expect(
          time.left,
          greaterThan(tester.getRect(find.text(heading)).right),
        );
        expect(
          time.left,
          greaterThan(tester.getRect(find.text(_community)).right),
        );
      });
    }
    for (final (description, record) in [
      (
        'missing createdAt',
        <String, dynamic>{
          'uri': _replyUri,
          'cid': 'bafyrecord',
          'excerpt': _excerpt,
        },
      ),
      (
        'invalid createdAt',
        <String, dynamic>{..._liveRecord, 'createdAt': 'not-a-date'},
      ),
    ]) {
      testWidgets('B1 $description omits time but keeps header', (
        tester,
      ) async {
        await _pumpCard(tester, _row(record: record));

        expect(find.text('Reply to your post'), findsOneWidget);
        expect(find.text(_community), findsOneWidget);
        expect(find.byType(CommunityAvatar), findsOneWidget);
        expect(find.text('6d'), findsNothing);
        expect(find.text('1d'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('B1 community origin overrides the handle-derived host', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        _row(
          rootPost: {
            ..._liveRoot,
            'community': {
              ..._liveRoot['community'] as Map<String, dynamic>,
              'origin': 'lemmy.world',
            },
          },
        ),
      );

      expect(find.text('!gaming@lemmy.world'), findsOneWidget);
      expect(find.text(_community), findsNothing);
    });

    // B5: the root post shows as the reusable compact post card.
    testWidgets('B5 the root post shows as a compact post card', (
      tester,
    ) async {
      await _pumpCard(tester, _row(rootPost: _cardRoot));

      expect(find.byType(CompactPostCard), findsOneWidget);
      expect(_inCard(find.text(_title)), findsOneWidget);
      expect(_inCard(find.text('@poster.test')), findsOneWidget);
      expect(_inCard(find.text('7d')), findsOneWidget);
      expect(_inCard(find.text('12')), findsOneWidget);
      expect(_inCard(find.text('3')), findsOneWidget);
      expect(_inCard(_thumbnail()), findsOneWidget);
      expect(find.text(_title), findsOneWidget);
      expect(find.text('6d'), findsOneWidget, reason: 'the header time stays');
      expect(_inCard(find.text('6d')), findsNothing);
      expect(
        tester.getRect(find.byType(CompactPostCard)).top,
        greaterThanOrEqualTo(
          tester.getRect(find.text('Reply to your post')).bottom,
        ),
      );
      expect(
        tester.getTopLeft(find.text('Bob')).dy,
        greaterThan(tester.getRect(find.byType(CompactPostCard)).bottom),
        reason: 'the reply bubble sits below the post card',
      );
    });

    // B3: quoted author identity and group indentation.
    testWidgets('B3 quoted bubble shows author, handle and indented excerpt', (
      tester,
    ) async {
      await _pumpCard(tester, _row());

      expect(find.byType(UserAvatar), findsOneWidget);
      expect(
        tester.widget<UserAvatar>(find.byType(UserAvatar)).avatarUrl,
        'https://cdn.test/bob.png',
      );
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('@bob.coves.social'), findsOneWidget);
      expect(find.text(_excerpt), findsOneWidget);
      final titleLeft = tester.getRect(find.text(_title)).left;
      expect(
        tester.getRect(find.byType(UserAvatar)).left,
        greaterThan(titleLeft),
      );
      expect(tester.getRect(find.text(_excerpt)).left, greaterThan(titleLeft));
    });

    testWidgets('B3 handle becomes the name when displayName is absent', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        _row(author: {..._author}..remove('displayName')),
      );

      expect(find.text('bob.coves.social'), findsOneWidget);
      expect(find.text('Unknown user'), findsNothing);
      expect(find.text(_excerpt), findsOneWidget);
    });

    // B4: a DID must never be used as displayed identity.
    testWidgets('B4 DID-only author has a safe fallback identity', (
      tester,
    ) async {
      await _pumpCard(tester, _row(author: {'did': 'did:plc:bob'}));

      expect(find.byType(UserAvatar), findsOneWidget);
      expect(
        tester.widget<UserAvatar>(find.byType(UserAvatar)).avatarUrl,
        isNull,
      );
      expect(find.text('Unknown user'), findsOneWidget);
      expect(find.textContaining(RegExp('^@')), findsNothing);
      expect(find.textContaining('did:plc:bob'), findsNothing);
    });

    // B5: a mention of a post does not repeat the same excerpt as its title.
    for (final (description, excerpt) in [
      ('matching excerpt', _title),
      ('distinct excerpt', _excerpt),
    ]) {
      testWidgets('B5 mention of post with $description', (tester) async {
        await _pumpCard(
          tester,
          _row(
            reason: 'mention',
            rootPost: {..._liveRoot, 'uri': _postMentionUri},
            record: {
              ..._liveRecord,
              'uri': _postMentionUri,
              'excerpt': excerpt,
            },
          ),
        );

        expect(find.text(_title), findsOneWidget);
        expect(find.text('Bob'), findsOneWidget);
        if (excerpt != _title) {
          expect(find.text(_excerpt), findsOneWidget);
        }
      });
    }

    // The backend cuts a post mention's excerpt from the title at 140
    // graphemes with no ellipsis, so a longer title arrives as a prefix.
    testWidgets('B5 mention of post with title-prefix excerpt', (tester) async {
      final semantics = tester.ensureSemantics();
      final longTitle = List.generate(
        141,
        (index) => String.fromCharCode(97 + index % 26),
      ).join();
      final excerpt = longTitle.substring(0, 140);
      await _pumpCard(
        tester,
        _row(
          reason: 'mention',
          rootPost: {..._liveRoot, 'title': longTitle},
          record: {..._liveRecord, 'uri': _postMentionUri, 'excerpt': excerpt},
        ),
      );

      expect(find.text(longTitle), findsOneWidget);
      expect(find.text(excerpt), findsNothing);
      expect(
        tester.getSemantics(find.byType(NotificationReplyCard)).label,
        'Mentioned you, !gaming@coves.social, $longTitle, Bob, 6d',
      );
      semantics.dispose();
    });

    // Only a post mention drops a title-matching excerpt; a comment mention
    // keeps its own text even when it equals the root post's title.
    testWidgets('B5 mention of comment keeps excerpt matching the title', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        _row(
          reason: 'mention',
          record: {..._liveRecord, 'uri': _replyUri, 'excerpt': _title},
        ),
      );

      expect(find.text(_title), findsNWidgets(2));
    });

    // B6: sparse root replaces the whole header/title, not the live bubble.
    for (final (status, placeholder) in [
      ('removedByModerator', RemovalCopy.removedByCommunityModerator),
      ('deleted', RemovalCopy.deletedByUser),
    ]) {
      testWidgets('B6 $status root shows title-position placeholder', (
        tester,
      ) async {
        var taps = 0;
        await _pumpCard(
          tester,
          _row(
            rootPost: {'uri': _rootUri, 'cid': 'bafyroot', 'status': status},
          ),
          onTap: () => taps++,
        );

        expect(find.text(placeholder), findsOneWidget);
        expect(find.byType(CommunityAvatar), findsNothing);
        for (final reason in [
          'Reply to your post',
          'Reply to your comment',
          'Mentioned you',
        ]) {
          expect(find.text(reason), findsNothing);
        }
        expect(find.text(_community), findsNothing);
        expect(find.text('6d'), findsNothing);
        expect(find.text('Bob'), findsOneWidget);
        expect(find.text(_excerpt), findsOneWidget);
        final placeholderTop = tester.getTopLeft(find.text(placeholder)).dy;
        for (final text in find.byType(Text).evaluate()) {
          expect(
            tester
                .getTopLeft(
                  find.byElementPredicate((element) => element == text),
                )
                .dy,
            greaterThanOrEqualTo(placeholderTop),
          );
        }
        await tester.tap(find.byType(NotificationReplyCard));
        expect(taps, 1);
      });
    }

    // B7: sparse record replaces excerpt while retaining root header/title.
    for (final (status, placeholder) in [
      ('deleted', RemovalCopy.deletedByUser),
      ('removedByServerAdmin', RemovalCopy.removedByServerAdmin),
    ]) {
      testWidgets('B7 $status record shows excerpt-position placeholder', (
        tester,
      ) async {
        var taps = 0;
        await _pumpCard(
          tester,
          _row(
            record: {
              'uri': _replyUri,
              'cid': 'bafyrecord',
              'status': status,
              'createdAt': '2026-10-01T12:00:00.000Z',
            },
          ),
          onTap: () => taps++,
        );

        expect(find.text(placeholder), findsOneWidget);
        expect(find.text(_excerpt), findsNothing);
        expect(find.text('Bob'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text(placeholder)).dy,
          greaterThan(tester.getTopLeft(find.text('Bob')).dy),
        );
        expect(find.text('Reply to your post'), findsOneWidget);
        expect(find.text(_community), findsOneWidget);
        expect(find.text('6d'), findsOneWidget);
        expect(find.text(_title), findsOneWidget);
        await tester.tap(find.byType(NotificationReplyCard));
        expect(taps, 1);
      });
    }

    // B8: one activatable row node announces only the shown content.
    for (final (description, wire, label) in [
      (
        'live postReply',
        _row(),
        'Reply to your post, !gaming@coves.social, '
            'Best budget keyboards?, Bob, I use a Keychron K2., 6d',
      ),
      (
        'removed root',
        _row(
          rootPost: {
            'uri': _rootUri,
            'cid': 'bafyroot',
            'status': 'removedByModerator',
          },
        ),
        '${RemovalCopy.removedByCommunityModerator}, Bob, I use a Keychron K2.',
      ),
      (
        'DID-only commentReply',
        _row(reason: 'commentReply', author: {'did': 'did:plc:bob'}),
        'Reply to your comment, !gaming@coves.social, '
            'Best budget keyboards?, Unknown user, I use a Keychron K2., 6d',
      ),
      (
        'mention of post with duplicate excerpt',
        _row(
          reason: 'mention',
          record: {..._liveRecord, 'uri': _postMentionUri, 'excerpt': _title},
        ),
        'Mentioned you, !gaming@coves.social, Best budget keyboards?, Bob, 6d',
      ),
      (
        'deleted record',
        _row(
          record: {
            'uri': _replyUri,
            'cid': 'bafyrecord',
            'status': 'deleted',
            'createdAt': '2026-10-01T12:00:00.000Z',
          },
        ),
        'Reply to your post, !gaming@coves.social, '
            'Best budget keyboards?, Bob, ${RemovalCopy.deletedByUser}, 6d',
      ),
    ]) {
      testWidgets('B8 $description has one exact activatable row label', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        try {
          var taps = 0;
          await _pumpCard(tester, wire, onTap: () => taps++);

          final card = find.byType(NotificationReplyCard);
          expect(activatableLabels(tester, card), [label]);
          for (final node in allSemanticsNodes(tester, card)) {
            if (node.label.isNotEmpty) {
              expect(node.label, label);
            }
          }
          final rowNode = activatableNodes(
            tester,
            card,
          ).singleWhere((node) => node.label == label);
          expect(
            rowNode,
            isSemantics(isButton: true, hasTapAction: true, label: label),
          );
          activateSemanticsNode(rowNode);
          await tester.pump();
          expect(taps, 1);
        } finally {
          semantics.dispose();
        }
      });
    }

    // C13 B2: a reference whose root and record are both gone shows one
    // placeholder, in the title position, above the live author identity.
    for (final (description, wire, placeholder) in [
      (
        'deleted post mention',
        _row(
          reason: 'mention',
          rootPost: _statusRoot('deleted', uri: _postMentionUri),
          record: _statusRecord('deleted', uri: _postMentionUri),
        ),
        RemovalCopy.deletedByUser,
      ),
      (
        'moderator-removed post mention',
        _row(
          reason: 'mention',
          rootPost: _statusRoot('removedByModerator', uri: _postMentionUri),
          record: _statusRecord('removedByModerator', uri: _postMentionUri),
        ),
        RemovalCopy.removedByCommunityModerator,
      ),
      (
        'admin-removed post mention',
        _row(
          reason: 'mention',
          rootPost: _statusRoot('removedByServerAdmin', uri: _postMentionUri),
          record: _statusRecord('removedByServerAdmin', uri: _postMentionUri),
        ),
        RemovalCopy.removedByServerAdmin,
      ),
      (
        'moderator-removed commentReply',
        _row(
          reason: 'commentReply',
          rootPost: _statusRoot('removedByModerator'),
          record: _statusRecord('removedByModerator'),
        ),
        RemovalCopy.removedByCommunityModerator,
      ),
      (
        'admin-removed postReply',
        _row(
          rootPost: _statusRoot('removedByServerAdmin'),
          record: _statusRecord('removedByServerAdmin'),
        ),
        RemovalCopy.removedByServerAdmin,
      ),
    ]) {
      testWidgets('C13 B2 $description shows one title-position placeholder', (
        tester,
      ) async {
        var taps = 0;
        await _pumpCard(tester, wire, onTap: () => taps++);

        expect(find.text(placeholder), findsOneWidget);
        final placeholderTop = tester.getTopLeft(find.text(placeholder)).dy;
        for (final top in _textTops(tester)) {
          expect(top, greaterThanOrEqualTo(placeholderTop));
        }
        expect(find.text('Bob'), findsOneWidget);
        expect(find.text('@bob.coves.social'), findsOneWidget);
        await tester.tap(find.byType(NotificationReplyCard));
        expect(taps, 1);
      });
    }

    // C13 B3: distinct root and record placeholders each keep their position.
    for (final (description, rootPost, record, titleCopy, excerptCopy) in [
      (
        'moderator-removed root with admin-removed record',
        _statusRoot('removedByModerator'),
        _statusRecord('removedByServerAdmin'),
        RemovalCopy.removedByCommunityModerator,
        RemovalCopy.removedByServerAdmin,
      ),
      (
        'deleted root with deleted reply',
        _statusRoot('deleted'),
        _statusRecord('deleted'),
        RemovalCopy.deletedByUser,
        RemovalCopy.deletedByUser,
      ),
    ]) {
      testWidgets('C13 B3 postReply $description keeps both placeholders', (
        tester,
      ) async {
        await _pumpCard(tester, _row(rootPost: rootPost, record: record));

        final authorTop = tester.getTopLeft(find.text('Bob')).dy;
        double topOf(Element element) => tester
            .getTopLeft(
              find.byElementPredicate((candidate) => candidate == element),
            )
            .dy;
        if (titleCopy == excerptCopy) {
          expect(find.text(titleCopy), findsNWidgets(2));
        } else {
          expect(find.text(titleCopy), findsOneWidget);
          expect(find.text(excerptCopy), findsOneWidget);
        }
        final titleTops = find
            .text(titleCopy)
            .evaluate()
            .map(topOf)
            .where((top) => top < authorTop)
            .toList();
        final excerptTops = find
            .text(excerptCopy)
            .evaluate()
            .map(topOf)
            .where((top) => top > authorTop)
            .toList();
        expect(titleTops, hasLength(1));
        expect(excerptTops, hasLength(1));
        for (final top in _textTops(tester)) {
          expect(top, greaterThanOrEqualTo(titleTops.single));
        }
      });
    }

    // C13 B4: the collapsed post mention announces its placeholder once.
    testWidgets('C13 B4 deleted post mention has one exact activatable label', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      var taps = 0;
      await _pumpCard(
        tester,
        _row(
          reason: 'mention',
          rootPost: _statusRoot('deleted', uri: _postMentionUri),
          record: _statusRecord('deleted', uri: _postMentionUri),
        ),
        onTap: () => taps++,
      );

      const label = '[Deleted by user], Bob';
      final node = tester.getSemantics(find.byType(NotificationReplyCard));
      expect(node.label, label);
      expect(find.bySemanticsLabel(label), findsOneWidget);
      expect(
        node,
        isSemantics(
          isButton: true,
          hasTapAction: true,
          label: label,
          children: const [],
        ),
      );
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pump();
      expect(taps, 1);
      semantics.dispose();
    });

    // B5 (R3): on a reply to the viewer's comment, a quotable subject
    // replaces the post card with a quote of that comment.
    testWidgets('B5 a reply to your comment quotes it instead of the post', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        _commentReply(
          subject: {
            'uri': _yourCommentUri,
            'cid': 'bafymine',
            'preview': _yourComment,
          },
        ),
      );

      expect(find.text(_yourComment), findsOneWidget);
      expect(find.byType(CompactPostCard), findsNothing);
      expect(find.text(_title), findsNothing);
      expect(find.text('Reply to your comment'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text(_excerpt), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(_yourComment)).dy,
        lessThan(tester.getTopLeft(find.text('Bob')).dy),
        reason: 'your comment is quoted above the reply',
      );
    });

    testWidgets('B5 a removed comment of yours is quoted as its placeholder', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        _commentReply(
          subject: {
            'uri': _yourCommentUri,
            'cid': 'bafymine',
            'status': 'removedByServerAdmin',
          },
        ),
      );

      expect(find.text(RemovalCopy.removedByServerAdmin), findsOneWidget);
      expect(find.byType(CompactPostCard), findsNothing);
      expect(find.text(_title), findsNothing);
      expect(find.text(_excerpt), findsOneWidget);
    });

    testWidgets('B5 a reply to your comment without a preview shows the post', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        _commentReply(subject: {'uri': _yourCommentUri, 'cid': 'bafymine'}),
      );

      expect(find.byType(CompactPostCard), findsOneWidget);
      expect(_inCard(find.text(_title)), findsOneWidget);
    });

    for (final (description, wire) in [
      ('postReply', _row(rootPost: _statusRoot('removedByModerator'))),
      (
        'commentReply with a quotable comment of yours',
        _commentReply(
          rootPost: _statusRoot('removedByModerator'),
          subject: {
            'uri': _yourCommentUri,
            'cid': 'bafymine',
            'preview': _yourComment,
          },
        ),
      ),
    ]) {
      testWidgets('B5 a removed root on a $description shows the placeholder '
          'post card', (tester) async {
        await _pumpCard(tester, wire);

        expect(find.byType(CompactPostCard), findsOneWidget);
        expect(
          _inCard(find.text(RemovalCopy.removedByCommunityModerator)),
          findsOneWidget,
        );
        expect(
          find.text(RemovalCopy.removedByCommunityModerator),
          findsOneWidget,
        );
        expect(find.text(_yourComment), findsNothing);
        expect(find.text('Bob'), findsOneWidget);
        expect(find.text(_excerpt), findsOneWidget);
      });
    }

    // B5 (R4): a post mention whose excerpt the title already shows drops
    // the bubble when the post card names the author.
    for (final (description, title, excerpt) in [
      ('equal to the title', _title, _title),
      (
        'a 140-grapheme prefix of the title',
        _longTitle,
        _longTitle.substring(0, 140),
      ),
    ]) {
      testWidgets('B5 post mention with an excerpt $description drops the '
          'bubble when the post card shows the author', (tester) async {
        await _pumpCard(
          tester,
          _postMention(
            rootPost: {..._authoredMentionRoot, 'title': title},
            excerpt: excerpt,
          ),
        );

        expect(find.text('Bob'), findsNothing);
        expect(find.byType(CompactPostCard), findsOneWidget);
        expect(_inCard(find.text(title)), findsOneWidget);
        expect(_inCard(find.text('@bob.coves.social')), findsOneWidget);
        expect(find.text('@bob.coves.social'), findsOneWidget);
        expect(
          find.text(excerpt),
          title == excerpt ? findsOneWidget : findsNothing,
        );

        // A distinct excerpt adds text, so the bubble stays.
        await _pumpCard(
          tester,
          _postMention(rootPost: _authoredMentionRoot, excerpt: _excerpt),
        );
        expect(find.text('Bob'), findsOneWidget);
        expect(find.text(_excerpt), findsOneWidget);
      });
    }

    testWidgets('B5 a comment mention keeps its bubble under an authored post '
        'card', (tester) async {
      await _pumpCard(
        tester,
        _row(
          reason: 'mention',
          rootPost: _cardRoot,
          record: {..._liveRecord, 'excerpt': _title},
        ),
      );

      expect(find.byType(CompactPostCard), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text(_title), findsNWidgets(2));
    });
  });
}
