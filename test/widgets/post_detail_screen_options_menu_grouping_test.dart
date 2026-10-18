// The post detail app bar's ⋮ menu offers the same grouped entries as the
// feed card's ⋯ menu, held to the same literal rows. Hide post and Copy
// link are gone.
import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/screens/home/post_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers/post_options_menu_rows.dart';
import '../test_helpers/pump_helpers.dart';

void main() {
  group('post detail More options menu', () {
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
        // Unmounted before the harness's providers are disposed.
        addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
        await tester.pumpWidget(
          MultiProvider(
            providers: harness.providers,
            child: MaterialApp(
              theme: AppTheme.dark,
              // Optimistic, so the screen skips its initial comment load.
              home: PostDetailScreen(
                post: menuPost(row.viewer),
                sessionStamp: harness.sessionStamp,
                isOptimistic: true,
              ),
            ),
          ),
        );
        await pumpFrames(tester);

        await tester.tap(find.byTooltip('More options'));
        await pumpFrames(tester);

        expect(openMenuRows(tester), row.expected);
        expect(find.text('Copy link'), findsNothing);
        expect(find.text('Hide post'), findsNothing);
      });
    }
  });
}
