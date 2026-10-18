// The feed card's ⋯ menu groups its entries: the community subscription,
// then blocks, then reporting or deleting, then any admin tools, each group
// set off by a divider. Copy link is not in the menu: Share covers it.
import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/widgets/post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers/post_options_menu_rows.dart';
import '../test_helpers/pump_helpers.dart';

void main() {
  group('feed card Post options menu', () {
    for (final row in postOptionsMenuRows) {
      testWidgets('lists grouped entries: ${row.name}', (tester) async {
        tester.view.physicalSize = const Size(540, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (_) async => null,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        final harness = MenuHarness.create(row.viewer);
        await tester.pumpWidget(
          MultiProvider(
            providers: harness.providers,
            child: MaterialApp(
              theme: AppTheme.dark,
              home: Scaffold(
                body: PostCard(
                  post: menuPost(row.viewer),
                  sessionStamp: harness.sessionStamp,
                ),
              ),
            ),
          ),
        );
        await pumpFrames(tester);

        await tester.tap(find.byTooltip('Post options'));
        await pumpFrames(tester);

        expect(openMenuRows(tester), row.expected);
        expect(find.text('Copy link'), findsNothing);
      });
    }
  });
}
