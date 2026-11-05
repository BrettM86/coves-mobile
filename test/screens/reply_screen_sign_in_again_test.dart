import 'dart:io';
import 'dart:typed_data';

import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/post_embed_input.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/screens/compose/reply_screen.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/utils/image_preparation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/fake_image_encoder.dart';
import '../test_helpers/image_fixtures.dart';
import '../test_helpers/image_picking_fakes.dart';
import '../test_helpers/image_strip_helpers.dart';
import '../test_helpers/pump_helpers.dart';
import '../test_helpers/reply_screen_harness.dart';

final _dialog = find.byKey(const Key('sign-in-again-dialog'));
final _differentAccount = find.byKey(
  const Key('sign-in-again-different-account'),
);

Finder _tile(int index) => find.byKey(Key('image-attachment-tile-$index'));
Finder _inDialog(String text) =>
    find.descendant(of: _dialog, matching: find.text(text));

/// What one onSubmit call received.
typedef _Submission = ({
  String content,
  List<RichTextFacet> facets,
  ImagesEmbedInput? embed,
});

/// Each embed image's blob link and alt, in embed order.
List<(Object?, String?)> _blobLinksAndAlts(ImagesEmbedInput embed) => [
  for (final image in embed.images)
    ((image.blob['ref'] as Map<String, dynamic>)[r'$link'], image.alt),
];

void main() {
  late ReplyScreenHarness harness;
  late FakePostImagePicker picker;
  late Directory directory;
  late Directory conversionDirectory;
  late UploadScript uploads;
  late List<_Submission> submitted;

  setUp(() {
    harness = ReplyScreenHarness();
    // Signed in as did:plc:testuser (the harness DID)
    when(harness.auth.isAuthenticated).thenReturn(true);
    picker = FakePostImagePicker();
    directory = Directory.systemTemp.createTempSync('reply_sign_in');
    conversionDirectory = Directory.systemTemp.createTempSync(
      'reply_sign_in_conversions',
    );
    uploads = UploadScript(harness.api, {'a': tinyPng4x3, 'b': tinyJpeg4x3});
    submitted = [];
  });

  tearDown(() {
    harness.dispose();
    directory.deleteSync(recursive: true);
    conversionDirectory.deleteSync(recursive: true);
  });

  String writeImage(String name, Uint8List bytes) {
    final path = '${directory.path}/$name';
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  String replyText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  /// Opens the reply screen, types "Two photos", picks two images with alts
  /// "a cat" and "a dog", makes the second upload throw [failure] once, and
  /// taps Send.
  Future<void> sendWithSecondUploadFailing(
    WidgetTester tester,
    Exception failure,
  ) async {
    final originalPicker = ImagePickerPlatform.instance;
    addTearDown(() => ImagePickerPlatform.instance = originalPicker);
    ImagePickerPlatform.instance = picker;

    await harness.pumpBase(tester);
    await harness.pushReply(
      tester,
      comment: harness.threadComment('at://did:plc:author/comment/1'),
      imagePreparer: ImagePreparer(
        encoder: RecordingImageEncoder(),
        temporaryDirectory: () async => conversionDirectory,
      ),
      onSubmit: (content, facets, embed) async {
        submitted.add((content: content, facets: facets, embed: embed));
      },
    );
    await tester.enterText(find.byType(TextField), 'Two photos');
    await tester.pump();

    picker.nextMulti = [
      XFile(writeImage('a.png', tinyPng4x3)),
      XFile(writeImage('b.jpg', tinyJpeg4x3)),
    ];
    await tester.tap(replyAddImage);
    await pumpFrames(tester);
    await tester.tap(find.text('Choose from Gallery'));
    await settleRealIo(tester, until: () => _tile(1).evaluate().isNotEmpty);
    await setImageAlt(tester, 0, 'a cat');
    await setImageAlt(tester, 1, 'a dog');

    uploads.failOnceWith['b'] = failure;
    await tester.tap(find.text('Send'));
    await settleRealIo(
      tester,
      until: () => find.text('Send').evaluate().isNotEmpty,
    );

    expect(uploads.calls, ['a', 'b']);
    expect(submitted, isEmpty);
  }

  /// The reply text and both tiles are still on the screen.
  void expectReplyKept(WidgetTester tester) {
    expect(find.byType(ReplyScreen), findsOneWidget);
    expect(replyText(tester), 'Two photos');
    expect(_tile(0), findsOneWidget);
    expect(_tile(1), findsOneWidget);
    expect(_tile(2), findsNothing);
  }

  group('B5 an upload rejected for a missing upload permission', () {
    for (final errorCode in ['MissingBlobScope', 'PermissionDenied']) {
      testWidgets('($errorCode) shows the sign-in-again dialog; Sign in '
          'keeps the reply, and the next Send uploads only the second image '
          'and submits the text with both blobs and alts', (tester) async {
        var reauthenticateCalls = 0;
        when(harness.auth.reauthenticate()).thenAnswer((_) async {
          reauthenticateCalls++;
          // The session is replaced for the same account
          harness.notifyAuthListeners();
          return ReauthenticationResult.success;
        });
        await sendWithSecondUploadFailing(
          tester,
          ApiException(
            'Upload not permitted',
            statusCode: 403,
            errorCode: errorCode,
          ),
        );

        expect(_dialog, findsOneWidget);
        expect(_inDialog('Sign in again to upload images'), findsOneWidget);
        expect(_inDialog('Sign in'), findsOneWidget);
        expect(_inDialog('Cancel'), findsOneWidget);

        await tester.tap(_inDialog('Sign in'));
        await pumpFrames(tester);

        expect(reauthenticateCalls, 1);
        expect(_dialog, findsNothing);
        expectReplyKept(tester);
        expect(uploads.calls, ['a', 'b']);
        expect(submitted, isEmpty);

        await tester.tap(find.text('Send'));
        await settleRealIo(tester, until: () => submitted.isNotEmpty);

        expect(uploads.calls, ['a', 'b', 'b']);
        expect(submitted.single.content, 'Two photos');
        expect(_blobLinksAndAlts(submitted.single.embed!), [
          ('bafkrei-a', 'a cat'),
          ('bafkrei-b', 'a dog'),
        ]);
      });
    }
  });

  testWidgets('B7 after the MissingBlobScope dialog, Sign in returning '
      'differentAccount shows the different-account message and keeps the '
      'reply unsent', (tester) async {
    when(harness.auth.reauthenticate())
        .thenAnswer((_) async => ReauthenticationResult.differentAccount);
    await sendWithSecondUploadFailing(
      tester,
      ApiException(
        'Upload not permitted',
        statusCode: 403,
        errorCode: 'MissingBlobScope',
      ),
    );
    expect(_dialog, findsOneWidget);

    await tester.tap(_inDialog('Sign in'));
    await pumpFrames(tester);

    verify(harness.auth.reauthenticate()).called(1);
    expect(_differentAccount, findsOneWidget);
    expectReplyKept(tester);
    expect(uploads.calls, ['a', 'b']);
    expect(submitted, isEmpty);
  });
}
