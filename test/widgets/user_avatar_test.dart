import 'package:cached_network_image/cached_network_image.dart';
import 'package:coves_flutter/constants/app_colors.dart';
import 'package:coves_flutter/utils/display_utils.dart';
import 'package:coves_flutter/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// RED: lib/widgets/user_avatar.dart does not exist yet.
///
/// Seven hand-rolled author/user avatars (post_card, detailed_post_view,
/// comment_card, bluesky_post_card x2, profile_header, edit_profile_screen)
/// are being unified onto this widget. This file is the spec for it and
/// fails to compile until the Green phase creates the widget — it is kept in
/// its own file so that no other test suite is compile-broken by it.
///
/// Contract (from the work brief):
///   UserAvatar({
///     required String name,      // display name or handle: initial + hash
///     String? avatarUrl,
///     required double size,
///     Color? fallbackColor,      // default DisplayUtils.getFallbackColor(name)
///     Color? fallbackTextColor,  // default white
///     Widget? fallbackIcon,      // icon instead of initial
///     bool showLoadingIndicator = false,
///   })
/// Always circular.
void main() {
  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  BoxDecoration decorationBehind(WidgetTester tester, Finder inner) {
    final decorated = tester.widget<DecoratedBox>(
      find.ancestor(of: inner, matching: find.byType(DecoratedBox)).first,
    );
    return decorated.decoration as BoxDecoration;
  }

  group('UserAvatar fallback', () {
    testWidgets('renders the first letter of the name, uppercased', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const UserAvatar(name: 'ada.test', size: 24)),
      );

      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('renders "?" for an empty name instead of throwing', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const UserAvatar(name: '', size: 24)));

      expect(tester.takeException(), isNull);
      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('defaults to the shared hash color, not AppColors.primary', (
      tester,
    ) async {
      // 'commenter.test' deliberately hashes to a non-coral slot so this
      // distinguishes the unified color from the old AppColors.primary.
      const name = 'commenter.test';
      expect(
        DisplayUtils.getFallbackColor(name).toARGB32(),
        isNot(AppColors.primary.toARGB32()),
        reason: 'test fixture must hash away from the legacy color',
      );

      await tester.pumpWidget(wrap(const UserAvatar(name: name, size: 24)));

      expect(
        decorationBehind(tester, find.text('C')).color!.toARGB32(),
        DisplayUtils.getFallbackColor(name).toARGB32(),
      );
    });

    testWidgets('fallbackColor overrides the hash color', (tester) async {
      // Bluesky cards keep their own themed fallback through this param.
      await tester.pumpWidget(
        wrap(
          const UserAvatar(
            name: 'ada.test',
            size: 40,
            fallbackColor: Color(0xFF123456),
          ),
        ),
      );

      expect(
        decorationBehind(tester, find.text('A')).color!.toARGB32(),
        0xFF123456,
      );
    });

    testWidgets('fallback text is white by default and overridable', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const UserAvatar(name: 'ada.test', size: 40)),
      );
      expect(
        tester.widget<Text>(find.text('A')).style?.color?.toARGB32(),
        Colors.white.toARGB32(),
      );

      await tester.pumpWidget(
        wrap(
          const UserAvatar(
            name: 'ada.test',
            size: 40,
            fallbackTextColor: AppColors.coral,
          ),
        ),
      );
      expect(
        tester.widget<Text>(find.text('A')).style?.color?.toARGB32(),
        AppColors.coral.toARGB32(),
      );
    });

    testWidgets('fallbackIcon replaces the initial', (tester) async {
      // profile_header / edit_profile_screen show Icons.person, no letter.
      await tester.pumpWidget(
        wrap(
          const UserAvatar(
            name: 'ada.test',
            size: 74,
            fallbackIcon: Icon(Icons.person, size: 40),
          ),
        ),
      );

      expect(find.byIcon(Icons.person), findsOneWidget);
      expect(find.text('A'), findsNothing);
    });

    testWidgets('fills exactly size x size', (tester) async {
      await tester.pumpWidget(
        wrap(const UserAvatar(name: 'ada.test', size: 24)),
      );

      expect(
        tester.getSize(
          find.ancestor(
            of: find.text('A'),
            matching: find.byType(DecoratedBox),
          ).first,
        ),
        const Size(24, 24),
      );
    });

    testWidgets('is circular', (tester) async {
      const size = 24.0;
      await tester.pumpWidget(
        wrap(const UserAvatar(name: 'ada.test', size: size)),
      );

      final decoration = decorationBehind(tester, find.text('A'));
      final isCircle =
          decoration.shape == BoxShape.circle ||
          decoration.borderRadius == BorderRadius.circular(size / 2);
      expect(isCircle, isTrue, reason: 'user avatars are always circular');
    });
  });

  group('UserAvatar image', () {
    testWidgets('loads the avatar at exactly the avatar size', (tester) async {
      // The comment_card bug this widget replaces was an image smaller than
      // its own fallback, which reflowed the row when loading failed.
      await tester.pumpWidget(
        wrap(
          const UserAvatar(
            name: 'ada.test',
            size: 24,
            avatarUrl: 'https://example.com/a.jpg',
          ),
        ),
      );

      final image = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      expect(image.imageUrl, 'https://example.com/a.jpg');
      expect(image.width, 24);
      expect(image.height, 24);
    });

    testWidgets('an empty avatarUrl falls back instead of loading', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const UserAvatar(name: 'ada.test', size: 24, avatarUrl: '')),
      );

      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('clips with at most one ClipOval', (tester) async {
      // ProfileHeader's geometry tests locate the avatar via a single
      // ClipOval descendant (test/widgets/profile_header_test.dart) — nesting
      // another one inside UserAvatar would break them.
      await tester.pumpWidget(
        wrap(
          const UserAvatar(
            name: 'ada.test',
            size: 74,
            avatarUrl: 'https://example.com/a.jpg',
          ),
        ),
      );

      expect(
        tester.widgetList(find.byType(ClipOval)).length,
        lessThanOrEqualTo(1),
      );
    });
  });
}
