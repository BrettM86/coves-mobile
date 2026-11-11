import 'dart:async';

import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/screens/compose/reply_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'reply_screen_test_harness.dart';

const _postBody = 'Distinctive parent post body for selection';
const _commentBody = 'Distinctive parent comment body for selection';

FeedViewPost _post() => FeedViewPost(
  post: PostView(
    uri: testPostUri,
    cid: testPostCid,
    rkey: '123',
    author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
    community: CommunityRef(did: 'did:plc:community', name: 'test'),
    createdAt: DateTime(2025),
    indexedAt: DateTime(2025),
    record: const PostRecord(content: _postBody),
    stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
  ),
);

ThreadViewComment _comment() => ThreadViewComment(
  comment: CommentView(
    uri: 'at://did:plc:author/comment/1',
    cid: 'cid-comment-1',
    record: const CommentRecord(content: _commentBody),
    createdAt: DateTime(2025),
    indexedAt: DateTime(2025),
    author: AuthorView(did: 'did:plc:author', handle: 'test.user'),
    post: CommentRef(uri: testPostUri, cid: testPostCid),
    stats: const CommentStats(),
  ),
);

void main() {
  testWidgets('long-pressing the reply context preview text offers Copy', (
    tester,
  ) async {
    final cases = <(String, String, ReplyScreen Function(ReplyScreenHarness))>[
      (
        'replying to a post',
        _postBody,
        (harness) => ReplyScreen(
          post: _post(),
          commentsProvider: harness.commentsProvider,
          onSubmit: (content, facets, embed) async {},
        ),
      ),
      (
        'replying to a comment',
        _commentBody,
        (harness) => ReplyScreen(
          comment: _comment(),
          commentsProvider: harness.commentsProvider,
          onSubmit: (content, facets, embed) async {},
        ),
      ),
    ];

    for (final (label, body, buildScreen) in cases) {
      final harness = ReplyScreenHarness();
      await harness.pumpBase(tester);
      unawaited(
        harness.navigatorKey.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => buildScreen(harness)),
        ),
      );
      await tester.pumpAndSettle();

      final bodyText = find.textContaining(body, findRichText: true);
      expect(bodyText, findsOneWidget, reason: '$label: preview shows body');
      expect(
        find.text('Copy'),
        findsNothing,
        reason: '$label: no toolbar before the long-press',
      );

      await tester.longPress(bodyText);
      await tester.pumpAndSettle();

      expect(
        find.text('Copy'),
        findsOneWidget,
        reason:
            '$label: long-pressing the context preview text selects it '
            'and shows a Copy action',
      );

      // Tear down this case's tree before the next case
      await tester.pumpWidget(const SizedBox.shrink());
      harness.dispose();
    }
  });
}
