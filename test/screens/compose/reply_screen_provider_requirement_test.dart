import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/screens/compose/reply_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'reply_screen_test_harness.dart';

FeedViewPost _post() => FeedViewPost(
  post: PostView(
    uri: testPostUri,
    cid: testPostCid,
    rkey: '123',
    author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
    community: CommunityRef(did: 'did:plc:community', name: 'test'),
    createdAt: DateTime(2025),
    indexedAt: DateTime(2025),
    record: const PostRecord(content: 'A post'),
    stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
  ),
);

Future<void> _noopSubmit(String content, List<RichTextFacet> facets) async {}

void main() {
  group('ReplyScreen reply mode requires a CommentsProvider', () {
    test('replying to a post without one fails at construction', () {
      expect(
        () => ReplyScreen(post: _post(), onSubmit: _noopSubmit),
        throwsAssertionError,
      );
    });

    test('replying to a comment without one fails at construction', () {
      expect(
        () => ReplyScreen(
          comment: createComment('at://did:plc:author/comment/1'),
          onSubmit: _noopSubmit,
        ),
        throwsAssertionError,
      );
    });
  });
}
