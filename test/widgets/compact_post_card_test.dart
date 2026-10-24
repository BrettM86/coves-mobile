import 'package:cached_network_image/cached_network_image.dart';
import 'package:coves_flutter/widgets/compact_post_card.dart';
import 'package:coves_flutter/widgets/icons/lucide_paths.dart';
import 'package:coves_flutter/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/lucide_glyph_finder.dart';
import '../test_helpers/semantics_helpers.dart';
import '../test_helpers/theme_pump.dart';

const _handle = 'poster.example';
const _avatarUrl = 'https://cdn.test/poster.png';
const _title = 'Best budget keyboards?';
const _thumbnailUrl = 'https://cdn.test/thumb.jpg';
const _thumbnailAlt = 'A mechanical keyboard';
const _placeholder = 'Deleted by user';
final _createdAt = DateTime.utc(2026, 10, 1, 12);
final _currentTime = DateTime.utc(2026, 10, 7, 12);

Future<void> _pumpCard(
  WidgetTester tester, {
  String? authorHandle = _handle,
  String? authorAvatarUrl = _avatarUrl,
  DateTime? createdAt,
  bool omitCreatedAt = false,
  String? title = _title,
  int? score = 1234,
  int? commentCount = 56,
  String? thumbnailUrl = _thumbnailUrl,
  String? thumbnailAlt,
  String? placeholder,
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await pumpUnderAppTheme(
    tester,
    CompactPostCard(
      authorHandle: authorHandle,
      authorAvatarUrl: authorAvatarUrl,
      createdAt: omitCreatedAt ? null : (createdAt ?? _createdAt),
      currentTime: _currentTime,
      title: title,
      score: score,
      commentCount: commentCount,
      thumbnailUrl: thumbnailUrl,
      thumbnailAlt: thumbnailAlt,
      placeholder: placeholder,
    ),
  );
}

Finder _inCard(Finder finder) =>
    find.descendant(of: find.byType(CompactPostCard), matching: finder);

Finder _thumbnail() => _inCard(
  find.byWidgetPredicate(
    (widget) =>
        widget is CachedNetworkImage && widget.imageUrl == _thumbnailUrl,
  ),
);

Finder _glyph(List<String> paths) =>
    findLucideGlyph(paths, within: find.byType(CompactPostCard));

/// The media tile's rounded, bordered frame around [content], if any. The
/// card's own frame has a different radius, so it never matches.
Finder _tileFrame(Finder content) => find.ancestor(
  of: content,
  matching: find.byWidgetPredicate((widget) {
    if (widget is! DecoratedBox) {
      return false;
    }
    final decoration = widget.decoration;
    return decoration is BoxDecoration &&
        decoration.border != null &&
        decoration.borderRadius == BorderRadius.circular(16);
  }),
);

void main() {
  group('CompactPostCard', () {
    testWidgets('B3 shows author, time, title, stats and thumbnail', (
      tester,
    ) async {
      await _pumpCard(tester);

      expect(_inCard(find.byType(UserAvatar)), findsOneWidget);
      expect(
        tester.widget<UserAvatar>(_inCard(find.byType(UserAvatar))).avatarUrl,
        _avatarUrl,
      );
      expect(_inCard(find.text('@poster.example')), findsOneWidget);
      expect(_inCard(find.text('6d')), findsOneWidget);
      expect(_inCard(find.text(_title)), findsOneWidget);
      expect(_inCard(find.text('1.2K')), findsOneWidget);
      expect(_inCard(find.text('56')), findsOneWidget);
      expect(_glyph(LucidePaths.heart), findsOneWidget);
      expect(_glyph(LucidePaths.messageSquare), findsOneWidget);
      expect(_glyph(LucidePaths.thumbsDown), findsOneWidget);
      expect(_thumbnail(), findsOneWidget);
      expect(_glyph(LucidePaths.fileText), findsNothing);
    });

    testWidgets('B3 a negative score is shown with its sign', (tester) async {
      await _pumpCard(tester, score: -3);

      expect(_inCard(find.text('-3')), findsOneWidget);
    });

    testWidgets('B3 the title is clamped to two lines', (tester) async {
      final longTitle = List.filled(40, 'keyboards').join(' ');
      await _pumpCard(tester, title: longTitle);

      expect(_inCard(find.text(longTitle)), findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(
        _inCard(find.text(longTitle)),
      );
      expect(paragraph.maxLines, 2);
      expect(paragraph.didExceedMaxLines, isTrue);
    });

    testWidgets('B3 the thumbnail carries its alt text', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pumpCard(tester, thumbnailAlt: _thumbnailAlt);

        expect(_thumbnail(), findsOneWidget);
        expect(find.bySemanticsLabel(_thumbnailAlt), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('a thumbnail is unframed; the text tile keeps its border', (
      tester,
    ) async {
      await _pumpCard(tester);
      expect(_tileFrame(_thumbnail()), findsNothing);

      await _pumpCard(tester, thumbnailUrl: null);
      expect(_tileFrame(_glyph(LucidePaths.fileText)), findsOneWidget);
    });

    testWidgets('B3 without a thumbnail the media tile shows a text glyph', (
      tester,
    ) async {
      await _pumpCard(tester, thumbnailUrl: null, authorAvatarUrl: null);

      expect(_inCard(find.text(_title)), findsOneWidget);
      expect(_inCard(find.byType(CachedNetworkImage)), findsNothing);
      expect(_glyph(LucidePaths.fileText), findsOneWidget);
    });

    testWidgets(
      'B3 a thumbnail that fails to load falls back to a text glyph',
      (tester) async {
        await _pumpCard(tester);

        expect(_thumbnail(), findsOneWidget);
        final image = tester.widget<CachedNetworkImage>(_thumbnail());
        expect(image.errorWidget, isNotNull);
        final fallback = image.errorWidget!(
          tester.element(_thumbnail()),
          _thumbnailUrl,
          Exception('decode failed'),
        );
        await pumpUnderAppTheme(tester, fallback);

        final glyph = findLucideGlyph(LucidePaths.fileText);
        expect(glyph, findsOneWidget);
        expect(_tileFrame(glyph), findsOneWidget);
      },
    );

    testWidgets(
      'B3 placeholder mode shows only the placeholder and text tile',
      (tester) async {
        await _pumpCard(tester, placeholder: _placeholder);

        expect(_inCard(find.text(_placeholder)), findsOneWidget);
        expect(_glyph(LucidePaths.fileText), findsOneWidget);
        expect(_inCard(find.text(_title)), findsNothing);
        expect(_inCard(find.byType(UserAvatar)), findsNothing);
        expect(_inCard(find.text('@poster.example')), findsNothing);
        expect(_inCard(find.text('6d')), findsNothing);
        expect(_inCard(find.text('1.2K')), findsNothing);
        expect(_inCard(find.text('56')), findsNothing);
        expect(_glyph(LucidePaths.heart), findsNothing);
        expect(_glyph(LucidePaths.messageSquare), findsNothing);
        expect(_glyph(LucidePaths.thumbsDown), findsNothing);
        expect(_inCard(find.byType(CachedNetworkImage)), findsNothing);
      },
    );

    testWidgets('B3 contains no activatable semantics nodes', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pumpCard(tester, thumbnailAlt: _thumbnailAlt);

        expect(_inCard(find.text(_title)), findsOneWidget);
        expect(
          activatableLabels(tester, find.byType(CompactPostCard)),
          isEmpty,
        );
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('B3 without an author handle there is no avatar or handle', (
      tester,
    ) async {
      await _pumpCard(tester, authorHandle: null);

      expect(_inCard(find.text('6d')), findsOneWidget);
      expect(_inCard(find.text(_title)), findsOneWidget);
      expect(_inCard(find.byType(UserAvatar)), findsNothing);
      expect(_inCard(find.textContaining('@')), findsNothing);
    });

    testWidgets('B3 without a created time there is no relative time', (
      tester,
    ) async {
      await _pumpCard(tester, omitCreatedAt: true);

      expect(_inCard(find.text('@poster.example')), findsOneWidget);
      expect(_inCard(find.text('6d')), findsNothing);
    });

    testWidgets('B3 without stats there is no score, count or vote glyphs', (
      tester,
    ) async {
      await _pumpCard(tester, score: null, commentCount: null);

      expect(_inCard(find.text(_title)), findsOneWidget);
      expect(_glyph(LucidePaths.heart), findsNothing);
      expect(_glyph(LucidePaths.messageSquare), findsNothing);
      expect(_glyph(LucidePaths.thumbsDown), findsNothing);
    });

    testWidgets(
      'B3 large counts at 1.5x text in a narrow row fit without overflow',
      (tester) async {
        tester.view.physicalSize = const Size(960, 2532);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await pumpUnderAppTheme(
          tester,
          MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 844),
              textScaler: TextScaler.linear(1.5),
            ),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 270,
                child: CompactPostCard(
                  authorHandle: _handle,
                  authorAvatarUrl: _avatarUrl,
                  createdAt: _createdAt,
                  currentTime: _currentTime,
                  title: _title,
                  score: 123456,
                  commentCount: 98765,
                  thumbnailUrl: _thumbnailUrl,
                ),
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(_inCard(find.text('123.5K')), findsOneWidget);
        expect(_inCard(find.text('98.8K')), findsOneWidget);
      },
    );

    testWidgets('B3 without a title only the meta, stats and tile show', (
      tester,
    ) async {
      await _pumpCard(tester, title: null);

      expect(_inCard(find.text('@poster.example')), findsOneWidget);
      expect(_inCard(find.text('1.2K')), findsOneWidget);
      expect(_inCard(find.text(_title)), findsNothing);
    });
  });
}
