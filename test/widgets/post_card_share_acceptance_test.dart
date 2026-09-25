import 'package:coves_flutter/config/environment_config.dart';
import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/services/link_sharer.dart';
import 'package:coves_flutter/widgets/post_card.dart';
import 'package:coves_flutter/widgets/share_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_providers.dart';

/// A `LinkSharer` that records dispatches instead of opening a native sheet.
class RecordingLinkSharer implements LinkSharer {
  final List<String> sharedUrls = [];
  final List<Rect> sharePositionOrigins = [];

  @override
  Future<void> shareLink(
    String url, {
    required Rect sharePositionOrigin,
  }) async {
    sharedUrls.add(url);
    sharePositionOrigins.add(sharePositionOrigin);
  }
}

void main() {
  // Literal, never produced by the code under test.
  const expectedShareUrl =
      'https://coves.social/c/gaming/post/alice.coves.social/3kabcxyz';

  late FakeAuthProvider auth;
  late RecordingLinkSharer linkSharer;

  setUp(() {
    auth = FakeAuthProvider();
    linkSharer = RecordingLinkSharer();
  });

  /// A post in the author's own repo, with a valid handle and a community
  /// served by this instance.
  FeedViewPost authorOwnedPost() {
    return FeedViewPost(
      post: PostView(
        uri: 'at://did:plc:author123/social.coves.community.postv2/3kabcxyz',
        cid: 'cid123',
        rkey: '3kabcxyz',
        author: AuthorView(
          did: 'did:plc:author123',
          handle: 'alice.coves.social',
        ),
        community: CommunityRef(
          did: 'did:plc:community456',
          name: 'Gaming',
          origin: 'coves.social',
        ),
        createdAt: DateTime(2024),
        indexedAt: DateTime(2024),
        record: const PostRecord(
          content: 'Test post content',
          title: 'Test Post Title',
        ),
        stats: PostStats(upvotes: 1, downvotes: 0, score: 1, commentCount: 0),
      ),
    );
  }

  Widget createTestWidget(FeedViewPost post) {
    // PostCard's subtree navigates with go_router, so it needs a router
    // rather than a bare MaterialApp.
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(body: PostCard(post: post)),
        ),
      ],
    );
    addTearDown(router.dispose);

    return MultiProvider(
      providers: [
        ...postCardProviders(auth: auth),
        Provider<LinkSharer>.value(value: linkSharer),
      ],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    );
  }

  testWidgets('share button dispatches the post web link exactly once', (
    tester,
  ) async {
    // The expected URL assumes the production web origin; `flutter test`
    // passes no ENVIRONMENT/flavor define, so the config defaults there.
    expect(EnvironmentConfig.current.isProduction, isTrue);

    await tester.pumpWidget(createTestWidget(authorOwnedPost()));

    // The card's share control renders as a Semantics/InkWell pair, not a
    // Tooltip widget, so match the widget by its tooltip property.
    final shareButton = find.byWidgetPredicate(
      (widget) => widget is ShareButton && widget.tooltip == 'Share post',
    );
    expect(shareButton, findsOneWidget);

    await tester.tap(shareButton);
    await tester.pumpAndSettle();

    expect(linkSharer.sharedUrls, [expectedShareUrl]);
    expect(find.text('Share coming soon!'), findsNothing);
  });
}
