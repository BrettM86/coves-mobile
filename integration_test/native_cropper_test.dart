// Real native cropper verification, driven by a person or Maestro.
// Start the matching .maestro/native_cropper_<platform>.yaml flow first.
// Android accessibility must be active before the test records its baseline.
// Save the first two crops, then cancel the next two:
// flutter test integration_test/native_cropper_test.dart \
//   -d <device-id> --flavor dev --dart-define=ENVIRONMENT=local --no-uninstall
// No account or backend is required. Native buttons are not mocked.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:coves_flutter/utils/image_crop_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native avatar and banner crops save and cancel', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Native cropper verification')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final directory = await Directory.systemTemp.createTemp('coves-cropper-');
    final outputFiles = <File>[];
    try {
      // The existing bundled logo is SVG; native croppers need raster input.
      final picture = await vg.loadPicture(
        const SvgAssetLoader('assets/logo/lil_dude.svg'),
        null,
      );
      late ui.Image sourceImage;
      try {
        sourceImage = await picture.picture.toImage(
          picture.size.width.ceil(),
          picture.size.height.ceil(),
        );
      } finally {
        picture.picture.dispose();
      }
      final sourceFile = File('${directory.path}/logo.png');
      try {
        final png = await sourceImage.toByteData(
          format: ui.ImageByteFormat.png,
        );
        expect(png, isNotNull, reason: 'Bundled logo must rasterize to PNG.');
        await sourceFile.writeAsBytes(
          png!.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
        );
      } finally {
        sourceImage.dispose();
      }

      for (final (label, configuration, shouldSave) in [
        ('AVATAR SAVE', CropConfig.avatar, true),
        ('BANNER SAVE', CropConfig.banner, true),
        ('AVATAR CANCEL', CropConfig.avatar, false),
        ('BANNER CANCEL', CropConfig.banner, false),
      ]) {
        debugPrintSynchronously('NATIVE CROPPER: $label');
        final result = await ImageCropUtils.cropImage(
          sourcePath: sourceFile.path,
          config: configuration,
        ).timeout(const Duration(seconds: 90));
        if (result != null) {
          outputFiles.add(File(result.path));
        }

        if (!shouldSave) {
          expect(result, isNull, reason: '$label must return no cropped file.');
        } else {
          expect(
            result,
            isNotNull,
            reason: '$label must return a cropped file.',
          );
          final bytes = await result!.readAsBytes();
          expect(
            bytes.isNotEmpty,
            isTrue,
            reason: '$label output must not be empty.',
          );
          final codec = await ui.instantiateImageCodec(bytes);
          try {
            final frame = await codec.getNextFrame();
            try {
              final image = frame.image;
              expect(image.width, greaterThan(0));
              expect(image.height, greaterThan(0));
              if (configuration == CropConfig.avatar) {
                expect(
                  image.width,
                  image.height,
                  reason: 'Avatar crop must be square.',
                );
              } else {
                expect(
                  (image.width - 3 * image.height).abs(),
                  lessThanOrEqualTo(3),
                  reason: 'Banner crop must be 3:1 within pixel rounding.',
                );
              }
            } finally {
              frame.image.dispose();
            }
          } finally {
            codec.dispose();
          }
        }
        debugPrintSynchronously('NATIVE CROPPER: $label COMPLETE');
        // Allow the native dismissal to finish before presenting another crop.
        await tester.pumpAndSettle();
      }
    } finally {
      for (final file in outputFiles) {
        if (file.existsSync()) {
          await file.delete();
        }
      }
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
