import 'package:coves_flutter/utils/image_decode_size.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Pumps a [MediaQuery] with [devicePixelRatio] and [size], and returns a
  /// context below it.
  Future<BuildContext> pumpMediaQuery(
    WidgetTester tester, {
    required double devicePixelRatio,
    Size size = const Size(400, 800),
  }) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size, devicePixelRatio: devicePixelRatio),
        child: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return captured;
  }

  group('decodeWidthFor', () {
    testWidgets('at DPR 2 rounds 20 and 24 logical px up to 64', (
      tester,
    ) async {
      final context = await pumpMediaQuery(tester, devicePixelRatio: 2);

      // 40 and 48 physical px share one 64px decode.
      expect(decodeWidthFor(context, 20), 64);
      expect(decodeWidthFor(context, 24), 64);
    });

    testWidgets('at DPR 3 rounds up to the next multiple of 64', (
      tester,
    ) async {
      final context = await pumpMediaQuery(tester, devicePixelRatio: 3);

      // 60 physical px -> 64; 72 physical px -> 128.
      expect(decodeWidthFor(context, 20), 64);
      expect(decodeWidthFor(context, 24), 128);
      // 216 physical px -> 256.
      expect(decodeWidthFor(context, 72), 256);
    });

    testWidgets('an exact multiple of 64 is not rounded further', (
      tester,
    ) async {
      final context = await pumpMediaQuery(tester, devicePixelRatio: 2);

      expect(decodeWidthFor(context, 32), 64);
      expect(decodeWidthFor(context, 64), 128);
    });

    testWidgets('never returns less than 64', (tester) async {
      final context = await pumpMediaQuery(tester, devicePixelRatio: 3);

      expect(decodeWidthFor(context, 0), 64);
      expect(decodeWidthFor(context, 1), 64);
    });
  });

  group('fullWidthDecodeWidth', () {
    testWidgets('decodes the screen width at the device pixel ratio', (
      tester,
    ) async {
      final context = await pumpMediaQuery(
        tester,
        devicePixelRatio: 3,
        size: const Size(390, 844),
      );

      // 1170 physical px -> 1216 (19 x 64).
      expect(fullWidthDecodeWidth(context), 1216);
      expect(fullWidthDecodeWidth(context), decodeWidthFor(context, 390));
    });

    testWidgets('at DPR 2', (tester) async {
      // The helper's default size is 400 x 800.
      final context = await pumpMediaQuery(tester, devicePixelRatio: 2);

      // 800 physical px -> 832 (13 x 64).
      expect(fullWidthDecodeWidth(context), 832);
    });
  });
}
