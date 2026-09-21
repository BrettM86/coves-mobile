import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/bluesky_post.dart';
import 'package:coves_flutter/widgets/bluesky_post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BlueskyPostCard with an unavailable quoted post', () {
    testWidgets(
      'renders the available parent post and the deleted quote message',
      (tester) async {
        // Backend wire shape: the parent resolves fine, but its quoted post
        // was deleted, so it arrives with unavailable/message and no author.
        final embed = BlueskyPostEmbed.fromJson(<String, dynamic>{
          'post': <String, dynamic>{
            'uri': 'at://did:plc:parent/app.bsky.feed.post/p1',
            'cid': 'bafyparentcid',
          },
          'resolved': <String, dynamic>{
            'uri': 'at://did:plc:parent/app.bsky.feed.post/p1',
            'cid': 'bafyparentcid',
            'text': 'Parent post text',
            'createdAt': '2026-09-01T12:00:00Z',
            'author': <String, dynamic>{
              'did': 'did:plc:parent',
              'handle': 'parent.bsky.social',
            },
            'replyCount': 0,
            'repostCount': 0,
            'likeCount': 0,
            'mediaCount': 0,
            'hasMedia': false,
            'unavailable': false,
            'quotedPost': <String, dynamic>{
              'uri': 'at://did:plc:quoted/app.bsky.feed.post/q1',
              'cid': '',
              'text': '',
              'createdAt': '0001-01-01T00:00:00Z',
              'replyCount': 0,
              'repostCount': 0,
              'likeCount': 0,
              'mediaCount': 0,
              'hasMedia': false,
              'unavailable': true,
              'message': 'This post has been deleted',
            },
          },
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(
              body: SingleChildScrollView(
                child: BlueskyPostCard(
                  embed: embed,
                  currentTime: DateTime.parse('2026-09-02T12:00:00Z'),
                ),
              ),
            ),
          ),
        );

        expect(find.text('Parent post text'), findsOneWidget);
        expect(find.text('@parent.bsky.social'), findsOneWidget);
        expect(find.text('This post has been deleted'), findsOneWidget);
        expect(
          find.text('Post not found, it may have been deleted.'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('renders the fallback message when the quote has no message', (
      tester,
    ) async {
      final embed = BlueskyPostEmbed.fromJson(<String, dynamic>{
        'post': <String, dynamic>{
          'uri': 'at://did:plc:parent/app.bsky.feed.post/p1',
          'cid': 'bafyparentcid',
        },
        'resolved': <String, dynamic>{
          'uri': 'at://did:plc:parent/app.bsky.feed.post/p1',
          'cid': 'bafyparentcid',
          'text': 'Parent post text',
          'createdAt': '2026-09-01T12:00:00Z',
          'author': <String, dynamic>{
            'did': 'did:plc:parent',
            'handle': 'parent.bsky.social',
          },
          'replyCount': 0,
          'repostCount': 0,
          'likeCount': 0,
          'mediaCount': 0,
          'hasMedia': false,
          'unavailable': false,
          'quotedPost': <String, dynamic>{
            'uri': 'at://did:plc:quoted/app.bsky.feed.post/q1',
            'cid': '',
            'text': '',
            'createdAt': '0001-01-01T00:00:00Z',
            'replyCount': 0,
            'repostCount': 0,
            'likeCount': 0,
            'mediaCount': 0,
            'hasMedia': false,
            'unavailable': true,
          },
        },
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(
              child: BlueskyPostCard(
                embed: embed,
                currentTime: DateTime.parse('2026-09-02T12:00:00Z'),
              ),
            ),
          ),
        ),
      );

      // The parent renders, and only the quote box falls back to the generic
      // message — not the whole-embed unavailable card.
      expect(find.text('Parent post text'), findsOneWidget);
      expect(find.text('@parent.bsky.social'), findsOneWidget);
      expect(
        find.text('Post not found, it may have been deleted.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('BlueskyPostCard with an unavailable top-level post', () {
    testWidgets('renders the unavailable card when the post has no author', (
      tester,
    ) async {
      final embed = BlueskyPostEmbed.fromJson(<String, dynamic>{
        'post': <String, dynamic>{
          'uri': 'at://did:plc:parent/app.bsky.feed.post/p1',
          'cid': 'bafyparentcid',
        },
        'resolved': <String, dynamic>{
          'uri': 'at://did:plc:parent/app.bsky.feed.post/p1',
          'cid': '',
          'text': '',
          'createdAt': '0001-01-01T00:00:00Z',
          'replyCount': 0,
          'repostCount': 0,
          'likeCount': 0,
          'mediaCount': 0,
          'hasMedia': false,
          'unavailable': true,
          'message': 'This post has been deleted',
        },
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(child: BlueskyPostCard(embed: embed)),
          ),
        ),
      );

      expect(
        find.text('Post not found, it may have been deleted.'),
        findsOneWidget,
      );
      expect(find.text('likes'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Text && (widget.data ?? '').startsWith('@'),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
