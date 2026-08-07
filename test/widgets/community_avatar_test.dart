import 'package:cached_network_image/cached_network_image.dart';
import 'package:coves_flutter/utils/display_utils.dart';
import 'package:coves_flutter/widgets/community_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Characterization tests for the canonical [CommunityAvatar].
///
/// Every hand-rolled community avatar in the app is being migrated onto this
/// widget, so these tests pin the contract the migrated call sites inherit:
/// the fallback glyph, the deterministic hash color, the shape variants and
/// the sizing of both the fallback and the network-image paths.
///
/// The NEW `fallbackIcon` parameter lives in
/// test/widgets/community_avatar_fallback_icon_test.dart — it references an
/// API that does not exist yet, so it is kept in its own file to avoid
/// compile-breaking the characterization suite.
void main() {
  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  /// Reads the background color painted behind [textFinder].
  ///
  /// Asserting on the nearest [DecoratedBox] rather than on a `Container`
  /// keeps this independent of whether the fallback is built with a
  /// Container, a DecoratedBox, or a ClipOval-wrapped box.
  Color paintedColorBehind(WidgetTester tester, Finder textFinder) {
    final decorated = tester.widget<DecoratedBox>(
      find.ancestor(of: textFinder, matching: find.byType(DecoratedBox)).first,
    );
    return (decorated.decoration as BoxDecoration).color!;
  }

  BoxDecoration decorationBehind(WidgetTester tester, Finder textFinder) {
    final decorated = tester.widget<DecoratedBox>(
      find.ancestor(of: textFinder, matching: find.byType(DecoratedBox)).first,
    );
    return decorated.decoration as BoxDecoration;
  }

  group('CommunityAvatar fallback', () {
    testWidgets('renders the first letter of the name, uppercased', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const CommunityAvatar(name: 'gaming', size: 40)),
      );

      expect(find.text('G'), findsOneWidget);
    });

    testWidgets('renders "?" when the name is empty', (tester) async {
      await tester.pumpWidget(wrap(const CommunityAvatar(name: '', size: 40)));

      expect(find.text('?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('uses the deterministic hash color from DisplayUtils', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const CommunityAvatar(name: 'gaming', size: 40)),
      );

      expect(
        paintedColorBehind(tester, find.text('G')).toARGB32(),
        DisplayUtils.getFallbackColor('gaming').toARGB32(),
      );
    });

    testWidgets('the same name always yields the same color', (tester) async {
      await tester.pumpWidget(
        wrap(
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CommunityAvatar(name: 'gaming', size: 40),
              CommunityAvatar(name: 'gaming', size: 24),
            ],
          ),
        ),
      );

      final colors = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((d) => (d.decoration as BoxDecoration).color?.toARGB32())
          .whereType<int>()
          .toSet();

      expect(colors, hasLength(1));
    });

    testWidgets('applies fallbackColorAlpha to the background', (tester) async {
      await tester.pumpWidget(
        wrap(
          const CommunityAvatar(
            name: 'gaming',
            size: 40,
            fallbackColorAlpha: 0.2,
          ),
        ),
      );

      expect(paintedColorBehind(tester, find.text('G')).a, closeTo(0.2, 0.01));
    });

    testWidgets('fills exactly size x size', (tester) async {
      await tester.pumpWidget(
        wrap(const CommunityAvatar(name: 'gaming', size: 40)),
      );

      expect(
        tester.getSize(
          find.ancestor(
            of: find.text('G'),
            matching: find.byType(DecoratedBox),
          ).first,
        ),
        const Size(40, 40),
      );
    });

    testWidgets('circle shape paints a circular box', (tester) async {
      await tester.pumpWidget(
        wrap(const CommunityAvatar(name: 'gaming', size: 40)),
      );

      expect(decorationBehind(tester, find.text('G')).shape, BoxShape.circle);
    });

    testWidgets('roundedRect shape paints a rounded rectangle', (tester) async {
      await tester.pumpWidget(
        wrap(
          const CommunityAvatar(
            name: 'gaming',
            size: 40,
            shape: CommunityAvatarShape.roundedRect,
            borderRadius: 8,
          ),
        ),
      );

      final decoration = decorationBehind(tester, find.text('G'));
      expect(decoration.shape, BoxShape.rectangle);
      expect(decoration.borderRadius, BorderRadius.circular(8));
    });

    testWidgets('an empty avatarUrl is treated as no avatar', (tester) async {
      await tester.pumpWidget(
        wrap(const CommunityAvatar(name: 'gaming', size: 40, avatarUrl: '')),
      );

      expect(find.text('G'), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });
  });

  group('CommunityAvatar image', () {
    testWidgets('requests the image at the avatar size', (tester) async {
      await tester.pumpWidget(
        wrap(
          const CommunityAvatar(
            name: 'gaming',
            size: 40,
            avatarUrl: 'https://example.com/a.jpg',
          ),
        ),
      );

      final image = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      expect(image.imageUrl, 'https://example.com/a.jpg');
      expect(image.width, 40);
      expect(image.height, 40);
    });

    for (final shape in CommunityAvatarShape.values) {
      testWidgets('$shape loads without a fade, like UserAvatar', (
        tester,
      ) async {
        // The fade is what makes avatars flicker as list rows recycle during
        // a scroll; both shapes must opt out of it, not just the circle.
        await tester.pumpWidget(
          wrap(
            CommunityAvatar(
              name: 'gaming',
              size: 40,
              shape: shape,
              avatarUrl: 'https://example.com/a.jpg',
            ),
          ),
        );

        final image = tester.widget<CachedNetworkImage>(
          find.byType(CachedNetworkImage),
        );
        expect(image.fadeInDuration, Duration.zero);
        expect(image.fadeOutDuration, Duration.zero);
      });
    }
  });
}
