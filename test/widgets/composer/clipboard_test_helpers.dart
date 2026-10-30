import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A clipboard behind the platform channel, holding plain text only.
class MockClipboard {
  String? text;

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'Clipboard.setData':
        text = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        return null;
      case 'Clipboard.getData':
        return text == null ? null : <String, Object?>{'text': text};
      case 'Clipboard.hasStrings':
        return <String, Object?>{'value': text?.isNotEmpty ?? false};
    }
    return null;
  }
}

MockClipboard installClipboard(WidgetTester tester, {String? text}) {
  final clipboard = MockClipboard()..text = text;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    clipboard.handle,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return clipboard;
}

/// Presses [key] with Control held, as the keyboard shortcut for it.
Future<void> pressWithControl(
  WidgetTester tester,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}
