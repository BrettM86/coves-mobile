import 'package:flutter_test/flutter_test.dart';

/// Bounded pumps: long enough for post-frame loads, resolved mock futures,
/// and a page transition (the zoom transition takes 500ms). Never
/// pumpAndSettle while a spinner may be up.
Future<void> pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
  await tester.pump();
}
