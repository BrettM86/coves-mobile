import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/services/streamable_service.dart';
import 'package:coves_flutter/widgets/bluesky_post_card.dart';
import 'package:coves_flutter/widgets/detailed_post_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers/bluesky_title_fixtures.dart';

const _bannerKey = Key('sensitive-content-banner');

const _quotedText = 'Breaking: the river flooded the old mill';
const _ownTitle = 'Worth reading before the vote';

void main() {
  Future<void> pumpDetail(WidgetTester tester, FeedViewPost post) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<StreamableService>.value(value: StreamableService()),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(child: DetailedPostView(post: post)),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder insideQuoteCard(String text) => find.descendant(
    of: find.byType(BlueskyPostCard),
    matching: find.text(text),
  );

  group('DetailedPostView sharing a Bluesky post', () {
    testWidgets('a title that repeats the quoted post is shown only once', (
      tester,
    ) async {
      await pumpDetail(
        tester,
        blueskySharePost(
          title: _quotedText,
          embed: blueskyQuoteEmbed(text: _quotedText),
        ),
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
      await pumpDetail(
        tester,
        blueskySharePost(
          title: _ownTitle,
          embed: blueskyQuoteEmbed(text: _quotedText),
        ),
      );

      expect(find.text(_ownTitle), findsOneWidget);
      expect(insideQuoteCard(_ownTitle), findsNothing);
      expect(insideQuoteCard(_quotedText), findsOneWidget);
    });

    testWidgets(
      'a sensitive post shows its duplicate title only while concealed',
      (tester) async {
        await pumpDetail(
          tester,
          blueskySharePost(
            title: _quotedText,
            embed: blueskyQuoteEmbed(text: _quotedText),
            sensitive: true,
          ),
        );

        expect(find.byType(BlueskyPostCard), findsNothing);
        expect(find.text(_quotedText), findsOneWidget);

        await tester.tap(find.byKey(_bannerKey));
        await tester.pump();

        expect(find.byType(BlueskyPostCard), findsOneWidget);
        expect(
          find.text(_quotedText),
          findsOneWidget,
          reason: 'once revealed, the text appears only inside the card',
        );
        expect(insideQuoteCard(_quotedText), findsOneWidget);

        await tester.tap(find.byKey(_bannerKey));
        await tester.pump();

        expect(find.byType(BlueskyPostCard), findsNothing);
        expect(find.text(_quotedText), findsOneWidget);
      },
    );
  });
}
