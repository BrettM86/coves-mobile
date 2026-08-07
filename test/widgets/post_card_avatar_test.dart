import 'package:coves_flutter/constants/app_colors.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/utils/display_utils.dart';
import 'package:coves_flutter/widgets/post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_providers.dart';

/// RED: PostCard still hand-rolls its avatars.
///
/// Two user-visible defects are pinned here:
///  1. The community fallback avatar paints AppColors.primary, so the same
///     community shows a different color on the feed than on the detail
///     screen (which uses the DisplayUtils hash). Everything must agree on
///     DisplayUtils.getFallbackColor.
///  2. `community.name[0]` is unguarded, so a community with an empty name
///     throws RangeError while building the card.
void main() {
  late FakeAuthProvider auth;

  setUp(() {
    auth = FakeAuthProvider();
  });

  Widget createTestWidget(FeedViewPost post, {bool showAuthorFooter = false}) {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder:
              (context, state) => Scaffold(
                body: PostCard(post: post, showAuthorFooter: showAuthorFooter),
              ),
        ),
        GoRoute(
          path: '/post/:uri',
          builder: (context, state) => const Scaffold(body: Text('DETAIL')),
        ),
      ],
    );
    addTearDown(router.dispose);

    return MultiProvider(
      providers: postCardProviders(auth: auth),
      child: MaterialApp.router(routerConfig: router),
    );
  }

  FeedViewPost buildPost({
    required String communityName,
    String authorHandle = 'author.test',
    String? authorDisplayName,
  }) {
    return FeedViewPost(
      post: PostView(
        uri: 'at://did:example/post/123',
        cid: 'cid123',
        rkey: '123',
        author: AuthorView(
          did: 'did:plc:author',
          handle: authorHandle,
          displayName: authorDisplayName,
        ),
        community: CommunityRef(
          did: 'did:plc:community',
          name: communityName,
        ),
        createdAt: DateTime(2024),
        indexedAt: DateTime(2024),
        record: const PostRecord(content: 'body', title: 'title'),
        stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
      ),
    );
  }

  /// Background color painted directly behind [inner].
  ///
  /// Matching on DecoratedBox rather than Container keeps this agnostic to
  /// whether the avatar is built with a Container, a DecoratedBox, or a
  /// clipped box once the shared widget lands.
  Color paintedColorBehind(WidgetTester tester, Finder inner) {
    final decorated = tester.widget<DecoratedBox>(
      find.ancestor(of: inner, matching: find.byType(DecoratedBox)).first,
    );
    return (decorated.decoration as BoxDecoration).color!;
  }

  group('PostCard community avatar', () {
    testWidgets('fallback uses the shared hash color, not AppColors.primary', (
      tester,
    ) async {
      const name = 'TestCommunity';
      // Guard: a name that happened to hash onto coral would make the
      // assertion below vacuous.
      expect(
        DisplayUtils.getFallbackColor(name).toARGB32(),
        isNot(AppColors.primary.toARGB32()),
        reason: 'fixture name must hash away from the legacy color',
      );

      await tester.pumpWidget(createTestWidget(buildPost(communityName: name)));

      expect(find.text('T'), findsOneWidget);
      expect(
        paintedColorBehind(tester, find.text('T')).toARGB32(),
        DisplayUtils.getFallbackColor(name).toARGB32(),
        reason:
            'feed and detail screens must agree on the community fallback '
            'color',
      );
    });

    testWidgets('an empty community name renders "?" without throwing', (
      tester,
    ) async {
      await tester.pumpWidget(createTestWidget(buildPost(communityName: '')));

      expect(
        tester.takeException(),
        isNull,
        reason: 'community.name[0] must be guarded against an empty name',
      );
      expect(find.text('?'), findsOneWidget);
    });
  });

  group('PostCard author avatar', () {
    testWidgets('fallback uses the shared hash color, not AppColors.primary', (
      tester,
    ) async {
      // Author avatars unify on the same hash-of-name color as every other
      // avatar in the app (work brief: "Design decisions").
      const handle = 'commenter.test';
      expect(
        DisplayUtils.getFallbackColor(handle).toARGB32(),
        isNot(AppColors.primary.toARGB32()),
        reason: 'fixture handle must hash away from the legacy color',
      );

      // The author avatar only renders in the footer variant (detail view).
      await tester.pumpWidget(
        createTestWidget(
          buildPost(communityName: 'TestCommunity', authorHandle: handle),
          showAuthorFooter: true,
        ),
      );

      expect(find.text('C'), findsOneWidget);
      expect(
        paintedColorBehind(tester, find.text('C')).toARGB32(),
        DisplayUtils.getFallbackColor(handle).toARGB32(),
      );
    });
  });
}
