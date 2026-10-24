import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/widgets/bluesky_post_card.dart';
import 'package:coves_flutter/widgets/post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../test_helpers/bluesky_title_fixtures.dart';
import '../test_helpers/fake_providers.dart';

const _quotedText = 'Breaking: the river flooded the old mill';
const _ownTitle = 'Worth reading before the vote';

void main() {
  /// Pumps [post] into a feed-shaped PostCard. [disableNavigation] mirrors
  /// the reply screen, which renders the title outside the InkWell.
  Future<void> pumpCard(
    WidgetTester tester,
    FeedViewPost post, {
    required bool disableNavigation,
  }) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: SingleChildScrollView(
              child: PostCard(
                post: post,
                sessionStamp: null,
                disableNavigation: disableNavigation,
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: postCardProviders(auth: FakeAuthProvider()),
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pump();
  }

  Finder insideQuoteCard(String text) => find.descendant(
    of: find.byType(BlueskyPostCard),
    matching: find.text(text),
  );

  for (final disableNavigation in [false, true]) {
    final config = disableNavigation ? 'navigation disabled' : 'navigable';

    group('PostCard sharing a Bluesky post ($config)', () {
      testWidgets('a title that repeats the quoted post is shown only once', (
        tester,
      ) async {
        await pumpCard(
          tester,
          blueskySharePost(
            title: _quotedText,
            embed: blueskyQuoteEmbed(text: _quotedText),
          ),
          disableNavigation: disableNavigation,
        );

        expect(find.byType(BlueskyPostCard), findsOneWidget);
        expect(insideQuoteCard(_quotedText), findsOneWidget);
        expect(
          find.text(_quotedText),
          findsOneWidget,
          reason: 'the duplicate title must not render outside the card',
        );
      });

      testWidgets('a title of its own is shown above the quoted post', (
        tester,
      ) async {
        await pumpCard(
          tester,
          blueskySharePost(
            title: _ownTitle,
            embed: blueskyQuoteEmbed(text: _quotedText),
          ),
          disableNavigation: disableNavigation,
        );

        expect(find.text(_ownTitle), findsOneWidget);
        expect(insideQuoteCard(_ownTitle), findsNothing);
        expect(insideQuoteCard(_quotedText), findsOneWidget);
      });

      testWidgets(
        'a hidden duplicate title leaves no gap above the quoted post',
        (tester) async {
          await pumpCard(
            tester,
            blueskySharePost(embed: blueskyQuoteEmbed(text: _quotedText)),
            disableNavigation: disableNavigation,
          );
          final untitledTop = tester
              .getTopLeft(find.byType(BlueskyPostCard))
              .dy;

          await pumpCard(
            tester,
            blueskySharePost(
              title: _quotedText,
              embed: blueskyQuoteEmbed(text: _quotedText),
            ),
            disableNavigation: disableNavigation,
          );

          expect(
            tester.getTopLeft(find.byType(BlueskyPostCard)).dy,
            untitledTop,
          );
        },
      );
    });
  }

  testWidgets('a concealed sensitive post keeps its duplicate title', (
    tester,
  ) async {
    await pumpCard(
      tester,
      blueskySharePost(
        title: _quotedText,
        embed: blueskyQuoteEmbed(text: _quotedText),
        sensitive: true,
      ),
      disableNavigation: false,
    );

    expect(find.byType(BlueskyPostCard), findsNothing);
    expect(find.text(_quotedText), findsOneWidget);
  });
}
