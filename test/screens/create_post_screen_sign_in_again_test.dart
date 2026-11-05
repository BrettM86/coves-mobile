import 'dart:io';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/community.dart';
import 'package:coves_flutter/models/post_embed_input.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/utils/image_preparation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/create_post_harness.dart';
import '../test_helpers/fake_image_encoder.dart';
import '../test_helpers/image_fixtures.dart';
import '../test_helpers/image_picking_fakes.dart';
import '../test_helpers/image_strip_helpers.dart';
import '../test_helpers/pump_helpers.dart';
import '../test_helpers/test_mocks.dart';

final _addImage = find.byKey(const Key('create-post-add-image'));
final _postButton = find.descendant(
  of: find.byType(AppBar),
  matching: find.byType(TextButton),
);
final _dialog = find.byKey(const Key('sign-in-again-dialog'));
final _differentAccount = find.byKey(
  const Key('sign-in-again-different-account'),
);
final _failed = find.byKey(const Key('sign-in-again-failed'));
final _titleField = find.widgetWithText(TextField, 'Two photos');
final _urlField = find.widgetWithText(TextField, 'https://example.com/article');
final _bodyField = find.widgetWithText(TextField, 'Shot on the hill');

Finder _tile(int index) => find.byKey(Key('image-attachment-tile-$index'));
Finder _inDialog(String text) =>
    find.descendant(of: _dialog, matching: find.text(text));

/// Each embed image's blob link and alt, in embed order.
List<(Object?, String?)> _blobLinksAndAlts(ImagesEmbedInput embed) => [
  for (final image in embed.images)
    ((image.blob['ref'] as Map<String, dynamic>)[r'$link'], image.alt),
];

