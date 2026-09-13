import 'package:cached_network_image/cached_network_image.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/widgets/icons/lucide_icon_painter.dart';
import 'package:coves_flutter/widgets/icons/lucide_paths.dart';
import 'package:coves_flutter/widgets/media/media_aspect.dart';
import 'package:coves_flutter/widgets/sensitive_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/theme_pump.dart';

const _bannerKey = Key('sensitive-content-banner');
const _placeholderKey = Key('sensitive-image-placeholder');

const _thumb = 'https://cdn.test/nsfw-thumb.jpg';
const _fullsize = 'https://cdn.test/nsfw-fullsize.jpg';
const _alt = 'A photograph the author marked as sensitive';

/// A 1:3 portrait: far taller than the feed's 3:4 floor, so the clamp
/// visibly changes the ratio and the test cannot pass by echoing the record.
EmbedImage sensitiveImage() {
  return EmbedImage(
    thumb: _thumb,
    fullsize: _fullsize,
    alt: _alt,
    aspectRatio: EmbedAspectRatio(width: 1, height: 3),
  );
}

/// Every semantics node in the pumped tree that a screen reader could
/// activate, in traversal order.
///
/// A control is only reachable if the node carrying its label is also the
/// node carrying the tap, so the labels of the activatable nodes are the
/// whole story.
List<String> activatableLabels(WidgetTester tester, Finder anyNode) {
  var root = tester.getSemantics(anyNode);
  while (root.parent != null) {
    root = root.parent!;
  }

  final labels = <String>[];
  void visit(SemanticsNode node) {
    if (node.getSemanticsData().hasAction(SemanticsAction.tap)) {
      labels.add(node.label);
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(root);
  return labels;
}

/// Fires the screen-reader activation gesture on the node [finder] locates.
void activateBySemantics(WidgetTester tester, Finder finder) {
  final node = tester.getSemantics(finder);
  node.owner!.performAction(node.id, SemanticsAction.tap);
}

void main() {
  group('SensitiveContentBanner', () {
    Future<void> pumpBanner(
      WidgetTester tester, {
      required bool concealed,
      VoidCallback? onToggle,
    }) {
      return pumpUnderAppTheme(
        tester,
        SensitiveContentBanner(
          concealed: concealed,
          onToggle: onToggle ?? () {},
        ),
      );
    }

    testWidgets('carries the key the post widgets find it by', (tester) async {
      await pumpBanner(tester, concealed: true);

      expect(find.byKey(_bannerKey), findsOneWidget);
    });

    testWidgets('offers to show the content while concealed', (tester) async {
      await pumpBanner(tester, concealed: true);

      expect(find.text('NSFW Content'), findsOneWidget);
      expect(find.text('Show'), findsOneWidget);
    });

    testWidgets('offers to hide the content once revealed', (tester) async {
      await pumpBanner(tester, concealed: false);

      expect(
        find.text('NSFW Content'),
        findsOneWidget,
        reason: 'the label stays so a revealed post is still marked',
      );
      expect(find.text('Hide'), findsOneWidget);
      expect(find.text('Show'), findsNothing);
    });

    testWidgets('announces a Show sensitive content button while concealed', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();

      await pumpBanner(tester, concealed: true);

      expect(
        tester.getSemantics(find.bySemanticsLabel('Show sensitive content')),
        isSemantics(
          isButton: true,
          label: 'Show sensitive content',
          hasTapAction: true,
        ),
        reason:
            'the child text must not merge into the wrapper, or the label '
            'a screen reader announces is the banner copy instead',
      );
      semantics.dispose();
    });

    testWidgets('announces a Hide sensitive content button once revealed', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();

      await pumpBanner(tester, concealed: false);

      expect(
        tester.getSemantics(find.bySemanticsLabel('Hide sensitive content')),
        isSemantics(
          isButton: true,
          label: 'Hide sensitive content',
          hasTapAction: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('the only activatable node is the labelled one', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();

      await pumpBanner(tester, concealed: true);

      expect(
        activatableLabels(
          tester,
          find.bySemanticsLabel('Show sensitive content'),
        ),
        const ['Show sensitive content'],
        reason:
            'the banner copy must not be the node that carries the tap, or '
            'a screen reader activates something it announced as plain text',
      );
      semantics.dispose();
    });

    testWidgets('a screen-reader activation invokes onToggle', (tester) async {
      final semantics = tester.ensureSemantics();
      var toggles = 0;

      await pumpBanner(tester, concealed: true, onToggle: () => toggles++);
      activateBySemantics(
        tester,
        find.bySemanticsLabel('Show sensitive content'),
      );
      await tester.pump();

      expect(
        toggles,
        1,
        reason:
            'TalkBack and VoiceOver activate the labelled node, so a tap '
            'that only exists on a child node is unreachable to them',
      );
      semantics.dispose();
    });

    testWidgets('a tap invokes onToggle exactly once', (tester) async {
      var toggles = 0;
      await pumpBanner(tester, concealed: true, onToggle: () => toggles++);

      await tester.tap(find.byKey(_bannerKey));
      await tester.pump();

      expect(toggles, 1);
    });

    testWidgets('paints without throwing', (tester) async {
      await pumpBanner(tester, concealed: true);
      await tester.pump();

      expect(
        tester.takeException(),
        isNull,
        reason: 'the info glyph paints raw svg path data at build time',
      );
    });
  });

  group('LucidePaths.info', () {
    testWidgets('renders as a glyph without throwing', (tester) async {
      await pumpUnderAppTheme(tester, const LucideGlyph(LucidePaths.info));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    test('is the three-part lucide info glyph', () {
      // circle, stem, dot — a shorter list means a path was dropped and the
      // glyph would paint as something other than an info mark.
      expect(LucidePaths.info, hasLength(3));
    });
  });

  group('SensitiveImagePlaceholder', () {
    Future<void> pumpPlaceholder(
      WidgetTester tester, {
      VoidCallback? onReveal,
    }) {
      return pumpUnderAppTheme(
        tester,
        SensitiveImagePlaceholder(
          image: sensitiveImage(),
          bounds: kFeedRatioBounds,
          onReveal: onReveal ?? () {},
        ),
      );
    }

    Finder inPlaceholder(Finder matching) {
      return find.descendant(
        of: find.byKey(_placeholderKey),
        matching: matching,
        matchRoot: true,
      );
    }

    testWidgets('carries the key the post widgets find it by', (tester) async {
      await pumpPlaceholder(tester);

      expect(find.byKey(_placeholderKey), findsOneWidget);
    });

    testWidgets('blurs its image with a sigma of 32', (tester) async {
      await pumpPlaceholder(tester);

      final filtered = inPlaceholder(find.byType(ImageFiltered));
      expect(filtered, findsOneWidget);
      expect(
        tester.widget<ImageFiltered>(filtered).imageFilter.toString(),
        contains('blur(32.0, 32.0'),
        reason: 'a weaker blur leaves the concealed image legible',
      );
    });

    testWidgets('fetches the thumb and never the fullsize rendering', (
      tester,
    ) async {
      await pumpPlaceholder(tester);

      final images = inPlaceholder(find.byType(CachedNetworkImage));
      expect(images, findsOneWidget);
      expect(tester.widget<CachedNetworkImage>(images).imageUrl, _thumb);
    });

    testWidgets('reserves the space the revealed image will occupy', (
      tester,
    ) async {
      await pumpPlaceholder(tester);

      final expected = clampMediaRatio(
        sensitiveImage().aspectRatio,
        min: kFeedRatioBounds.min,
        max: kFeedRatioBounds.max,
      );

      final ratios = inPlaceholder(find.byType(AspectRatio));
      expect(ratios, findsWidgets);
      expect(
        tester.widget<AspectRatio>(ratios.first).aspectRatio,
        closeTo(expected, 0.001),
        reason: 'revealing the image must not shift the layout',
      );
    });

    testWidgets('overlays the reveal copy', (tester) async {
      await pumpPlaceholder(tester);

      expect(inPlaceholder(find.text('NSFW Content')), findsOneWidget);
      expect(inPlaceholder(find.text('Show')), findsOneWidget);
    });

    testWidgets('announces a Show sensitive content button', (tester) async {
      final semantics = tester.ensureSemantics();

      await pumpPlaceholder(tester);

      expect(
        tester.getSemantics(find.bySemanticsLabel('Show sensitive content')),
        isSemantics(
          isButton: true,
          label: 'Show sensitive content',
          hasTapAction: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('the only activatable node is the labelled one', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();

      await pumpPlaceholder(tester);

      expect(
        activatableLabels(
          tester,
          find.bySemanticsLabel('Show sensitive content'),
        ),
        const ['Show sensitive content'],
        reason:
            'the overlay copy must not be the node that carries the tap, or '
            'a screen reader activates something it announced as plain text',
      );
      semantics.dispose();
    });

    testWidgets('a screen-reader activation invokes onReveal', (tester) async {
      final semantics = tester.ensureSemantics();
      var reveals = 0;

      await pumpPlaceholder(tester, onReveal: () => reveals++);
      activateBySemantics(
        tester,
        find.bySemanticsLabel('Show sensitive content'),
      );
      await tester.pump();

      expect(
        reveals,
        1,
        reason:
            'TalkBack and VoiceOver activate the labelled node, so a tap '
            'that only exists on a child node is unreachable to them',
      );
      semantics.dispose();
    });

    testWidgets('keeps the alt text out of the semantics tree', (tester) async {
      final semantics = tester.ensureSemantics();

      await pumpPlaceholder(tester);

      expect(
        find.bySemanticsLabel(_alt),
        findsNothing,
        reason: 'alt text describes the concealed image and must not leak',
      );
      semantics.dispose();
    });

    testWidgets('a tap invokes onReveal exactly once', (tester) async {
      var reveals = 0;
      await pumpPlaceholder(tester, onReveal: () => reveals++);

      await tester.tap(find.byKey(_placeholderKey));
      await tester.pump();

      expect(reveals, 1);
    });
  });
}
