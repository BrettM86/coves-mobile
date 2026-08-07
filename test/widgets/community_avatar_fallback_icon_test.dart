import 'package:coves_flutter/widgets/community_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// RED: [CommunityAvatar] has no `fallbackIcon` parameter yet.
///
/// The admin-panel community avatars (communities_admin_panel.dart at 40px,
/// 100px and 120px) fall back to an icon instead of an initial. Migrating
/// them onto the canonical widget needs `Widget? fallbackIcon`: when set the
/// icon is rendered in place of the letter, everything else (size, shape,
/// hash background) unchanged.
///
/// This file is deliberately separate from community_avatar_test.dart: it
/// references an API that does not exist, so it fails to compile until the
/// Green phase adds the parameter. Keeping it isolated lets the
/// characterization suite next door still run.
void main() {
  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  group('CommunityAvatar fallbackIcon', () {
    testWidgets('renders the icon instead of the name initial', (tester) async {
      await tester.pumpWidget(
        wrap(
          const CommunityAvatar(
            name: 'gaming',
            size: 40,
            fallbackIcon: Icon(Icons.workspaces_outlined, size: 20),
          ),
        ),
      );

      expect(find.byIcon(Icons.workspaces_outlined), findsOneWidget);
      expect(find.text('G'), findsNothing);
    });

    testWidgets('still fills exactly size x size', (tester) async {
      await tester.pumpWidget(
        wrap(
          const CommunityAvatar(
            name: 'gaming',
            size: 100,
            fallbackIcon: Icon(Icons.workspaces_outlined, size: 40),
          ),
        ),
      );

      expect(
        tester.getSize(
          find.ancestor(
            of: find.byIcon(Icons.workspaces_outlined),
            matching: find.byType(DecoratedBox),
          ).first,
        ),
        const Size(100, 100),
      );
    });

    testWidgets('the icon is used for the empty-name case too', (tester) async {
      await tester.pumpWidget(
        wrap(
          const CommunityAvatar(
            name: '',
            size: 40,
            fallbackIcon: Icon(Icons.workspaces_outlined, size: 20),
          ),
        ),
      );

      expect(find.byIcon(Icons.workspaces_outlined), findsOneWidget);
      expect(find.text('?'), findsNothing);
    });
  });
}