void main() {
  late FakeAuthProvider auth;
  late MockCovesApiService api;
  late FakePostImagePicker picker;
  late Directory directory;
  late Directory conversionDirectory;
  late UploadScript uploads;
  late String imageA;
  late String imageB;

  setUp(() {
    auth = FakeAuthProvider();
    api = MockCovesApiService();
    stubTestCove(api);
    picker = FakePostImagePicker();
    directory = Directory.systemTemp.createTempSync('create_post_sign_in');
    conversionDirectory = Directory.systemTemp.createTempSync(
      'create_post_sign_in_conversions',
    );
    uploads = UploadScript(api, {'a': tinyPng4x3, 'b': tinyJpeg4x3});
    imageA = '${directory.path}/a.png';
    File(imageA).writeAsBytesSync(tinyPng4x3);
    imageB = '${directory.path}/b.jpg';
    File(imageB).writeAsBytesSync(tinyJpeg4x3);
    when(
      api.createPost(
        community: anyNamed('community'),
        title: anyNamed('title'),
        content: anyNamed('content'),
        facets: anyNamed('facets'),
        embed: anyNamed('embed'),
        langs: anyNamed('langs'),
        labels: anyNamed('labels'),
      ),
    ).thenAnswer(
      (_) async => const CreatePostResponse(
        uri: 'at://did:plc:testuser/social.coves.community.post/created',
        cid: 'created-cid',
      ),
    );
  });

  tearDown(() {
    directory.deleteSync(recursive: true);
    conversionDirectory.deleteSync(recursive: true);
  });

  void verifyCreatePostNeverCalled() {
    verifyNever(
      api.createPost(
        community: anyNamed('community'),
        title: anyNamed('title'),
        content: anyNamed('content'),
        facets: anyNamed('facets'),
        embed: anyNamed('embed'),
        langs: anyNamed('langs'),
        labels: anyNamed('labels'),
      ),
    );
  }

  Future<void> tapPost(WidgetTester tester) async {
    await tester.tap(_postButton);
    await pumpFrames(tester);
  }

  /// Pumps the composer with a community, title, URL, body and two images
  /// with alts "a cat" and "a dog", where the upload of the second image
  /// throws [failure] once, then taps Post.
  Future<void> postWithSecondUploadFailing(
    WidgetTester tester,
    Exception failure,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final originalPicker = ImagePickerPlatform.instance;
    addTearDown(() => ImagePickerPlatform.instance = originalPicker);
    ImagePickerPlatform.instance = picker;

    await pumpWithPostDetailProviders(
      tester,
      auth: auth,
      api: api,
      theme: AppTheme.dark,
      imagePreparer: ImagePreparer(
        encoder: RecordingImageEncoder(),
        temporaryDirectory: () async => conversionDirectory,
      ),
    );
    await selectCommunity(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Title'),
      'Two photos',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'URL'),
      'https://example.com/article',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'What are your thoughts?'),
      'Shot on the hill',
    );
    await tester.pump();

    picker.nextMulti = [XFile(imageA), XFile(imageB)];
    await tester.ensureVisible(_addImage);
    await tester.pump();
    await tester.tap(_addImage);
    await pumpFrames(tester);
    await tester.tap(find.text('Choose from Gallery'));
    await settleRealIo(tester, until: () => _tile(1).evaluate().isNotEmpty);
    await setImageAlt(tester, 0, 'a cat');
    await setImageAlt(tester, 1, 'a dog');

    uploads.failOnceWith['b'] = failure;
    await tapPost(tester);

    expect(uploads.calls, ['a', 'b']);
    verifyCreatePostNeverCalled();
  }

  /// The title, URL, body and both tiles are still in the composer.
  void expectComposerKept() {
    expect(_titleField, findsOneWidget);
    expect(_urlField, findsOneWidget);
    expect(_bodyField, findsOneWidget);
    expect(_tile(0), findsOneWidget);
    expect(_tile(1), findsOneWidget);
    expect(_tile(2), findsNothing);
  }

  group('B3 an upload rejected for a missing upload permission', () {
    for (final errorCode in ['MissingBlobScope', 'PermissionDenied']) {
      testWidgets('($errorCode) shows the sign-in-again dialog; Sign in '
          'keeps the form, and the next Post uploads only the second image '
          'and creates the post with both blobs and alts', (tester) async {
        await postWithSecondUploadFailing(
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

        expect(auth.reauthenticateCalls, 1);
        expect(auth.did, 'did:plc:testuser');
        expect(_dialog, findsNothing);
        expectComposerKept();
        expect(uploads.calls, ['a', 'b']);
        verifyCreatePostNeverCalled();

        await tapPost(tester);
        await pumpFrames(tester);

        expect(uploads.calls, ['a', 'b', 'b']);
        final captured = verify(
          api.createPost(
            community: captureAnyNamed('community'),
            title: captureAnyNamed('title'),
            content: captureAnyNamed('content'),
            facets: anyNamed('facets'),
            embed: captureAnyNamed('embed'),
            langs: anyNamed('langs'),
            labels: anyNamed('labels'),
          ),
        ).captured;
        expect(captured.sublist(0, 3), [
          'did:plc:community',
          'Two photos',
          'Shot on the hill',
        ]);
        final embed = captured[3];
        expect(embed, isA<ImagesWithAttachmentInput>());
        final withAttachment = embed as ImagesWithAttachmentInput;
        expect(_blobLinksAndAlts(withAttachment.images), [
          ('bafkrei-a', 'a cat'),
          ('bafkrei-b', 'a dog'),
        ]);
        expect(withAttachment.attachment.uri, 'https://example.com/article');
      });
    }

    testWidgets('(NoAuthorCredentials) shows no dialog; the tile shows its '
        'error instead', (tester) async {
      await postWithSecondUploadFailing(
        tester,
        ApiException(
          'No author credentials',
          statusCode: 403,
          errorCode: 'NoAuthorCredentials',
        ),
      );

      expect(_dialog, findsNothing);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('image-attachment-error-1')))
            .data,
        'Image 2: Coves could not use your session to upload. '
        'Sign out and sign in again, then retry.',
      );
      expect(auth.reauthenticateCalls, 0);
    });
  });

  group('B4 after the MissingBlobScope dialog', () {
    final rows =
        <
          ({
            String name,
            ReauthenticationResult? result,
            int expectedCalls,
            bool differentAccountShown,
            bool failedShown,
            bool dialogStaysOpen,
          })
        >[
          (
            name:
                'Sign in returning differentAccount shows the '
                'different-account message',
            result: ReauthenticationResult.differentAccount,
            expectedCalls: 1,
            differentAccountShown: true,
            failedShown: false,
            dialogStaysOpen: true,
          ),
          (
            name:
                'Sign in returning failed shows the failed message and '
                'keeps the dialog open',
            result: ReauthenticationResult.failed,
            expectedCalls: 1,
            differentAccountShown: false,
            failedShown: true,
            dialogStaysOpen: true,
          ),
          (
            name:
                'Sign in returning cancelled shows no different-account '
                'message',
            result: ReauthenticationResult.cancelled,
            expectedCalls: 1,
            differentAccountShown: false,
            failedShown: false,
            dialogStaysOpen: false,
          ),
          (
            name: 'Cancel closes the dialog without signing in',
            result: null,
            expectedCalls: 0,
            differentAccountShown: false,
            failedShown: false,
            dialogStaysOpen: false,
          ),
        ];
    for (final row in rows) {
      testWidgets('${row.name}; the composer keeps title, body and both '
          'tiles, no post is created, and Post stays enabled', (tester) async {
        await postWithSecondUploadFailing(
          tester,
          ApiException(
            'Upload not permitted',
            statusCode: 403,
            errorCode: 'MissingBlobScope',
          ),
        );
        expect(_dialog, findsOneWidget);

        final result = row.result;
        if (result == null) {
          await tester.tap(_inDialog('Cancel'));
        } else {
          auth.reauthenticateResult = result;
          await tester.tap(_inDialog('Sign in'));
        }
        await pumpFrames(tester);

        expect(auth.reauthenticateCalls, row.expectedCalls);
        expect(
          _differentAccount,
          row.differentAccountShown ? findsOneWidget : findsNothing,
        );
        expect(_failed, row.failedShown ? findsOneWidget : findsNothing);
        expect(_dialog, row.dialogStaysOpen ? findsOneWidget : findsNothing);
        expect(_titleField, findsOneWidget);
        expect(_bodyField, findsOneWidget);
        expect(_tile(0), findsOneWidget);
        expect(_tile(1), findsOneWidget);
        expect(uploads.calls, ['a', 'b']);
        verifyCreatePostNeverCalled();
        expect(tester.widget<TextButton>(_postButton).onPressed, isNotNull);
      });
    }
  });
}
