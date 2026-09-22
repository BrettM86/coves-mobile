import 'package:cached_network_image/cached_network_image.dart';
import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/bluesky_post.dart';
import 'package:coves_flutter/widgets/bluesky_post_card.dart';
import 'package:coves_flutter/widgets/image_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../test_helpers/mock_url_launcher_platform.dart';

const imagesEmbedKey = Key('bluesky-images-embed');
const imagesCountBadgeKey = Key('bluesky-images-count-badge');
const quoteImagesEmbedKey = Key('bluesky-quote-images-embed');
const imageViewerKey = Key('image-viewer');

/// The clamp bounds the feed applies to an image's intrinsic ratio.
const widestRatio = 16 / 9;
const tallestRatio = 3 / 4;

/// Parent gallery URLs. The quote gallery uses different paths so a card that
/// renders the wrong gallery is detectable.
const parentThumb1 =
    'https://cdn.bsky.app/img/feed_thumbnail/plain/did:plc:parent/bafyparent1@jpeg';
const parentFullsize1 =
    'https://cdn.bsky.app/img/feed_fullsize/plain/did:plc:parent/bafyparent1@jpeg';
const parentThumb2 =
    'https://cdn.bsky.app/img/feed_thumbnail/plain/did:plc:parent/bafyparent2@jpeg';
const parentFullsize2 =
    'https://cdn.bsky.app/img/feed_fullsize/plain/did:plc:parent/bafyparent2@jpeg';

/// Quote gallery URLs, under a different DID than the parent's so a card that
/// renders the parent's gallery inside the quote is detectable.
const quoteThumb1 =
    'https://cdn.bsky.app/img/feed_thumbnail/plain/did:plc:quoted/bafyquote1@jpeg';
const quoteFullsize1 =
    'https://cdn.bsky.app/img/feed_fullsize/plain/did:plc:quoted/bafyquote1@jpeg';
const quoteThumb2 =
    'https://cdn.bsky.app/img/feed_thumbnail/plain/did:plc:quoted/bafyquote2@jpeg';
const quoteFullsize2 =
    'https://cdn.bsky.app/img/feed_fullsize/plain/did:plc:quoted/bafyquote2@jpeg';

const postText = 'Look at these cats';
const authorHandle = 'images.bsky.social';
const quoteText = 'Quoted cats';
const quoteAuthorHandle = 'quoted.bsky.social';

/// One entry of the backend `images` array (coves e92395d). `alt` and
/// `aspectRatio` are omitted from the map when not supplied, matching the
/// wire shape where those keys can be absent.
Map<String, dynamic> blueskyImageJson({
  required String thumb,
  required String fullsize,
  String? alt,
  int? aspectWidth,
  int? aspectHeight,
}) {
  return <String, dynamic>{
    'thumb': thumb,
    'fullsize': fullsize,
    'alt': ?alt,
    if (aspectWidth != null && aspectHeight != null)
      'aspectRatio': <String, dynamic>{
        'width': aspectWidth,
        'height': aspectHeight,
      },
  };
}

/// A resolved parent post carrying an image gallery. A null [images] omits the
/// `images` key entirely, which is what the backend sends for video posts and
/// for posts with no media.
Map<String, dynamic> blueskyImagesJson({
  List<Map<String, dynamic>>? images,
  bool hasMedia = true,
  int? mediaCount,
  Map<String, dynamic>? quotedPost,
}) {
  return <String, dynamic>{
    'post': <String, dynamic>{
      'uri': 'at://did:plc:parent/app.bsky.feed.post/p1',
      'cid': 'bafyparentcid',
    },
    'resolved': <String, dynamic>{
      'uri': 'at://did:plc:parent/app.bsky.feed.post/p1',
      'cid': 'bafyparentcid',
      'text': postText,
      'createdAt': '2026-09-01T12:00:00Z',
      'author': <String, dynamic>{
        'did': 'did:plc:parent',
        'handle': authorHandle,
      },
      'replyCount': 0,
      'repostCount': 0,
      'likeCount': 0,
      'hasMedia': hasMedia,
      'mediaCount': mediaCount ?? images?.length ?? 0,
      'unavailable': false,
      'images': ?images,
      'quotedPost': ?quotedPost,
    },
  };
}

