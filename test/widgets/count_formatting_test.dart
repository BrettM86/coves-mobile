import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/widgets/comments_header.dart';
import 'package:coves_flutter/widgets/post_action_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every count in the UI is expected to render through the one canonical
/// formatter (`DisplayUtils.formatCount`): uppercase K/M, with a real M tier.
///
/// These two widgets need no providers, so they pin the shared contract
/// cheaply. PostCardActions and CommentCard cover the same contract inside
/// their existing provider harnesses (post_card_test.dart,
/// comment_thread_test.dart).
void main() {
  FeedViewPost createPost({required int score, required int commentCount}) {
    return FeedViewPost(
      post: PostView(
        uri: 'at://did:example/post/123',
        cid: 'cid123',
        rkey: '123',
        author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
        community: CommunityRef(
          did: 'did:plc:community',
          name: 'test-community',
        ),
        createdAt: DateTime(2024),
        indexedAt: DateTime(2024),
        stats: PostStats(
          upvotes: score,
          downvotes: 0,
          score: score,
          commentCount: commentCount,
        ),
      ),
    );
  }

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('PostActionBar count formatting', () {
    testWidgets('renders a millions-scale vote score with an uppercase M', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(PostActionBar(post: createPost(score: 1500000, commentCount: 0))),
      );

      expect(find.text('1.5M'), findsOneWidget);
      // The old formatter had no M tier and used a lowercase suffix.
      expect(find.text('1500.0k'), findsNothing);
    });

    testWidgets('renders a thousands-scale vote score with an uppercase K', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(PostActionBar(post: createPost(score: 5234, commentCount: 0))),
      );

      expect(find.text('5.2K'), findsOneWidget);
      expect(find.text('5.2k'), findsNothing);
    });

    testWidgets('renders the comment count with an uppercase K', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(PostActionBar(post: createPost(score: 0, commentCount: 12500))),
      );

      expect(find.text('12.5K'), findsOneWidget);
      expect(find.text('12.5k'), findsNothing);
    });

    testWidgets('renders small counts unchanged', (tester) async {
      await tester.pumpWidget(
        wrap(PostActionBar(post: createPost(score: 8, commentCount: 5))),
      );

      expect(find.text('8'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
    });
  });

  group('CommentsHeader count formatting', () {
    Widget header(int count) => wrap(
      CommentsHeader(
        commentCount: count,
        currentSort: 'hot',
        onSortChanged: (_) {},
      ),
    );

    testWidgets('formats a large comment count', (tester) async {
      await tester.pumpWidget(header(5234));

      expect(find.text('5.2K Comments'), findsOneWidget);
      expect(find.text('5234 Comments'), findsNothing);
    });

    testWidgets('formats a millions-scale comment count', (tester) async {
      await tester.pumpWidget(header(1500000));

      expect(find.text('1.5M Comments'), findsOneWidget);
    });

    testWidgets('leaves small counts unformatted and singular at 1', (
      tester,
    ) async {
      await tester.pumpWidget(header(1));
      expect(find.text('1 Comment'), findsOneWidget);

      await tester.pumpWidget(header(42));
      expect(find.text('42 Comments'), findsOneWidget);
    });

    testWidgets('renders the empty state at zero', (tester) async {
      await tester.pumpWidget(header(0));

      expect(find.text('No comments yet'), findsOneWidget);
    });
  });
}
