import 'package:coves_flutter/models/post.dart';
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
