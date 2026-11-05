import 'package:cached_network_image/cached_network_image.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/widgets/media/media_page_dots.dart';
import 'package:coves_flutter/widgets/media/native_image_embed.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Both native-image widgets index `images.first`. The invariant that makes
/// that safe lives in [ImagesPostEmbed], one layer up — these asserts pin it
/// at the widget boundary so a future caller that hand-rolls the list fails
/// loudly in debug instead of throwing a bare StateError out of `first`.
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  EmbedImage image() => const EmbedImage(
    thumb: 'https://cdn.test/thumb.jpg',
    fullsize: 'https://cdn.test/full.jpg',
  );

  group('empty-gallery guard', () {
    testWidgets('NativeImageThumb asserts on an empty image list', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const NativeImageThumb(images: [], keyPrefix: 'post')),
      );

      final error = tester.takeException();
      expect(error, isA<AssertionError>());
      expect(error.toString(), contains('ImagesPostEmbed'));
    });

    testWidgets('NativeImageGallery asserts on an empty image list', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          NativeImageGallery(
            images: const [],
            keyPrefix: 'detail',
            onOpen: (_) {},
          ),
        ),
      );

      final error = tester.takeException();
      expect(error, isA<AssertionError>());
      expect(error.toString(), contains('ImagesPostEmbed'));
    });

    testWidgets('a one-image list renders normally', (tester) async {
      await tester.pumpWidget(
        wrap(NativeImageThumb(images: [image()], keyPrefix: 'post')),
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        wrap(
          NativeImageGallery(
            images: [image()],
            keyPrefix: 'detail',
            onOpen: (_) {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a single image is shown whole, like a gallery page, even when '
      'its shape is outside the frame bounds', (tester) async {
    // A 1:3 portrait is taller than the feed's 3:4 limit, so the frame clips
    // its height; the image must fit inside rather than be cropped.
    await tester.pumpWidget(
      wrap(
        NativeImageThumb(
          images: [
            EmbedImage(
              thumb: 'https://cdn.test/tall.jpg',
              fullsize: 'https://cdn.test/tall-full.jpg',
              aspectRatio: EmbedAspectRatio(width: 1000, height: 3000),
            ),
          ],
          keyPrefix: 'post',
        ),
      ),
    );

    final rendered = tester.widget<CachedNetworkImage>(
      find.descendant(
        of: find.byKey(const Key('post-images-embed')),
        matching: find.byType(CachedNetworkImage),
      ),
    );
    expect(rendered.fit, BoxFit.contain);
  });

  group('B1g gallery page dots', () {
    const embedKey = Key('detail-images-embed');
    const indicatorKey = Key('detail-images-page-indicator');

    MediaPageDots dots(WidgetTester tester) {
      final finder = find.descendant(
        of: find.byKey(indicatorKey),
        matching: find.byType(MediaPageDots),
        matchRoot: true,
      );
      expect(finder, findsOneWidget, reason: 'the indicator holds the dots');
      return tester.widget<MediaPageDots>(finder);
    }

    Future<void> pumpGallery(
      WidgetTester tester, {
      required ValueChanged<int> onOpen,
    }) async {
      await tester.pumpWidget(
        wrap(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              child: NativeImageGallery(
                images: [
                  for (var i = 0; i < 3; i++)
                    EmbedImage(
                      thumb: 'https://cdn.test/t$i.jpg',
                      fullsize: 'https://cdn.test/f$i.jpg',
                    ),
                ],
                keyPrefix: 'detail',
                onOpen: onOpen,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('dots sit centred on the bottom of the gallery and follow a '
        'swipe', (tester) async {
      await pumpGallery(tester, onOpen: (_) {});

      expect(dots(tester).count, 3);
      expect(dots(tester).index, 0);
      expect(find.text('1/3'), findsNothing);

      final frame = tester.getRect(find.byKey(embedKey));
      final indicator = tester.getRect(find.byKey(indicatorKey));
      expect(
        frame.contains(indicator.topLeft) &&
            frame.contains(indicator.bottomRight - const Offset(1, 1)),
        isTrue,
        reason: 'the dots pill sits over the image so its backdrop shows',
      );
      expect(frame.bottom - indicator.bottom, inInclusiveRange(4, 16));
      expect(indicator.center.dx, closeTo(frame.center.dx, 1));

      // A tap on the pill still opens the gallery.
      var opened = -1;
      await pumpGallery(tester, onOpen: (index) => opened = index);
      await tester.tap(find.byKey(indicatorKey), warnIfMissed: false);
      expect(opened, 0);

      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await tester.pumpAndSettle();

      expect(dots(tester).index, 1);
      expect(find.text('2/3'), findsNothing);
    });
  });

  test('ImagesPostEmbed is the guarantor of the invariant', () {
    // The widgets' asserts are a debug backstop; the real enforcement is the
    // model constructor, which throws in release too.
    expect(
      () => ImagesPostEmbed(
        type: 'app.coves.embed.images',
        images: const [],
        data: const {},
      ),
      throwsArgumentError,
    );
  });
}
