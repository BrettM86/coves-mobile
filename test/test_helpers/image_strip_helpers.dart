import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pump_helpers.dart';

/// The local file path an image provider draws from; fails on anything but
/// a FileImage (optionally wrapped in a ResizeImage).
String filePathOf(ImageProvider provider) {
  final unwrapped = provider is ResizeImage ? provider.imageProvider : provider;
  expect(unwrapped, isA<FileImage>(), reason: 'image provider $unwrapped');
  return (unwrapped as FileImage).file.path;
}

/// The file paths of every Image under [subtree], in tree order; fails when
/// any of them is not drawn from a local file.
List<String> imagePathsIn(WidgetTester tester, Finder subtree) {
  expect(
    find.descendant(of: subtree, matching: find.byType(CachedNetworkImage)),
    findsNothing,
    reason: 'no network image under $subtree',
  );
  return [
    for (final image in tester.widgetList<Image>(
      find.descendant(of: subtree, matching: find.byType(Image)),
    ))
      filePathOf(image.image),
  ];
}

/// Drags [from] with one held pointer until its centre is just past the
/// centre of [to], then drops it.
///
/// With [holdForLongPress] the pointer is held past the long-press timeout
/// before it moves; without it the pointer moves at once.
Future<void> longPressDrag(
  WidgetTester tester,
  Finder from,
  Finder to, {
  bool holdForLongPress = true,
}) async {
  await tester.ensureVisible(from);
  await tester.pump();
  final start = tester.getCenter(from);
  final target = tester.getCenter(to);
  final direction = target.dx > start.dx ? 1.0 : -1.0;
  final end = Offset(target.dx + direction * 12, start.dy);

  final gesture = await tester.startGesture(start);
  if (holdForLongPress) {
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
  }
  const steps = 12;
  for (var step = 1; step <= steps; step++) {
    await gesture.moveTo(Offset.lerp(start, end, step / steps)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await pumpFrames(tester);
}

/// Sets the alt of the strip tile at [index] through its Alt control and
/// the alt editor.
Future<void> setImageAlt(WidgetTester tester, int index, String alt) async {
  final altControl = find.byKey(Key('image-attachment-alt-$index'));
  expect(altControl, findsOneWidget, reason: 'the Alt control of $index');
  await tester.ensureVisible(altControl);
  await tester.pump();
  await tester.tap(altControl);
  await pumpFrames(tester);
  await tester.enterText(find.byKey(const Key('image-alt-editor-field')), alt);
  await tester.pump();
  await tester.tap(find.byKey(const Key('image-alt-editor-save')));
  await pumpFrames(tester);
}
