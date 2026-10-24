import 'package:coves_flutter/constants/embed_types.dart';
import 'package:coves_flutter/models/post.dart';

/// A quoted Bluesky post embed built through the real model parser.
///
/// [text] is the resolved post's text. A null [text] omits `resolved`
/// entirely, the shape the appview sends when it could not hydrate the quote.
/// [unavailable] marks a resolved post the appview flagged as blocked,
/// deleted or detached while still carrying a text and author.
PostEmbed blueskyQuoteEmbed({String? text, bool unavailable = false}) {
  return PostEmbed.fromJson({
    r'$type': EmbedTypes.postView,
    'post': {
      'uri': 'at://did:plc:quoted/app.bsky.feed.post/q1',
      'cid': 'bafyquotedcid',
    },
    if (text != null)
      'resolved': {
        'uri': 'at://did:plc:quoted/app.bsky.feed.post/q1',
        'cid': 'bafyquotedcid',
        'text': text,
        'createdAt': '2026-09-01T12:00:00Z',
        'author': {'did': 'did:plc:quoted', 'handle': 'quoted.bsky.social'},
        'replyCount': 0,
        'repostCount': 0,
        'likeCount': 0,
        'hasMedia': false,
        'mediaCount': 0,
        'unavailable': unavailable,
      },
  });
}

/// A Coves post sharing a Bluesky post, with an empty Coves body and no
/// other media, so the title and the quote card are the only content.
FeedViewPost blueskySharePost({
  String? title,
  required PostEmbed embed,
  bool sensitive = false,
}) {
  return FeedViewPost(
    post: PostView(
      uri: 'at://did:plc:author/social.coves.community.post/share',
      cid: 'cid-share',
      rkey: 'share',
      author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
      community: CommunityRef(did: 'did:plc:community', name: 'test-community'),
      createdAt: DateTime(2024),
      indexedAt: DateTime(2024),
      record: PostRecord(
        title: title,
        content: '',
        labels: sensitive ? const ['nsfw'] : const [],
      ),
      stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
      embed: embed,
    ),
  );
}
