// Reply-preview fixtures P (a post) and C (a comment with one reply),
// shared by the reply screen's preview tests and the feed-card guards.
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';

import 'reply_screen_test_harness.dart';

// 2025-01-01T00:00Z; the month and day are the defaults.
final previewCreatedAt = DateTime.utc(2025);
final previewCurrentTime = DateTime.utc(2025, 1, 1, 5);

const previewPostTitle = 'Preview post title';
const previewPostText = 'Preview post body text.';
const previewPostAuthorHandle = 'preview.author.test';

/// Fixture P, with an optional [embed] and the self-applied sensitive label.
FeedViewPost previewPost({PostEmbed? embed, bool sensitive = false}) =>
    FeedViewPost(
      post: PostView(
        uri: testPostUri,
        cid: testPostCid,
        rkey: '123',
        author: AuthorView(
          did: 'did:plc:preview',
          handle: previewPostAuthorHandle,
        ),
        community: CommunityRef(did: 'did:plc:community', name: 'tidepools'),
        createdAt: previewCreatedAt,
        indexedAt: previewCreatedAt,
        record: PostRecord(
          title: previewPostTitle,
          content: previewPostText,
          labels: sensitive ? const ['nsfw'] : const [],
        ),
        stats: PostStats(upvotes: 3, downvotes: 0, score: 3, commentCount: 1),
        embed: embed,
      ),
    );

CommentView previewCommentView({
  required String id,
  required String? body,
  required String handle,
  int score = 0,
  int replyCount = 0,
  bool deleted = false,
  PostEmbed? embed,
}) => CommentView(
  uri: 'at://did:plc:$id/social.coves.community.comment/$id',
  cid: 'cid-$id',
  record: deleted ? null : CommentRecord(content: body!),
  isDeleted: deleted,
  deletionReason: deleted ? 'author' : null,
  createdAt: previewCreatedAt,
  indexedAt: previewCreatedAt,
  author: AuthorView(did: 'did:plc:$id', handle: handle),
  post: CommentRef(uri: testPostUri, cid: testPostCid),
  stats: CommentStats(upvotes: score, score: score, replyCount: replyCount),
  parsedEmbed: embed,
);

/// Fixture C; with [nestedDeleted] the reply is a deleted placeholder, and
/// [firstEmbed] goes on the first comment.
ThreadViewComment previewCommentChain({
  bool nestedDeleted = false,
  PostEmbed? firstEmbed,
}) => ThreadViewComment(
  comment: previewCommentView(
    id: 'first',
    body: 'First comment body.',
    handle: 'first.commenter.test',
    score: 5,
    replyCount: 1,
    embed: firstEmbed,
  ),
  replies: [
    ThreadViewComment(
      comment: nestedDeleted
          ? previewCommentView(
              id: 'second',
              body: null,
              handle: 'handle.invalid',
              deleted: true,
            )
          : previewCommentView(
              id: 'second',
              body: 'Nested reply body.',
              handle: 'second.commenter.test',
              score: 2,
            ),
    ),
  ],
);
