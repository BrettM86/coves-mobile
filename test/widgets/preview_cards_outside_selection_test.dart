// Feed cards outside any selection region: the reply preview's selection
// changes must leave their rendering and long-press collapse unchanged.
import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/widgets/comment_thread.dart';
import 'package:coves_flutter/widgets/post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../screens/compose/reply_preview_fixtures.dart';
import '../test_helpers/fake_providers.dart';

void main() {
  final android = TargetPlatformVariant.only(TargetPlatform.android);

  /// A feed PostCard for P above a CommentThread for C whose long-press
  /// toggles collapse the way the comments screen does.
  Future<void> pumpFeedCards(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    // The collapse long-press awaits a haptic; answer it.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (methodCall) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final collapsed = <String>{};
    await tester.pumpWidget(
      MultiProvider(
        providers: postCardProviders(auth: FakeAuthProvider()),
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) => Column(
                  children: [
                    PostCard(
                      post: previewPost(),
                      sessionStamp: null,
                      currentTime: previewCurrentTime,
                    ),
                    CommentThread(
                      thread: previewCommentChain(),
                      sessionStamp: null,
                      currentTime: previewCurrentTime,
                      collapsedComments: collapsed,
                      onCollapseToggle: (uri) => setState(() {
                        if (!collapsed.remove(uri)) {
                          collapsed.add(uri);
                        }
                      }),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('B5 a feed PostCard and CommentThread still show the handles '
      'and the relative time', (tester) async {
    await pumpFeedCards(tester);

    expect(find.text('@preview.author.test'), findsOneWidget);
    expect(find.text('@first.commenter.test'), findsOneWidget);
    expect(find.text('5h'), findsWidgets);
  }, variant: android);

  for (final target in ['First comment body.', '@first.commenter.test']) {
    testWidgets('B5 long-pressing "$target" in a feed CommentThread '
        'collapses the comment', (tester) async {
      await pumpFeedCards(tester);
      expect(find.text('Nested reply body.'), findsOneWidget);
      expect(find.text('+1'), findsNothing);

      await tester.longPress(find.text(target));
      await tester.pumpAndSettle();

      expect(find.text('Nested reply body.'), findsNothing);
      expect(find.text('First comment body.'), findsNothing);
      expect(find.text('+1'), findsOneWidget);
    }, variant: android);
  }
}