/// A resolved quoted post carrying its own image gallery, for the `quotedPost`
/// slot of [blueskyImagesJson].
Map<String, dynamic> blueskyQuotedPostJson({
  List<Map<String, dynamic>>? images,
  bool hasMedia = true,
  int? mediaCount,
}) {
  return <String, dynamic>{
    'uri': 'at://did:plc:quoted/app.bsky.feed.post/q1',
    'cid': 'bafyquotedcid',
    'text': quoteText,
    'createdAt': '2026-09-01T11:00:00Z',
    'author': <String, dynamic>{
      'did': 'did:plc:quoted',
      'handle': quoteAuthorHandle,
    },
    'replyCount': 0,
    'repostCount': 0,
    'likeCount': 0,
    'hasMedia': hasMedia,
    'mediaCount': mediaCount ?? images?.length ?? 0,
    'unavailable': false,
    'images': ?images,
  };
}

/// Scopes a finder to the widget subtree under [blockKey], so an assertion
/// about the parent gallery cannot be satisfied by the quote gallery.
Finder inBlock(Key blockKey, Finder matching) {
  return find.descendant(
    of: find.byKey(blockKey),
    matching: matching,
    matchRoot: true,
  );
}

/// The aspect ratio the block under [blockKey] actually renders at.
double renderedAspectRatio(WidgetTester tester, Key blockKey) {
  final finder = inBlock(blockKey, find.byType(AspectRatio));
  expect(
    finder,
    findsWidgets,
    reason: 'media block $blockKey should size itself with an AspectRatio',
  );
  return tester.widget<AspectRatio>(finder.first).aspectRatio;
}

