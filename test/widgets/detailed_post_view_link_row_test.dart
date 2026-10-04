import 'package:cached_network_image/cached_network_image.dart';
import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/widgets/detailed_post_view.dart';
import 'package:coves_flutter/widgets/external_link_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../test_helpers/mock_url_launcher_platform.dart';

/// The link a tap opens.
const _linkUri = 'https://evil.example/login';

/// The author-declared domain, naming a different site than [_linkUri].
const _declaredDomain = 'paypal.com';

/// What the link row shows for [_linkUri]: host and path.
const _linkRowLabel = 'evil.example/login';

const _thumb1 = 'https://cdn.test/t1.jpg';
const _thumb2 = 'https://cdn.test/t2.jpg';

/// The external cards in the detail view carry their own link row under the
/// image or carousel. Its favicon must stand for the host the tap opens, not
/// the domain the record declares, or the card can show one site's icon and
/// open another. A row whose uri a tap cannot open is inert.
void main() {
  late MockUrlLauncherPlatform mockPlatform;

  setUp(() {
    mockPlatform = MockUrlLauncherPlatform();
    UrlLauncherPlatform.instance = mockPlatform;
  });

  /// A tall phone surface. DetailedPostView is an unbounded Column, so the
  /// harness scrolls it like the real SliverList in post_detail_screen.dart.
  void useDetailSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pumpDetail(WidgetTester tester, PostEmbed embed) async {
    useDetailSurface(tester);
    final post = FeedViewPost(
      post: PostView(
        uri: 'at://did:plc:author/social.coves.community.post/aaa',
        cid: 'cid-aaa',
        rkey: 'aaa',
        author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
        community: CommunityRef(
          did: 'did:plc:community',
          name: 'test-community',
        ),
        createdAt: DateTime(2024),
        indexedAt: DateTime(2024),
        record: const PostRecord(title: 'A linked post', content: 'Body text'),
        stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
        embed: embed,
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
  }

  /// Legacy `external#view` embed built through the real model parser.
  PostEmbed externalEmbed({
    String uri = _linkUri,
    String? thumb,
    List<Map<String, dynamic>>? images,
  }) {
    return PostEmbed.fromJson({
      r'$type': 'social.coves.embed.external#view',
      'external': {
        'uri': uri,
        'domain': _declaredDomain,
        'thumb': ?thumb,
        'images': ?images,
      },
    });
  }

  /// The favicon inside the link row that shows [_linkRowLabel], and nothing
  /// else on screen: the nearest Row around the label, then its images.
  Finder linkRowFavicon() {
    final linkRow = find
        .ancestor(of: find.text(_linkRowLabel), matching: find.byType(Row))
        .first;
    return find.descendant(
      of: linkRow,
      matching: find.byType(CachedNetworkImage),
    );
  }

  String requestedFaviconDomain(WidgetTester tester) {
    final imageUrl = tester
        .widget<CachedNetworkImage>(linkRowFavicon())
        .imageUrl;
    return Uri.parse(imageUrl).queryParameters['domain']!;
  }

  group('DetailedPostView link rows fetch the favicon for the uri host', () {
    testWidgets('the row under a single-image link card', (tester) async {
      await pumpDetail(tester, externalEmbed(thumb: _thumb1));

      expect(find.text(_linkRowLabel), findsOneWidget);
      expect(linkRowFavicon(), findsOneWidget);
      expect(requestedFaviconDomain(tester), 'evil.example');
    });

    testWidgets('the row under a multi-image carousel', (tester) async {
      await pumpDetail(
        tester,
        externalEmbed(
          images: [
            {'thumb': _thumb1},
            {'thumb': _thumb2},
          ],
        ),
      );

      expect(find.text(_linkRowLabel), findsOneWidget);
      expect(linkRowFavicon(), findsOneWidget);
      expect(requestedFaviconDomain(tester), 'evil.example');
    });
  });

  /// The two image cards under test, by the embed each needs for a [uri].
  final cards = <String, PostEmbed Function(String uri)>{
    'single-image link card': (uri) => externalEmbed(uri: uri, thumb: _thumb1),
    'multi-image carousel': (uri) => externalEmbed(
      uri: uri,
      images: [
        {'thumb': _thumb1},
        {'thumb': _thumb2},
      ],
    ),
  };

  /// A widget that would make a tap on the row do something.
  final tapHandler = find.byWidgetPredicate(
    (widget) =>
        widget is InkWell ||
        (widget is GestureDetector && widget.onTap != null),
  );

  group('DetailedPostView link rows still open a uri a tap can open', () {
    for (final MapEntry(key: card, value: embedFor) in cards.entries) {
      testWidgets('the row under a $card', (tester) async {
        await pumpDetail(tester, embedFor(_linkUri));

        final linkRow = find
            .ancestor(of: find.text(_linkRowLabel), matching: find.byType(Row))
            .first;
        expect(
          find.descendant(
            of: linkRow,
            matching: find.byIcon(Icons.open_in_new),
          ),
          findsOneWidget,
        );
        expect(
          find.ancestor(of: find.text(_linkRowLabel), matching: tapHandler),
          findsWidgets,
        );

        await tester.tap(find.text(_linkRowLabel));
        await tester.pumpAndSettle();

        expect(mockPlatform.launchedUrls, [_linkUri]);
      });
    }

    testWidgets('the images of a multi-image carousel', (tester) async {
      await pumpDetail(tester, cards['multi-image carousel']!(_linkUri));

      await tester.tap(find.byType(PageView));
      await tester.pumpAndSettle();

      expect(mockPlatform.launchedUrls, [_linkUri]);
    });
  });

  group('DetailedPostView link rows for a uri a tap cannot open are inert', () {
    /// The row's text for [label]: the image card's link row, not the
    /// ExternalLinkBar under the card, which can show the same text.
    Finder rowLabel(String label) => find.byElementPredicate(
      (element) =>
          element.widget is Text &&
          (element.widget as Text).data == label &&
          element.findAncestorWidgetOfExactType<ExternalLinkBar>() == null,
      description: 'link-row text "$label"',
    );

    // Each uri with the label its row shows: a hosted uri with a scheme a
    // tap refuses (shown as written, not as "paypal.com"), a hostless uri
    // (trimmed), and a blank one.
    const labels = <String, String>{
      'ftp://paypal.com/': 'ftp://paypal.com/',
      '  https:paypal.com  ': 'https:paypal.com',
      '': 'Invalid link',
    };

    for (final MapEntry(key: card, value: embedFor) in cards.entries) {
      for (final MapEntry(key: uri, value: label) in labels.entries) {
        testWidgets(
          'the row under a $card for "$uri" reads "$label", shows the generic '
          'link glyph, and has no arrow or tap target',
          (tester) async {
            final handle = tester.ensureSemantics();
            try {
              await pumpDetail(tester, embedFor(uri));

              expect(rowLabel(label), findsOneWidget);
              expect(find.text('paypal.com'), findsNothing);

              final linkRow = find
                  .ancestor(of: rowLabel(label), matching: find.byType(Row))
                  .first;
              expect(
                find.descendant(
                  of: linkRow,
                  matching: find.byType(CachedNetworkImage),
                ),
                findsNothing,
              );
              expect(
                find.descendant(of: linkRow, matching: find.byIcon(Icons.link)),
                findsOneWidget,
              );
              expect(
                find.descendant(
                  of: linkRow,
                  matching: find.byIcon(Icons.open_in_new),
                ),
                findsNothing,
              );
              expect(
                find.ancestor(of: rowLabel(label), matching: tapHandler),
                findsNothing,
              );

              expect(
                tester.getSemantics(rowLabel(label)),
                isSemantics(label: label, isButton: false, hasTapAction: false),
              );

              await tester.tap(rowLabel(label));
              await tester.pumpAndSettle();

              expect(mockPlatform.launchedUrls, isEmpty);
              expect(find.text('Invalid link format'), findsNothing);
            } finally {
              handle.dispose();
            }
          },
        );
      }
    }

    for (final uri in labels.keys) {
      testWidgets(
        'the images of a multi-image carousel for "$uri" have no tap target',
        (tester) async {
          await pumpDetail(tester, cards['multi-image carousel']!(uri));

          final carousel = find.byType(PageView);
          expect(
            find.ancestor(of: carousel, matching: tapHandler),
            findsNothing,
          );

          await tester.tap(carousel);
          await tester.pumpAndSettle();

          expect(mockPlatform.launchedUrls, isEmpty);
          expect(find.text('Invalid link format'), findsNothing);
        },
      );
    }
  });
}
