import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/widgets/detailed_post_view.dart';
import 'package:coves_flutter/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/default_avatar_expectations.dart';

/// The detail view's author avatar shows the author's DID default when the
/// author has no avatar.
void main() {
  testWidgets('an author with no avatar shows their DID default', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final post = FeedViewPost(
      post: PostView(
        uri: 'at://did:web:coves.social/social.coves.community.post/aaa',
        cid: 'cid-aaa',
        rkey: 'aaa',
        author: AuthorView(did: 'did:web:coves.social', handle: 'coves.social'),
        community: CommunityRef(
          did: 'did:plc:community',
          name: 'test-community',
        ),
        createdAt: DateTime(2024),
        indexedAt: DateTime(2024),
        record: const PostRecord(title: 'A post', content: 'Body text'),
        stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SingleChildScrollView(child: DetailedPostView(post: post)),
        ),
      ),
    );
    await tester.pump();

    expectDefaultAvatar(
      find.byType(UserAvatar),
      url: 'http://127.0.0.1:1/img/default-avatars/v1/sandcastle.webp',
      tint: 0xFFD5E6E3,
    );
  });
}
