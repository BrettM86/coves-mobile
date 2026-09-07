import 'package:coves_flutter/constants/app_colors.dart';
import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/widgets/icons/animated_heart_icon.dart';
import 'package:coves_flutter/widgets/icons/reply_icon.dart';
import 'package:coves_flutter/widgets/post_action_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FeedViewPost createPost({int score = 4}) {
  return FeedViewPost(
    post: PostView(
      uri: 'at://did:plc:author/social.coves.community.post/123',
      cid: 'cid123',
      rkey: '123',
      author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
      community: CommunityRef(did: 'did:plc:community', name: 'test-community'),
      createdAt: DateTime(2024),
      indexedAt: DateTime(2024),
      stats: PostStats(
        upvotes: score + 1,
        downvotes: 1,
        score: score,
        commentCount: 0,
      ),
    ),
  );
}

Widget postActionBarHarness({
  FeedViewPost? post,
  VoidCallback? onVoteTap,
  VoidCallback? onSaveTap,
  bool isVoted = false,
  bool isSaved = false,
  bool isVotePending = false,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    theme: AppTheme.dark,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(disableAnimations: disableAnimations),
      child: child!,
    ),
    home: Scaffold(
      bottomNavigationBar: PostActionBar(
        post: post ?? createPost(),
        onVoteTap: onVoteTap,
        onSaveTap: onSaveTap,
        isVoted: isVoted,
        isSaved: isSaved,
        isVotePending: isVotePending,
      ),
    ),
  );
}

Finder downvoteControl(String actionLabel) {
  final semanticDownvote = find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == actionLabel,
    description: 'Semantics labelled "$actionLabel"',
  );
  final tooltipDownvote = find.byWidgetPredicate(
    (widget) => widget is Tooltip && widget.message == actionLabel,
    description: 'Tooltip labelled "$actionLabel"',
  );
  return semanticDownvote.evaluate().isNotEmpty
      ? semanticDownvote
      : tooltipDownvote;
}

Finder upvoteControl(String actionLabel) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == actionLabel,
  description: 'Semantics labelled "$actionLabel"',
);

void expectMinimumTapTargets(
  WidgetTester tester,
  Map<String, Finder> controls,
) {
  final undersized = <String, Size>{};
  for (final entry in controls.entries) {
    final size = tester.getSize(entry.value);
    if (size.width < 48 || size.height < 48) {
      undersized[entry.key] = size;
    }
  }
  expect(
    undersized,
    isEmpty,
    reason: 'interactive vote render boxes must be at least 48x48',
  );
}

Color? scoreColor(WidgetTester tester, String score) =>
    tester.widget<Text>(find.text(score)).style?.color;

void main() {
  testWidgets('detail retains bookmark and compact score tight beside heart', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 800);
    await tester.pumpWidget(
      postActionBarHarness(post: createPost(score: 5234)),
    );
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
    expect(downvoteControl('Downvote post'), findsNothing);
    final score = find.text('5.2K');
    final heart = find.byType(AnimatedHeartIcon);
    final upvote = upvoteControl('Upvote post');
    expect(score, findsOneWidget);
    expect(tester.getTopLeft(score).dx - tester.getTopRight(heart).dx, 4);
    expect(find.descendant(of: upvote, matching: score), findsOneWidget);
    expectMinimumTapTargets(tester, {'upvote': upvote});
  });

  testWidgets('bookmark retains main sizing count and action spacing', (
    tester,
  ) async {
    await tester.pumpWidget(postActionBarHarness());
    final bookmark = find.byIcon(Icons.bookmark_border);
    final save = upvoteControl('Save post');
    final saveCount = find.descendant(of: save, matching: find.text('0'));
    final upvote = upvoteControl('Upvote post');
    final reply = find.byType(ReplyIcon);
    final input = find
        .ancestor(
          of: find.text('Comment'),
          matching: find.byType(GestureDetector),
        )
        .first;

    expect(bookmark, findsOneWidget);
    expect(tester.getSize(bookmark), const Size(24, 24));
    expect(saveCount, findsOneWidget);
    expect(
      tester.getTopLeft(saveCount).dx - tester.getTopRight(bookmark).dx,
      4,
    );
    expect(tester.getTopLeft(bookmark).dx - tester.getTopRight(upvote).dx, 16);
    expect(tester.getTopLeft(reply).dx - tester.getTopRight(saveCount).dx, 16);
    expect(tester.getTopLeft(upvote).dx - tester.getTopRight(input).dx, 16);
  });

  testWidgets('liked score is red and score tap invokes upvote', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      postActionBarHarness(isVoted: true, onVoteTap: () => calls++),
    );
    expect(scoreColor(tester, '4'), AppColors.voteLiked);
    await tester.tap(find.text('4'));
    expect(calls, 1);
  });

  testWidgets('bookmark invokes save independently and reflects selection', (
    tester,
  ) async {
    var saves = 0;
    var votes = 0;
    await tester.pumpWidget(
      postActionBarHarness(
        isSaved: true,
        onSaveTap: () => saves++,
        onVoteTap: () => votes++,
      ),
    );
    await tester.tap(find.byIcon(Icons.bookmark));
    expect(saves, 1);
    expect(votes, 0);
  });

  testWidgets('score animates only on change for 400ms', (tester) async {
    await tester.pumpWidget(postActionBarHarness());
    final restingY = tester.getTopLeft(find.text('4')).dy;
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getTopLeft(find.text('4')).dy, restingY);
    await tester.pumpWidget(postActionBarHarness(post: createPost(score: 5)));
    expect(find.text('4'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(tester.getTopLeft(find.text('5')).dy, lessThan(restingY));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('4'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    // The visible transition ends at 400ms; Flutter removes its outgoing
    // element on the next ticker notification.
    final outgoingOpacity = find.ancestor(
      of: find.text('4'),
      matching: find.byType(Opacity),
    );
    if (outgoingOpacity.evaluate().isNotEmpty) {
      expect(tester.widget<Opacity>(outgoingOpacity.first).opacity, 0);
    }
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('4'), findsNothing);
    expect(find.text('5'), findsOneWidget);
    expect(tester.getTopLeft(find.text('5')).dy, restingY);
  });

  testWidgets('reduced motion updates score immediately', (tester) async {
    await tester.pumpWidget(postActionBarHarness(disableAnimations: true));
    await tester.pumpWidget(
      postActionBarHarness(post: createPost(score: 5), disableAnimations: true),
    );
    expect(find.text('4'), findsNothing);
    expect(find.text('5'), findsOneWidget);
    final position = tester.getTopLeft(find.text('5'));
    await tester.pump(const Duration(milliseconds: 96));
    expect(tester.getTopLeft(find.text('5')), position);
    expect(find.text('4'), findsNothing);
  });

  testWidgets('pending upvote stays visible and inert', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      postActionBarHarness(
        isVoted: true,
        isVotePending: true,
        onVoteTap: () => calls++,
      ),
    );
    await tester.tap(find.byType(AnimatedHeartIcon));
    await tester.tap(find.text('4'));
    expect(calls, 0);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('4'), findsOneWidget);
  });
}