/// Labels of every semantics node flagged as an image at or below the node
/// that owns the block under [blockKey].
List<String> imageSemanticsLabelsUnder(WidgetTester tester, Key blockKey) {
  final labels = <String>[];
  void visit(SemanticsNode node) {
    if (node.getSemanticsData().flagsCollection.isImage) {
      labels.add(node.label);
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(tester.getSemantics(find.byKey(blockKey)));
  return labels;
}

/// Gives the card a phone-sized surface. The default 800x600 test view is too
/// short for a full-width media block plus header, text and action bar.
void useMediaSizedSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget blueskyCardHarness(BlueskyPostEmbed embed) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      body: SingleChildScrollView(
        child: BlueskyPostCard(
          embed: embed,
          currentTime: DateTime.parse('2026-09-02T12:00:00Z'),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BlueskyPostCard with an unavailable quoted post', () {
    testWidgets(
      'renders the available parent post and the deleted quote message',
      (tester) async {
        // Backend wire shape: the parent resolves fine, but its quoted post
        // was deleted, so it arrives with unavailable/message and no author.
        final embed = BlueskyPostEmbed.fromJson(<String, dynamic>{
          'post': <String, dynamic>{
            'uri': 'at://did:plc:parent/app.bsky.feed.post/p1',
            'cid': 'bafyparentcid',
          },
          'resolved': <String, dynamic>{
            'uri': 'at://did:plc:parent/app.bsky.feed.post/p1',
            'cid': 'bafyparentcid',
            'text': 'Parent post text',
            'createdAt': '2026-09-01T12:00:00Z',
            'author': <String, dynamic>{
              'did': 'did:plc:parent',
              'handle': 'parent.bsky.social',
            },
            'replyCount': 0,
            'repostCount': 0,
            'likeCount': 0,
            'mediaCount': 0,
            'hasMedia': false,
            'unavailable': false,
            'quotedPost': <String, dynamic>{
              'uri': 'at://did:plc:quoted/app.bsky.feed.post/q1',
              'cid': '',
              'text': '',
              'createdAt': '0001-01-01T00:00:00Z',
              'replyCount': 0,
              'repostCount': 0,
              'likeCount': 0,
              'mediaCount': 0,
              'hasMedia': false,
              'unavailable': true,
              'message': 'This post has been deleted',
            },
          },
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(
              body: SingleChildScrollView(
                child: BlueskyPostCard(
                  embed: embed,
                  currentTime: DateTime.parse('2026-09-02T12:00:00Z'),
                ),
              ),
            ),
          ),
        );

        expect(find.text('Parent post text'), findsOneWidget);
        expect(find.text('@parent.bsky.social'), findsOneWidget);
        expect(find.text('This post has been deleted'), findsOneWidget);
        expect(
          find.text('Post not found, it may have been deleted.'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('renders the fallback message when the quote has no message', (
      tester,
    ) async {
      final embed = BlueskyPostEmbed.fromJson(<String, dynamic>{
        'post': <String, dynamic>{
          'uri': 'at://did:plc:parent/app.bsky.feed.post/p1',
          'cid': 'bafyparentcid',
        },
        'resolved': <String, dynamic>{
          'uri': 'at://did:plc:parent/app.bsky.feed.post/p1',
          'cid': 'bafyparentcid',
          'text': 'Parent post text',
          'createdAt': '2026-09-01T12:00:00Z',
          'author': <String, dynamic>{
            'did': 'did:plc:parent',
            'handle': 'parent.bsky.social',
          },
          'replyCount': 0,
          'repostCount': 0,
          'likeCount': 0,
          'mediaCount': 0,
          'hasMedia': false,
          'unavailable': false,
          'quotedPost': <String, dynamic>{
            'uri': 'at://did:plc:quoted/app.bsky.feed.post/q1',
            'cid': '',
            'text': '',
            'createdAt': '0001-01-01T00:00:00Z',
            'replyCount': 0,
            'repostCount': 0,
            'likeCount': 0,
            'mediaCount': 0,
            'hasMedia': false,
            'unavailable': true,
          },
        },
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(
              child: BlueskyPostCard(
                embed: embed,
                currentTime: DateTime.parse('2026-09-02T12:00:00Z'),
              ),
            ),
          ),
        ),
      );

      // The parent renders, and only the quote box falls back to the generic
      // message — not the whole-embed unavailable card.
      expect(find.text('Parent post text'), findsOneWidget);
      expect(find.text('@parent.bsky.social'), findsOneWidget);
      expect(
        find.text('Post not found, it may have been deleted.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('BlueskyPostCard with an unavailable top-level post', () {
    testWidgets('renders the unavailable card when the post has no author', (
      tester,
    ) async {
      final embed = BlueskyPostEmbed.fromJson(<String, dynamic>{
        'post': <String, dynamic>{
          'uri': 'at://did:plc:parent/app.bsky.feed.post/p1',
          'cid': 'bafyparentcid',
        },
        'resolved': <String, dynamic>{
          'uri': 'at://did:plc:parent/app.bsky.feed.post/p1',
          'cid': '',
          'text': '',
          'createdAt': '0001-01-01T00:00:00Z',
          'replyCount': 0,
          'repostCount': 0,
          'likeCount': 0,
          'mediaCount': 0,
          'hasMedia': false,
          'unavailable': true,
          'message': 'This post has been deleted',
        },
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(child: BlueskyPostCard(embed: embed)),
          ),
        ),
      );

      expect(
        find.text('Post not found, it may have been deleted.'),
        findsOneWidget,
      );
      expect(find.text('likes'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Text && (widget.data ?? '').startsWith('@'),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('images', () {
    testWidgets('renders the first image of a two-image gallery instead of the '
        'media placeholder', (tester) async {
      useMediaSizedSurface(tester);

      final embed = BlueskyPostEmbed.fromJson(
        blueskyImagesJson(
          images: [
            blueskyImageJson(
              thumb: parentThumb1,
              fullsize: parentFullsize1,
              alt: 'A cat',
              aspectWidth: 1200,
              aspectHeight: 900,
            ),
            blueskyImageJson(thumb: parentThumb2, fullsize: parentFullsize2),
          ],
        ),
      );

      await tester.pumpWidget(blueskyCardHarness(embed));
      // Single pump: CachedNetworkImage never settles in tests.
      await tester.pump();

      expect(find.byKey(imagesEmbedKey), findsOneWidget);

      final imageFinder = inBlock(
        imagesEmbedKey,
        find.byType(CachedNetworkImage),
      );
      expect(imageFinder, findsOneWidget);
      expect(
        tester.widget<CachedNetworkImage>(imageFinder).imageUrl,
        parentThumb1,
        reason: 'only the FIRST image renders on the card',
      );

      expect(inBlock(imagesCountBadgeKey, find.text('1/2')), findsOneWidget);

      expect(find.text(postText), findsOneWidget);
      expect(find.text('@$authorHandle'), findsOneWidget);

      expect(
        find.textContaining('Contains'),
        findsNothing,
        reason: 'the gallery replaces the media placeholder',
      );
      expect(tester.takeException(), isNull);
    });

    /// Pumps a single-image card, letting each test vary only the image.
    Future<void> pumpSingleImage(
      WidgetTester tester, {
      String? alt,
      int? aspectWidth,
      int? aspectHeight,
    }) async {
      final embed = BlueskyPostEmbed.fromJson(
        blueskyImagesJson(
          images: [
            blueskyImageJson(
              thumb: parentThumb1,
              fullsize: parentFullsize1,
              alt: alt,
              aspectWidth: aspectWidth,
              aspectHeight: aspectHeight,
            ),
          ],
        ),
      );

      await tester.pumpWidget(blueskyCardHarness(embed));
      await tester.pump();
    }

    testWidgets('honours an in-range aspect ratio', (tester) async {
      useMediaSizedSurface(tester);

      await pumpSingleImage(tester, aspectWidth: 1200, aspectHeight: 900);

      expect(renderedAspectRatio(tester, imagesEmbedKey), closeTo(4 / 3, 0.01));
    });

    testWidgets('uses 16:9 when aspectRatio is absent', (tester) async {
      useMediaSizedSurface(tester);

      await pumpSingleImage(tester);

      expect(
        renderedAspectRatio(tester, imagesEmbedKey),
        closeTo(widestRatio, 0.01),
      );
    });

    testWidgets('clamps a very tall image to 3:4', (tester) async {
      useMediaSizedSurface(tester);

      await pumpSingleImage(tester, aspectWidth: 300, aspectHeight: 900);

      expect(
        renderedAspectRatio(tester, imagesEmbedKey),
        closeTo(tallestRatio, 0.01),
      );
    });

    testWidgets('clamps a very wide image to 16:9', (tester) async {
      useMediaSizedSurface(tester);

      await pumpSingleImage(tester, aspectWidth: 3000, aspectHeight: 900);

      expect(
        renderedAspectRatio(tester, imagesEmbedKey),
        closeTo(widestRatio, 0.01),
      );
    });

    testWidgets('exposes alt text as image semantics', (tester) async {
      useMediaSizedSurface(tester);
      final handle = tester.ensureSemantics();

      await pumpSingleImage(tester, alt: 'A cat');

      expect(
        inBlock(imagesEmbedKey, find.bySemanticsLabel('A cat')),
        findsOneWidget,
        reason: 'alt text must reach the semantics tree for screen readers',
      );
      expect(imageSemanticsLabelsUnder(tester, imagesEmbedKey), <String>[
        'A cat',
      ]);
      handle.dispose();
    });

    testWidgets('omits image semantics when alt is absent', (tester) async {
      useMediaSizedSurface(tester);
      final handle = tester.ensureSemantics();

      await pumpSingleImage(tester);

      expect(find.byKey(imagesEmbedKey), findsOneWidget);
      expect(find.bySemanticsLabel('A cat'), findsNothing);
      expect(
        imageSemanticsLabelsUnder(tester, imagesEmbedKey),
        isEmpty,
        reason: 'an image with no alt exposes no image node to announce',
      );
      handle.dispose();
    });

    testWidgets('omits the count badge for a single image', (tester) async {
      useMediaSizedSurface(tester);

      await pumpSingleImage(tester);

      expect(find.byKey(imagesEmbedKey), findsOneWidget);
      expect(find.byKey(imagesCountBadgeKey), findsNothing);
      expect(find.text('1/1'), findsNothing);
    });

    group('taps', () {
      late MockUrlLauncherPlatform mockPlatform;

      setUp(() {
        mockPlatform = MockUrlLauncherPlatform();
        UrlLauncherPlatform.instance = mockPlatform;
      });

      /// Pumps a card whose parent post carries the two-image parent gallery.
      Future<void> pumpTwoImageCard(WidgetTester tester) async {
        final embed = BlueskyPostEmbed.fromJson(
          blueskyImagesJson(
            images: [
              blueskyImageJson(
                thumb: parentThumb1,
                fullsize: parentFullsize1,
                alt: 'A cat',
                aspectWidth: 1200,
                aspectHeight: 900,
              ),
              blueskyImageJson(thumb: parentThumb2, fullsize: parentFullsize2),
            ],
          ),
        );

        await tester.pumpWidget(blueskyCardHarness(embed));
        await tester.pump();
      }

      testWidgets('tapping the image block opens the viewer on the gallery', (
        tester,
      ) async {
        useMediaSizedSurface(tester);

        await pumpTwoImageCard(tester);

        await tester.tap(find.byKey(imagesEmbedKey));
        await tester.pumpAndSettle();

        expect(
          find.byKey(imageViewerKey),
          findsOneWidget,
          reason: 'an image tap opens the viewer, not bsky.app in a browser',
        );

        final viewer = tester.widget<ImageViewer>(find.byType(ImageViewer));
        expect(viewer.images.map((image) => image.fullsize).toList(), <String>[
          parentFullsize1,
          parentFullsize2,
        ], reason: 'the viewer gets the whole parent gallery, in wire order');

        expect(
          mockPlatform.launchedUrls,
          isEmpty,
          reason: 'the image tap must not also launch the post URL',
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('tapping the post text launches the post URL', (
        tester,
      ) async {
        useMediaSizedSurface(tester);

        await pumpTwoImageCard(tester);

        await tester.tap(find.text(postText));
        await tester.pumpAndSettle();

        expect(mockPlatform.launchedUrls, hasLength(1));
        expect(mockPlatform.launchedUrls.single, contains('bsky.app'));
        expect(
          mockPlatform.launchedUrls.single,
          contains('/post/p1'),
          reason: 'the launched URL points at this post, not the profile',
        );
        expect(
          find.byKey(imageViewerKey),
          findsNothing,
          reason: 'a text tap leaves the app, it does not open the viewer',
        );
        expect(tester.takeException(), isNull);
      });
    });

    group('quoted post', () {
      late MockUrlLauncherPlatform mockPlatform;

      setUp(() {
        mockPlatform = MockUrlLauncherPlatform();
        UrlLauncherPlatform.instance = mockPlatform;
      });

      /// Pumps a card whose parent has NO images and whose quoted post carries
      /// the two-image quote gallery, so anything rendering the parent's
      /// gallery in the quote's place shows up as a wrong URL.
      Future<void> pumpQuotedImageCard(WidgetTester tester) async {
        final embed = BlueskyPostEmbed.fromJson(
          blueskyImagesJson(
            hasMedia: false,
            quotedPost: blueskyQuotedPostJson(
              images: [
                blueskyImageJson(
                  thumb: quoteThumb1,
                  fullsize: quoteFullsize1,
                  alt: 'A quoted cat',
                  aspectWidth: 1200,
                  aspectHeight: 900,
                ),
                blueskyImageJson(thumb: quoteThumb2, fullsize: quoteFullsize2),
              ],
            ),
          ),
        );

        await tester.pumpWidget(blueskyCardHarness(embed));
        await tester.pump();
      }

      testWidgets('renders the quote gallery instead of the placeholder', (
        tester,
      ) async {
        useMediaSizedSurface(tester);

        await pumpQuotedImageCard(tester);

        expect(find.byKey(quoteImagesEmbedKey), findsOneWidget);

        final imageFinder = inBlock(
          quoteImagesEmbedKey,
          find.byType(CachedNetworkImage),
        );
        expect(imageFinder, findsOneWidget);
        expect(
          tester.widget<CachedNetworkImage>(imageFinder).imageUrl,
          quoteThumb1,
          reason: "the quote shows the QUOTE's first thumb",
        );

        expect(find.text('1/2'), findsOneWidget);

        expect(find.text(quoteText), findsOneWidget);
        expect(
          find.textContaining('Contains'),
          findsNothing,
          reason: 'the quote gallery replaces the media placeholder',
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('tapping the quote gallery opens the viewer on the quote', (
        tester,
      ) async {
        useMediaSizedSurface(tester);

        await pumpQuotedImageCard(tester);

        expect(find.byKey(quoteImagesEmbedKey), findsOneWidget);
        await tester.ensureVisible(find.byKey(quoteImagesEmbedKey));
        await tester.pump();
        await tester.tap(find.byKey(quoteImagesEmbedKey));
        await tester.pumpAndSettle();

        expect(find.byKey(imageViewerKey), findsOneWidget);

        final viewer = tester.widget<ImageViewer>(find.byType(ImageViewer));
        expect(viewer.images.map((image) => image.fullsize).toList(), <String>[
          quoteFullsize1,
          quoteFullsize2,
        ], reason: "the viewer gets the QUOTE's gallery, not the parent's");

        expect(
          mockPlatform.launchedUrls,
          isEmpty,
          reason: 'the image tap must not also launch the quote URL',
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('a parent and a quote gallery each render and open their '
          'own images', (tester) async {
        useMediaSizedSurface(tester);

        final embed = BlueskyPostEmbed.fromJson(
          blueskyImagesJson(
            images: [
              blueskyImageJson(
                thumb: parentThumb1,
                fullsize: parentFullsize1,
                aspectWidth: 1200,
                aspectHeight: 900,
              ),
              blueskyImageJson(thumb: parentThumb2, fullsize: parentFullsize2),
            ],
            quotedPost: blueskyQuotedPostJson(
              images: [
                blueskyImageJson(thumb: quoteThumb1, fullsize: quoteFullsize1),
              ],
            ),
          ),
        );

        await tester.pumpWidget(blueskyCardHarness(embed));
        await tester.pump();

        final parentImage = inBlock(
          imagesEmbedKey,
          find.byType(CachedNetworkImage),
        );
        expect(parentImage, findsOneWidget);
        expect(
          tester.widget<CachedNetworkImage>(parentImage).imageUrl,
          parentThumb1,
        );
        final quoteImage = inBlock(
          quoteImagesEmbedKey,
          find.byType(CachedNetworkImage),
        );
        expect(quoteImage, findsOneWidget);
        expect(
          tester.widget<CachedNetworkImage>(quoteImage).imageUrl,
          quoteThumb1,
        );
        expect(inBlock(imagesCountBadgeKey, find.text('1/2')), findsOneWidget);

        await tester.ensureVisible(find.byKey(quoteImagesEmbedKey));
        await tester.pump();
        await tester.tap(find.byKey(quoteImagesEmbedKey));
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<ImageViewer>(find.byType(ImageViewer))
              .images
              .map((image) => image.fullsize)
              .toList(),
          <String>[quoteFullsize1],
          reason: "the quote tap opens the QUOTE's gallery",
        );
        expect(mockPlatform.launchedUrls, isEmpty);

        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(find.byKey(imageViewerKey), findsNothing);

        await tester.ensureVisible(find.byKey(imagesEmbedKey));
        await tester.pump();
        await tester.tap(find.byKey(imagesEmbedKey));
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<ImageViewer>(find.byType(ImageViewer))
              .images
              .map((image) => image.fullsize)
              .toList(),
          <String>[parentFullsize1, parentFullsize2],
          reason: "the parent tap opens the PARENT's gallery",
        );
        expect(mockPlatform.launchedUrls, isEmpty);
        expect(tester.takeException(), isNull);
      });

      testWidgets('tapping the quote text launches the quote URL', (
        tester,
      ) async {
        useMediaSizedSurface(tester);

        await pumpQuotedImageCard(tester);

        await tester.ensureVisible(find.text(quoteText));
        await tester.pump();
        await tester.tap(find.text(quoteText));
        await tester.pumpAndSettle();

        expect(mockPlatform.launchedUrls, hasLength(1));
        expect(
          mockPlatform.launchedUrls.single,
          contains('/post/q1'),
          reason: 'the quote text opens the QUOTED post, not the parent',
        );
        expect(find.byKey(imageViewerKey), findsNothing);
        expect(tester.takeException(), isNull);
      });
    });

    group('media placeholder', () {
      testWidgets('a media post with no images says it contains media', (
        tester,
      ) async {
        useMediaSizedSurface(tester);

        // Video posts, and image posts served from a legacy backend cache,
        // arrive with hasMedia/mediaCount but no `images` key, so the wording
        // stays neutral about the kind of media.
        final embed = BlueskyPostEmbed.fromJson(
          blueskyImagesJson(mediaCount: 1),
        );

        await tester.pumpWidget(blueskyCardHarness(embed));
        await tester.pump();

        expect(find.text('Contains media'), findsOneWidget);
        expect(find.textContaining('Contains a video'), findsNothing);
        expect(find.text('Contains 1 image'), findsNothing);
        expect(find.byKey(imagesEmbedKey), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a quoted media post with no images says it contains media', (
        tester,
      ) async {
        useMediaSizedSurface(tester);

        final embed = BlueskyPostEmbed.fromJson(
          blueskyImagesJson(
            hasMedia: false,
            quotedPost: blueskyQuotedPostJson(mediaCount: 1),
          ),
        );

        await tester.pumpWidget(blueskyCardHarness(embed));
        await tester.pump();

        expect(
          find.text('Contains media'),
          findsOneWidget,
          reason: 'only the quote has media, so the wording appears once',
        );
        expect(find.textContaining('Contains a video'), findsNothing);
        expect(find.text('Contains 1 image'), findsNothing);
        expect(find.byKey(quoteImagesEmbedKey), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a post with no media shows neither block nor placeholder', (
        tester,
      ) async {
        useMediaSizedSurface(tester);

        final embed = BlueskyPostEmbed.fromJson(
          blueskyImagesJson(hasMedia: false),
        );

        await tester.pumpWidget(blueskyCardHarness(embed));
        await tester.pump();

        expect(find.byKey(imagesEmbedKey), findsNothing);
        expect(find.textContaining('Contains'), findsNothing);
        expect(find.text(postText), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('images render even when hasMedia is false', (tester) async {
        useMediaSizedSurface(tester);

        final embed = BlueskyPostEmbed.fromJson(
          blueskyImagesJson(
            hasMedia: false,
            mediaCount: 0,
            images: [
              blueskyImageJson(thumb: parentThumb1, fullsize: parentFullsize1),
            ],
          ),
        );

        await tester.pumpWidget(blueskyCardHarness(embed));
        await tester.pump();

        final imageFinder = inBlock(
          imagesEmbedKey,
          find.byType(CachedNetworkImage),
        );
        expect(imageFinder, findsOneWidget);
        expect(
          tester.widget<CachedNetworkImage>(imageFinder).imageUrl,
          parentThumb1,
        );
        expect(find.textContaining('Contains'), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('quote images render even when the quote hasMedia is false', (
        tester,
      ) async {
        useMediaSizedSurface(tester);

        final embed = BlueskyPostEmbed.fromJson(
          blueskyImagesJson(
            hasMedia: false,
            quotedPost: blueskyQuotedPostJson(
              hasMedia: false,
              mediaCount: 0,
              images: [
                blueskyImageJson(thumb: quoteThumb1, fullsize: quoteFullsize1),
              ],
            ),
          ),
        );

        await tester.pumpWidget(blueskyCardHarness(embed));
        await tester.pump();

        final imageFinder = inBlock(
          quoteImagesEmbedKey,
          find.byType(CachedNetworkImage),
        );
        expect(imageFinder, findsOneWidget);
        expect(
          tester.widget<CachedNetworkImage>(imageFinder).imageUrl,
          quoteThumb1,
        );
        expect(find.textContaining('Contains'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    });
  });
}
