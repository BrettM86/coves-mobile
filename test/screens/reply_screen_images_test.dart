import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/post_embed_input.dart';
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

Finder _tile(int index) => find.byKey(Key('image-attachment-tile-$index'));
Finder _tileError(int index) =>
    find.byKey(Key('image-attachment-error-$index'));
Finder _tileRetry(int index) =>
    find.byKey(Key('image-attachment-retry-$index'));
const _preparingTile = Key('image-attachment-preparing');

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

/// A second converted JPEG, told apart from [tinyJpeg4x3] by one trailing
/// byte after its end marker.
final Uint8List _otherConvertedJpeg = Uint8List.fromList([...tinyJpeg4x3, 0]);

void main() {
  late ReplyScreenHarness harness;
  late FakePostImagePicker picker;
  late Directory directory;
  late Directory conversionDirectory;
  late ImagePreparer preparer;

  setUp(() {
    harness = ReplyScreenHarness();
    picker = FakePostImagePicker();
    directory = Directory.systemTemp.createTempSync('reply_images');
    conversionDirectory = Directory.systemTemp.createTempSync(
      'reply_image_conversions',
    );
    preparer = ImagePreparer(
      encoder: RecordingImageEncoder(),
      temporaryDirectory: () async => conversionDirectory,
    );
  });

  tearDown(() {
    harness.dispose();
    directory.deleteSync(recursive: true);
    conversionDirectory.deleteSync(recursive: true);
  });

  /// Installs the fake picker for the rest of the test.
  void installPicker() {
    final originalPicker = ImagePickerPlatform.instance;
    addTearDown(() => ImagePickerPlatform.instance = originalPicker);
    ImagePickerPlatform.instance = picker;
  }

  /// Writes [bytes] to a temp file called [name] and returns its path.
  String writeImage(String name, Uint8List bytes) {
    final path = '${directory.path}/$name';
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  /// Picks [paths] from the library in one multi-image pick through the
  /// reply toolbar and waits until [until] holds.
  Future<void> pickPaths(
    WidgetTester tester,
    List<String> paths, {
    required bool Function() until,
  }) async {
    picker.nextMulti = [for (final path in paths) XFile(path)];
    await tester.tap(replyAddImage);
    await pumpFrames(tester);
    expect(
      find.text('Choose from Gallery'),
      findsOneWidget,
      reason: 'the add-image control opens the image source sheet',
    );
    await tester.tap(find.text('Choose from Gallery'));
    await settleRealIo(tester, until: until);
  }

  /// Picks [path] from the library through the reply toolbar and waits for
  /// its tile.
  Future<void> pickFromLibrary(WidgetTester tester, String path) =>
      pickPaths(tester, [path], until: () => _tile(0).evaluate().isNotEmpty);

  /// Writes a HEIC header file called [name], which the preparer converts
  /// into a new JPEG file in [conversionDirectory].
  String writeHeic(String name) =>
      writeImage(name, headerBytes(ftyp('heic'), padTo: 64));

  /// A preparer that converts through [encoder] into [conversionDirectory].
  ImagePreparer convertingPreparer(RecordingImageEncoder encoder) =>
      ImagePreparer(
        encoder: encoder,
        temporaryDirectory: () async => conversionDirectory,
      );

  /// The local file the tile at [index] draws from.
  String tilePath(WidgetTester tester, int index) =>
      imagePathsIn(tester, _tile(index)).single;

  /// Whether [path] is a file inside [conversionDirectory].
  bool isConverted(String path) =>
      path.startsWith('${conversionDirectory.path}${Platform.pathSeparator}');

  /// The reply text field's current text.
  String replyText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  group('image-only reply', () {
    testWidgets('B4 one image and no text enables Send, and Send uploads it '
        'and submits empty content with the uploaded blob', (tester) async {
      installPicker();
      final uploads = UploadScript(harness.api, {'a': tinyPng4x3});
      final comment = harness.threadComment('at://did:plc:author/comment/1');
      ({String content, List<RichTextFacet> facets, ImagesEmbedInput? embed})?
      submitted;
      await harness.pumpBase(tester);
      await harness.pushReply(
        tester,
        comment: comment,
        imagePreparer: preparer,
        onSubmit: (content, facets, embed) async {
          submitted = (content: content, facets: facets, embed: embed);
        },
      );

      await pickFromLibrary(tester, writeImage('a.png', tinyPng4x3));

      expect(harness.sendButton(tester).onTap, isNotNull);

      await tester.tap(find.text('Send'));
      await settleRealIo(tester, until: () => submitted != null);

      expect(uploads.calls, ['a']);
      expect(submitted!.content, '');
      expect(submitted!.facets, isEmpty);
      final images = submitted!.embed!.images;
      expect(images, hasLength(1));
      expect(images.single.blob, {
        'ref': {r'$link': 'bafkrei-a'},
      });
    });

    testWidgets('B4 with no images and no text Send is disabled', (
      tester,
    ) async {
      final comment = harness.threadComment('at://did:plc:author/comment/1');
      await harness.pumpBase(tester);
      await harness.pushReply(
        tester,
        comment: comment,
        imagePreparer: preparer,
      );

      expect(harness.sendButton(tester).onTap, isNull);
    });
  });

  /// Sets the alt of the tile at [index] through the strip's alt editor.
  Future<void> setAlt(WidgetTester tester, int index, String alt) async {
    final altControl = find.byKey(Key('image-attachment-alt-$index'));
    expect(altControl, findsOneWidget, reason: 'the Alt control of $index');
    await tester.ensureVisible(altControl);
    await tester.pump();
    await tester.tap(altControl);
    await pumpFrames(tester);
    await tester.enterText(
      find.byKey(const Key('image-alt-editor-field')),
      alt,
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('image-alt-editor-save')));
    await pumpFrames(tester);
  }

  group('a reply draft with images', () {
    final closes = <String, Future<void> Function(WidgetTester)>{
      'the Cancel button': (tester) => harness.cancel(tester),
      'system back': (tester) => harness.systemBack(tester),
    };
    for (final close in closes.entries) {
      testWidgets('B5 with text, alt and two converted images, the first '
          'uploaded and the second failed, survives closing by ${close.key} '
          'and reopening, and the next Send uploads only the second', (
        tester,
      ) async {
        installPicker();
        final encoder = RecordingImageEncoder([
          tinyJpeg4x3,
          _otherConvertedJpeg,
        ]);
        final uploads = UploadScript(harness.api, {
          'a': tinyJpeg4x3,
          'b': _otherConvertedJpeg,
        })..failOnce.add('b');
        final comment = harness.threadComment('at://did:plc:author/comment/1');
        final submitted = <_Submission>[];
        Future<void> onSubmit(
          String content,
          List<RichTextFacet> facets,
          ImagesEmbedInput? embed,
        ) async {
          submitted.add((content: content, facets: facets, embed: embed));
        }

        await harness.pumpBase(tester);
        await harness.pushReply(
          tester,
          comment: comment,
          imagePreparer: convertingPreparer(encoder),
          onSubmit: onSubmit,
        );
        await tester.enterText(find.byType(TextField), 'Two photos');
        await tester.pump();
        await pickPaths(tester, [
          writeHeic('a.heic'),
          writeHeic('b.heic'),
        ], until: () => _tile(1).evaluate().isNotEmpty);
        final convertedA = tilePath(tester, 0);
        final convertedB = tilePath(tester, 1);
        expect(isConverted(convertedA), isTrue, reason: convertedA);
        expect(isConverted(convertedB), isTrue, reason: convertedB);
        await setAlt(tester, 0, 'a cat');

        await tester.tap(find.text('Send'));
        await settleRealIo(
          tester,
          until: () =>
              _tileError(1).evaluate().isNotEmpty &&
              find.text('Send').evaluate().isNotEmpty,
        );
        expect(uploads.calls, ['a', 'b']);
        expect(submitted, isEmpty);

        await close.value(tester);
        await settleRealIo(tester);

        expect(find.text('base route'), findsOneWidget);
        expect(File(convertedA).existsSync(), isTrue);
        expect(File(convertedB).existsSync(), isTrue);

        await harness.pushReply(
          tester,
          comment: comment,
          imagePreparer: convertingPreparer(encoder),
          onSubmit: onSubmit,
        );

        expect(replyText(tester), 'Two photos');
        expect(_tile(1), findsOneWidget);
        expect(_tile(2), findsNothing);
        expect(
          [tilePath(tester, 0), tilePath(tester, 1)],
          [convertedA, convertedB],
        );
        expect(File(convertedA).existsSync(), isTrue);
        expect(File(convertedB).existsSync(), isTrue);

        await tester.tap(find.text('Send'));
        await settleRealIo(tester, until: () => submitted.isNotEmpty);

        expect(uploads.calls, ['a', 'b', 'b']);
        expect(submitted.single.content, 'Two photos');
        expect(_blobLinksAndAlts(submitted.single.embed!), [
          ('bafkrei-a', 'a cat'),
          ('bafkrei-b', null),
        ]);
      });
    }

    testWidgets('B5 with one converted image and no text survives closing '
        'and reopening, and Send stays enabled', (tester) async {
      installPicker();
      final encoder = RecordingImageEncoder([tinyJpeg4x3]);
      final comment = harness.threadComment('at://did:plc:author/comment/1');
      await harness.pumpBase(tester);
      await harness.pushReply(
        tester,
        comment: comment,
        imagePreparer: convertingPreparer(encoder),
      );
      await pickFromLibrary(tester, writeHeic('a.heic'));
      final converted = tilePath(tester, 0);
      expect(isConverted(converted), isTrue, reason: converted);

      await harness.cancel(tester);
      await settleRealIo(tester);

      expect(
        harness.commentsProvider.hasDraft(parentUri: comment.comment.uri),
        isTrue,
      );
      expect(File(converted).existsSync(), isTrue);

      await harness.pushReply(
        tester,
        comment: comment,
        imagePreparer: convertingPreparer(encoder),
      );

      expect(replyText(tester), '');
      expect(_tile(0), findsOneWidget);
      expect(_tile(1), findsNothing);
      expect(tilePath(tester, 0), converted);
      expect(File(converted).existsSync(), isTrue);
      expect(harness.sendButton(tester).onTap, isNotNull);
    });
  });

  group('sending a reply with an image', () {
    testWidgets('B6 whose upload fails never calls onSubmit, shows the '
        "tile's error and Retry, and leaves Send usable", (tester) async {
      installPicker();
      final uploads = UploadScript(harness.api, {'a': tinyPng4x3})
        ..failOnce.add('a');
      final comment = harness.threadComment('at://did:plc:author/comment/1');
      final submitted = <_Submission>[];
      await harness.pumpBase(tester);
      await harness.pushReply(
        tester,
        comment: comment,
        imagePreparer: preparer,
        onSubmit: (content, facets, embed) async {
          submitted.add((content: content, facets: facets, embed: embed));
        },
      );
      await pickFromLibrary(tester, writeImage('a.png', tinyPng4x3));

      await tester.tap(find.text('Send'));
      await settleRealIo(
        tester,
        until: () =>
            _tileError(0).evaluate().isNotEmpty &&
            find.text('Send').evaluate().isNotEmpty,
      );

      expect(uploads.calls, ['a']);
      expect(submitted, isEmpty);
      expect(_tileError(0), findsOneWidget);
      expect(_tileRetry(0), findsOneWidget);
      expect(harness.sendButton(tester).onTap, isNotNull);

      await tester.tap(find.text('Send'));
      await settleRealIo(tester, until: () => submitted.isNotEmpty);

      expect(uploads.calls, ['a', 'a']);
      expect(_blobLinksAndAlts(submitted.single.embed!), [('bafkrei-a', null)]);
    });

    testWidgets('B6 a second Send tap while the upload is in flight does '
        'nothing: one upload and one onSubmit once it ends', (tester) async {
      installPicker();
      final uploads = UploadScript(harness.api, {'a': tinyPng4x3});
      final gate = Completer<void>();
      uploads.gates['a'] = gate;
      final comment = harness.threadComment('at://did:plc:author/comment/1');
      final submitted = <_Submission>[];
      await harness.pumpBase(tester);
      await harness.pushReply(
        tester,
        comment: comment,
        imagePreparer: preparer,
        onSubmit: (content, facets, embed) async {
          submitted.add((content: content, facets: facets, embed: embed));
        },
      );
      await pickFromLibrary(tester, writeImage('a.png', tinyPng4x3));

      await tester.tap(find.text('Send'));
      await settleRealIo(tester, until: () => uploads.calls.isNotEmpty);
      await tester.tap(replySendControl, warnIfMissed: false);
      await settleRealIo(tester);

      expect(uploads.calls, ['a']);
      expect(submitted, isEmpty);

      gate.complete();
      await settleRealIo(tester, until: () => submitted.isNotEmpty);
      await settleRealIo(tester);

      expect(uploads.calls, ['a']);
      expect(submitted, hasLength(1));
      expect(_blobLinksAndAlts(submitted.single.embed!), [('bafkrei-a', null)]);
    });

    testWidgets('B6 whose onSubmit fails after the upload keeps the screen '
        'and the tile, and the next Send submits the same blob without '
        'uploading again', (tester) async {
      installPicker();
      final uploads = UploadScript(harness.api, {'a': tinyPng4x3});
      final comment = harness.threadComment('at://did:plc:author/comment/1');
      final submitted = <_Submission>[];
      await harness.pumpBase(tester);
      await harness.pushReply(
        tester,
        comment: comment,
        imagePreparer: preparer,
        onSubmit: (content, facets, embed) async {
          submitted.add((content: content, facets: facets, embed: embed));
          if (submitted.length == 1) {
            throw ApiException('Rejected', statusCode: 500);
          }
        },
      );
      final path = writeImage('a.png', tinyPng4x3);
      await pickFromLibrary(tester, path);

      await tester.tap(find.text('Send'));
      await settleRealIo(
        tester,
        until: () =>
            submitted.isNotEmpty && find.text('Send').evaluate().isNotEmpty,
      );

      expect(find.byType(ReplyScreen), findsOneWidget);
      expect(tilePath(tester, 0), path);

      await tester.tap(find.text('Send'));
      await settleRealIo(tester, until: () => submitted.length == 2);

      expect(uploads.calls, ['a']);
      expect(_blobLinksAndAlts(submitted[1].embed!), [('bafkrei-a', null)]);
    });

    testWidgets('B13 a switch to another account during the upload never '
        'calls onSubmit, and the next Send uploads the image again', (
      tester,
    ) async {
      installPicker();
      final uploads = UploadScript(harness.api, {'a': tinyPng4x3});
      final gate = Completer<void>();
      uploads.gates['a'] = gate;
      final comment = harness.threadComment('at://did:plc:author/comment/1');
      final submitted = <_Submission>[];
      await harness.pumpBase(tester);
      await harness.pushReply(
        tester,
        comment: comment,
        imagePreparer: preparer,
        onSubmit: (content, facets, embed) async {
          submitted.add((content: content, facets: facets, embed: embed));
        },
      );
      await pickFromLibrary(tester, writeImage('a.png', tinyPng4x3));

      await tester.tap(find.text('Send'));
      await settleRealIo(tester, until: () => uploads.calls.isNotEmpty);
      when(harness.auth.did).thenReturn('did:plc:otheruser');
      gate.complete();
      await settleRealIo(
        tester,
        until: () => find.text('Send').evaluate().isNotEmpty,
      );

      expect(submitted, isEmpty);

      await tester.tap(find.text('Send'));
      await settleRealIo(tester, until: () => submitted.isNotEmpty);

      expect(uploads.calls, ['a', 'a']);
      expect(_blobLinksAndAlts(submitted.single.embed!), [('bafkrei-a', null)]);
    });

    testWidgets('a switch to another account between two Sends makes the '
        'second Send upload the image again', (tester) async {
      installPicker();
      final uploads = UploadScript(harness.api, {'a': tinyPng4x3});
      final comment = harness.threadComment('at://did:plc:author/comment/1');
      final submitted = <_Submission>[];
      await harness.pumpBase(tester);
      clearInteractions(harness.auth);
      await harness.pushReply(
        tester,
        comment: comment,
        imagePreparer: preparer,
        onSubmit: (content, facets, embed) async {
          submitted.add((content: content, facets: facets, embed: embed));
          if (submitted.length == 1) {
            throw ApiException('Rejected', statusCode: 500);
          }
        },
      );
      await pickFromLibrary(tester, writeImage('a.png', tinyPng4x3));

      await tester.tap(find.text('Send'));
      await settleRealIo(
        tester,
        until: () =>
            submitted.isNotEmpty && find.text('Send').evaluate().isNotEmpty,
      );
      expect(uploads.calls, ['a']);

      // Another account signs in; the auth listeners run as notifyListeners
      // would run them
      when(harness.auth.isAuthenticated).thenReturn(true);
      when(harness.auth.did).thenReturn('did:plc:otheruser');
      final listeners = verify(harness.auth.addListener(captureAny)).captured
          .cast<VoidCallback>();
      for (final listener in listeners) {
        listener();
      }
      await tester.pump();
      expect(find.byType(ReplyScreen), findsOneWidget);

      await tester.tap(find.text('Send'));
      await settleRealIo(tester, until: () => submitted.length == 2);

      expect(uploads.calls, ['a', 'a']);
      expect(_blobLinksAndAlts(submitted[1].embed!), [('bafkrei-a', null)]);
    });
  });

  group('an image still being prepared', () {
    testWidgets('B12 keeps Send disabled with text typed, and closing the '
        'screen before it is ready leaves no converted file and no draft '
        'attachment', (tester) async {
      installPicker();
      final release = Completer<void>();
      final encoder = RecordingImageEncoder([tinyJpeg4x3])..gate = release;
      final comment = harness.threadComment('at://did:plc:author/comment/1');
      await harness.pumpBase(tester);
      await harness.pushReply(
        tester,
        comment: comment,
        imagePreparer: convertingPreparer(encoder),
      );
      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pump();
      expect(harness.sendButton(tester).onTap, isNotNull);

      await pickPaths(tester, [
        writeHeic('a.heic'),
      ], until: () => encoder.requests.isNotEmpty);

      expect(find.byKey(_preparingTile), findsOneWidget);
      expect(harness.sendButton(tester).onTap, isNull);

      await harness.cancel(tester);
      release.complete();
      // The converted file is written, then deleted once the pick is found
      // dropped.
      var written = false;
      await settleRealIo(
        tester,
        until: () {
          final files = conversionDirectory.listSync();
          written = written || files.isNotEmpty;
          return written && files.isEmpty;
        },
      );

      expect(conversionDirectory.listSync(), isEmpty);
      expect(
        harness.commentsProvider.getDraft(parentUri: comment.comment.uri)?.text,
        'Hello',
      );
      expect(
        harness.commentsProvider.takeDraftAttachments(
          parentUri: comment.comment.uri,
        ),
        isEmpty,
      );
    });
  });

  /// Runs real-IO windows until [path] is gone, at most 50; the caller
  /// asserts the outcome.
  Future<void> waitForDeletion(WidgetTester tester, String path) async {
    for (var i = 0; i < 50 && File(path).existsSync(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }

  group('a reply with a converted image closed by system back mid-send', () {
    final rows =
        <
          ({
            String name,
            bool uploadFails,
            bool submitThrows,
            bool newerDraft,
            String reopenedText,
            bool reopenedShowsSent,
            bool sentFileKept,
          })
        >[
          (
            name:
                'whose upload then fails restores the text and the image '
                'on reopening, and keeps the file',
            uploadFails: true,
            submitThrows: false,
            newerDraft: false,
            reopenedText: 'Hello photo',
            reopenedShowsSent: true,
            sentFileKept: true,
          ),
          (
            name:
                'whose onSubmit then throws restores the text and the image '
                'on reopening, and the next Send submits the same blob '
                'without uploading again',
            uploadFails: false,
            submitThrows: true,
            newerDraft: false,
            reopenedText: 'Hello photo',
            reopenedShowsSent: true,
            sentFileKept: true,
          ),
          (
            name:
                'that then succeeds deletes the file and reopens to an '
                'empty draft',
            uploadFails: false,
            submitThrows: false,
            newerDraft: false,
            reopenedText: '',
            reopenedShowsSent: false,
            sentFileKept: false,
          ),
          (
            name:
                'that then fails after a second composer saved a newer '
                "image-only draft keeps the newer draft and deletes the send's "
                'file',
            uploadFails: true,
            submitThrows: false,
            newerDraft: true,
            reopenedText: '',
            reopenedShowsSent: false,
            sentFileKept: false,
          ),
        ];

    for (final row in rows) {
      testWidgets('B9 ${row.name}', (tester) async {
        installPicker();
        final encoder = RecordingImageEncoder([
          tinyJpeg4x3,
          _otherConvertedJpeg,
        ]);
        final uploads = UploadScript(harness.api, {
          'a': tinyJpeg4x3,
          'b': _otherConvertedJpeg,
        });
        final gate = Completer<void>();
        uploads.gates['a'] = gate;
        final comment = harness.threadComment('at://did:plc:author/comment/1');
        final submitted = <_Submission>[];
        Future<void> onSubmit(
          String content,
          List<RichTextFacet> facets,
          ImagesEmbedInput? embed,
        ) async {
          submitted.add((content: content, facets: facets, embed: embed));
          if (row.submitThrows && submitted.length == 1) {
            throw ApiException('Rejected', statusCode: 500);
          }
        }

        await harness.pumpBase(tester);
        await harness.pushReply(
          tester,
          comment: comment,
          imagePreparer: convertingPreparer(encoder),
          onSubmit: onSubmit,
        );
        await tester.enterText(find.byType(TextField), 'Hello photo');
        await tester.pump();
        await pickFromLibrary(tester, writeHeic('a.heic'));
        final sent = tilePath(tester, 0);
        expect(isConverted(sent), isTrue, reason: sent);

        await tester.tap(find.text('Send'));
        await settleRealIo(tester, until: () => uploads.calls.isNotEmpty);
        await harness.systemBack(tester);
        await settleRealIo(tester);

        expect(find.text('base route'), findsOneWidget);
        expect(File(sent).existsSync(), isTrue);

        String? newer;
        if (row.newerDraft) {
          await harness.pushReply(
            tester,
            comment: comment,
            imagePreparer: convertingPreparer(encoder),
            onSubmit: onSubmit,
          );
          await pickFromLibrary(tester, writeHeic('b.heic'));
          newer = tilePath(tester, 0);
          expect(isConverted(newer), isTrue, reason: newer);
          await harness.cancel(tester);
          await settleRealIo(tester);
        }

        if (row.uploadFails) {
          gate.completeError(
            ApiException(
              'Upload rate limited',
              statusCode: 429,
              errorCode: 'UploadRateLimited',
            ),
          );
        } else {
          gate.complete();
        }
        await settleRealIo(tester);
        if (!row.sentFileKept) {
          await waitForDeletion(tester, sent);
        }

        expect(File(sent).existsSync(), row.sentFileKept);

        await harness.pushReply(
          tester,
          comment: comment,
          imagePreparer: convertingPreparer(encoder),
          onSubmit: onSubmit,
        );

        expect(replyText(tester), row.reopenedText);
        if (row.reopenedShowsSent) {
          expect(_tile(0), findsOneWidget);
          expect(_tile(1), findsNothing);
          expect(tilePath(tester, 0), sent);
        } else if (newer != null) {
          expect(_tile(0), findsOneWidget);
          expect(_tile(1), findsNothing);
          expect(tilePath(tester, 0), newer);
          expect(File(newer).existsSync(), isTrue);
        } else {
          expect(_tile(0), findsNothing);
        }

        if (row.submitThrows) {
          await tester.tap(find.text('Send'));
          await settleRealIo(tester, until: () => submitted.length == 2);

          expect(uploads.calls, ['a']);
          expect(submitted[1].content, 'Hello photo');
          expect(_blobLinksAndAlts(submitted[1].embed!), [('bafkrei-a', null)]);
        }
      });
    }
  });

  /// Pushes a reply, types text, picks a HEIC that converts to a file of its
  /// own, and taps Send with its upload held at [gate]; returns the
  /// converted file's path once the upload has started.
  Future<String> sendConvertedImageHeldAtUpload(
    WidgetTester tester, {
    required Completer<void> gate,
    required ThreadViewComment comment,
    ReplySubmit? onSubmit,
  }) async {
    final uploads = UploadScript(harness.api, {'a': tinyJpeg4x3});
    uploads.gates['a'] = gate;
    await harness.pumpBase(tester);
    await harness.pushReply(
      tester,
      comment: comment,
      imagePreparer: convertingPreparer(RecordingImageEncoder([tinyJpeg4x3])),
      onSubmit: onSubmit,
    );
    await tester.enterText(find.byType(TextField), 'Hello photo');
    await tester.pump();
    await pickFromLibrary(tester, writeHeic('a.heic'));
    final sent = tilePath(tester, 0);
    expect(isConverted(sent), isTrue, reason: sent);

    await tester.tap(find.text('Send'));
    await settleRealIo(tester, until: () => uploads.calls.isNotEmpty);
    return sent;
  }

  group('a reply with a converted image closed mid-send', () {
    final closes = <String, Future<void> Function(WidgetTester)>{
      'the Cancel button': (tester) => tester.tap(find.text('Cancel')),
      'system back': (tester) => tester.binding.handlePopRoute(),
    };
    for (final close in closes.entries) {
      testWidgets('by ${close.key}, whose upload fails during the exit '
          'animation, restores the text and the image on reopening and '
          'keeps the file', (tester) async {
        installPicker();
        final gate = Completer<void>();
        final comment = harness.threadComment('at://did:plc:author/comment/1');
        final sent = await sendConvertedImageHeldAtUpload(
          tester,
          gate: gate,
          comment: comment,
        );

        await close.value(tester);
        await tester.pump();
        gate.completeError(
          ApiException(
            'Upload rate limited',
            statusCode: 429,
            errorCode: 'UploadRateLimited',
          ),
        );
        await tester.pump();
        await tester.pump();
        // The send ended while the route was still animating out
        expect(find.byType(ReplyScreen), findsOneWidget);

        await settleRealIo(tester);
        expect(find.text('base route'), findsOneWidget);
        expect(find.byType(ReplyScreen), findsNothing);
        expect(File(sent).existsSync(), isTrue);

        await harness.pushReply(tester, comment: comment);

        expect(replyText(tester), 'Hello photo');
        expect(_tile(0), findsOneWidget);
        expect(tilePath(tester, 0), sent);
        expect(File(sent).existsSync(), isTrue);
      });
    }

    testWidgets('by system back, whose send succeeds during the exit '
        'animation, deletes the file and reopens to an empty draft', (
      tester,
    ) async {
      installPicker();
      final gate = Completer<void>();
      final comment = harness.threadComment('at://did:plc:author/comment/1');
      final submitted = <_Submission>[];
      final sent = await sendConvertedImageHeldAtUpload(
        tester,
        gate: gate,
        comment: comment,
        onSubmit: (content, facets, embed) async {
          submitted.add((content: content, facets: facets, embed: embed));
        },
      );

      await tester.binding.handlePopRoute();
      await tester.pump();
      gate.complete();
      await tester.pump();
      await tester.pump();
      expect(submitted, hasLength(1));
      // The send ended while the route was still animating out
      expect(find.byType(ReplyScreen), findsOneWidget);

      await settleRealIo(tester);
      expect(find.byType(ReplyScreen), findsNothing);
      await waitForDeletion(tester, sent);
      expect(File(sent).existsSync(), isFalse);

      await harness.pushReply(tester, comment: comment);

      expect(replyText(tester), '');
      expect(_tile(0), findsNothing);
    });

    testWidgets('whose upload then fails says on the screen below that the '
        'reply was not sent', (tester) async {
      installPicker();
      final gate = Completer<void>();
      final comment = harness.threadComment('at://did:plc:author/comment/1');
      await sendConvertedImageHeldAtUpload(
        tester,
        gate: gate,
        comment: comment,
      );
      await harness.systemBack(tester);
      expect(find.text('base route'), findsOneWidget);

      gate.completeError(
        ApiException(
          'Upload rate limited',
          statusCode: 429,
          errorCode: 'UploadRateLimited',
        ),
      );
      await settleRealIo(tester);

      expect(
        find.text(
          "Your reply was not sent. You've uploaded a lot of images. "
          'Try again in ten minutes.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('during whose upload the account changes says on the screen '
        'below that nothing was sent', (tester) async {
      installPicker();
      final gate = Completer<void>();
      final comment = harness.threadComment('at://did:plc:author/comment/1');
      final submitted = <_Submission>[];
      await sendConvertedImageHeldAtUpload(
        tester,
        gate: gate,
        comment: comment,
        onSubmit: (content, facets, embed) async {
          submitted.add((content: content, facets: facets, embed: embed));
        },
      );
      await harness.systemBack(tester);
      expect(find.text('base route'), findsOneWidget);

      when(harness.auth.did).thenReturn('did:plc:otheruser');
      gate.complete();
      await settleRealIo(tester);

      expect(submitted, isEmpty);
      expect(
        find.text('Your account changed while sending, so nothing was sent'),
        findsOneWidget,
      );
    });
  });

  testWidgets('a reply with a converted image sent while the screen is open '
      'deletes the converted file once the screen closes', (tester) async {
    installPicker();
    final gate = Completer<void>()..complete();
    final comment = harness.threadComment('at://did:plc:author/comment/1');
    final submitted = <_Submission>[];
    final sent = await sendConvertedImageHeldAtUpload(
      tester,
      gate: gate,
      comment: comment,
      onSubmit: (content, facets, embed) async {
        submitted.add((content: content, facets: facets, embed: embed));
      },
    );
    await settleRealIo(
      tester,
      until: () => find.text('base route').evaluate().isNotEmpty,
    );
    await settleRealIo(tester);
    expect(submitted, hasLength(1));
    expect(find.byType(ReplyScreen), findsNothing);

    await waitForDeletion(tester, sent);

    expect(File(sent).existsSync(), isFalse);
  });
}
