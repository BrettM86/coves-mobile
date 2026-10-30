import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/notifications_shell_harness.dart';
import '../../widgets/composer/formatting_toolbar_test_helpers.dart';
import 'create_post_test_harness.dart';

void main() {
  /// Taps a phone bottom-nav tab and lets the shell switch to it
  Future<void> selectTab(WidgetTester tester, String label) async {
    await tester.tap(phoneNavItem(label));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  toolbarTest('the create tab keeps the body text and its formatting across '
      'a switch to another tab and back', (tester) async {
    useShellViewport(tester, const Size(540, 960));
    final harness = NotificationsShellHarness(count: 0);
    try {
      await harness.mount(tester);
      await selectTab(tester, 'Create');

      await tester.enterText(bodyEditable, 'hello');
      await focusField(
        tester,
        const TextSelection(baseOffset: 0, extentOffset: 5),
        field: bodyEditable,
      );
      await tapButton(tester, 'Bold');
      await tapButton(tester, 'Quote');

      await selectTab(tester, 'Home');
      expect(bodyEditable, findsNothing, reason: 'the create tab is hidden');
      await selectTab(tester, 'Create');

      final controller = bodyController(tester);
      expect(controller.text, 'hello');
      expect(controller.inlineRanges, hasLength(1));
      expect(controller.inlineRanges.single.format, InlineFormat.bold);
      expect(controller.inlineRanges.single.start, 0);
      expect(controller.inlineRanges.single.end, 5);
      expect(controller.blockRanges, hasLength(1));
      expect(controller.blockRanges.single.format, BlockFormat.blockquote);
      expect(controller.blockRanges.single.start, 0);
      expect(controller.blockRanges.single.end, 5);
    } finally {
      await harness.dispose(tester);
    }
  });
}
