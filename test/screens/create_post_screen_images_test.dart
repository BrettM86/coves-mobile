import 'dart:async';
import 'dart:io';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/community.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/post_embed_input.dart';
import 'package:coves_flutter/screens/home/post_detail_screen.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/post_change_broadcast.dart';
import 'package:coves_flutter/utils/image_format.dart';
import 'package:coves_flutter/utils/image_preparation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/create_post_harness.dart';
import '../test_helpers/fake_image_encoder.dart';
import '../test_helpers/image_fixtures.dart';
import '../test_helpers/image_picking_fakes.dart';
import '../test_helpers/image_strip_helpers.dart';
import '../test_helpers/pump_helpers.dart';
import '../test_helpers/test_mocks.dart';

const _created = CreatePostResponse(
  uri: 'at://did:plc:testuser/social.coves.community.post/created',
  cid: 'created-cid',
);

Future<CreatePostResponse> _createSucceeds() async => _created;

/// A server view of the post at [uri], as a PostReplaced broadcast carries.
PostView _replacementPost(String uri) => PostView(
  uri: uri,
  cid: 'cid-${uri.split('/').last}',
  rkey: uri.split('/').last,
  author: AuthorView(did: 'did:plc:testuser', handle: 'testuser.coves.social'),
  community: CommunityRef(did: 'did:plc:community', name: 'testcove'),
  createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
  indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
  record: const PostRecord(title: 'Replaced', content: ''),
  stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
);

final _addImage = find.byKey(const Key('create-post-add-image'));
final _strip = find.byKey(const Key('image-attachment-strip'));
final _postButton = find.descendant(
  of: find.byType(AppBar),
  matching: find.byType(TextButton),
);
final _detailGallery = find.byKey(const Key('detail-images-embed'));
final _viewer = find.byKey(const Key('image-viewer'));
final _sensitivePlaceholder = find.byKey(
  const Key('sensitive-image-placeholder'),
);

Finder _tile(int index) => find.byKey(Key('image-attachment-tile-$index'));

/// Taps the add-image control, picks [sourceLabel] in the source sheet and
/// waits until [until] holds.
Future<void> _pick(
  WidgetTester tester, {
  String sourceLabel = 'Choose from Gallery',
  required bool Function() until,
}) async {
  expect(_addImage, findsOneWidget, reason: 'the add-image control');
  await tester.ensureVisible(_addImage);
  await tester.pump();
  await tester.tap(_addImage);
  await pumpFrames(tester);
  await tester.tap(find.text(sourceLabel));
  await settleRealIo(tester, until: until);
}

/// How many images the strip holds, built or not.
int _tileCount(WidgetTester tester) {
  final list = find.descendant(
    of: _strip,
    matching: find.byType(ReorderableListView),
  );
  return list.evaluate().isEmpty
      ? 0
      : tester.widget<ReorderableListView>(list).itemCount;
}

/// The file path each strip tile draws from, in strip order.
List<String> _tilePaths(WidgetTester tester) {
  final tiles = find.descendant(
    of: _strip,
    matching: find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('image-attachment-tile-');
    }),
  );
  return [
    for (var i = 0; i < tiles.evaluate().length; i++)
      ...imagePathsIn(tester, _tile(i)),
  ];
}

void main() {
  late FakeAuthProvider auth;
  late MockCovesApiService api;
  late FakePostImagePicker picker;
  late Directory directory;
  late Directory conversionDirectory;
  late RecordingImageEncoder encoder;
  late Future<Directory> Function() conversionDirectoryLookup;

  setUp(() {
    auth = FakeAuthProvider();
    api = MockCovesApiService();
    stubTestCove(api);
    picker = FakePostImagePicker();
    directory = Directory.systemTemp.createTempSync('create_post_images');
    conversionDirectory = Directory.systemTemp.createTempSync(
      'create_post_conversions',
    );
    encoder = RecordingImageEncoder();
    conversionDirectoryLookup = () async => conversionDirectory;
  });

  tearDown(() {
    directory.deleteSync(recursive: true);
    conversionDirectory.deleteSync(recursive: true);
  });

  /// Writes [bytes] to a temp file called [name] and returns its path.
  String writeImage(String name, Uint8List bytes) {
    final path = '${directory.path}/$name';
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  /// Installs the fake picker and pumps the composer on a phone-sized
  /// surface with the providers the post detail screen needs.
  Future<void> pumpComposer(
    WidgetTester tester, {
    Size physicalSize = const Size(1080, 2400),
  }) async {
    tester.view.physicalSize = physicalSize;
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
        encoder: encoder,
        temporaryDirectory: () => conversionDirectoryLookup(),
      ),
    );
  }

  /// Picks [paths] from the library in one multi-image pick and waits until
  /// [until] holds, by default until every path has a tile.
  Future<void> pickFromLibrary(
    WidgetTester tester,
    List<String> paths, {
    bool Function()? until,
  }) async {
    final expectedTiles = _tileCount(tester) + paths.length;
    picker.nextMulti = [for (final path in paths) XFile(path)];
    await _pick(
      tester,
      until: until ?? () => _tileCount(tester) == expectedTiles,
    );
  }

  void verifyNoUploads() {
    verifyNever(
      api.uploadImage(
        any,
        any,
        cancelToken: anyNamed('cancelToken'),
        onSendProgress: anyNamed('onSendProgress'),
      ),
    );
  }

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

  /// Stubs createPost with [answer] for every call.
  void stubCreatePost(Future<CreatePostResponse> Function() answer) {
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
    ).thenAnswer((_) => answer());
  }

  group('picking images', () {
    testWidgets('picking two images from the library shows two tiles drawn '
        'from the picked files, with no upload', (tester) async {
      await pumpComposer(tester);
      final first = writeImage('first.png', tinyPng4x3);
      final second = writeImage('second.jpg', tinyJpeg4x3);

      await pickFromLibrary(tester, [first, second]);

      expect(_tilePaths(tester), [first, second]);
      verifyNoUploads();
    });

    testWidgets('remove deletes that tile, with no upload', (tester) async {
      await pumpComposer(tester);
      final first = writeImage('first.png', tinyPng4x3);
      final second = writeImage('second.jpg', tinyJpeg4x3);
      await pickFromLibrary(tester, [first, second]);

      final remove = find.byKey(const Key('image-attachment-remove-0'));
      expect(remove, findsOneWidget);
      await tester.ensureVisible(remove);
      await tester.pump();
      await tester.tap(remove);
      await pumpFrames(tester);

      expect(_tilePaths(tester), [second]);
      verifyNoUploads();
    });

    testWidgets('an unreadable picked file is reported and the readable ones '
        'are attached', (tester) async {
      await pumpComposer(tester);
      final readable = writeImage('readable.png', tinyPng4x3);

      await pickFromLibrary(tester, [
        '${directory.path}/missing.png',
        readable,
      ], until: () => _tileCount(tester) == 1);

      expect(find.text(unreadablePostImageMessage), findsOneWidget);
      expect(_tilePaths(tester), [readable]);
      verifyNoUploads();
    });

    testWidgets('a pick of a GIF over the pixel limit and a valid PNG '
        'attaches only the PNG and shows the too-many-pixels notice', (
      tester,
    ) async {
      await pumpComposer(tester);
      final oversizedGif = writeImage(
        'huge.gif',
        headerBytes(gif('GIF89a', 10000, 6000), padTo: 64),
      );
      final small = writeImage('small.png', tinyPng4x3);

      await pickFromLibrary(tester, [
        oversizedGif,
        small,
      ], until: () => _tileCount(tester) == 1);

      expect(_tilePaths(tester), [small]);
      expect(find.text(postImageTooManyPixelsMessage), findsOneWidget);
    });

    group('the picker call depends on the source and the slots left', () {
      final rows =
          <
            ({
              String name,
              int alreadyAttached,
              String sourceLabel,
              int? multiLimit,
              ImageSource? singleSource,
            })
          >[
            (
              name: 'library with 8 slots: multi-pick limited to 8',
              alreadyAttached: 0,
              sourceLabel: 'Choose from Gallery',
              multiLimit: 8,
              singleSource: null,
            ),
            (
              name: 'library with 2 slots: multi-pick limited to 2',
              alreadyAttached: 6,
              sourceLabel: 'Choose from Gallery',
              multiLimit: 2,
              singleSource: null,
            ),
            (
              name: 'library with 1 slot: single gallery pick',
              alreadyAttached: 7,
              sourceLabel: 'Choose from Gallery',
              multiLimit: null,
              singleSource: ImageSource.gallery,
            ),
            (
              name: 'camera: single camera pick',
              alreadyAttached: 0,
              sourceLabel: 'Take a Photo',
              multiLimit: null,
              singleSource: ImageSource.camera,
            ),
          ];

      for (final row in rows) {
        testWidgets('${row.name}, with no quality or size options', (
          tester,
        ) async {
          await pumpComposer(tester);
          if (row.alreadyAttached > 0) {
            await pickFromLibrary(tester, [
              for (var i = 0; i < row.alreadyAttached; i++)
                writeImage('attached-$i.png', tinyPng4x3),
            ]);
            picker.multiPicks.clear();
          }
          final next = writeImage('next.png', tinyPng1x1);
          picker
            ..nextMulti = [XFile(next)]
            ..nextSingle = XFile(next);

          await _pick(
            tester,
            sourceLabel: row.sourceLabel,
            until: () => _tileCount(tester) == row.alreadyAttached + 1,
          );

          if (row.multiLimit case final limit?) {
            expect(picker.singlePicks, isEmpty);
            expect(picker.multiPicks, hasLength(1));
            final options = picker.multiPicks.single;
            expect(options.limit, limit);
            expect(options.imageOptions.imageQuality, isNull);
            expect(options.imageOptions.maxWidth, isNull);
            expect(options.imageOptions.maxHeight, isNull);
          } else {
            expect(picker.multiPicks, isEmpty);
            expect(picker.singlePicks, hasLength(1));
            final pick = picker.singlePicks.single;
            expect(pick.source, row.singleSource);
            expect(pick.options.imageQuality, isNull);
            expect(pick.options.maxWidth, isNull);
            expect(pick.options.maxHeight, isNull);
          }
          verifyNoUploads();
        });
      }
    });
  });

  group('submitting images', () {
    late UploadScript uploads;
    late String imageC;
    late String imageB;

    setUp(() {
      uploads = UploadScript(api, {'c': tinyPng4x3, 'b': tinyJpeg4x3});
      imageC = writeImage('c.png', tinyPng4x3);
      imageB = writeImage('b.jpg', tinyJpeg4x3);
    });

    Future<void> tapPost(WidgetTester tester) async {
      await tester.tap(_postButton);
      await pumpFrames(tester);
    }

    testWidgets('a community and only images enable Post', (tester) async {
      await pumpComposer(tester);
      await selectCommunity(tester);
      expect(tester.widget<TextButton>(_postButton).onPressed, isNull);

      await pickFromLibrary(tester, [imageC]);

      expect(tester.widget<TextButton>(_postButton).onPressed, isNotNull);
    });

    testWidgets('whitespace-only text keeps Post disabled', (tester) async {
      await pumpComposer(tester);
      await selectCommunity(tester);

      await tester.enterText(find.widgetWithText(TextField, 'Title'), '   ');
      await tester.enterText(
        find.widgetWithText(TextField, 'What are your thoughts?'),
        '\n\n  ',
      );
      await tester.pump();
      expect(tester.widget<TextButton>(_postButton).onPressed, isNull);

      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'a');
      await tester.pump();
      expect(tester.widget<TextButton>(_postButton).onPressed, isNotNull);
    });

    testWidgets('a failed upload blocks the post and shows its error and '
        'Retry; Retry uploads it before Post, and Post then creates the post '
        'once with the uploaded blobs', (tester) async {
      stubCreatePost(_createSucceeds);
      uploads.failOnce.add('b');
      await pumpComposer(tester);
      await selectCommunity(tester);
      await pickFromLibrary(tester, [imageC, imageB]);

      await tapPost(tester);

      expect(uploads.calls, ['c', 'b']);
      verifyCreatePostNeverCalled();
      expect(
        tester
            .widget<Text>(find.byKey(const Key('image-attachment-error-1')))
            .data,
        "Image 2: You've uploaded a lot of images. Try again in ten minutes.",
      );
      expect(find.byKey(const Key('image-attachment-retry-1')), findsOneWidget);
      expect(find.byKey(const Key('image-attachment-error-0')), findsNothing);

      final retry = find.byKey(const Key('image-attachment-retry-1'));
      await tester.ensureVisible(retry);
      await tester.pump();
      await tester.tap(retry);
      await pumpFrames(tester);

      expect(uploads.calls, ['c', 'b', 'b']);
      verifyCreatePostNeverCalled();
      expect(find.byKey(const Key('image-attachment-error-1')), findsNothing);

      await tapPost(tester);

      expect(uploads.calls, ['c', 'b', 'b']);
      final embed = verify(
        api.createPost(
          community: anyNamed('community'),
          title: anyNamed('title'),
          content: anyNamed('content'),
          facets: anyNamed('facets'),
          embed: captureAnyNamed('embed'),
          langs: anyNamed('langs'),
          labels: anyNamed('labels'),
        ),
      ).captured.single;
      expect(embed, isA<ImagesEmbedInput>());
      expect(
        (embed as ImagesEmbedInput).images.map((image) => image.blob).toList(),
        [
          {
            'ref': {r'$link': 'bafkrei-c'},
          },
          {
            'ref': {r'$link': 'bafkrei-b'},
          },
        ],
      );
    });

    testWidgets('a failed create shows its error and keeps the tiles; the '
        'next Post creates the post without uploading again', (tester) async {
      var createCalls = 0;
      stubCreatePost(() async {
        createCalls++;
        if (createCalls == 1) {
          throw ServerException('Record write failed', statusCode: 500);
        }
        return _created;
      });
      await pumpComposer(tester);
      await selectCommunity(tester);
      await pickFromLibrary(tester, [imageC, imageB]);

      await tapPost(tester);

      expect(createCalls, 1);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(_tilePaths(tester), [imageC, imageB]);
      expect(uploads.calls, ['c', 'b']);

      await tapPost(tester);

      expect(createCalls, 2);
      expect(uploads.calls, ['c', 'b']);
    });

    testWidgets('a second tap on Post while an upload is in flight does not '
        'submit again', (tester) async {
      stubCreatePost(_createSucceeds);
      final gate = Completer<void>();
      uploads.gates['c'] = gate;
      await pumpComposer(tester);
      await selectCommunity(tester);
      await pickFromLibrary(tester, [imageC]);

      await tester.tap(_postButton);
      await tester.pump();
      await tester.tap(_postButton);
      await tester.pump();
      gate.complete();
      await pumpFrames(tester);

      expect(uploads.calls, ['c']);
      verify(
        api.createPost(
          community: anyNamed('community'),
          title: anyNamed('title'),
          content: anyNamed('content'),
          facets: anyNamed('facets'),
          embed: anyNamed('embed'),
          langs: anyNamed('langs'),
          labels: anyNamed('labels'),
        ),
      ).called(1);
    });

    testWidgets('the strip Add tile does nothing while an upload is in '
        'flight', (tester) async {
      stubCreatePost(_createSucceeds);
      final gate = Completer<void>();
      uploads.gates['c'] = gate;
      await pumpComposer(tester);
      await selectCommunity(tester);
      await pickFromLibrary(tester, [imageC]);

      await tester.tap(_postButton);
      await tester.pump();
      final addTile = find.byKey(const Key('image-attachment-add'));
      await tester.ensureVisible(addTile);
      await tester.pump();
      await tester.tap(addTile);
      await pumpFrames(tester);

      expect(find.text('Choose from Gallery'), findsNothing);
      gate.complete();
      await pumpFrames(tester);
    });

    testWidgets('remove and Retry do nothing while a submit is running', (
      tester,
    ) async {
      stubCreatePost(_createSucceeds);
      final gate = Completer<void>();
      uploads.gates['c'] = gate;
      uploads.failOnce.add('b');
      await pumpComposer(tester);
      await selectCommunity(tester);
      await pickFromLibrary(tester, [imageC, imageB]);

      await tester.tap(_postButton);
      await pumpFrames(tester);
      final retry = find.byKey(const Key('image-attachment-retry-1'));
      expect(retry, findsOneWidget);
      await tester.ensureVisible(retry);
      await tester.pump();
      await tester.tap(retry);
      await pumpFrames(tester);
      final remove = find.byKey(const Key('image-attachment-remove-0'));
      await tester.tap(remove);
      await pumpFrames(tester);

      expect(uploads.calls, ['c', 'b']);
      expect(_tilePaths(tester), [imageC, imageB]);
      gate.complete();
      await pumpFrames(tester);
      verifyCreatePostNeverCalled();
    });

    testWidgets('images picked after Post was tapped are not attached, and '
        'the post is created with the images it was submitted with', (
      tester,
    ) async {
      stubCreatePost(_createSucceeds);
      final uploadGate = Completer<void>();
      uploads.gates['c'] = uploadGate;
      await pumpComposer(tester);
      await selectCommunity(tester);
      await pickFromLibrary(tester, [imageC]);

      final pickerGate = Completer<List<XFile>>();
      picker.multiGate = pickerGate;
      await tester.ensureVisible(_addImage);
      await tester.pump();
      await tester.tap(_addImage);
      await pumpFrames(tester);
      await tester.tap(find.text('Choose from Gallery'));
      await pumpFrames(tester);
      await tester.tap(_postButton);
      await tester.pump();
      pickerGate.complete([XFile(imageB)]);
      await settleRealIo(tester);
      uploadGate.complete();
      await pumpFrames(tester);
      await pumpFrames(tester);

      expect(uploads.calls, ['c']);
      final embed = verify(
        api.createPost(
          community: anyNamed('community'),
          title: anyNamed('title'),
          content: anyNamed('content'),
          facets: anyNamed('facets'),
          embed: captureAnyNamed('embed'),
          langs: anyNamed('langs'),
          labels: anyNamed('labels'),
        ),
      ).captured.single;
      expect(
        (embed as ImagesEmbedInput).images.map((image) => image.blob).toList(),
        [
          {
            'ref': {r'$link': 'bafkrei-c'},
          },
        ],
      );
    });

    testWidgets('an account switch while images upload discards their '
        'blobs, so the next Post uploads them again under the new account', (
      tester,
    ) async {
      stubCreatePost(_createSucceeds);
      final gate = Completer<void>();
      uploads.gates['c'] = gate;
      await pumpComposer(tester);
      await selectCommunity(tester);
      await pickFromLibrary(tester, [imageC]);

      await tester.tap(_postButton);
      await tester.pump();
      auth.setAuthenticated(
        value: true,
        did: 'did:plc:otheruser',
        handle: 'otheruser.coves.social',
      );
      gate.complete();
      await pumpFrames(tester);

      expect(
        find.text('Your account changed while posting, so nothing was posted'),
        findsOneWidget,
      );
      verifyCreatePostNeverCalled();
      expect(_tilePaths(tester), [imageC]);

      uploads.gates.remove('c');
      await tapPost(tester);

      expect(uploads.calls, ['c', 'c']);
      verify(
        api.createPost(
          community: anyNamed('community'),
          title: anyNamed('title'),
          content: anyNamed('content'),
          facets: anyNamed('facets'),
          embed: anyNamed('embed'),
          langs: anyNamed('langs'),
          labels: anyNamed('labels'),
        ),
      ).called(1);
    });

    testWidgets('a second tap on Post while the create is in flight does not '
        'create twice', (tester) async {
      final gate = Completer<CreatePostResponse>();
      var createCalls = 0;
      stubCreatePost(() {
        createCalls++;
        return gate.future;
      });
      await pumpComposer(tester);
      await selectCommunity(tester);
      await pickFromLibrary(tester, [imageC]);

      await tester.tap(_postButton);
      await pumpFrames(tester);
      expect(createCalls, 1);
      await tester.tap(_postButton);
      await tester.pump();
      gate.complete(_created);
      await pumpFrames(tester);

      expect(createCalls, 1);
      expect(uploads.calls, ['c']);
    });
  });

  group('the optimistic post renders its images from the local files', () {
    late String imageC;
    late String imageB;
    late String imageA;

    setUp(() {
      UploadScript(api, {'c': tinyPng4x3, 'b': tinyJpeg4x3, 'a': tinyPng1x1});
      stubCreatePost(_createSucceeds);
      imageC = writeImage('c.png', tinyPng4x3);
      imageB = writeImage('b.jpg', tinyJpeg4x3);
      imageA = writeImage('a.png', tinyPng1x1);
    });

    /// Posts the three images, optionally labelled NSFW, and lands on the
    /// optimistic post detail.
    Future<void> postImages(WidgetTester tester, {bool nsfw = false}) async {
      await pumpComposer(tester);
      await selectCommunity(tester);
      await pickFromLibrary(tester, [imageC, imageB, imageA]);
      if (nsfw) {
        await tester.ensureVisible(find.byType(Switch));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
      }

      await tester.tap(_postButton);
      await pumpFrames(tester);
      await pumpFrames(tester);

      expect(find.byType(PostDetailScreen), findsOneWidget);
    }

    /// Pages through the detail gallery, checking every page draws from a
    /// local file, then opens the lightbox on the last page and checks it
    /// draws from that page's file.
    Future<void> expectGalleryAndLightboxFromFiles(WidgetTester tester) async {
      expect(_detailGallery, findsOneWidget);
      await tester.ensureVisible(_detailGallery);
      await pumpFrames(tester);

      final seen = <String>[...imagePathsIn(tester, _detailGallery)];
      for (var page = 1; page < 3; page++) {
        await tester.fling(_detailGallery, const Offset(-300, 0), 1500);
        await pumpFrames(tester);
        for (final path in imagePathsIn(tester, _detailGallery)) {
          if (!seen.contains(path)) {
            seen.add(path);
          }
        }
      }
      expect(seen, [imageC, imageB, imageA]);

      await tester.tap(_detailGallery);
      await pumpFrames(tester);

      expect(_viewer, findsOneWidget);
      final viewerPaths = imagePathsIn(tester, _viewer);
      expect(viewerPaths, isNotEmpty);
      expect(viewerPaths, contains(imageA));
    }

    testWidgets('in the native gallery and the lightbox, and the files '
        'outlive the form reset', (tester) async {
      await postImages(tester);

      await expectGalleryAndLightboxFromFiles(tester);
      for (final path in [imageC, imageB, imageA]) {
        expect(File(path).existsSync(), isTrue, reason: path);
      }
    });

    testWidgets('concealed behind a sensitive placeholder drawn from the '
        'local file, and from the files once revealed', (tester) async {
      await postImages(tester, nsfw: true);

      expect(_sensitivePlaceholder, findsOneWidget);
      expect(_detailGallery, findsNothing);
      expect(imagePathsIn(tester, _sensitivePlaceholder), [imageC]);

      await tester.ensureVisible(_sensitivePlaceholder);
      await tester.pump();
      await tester.tap(_sensitivePlaceholder);
      await pumpFrames(tester);

      await expectGalleryAndLightboxFromFiles(tester);
    });
  });

  group('a converted HEIC image', () {
    /// Writes a HEIC file to [directory] and returns its path.
    String writeHeic() =>
        writeImage('photo.heic', headerBytes(ftyp('heic'), padTo: 64));

    /// Picks a HEIC and returns the path of the converted file its one tile
    /// draws from, checking it is a new file inside the conversion directory.
    Future<String> pickConvertedHeic(WidgetTester tester) async {
      final heic = writeHeic();
      await pickFromLibrary(tester, [heic]);

      final paths = _tilePaths(tester);
      expect(paths, hasLength(1));
      final converted = paths.single;
      expect(converted, isNot(heic));
      expect(
        converted.startsWith(
          '${conversionDirectory.path}${Platform.pathSeparator}',
        ),
        isTrue,
        reason: '$converted inside ${conversionDirectory.path}',
      );
      expect(File(converted).existsSync(), isTrue);
      return converted;
    }

    testWidgets('is drawn from a new file in the temp directory, survives '
        'the post and a replacement of another post, renders in the '
        'optimistic post, and is deleted when the created post is replaced', (
      tester,
    ) async {
      encoder = RecordingImageEncoder([tinyJpeg4x3]);
      UploadScript(api, {'h': tinyJpeg4x3});
      stubCreatePost(_createSucceeds);
      await pumpComposer(tester);
      await selectCommunity(tester);

      final converted = await pickConvertedHeic(tester);

      await tester.tap(_postButton);
      await pumpFrames(tester);
      await pumpFrames(tester);

      final detail = find.byType(PostDetailScreen);
      expect(detail, findsOneWidget);
      expect(File(converted).existsSync(), isTrue);
      expect(_detailGallery, findsOneWidget);
      await tester.ensureVisible(_detailGallery);
      await pumpFrames(tester);
      expect(imagePathsIn(tester, _detailGallery), [converted]);

      final broadcast = tester.element(detail).read<PostChangeBroadcast>()
        ..replacePost(
          _replacementPost(
            'at://did:plc:testuser/social.coves.community.post/other',
          ),
        );
      await settleRealIo(tester);

      expect(File(converted).existsSync(), isTrue);

      broadcast.replacePost(_replacementPost(_created.uri));
      await settleRealIo(tester, until: () => !File(converted).existsSync());

      expect(File(converted).existsSync(), isFalse);
    });

    testWidgets('survives a same-URI replacement that still draws from it, '
        'such as a moderation update of the optimistic post', (tester) async {
      encoder = RecordingImageEncoder([tinyJpeg4x3]);
      UploadScript(api, {'h': tinyJpeg4x3});
      stubCreatePost(_createSucceeds);
      await pumpComposer(tester);
      await selectCommunity(tester);
      final converted = await pickConvertedHeic(tester);

      await tester.tap(_postButton);
      await pumpFrames(tester);
      await pumpFrames(tester);
      final detail = find.byType(PostDetailScreen);
      expect(detail, findsOneWidget);
      final optimistic = tester.widget<PostDetailScreen>(detail).post.post;
      expect(optimistic.uri, _created.uri);

      tester
          .element(detail)
          .read<PostChangeBroadcast>()
          .replacePost(
            optimistic.copyWith(
              stats: PostStats(
                upvotes: 1,
                downvotes: 0,
                score: 1,
                commentCount: 0,
              ),
            ),
          );
      await settleRealIo(tester);

      expect(File(converted).existsSync(), isTrue);
      await tester.ensureVisible(_detailGallery);
      await pumpFrames(tester);
      expect(imagePathsIn(tester, _detailGallery), [converted]);
    });

    group('a three-image pick whose second image fails', () {
      List<String> writeThreeHeics() => [
        for (final name in ['one', 'two', 'three'])
          writeImage('$name.heic', headerBytes(ftyp('heic'), padTo: 64)),
      ];

      testWidgets('to save attaches the other two, shows the notice and '
          'leaves only their files', (tester) async {
        encoder = RecordingImageEncoder([
          tinyJpeg4x3,
          tinyJpeg4x3,
          tinyJpeg4x3,
        ]);
        var lookups = 0;
        conversionDirectoryLookup = () async => ++lookups == 2
            ? Directory('${conversionDirectory.path}/missing')
            : conversionDirectory;
        await pumpComposer(tester);

        await pickFromLibrary(
          tester,
          writeThreeHeics(),
          until: () => _tileCount(tester) == 2,
        );

        final paths = _tilePaths(tester);
        expect(paths, hasLength(2));
        expect(find.text(postImageNotSavedMessage), findsOneWidget);
        expect(
          conversionDirectory
              .listSync()
              .whereType<File>()
              .map((file) => file.path)
              .toSet(),
          paths.toSet(),
        );
      });

      testWidgets('with an unexpected error deletes the first prepared file', (
        tester,
      ) async {
        encoder = RecordingImageEncoder([
          tinyJpeg4x3,
          StateError('unexpected'),
          tinyJpeg4x3,
        ]);
        await pumpComposer(tester);

        picker.nextMulti = [for (final path in writeThreeHeics()) XFile(path)];
        // The error escapes _addImages; the pick starts in a guarded zone so
        // the test can see it.
        final errors = <Object>[];
        await tester.ensureVisible(_addImage);
        await tester.pump();
        await runZonedGuarded(
          () => tester.tap(_addImage),
          (error, _) => errors.add(error),
        );
        await pumpFrames(tester);
        await tester.tap(find.text('Choose from Gallery'));
        await settleRealIo(
          tester,
          until: () =>
              errors.isNotEmpty && conversionDirectory.listSync().isEmpty,
        );

        expect(errors.single, isA<StateError>());
        expect(encoder.requests, hasLength(2));
        expect(_tilePaths(tester), isEmpty);
        expect(conversionDirectory.listSync(), isEmpty);
      });
    });

    testWidgets('is deleted when the composer is discarded', (tester) async {
      encoder = RecordingImageEncoder([tinyJpeg4x3]);
      await pumpComposer(tester);

      final converted = await pickConvertedHeic(tester);

      await tester.pumpWidget(const SizedBox());
      await settleRealIo(tester, until: () => !File(converted).existsSync());

      expect(File(converted).existsSync(), isFalse);
    });

    testWidgets('is deleted when the optimistic post it was posted with is '
        'popped', (tester) async {
      encoder = RecordingImageEncoder([tinyJpeg4x3]);
      UploadScript(api, {'h': tinyJpeg4x3});
      stubCreatePost(_createSucceeds);
      await pumpComposer(tester);
      await selectCommunity(tester);
      final converted = await pickConvertedHeic(tester);

      await tester.tap(_postButton);
      await pumpFrames(tester);
      await pumpFrames(tester);
      final detail = find.byType(PostDetailScreen);
      expect(detail, findsOneWidget);
      expect(File(converted).existsSync(), isTrue);

      Navigator.of(tester.element(detail)).pop();
      // The route is disposed once its pop transition ends.
      await pumpFrames(tester);
      await settleRealIo(tester, until: () => !File(converted).existsSync());

      expect(find.byType(PostDetailScreen), findsNothing);
      expect(File(converted).existsSync(), isFalse);
    });

    testWidgets('while converting shows a preparing indicator and keeps '
        'Post disabled; when done the tile appears and Post enables', (
      tester,
    ) async {
      final release = Completer<void>();
      encoder = RecordingImageEncoder([tinyJpeg4x3])..gate = release;
      stubCreatePost(_createSucceeds);
      await pumpComposer(tester);
      await selectCommunity(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'a');
      await tester.pump();
      expect(tester.widget<TextButton>(_postButton).onPressed, isNotNull);

      await pickFromLibrary(tester, [
        writeHeic(),
      ], until: () => encoder.requests.length == 1);

      expect(encoder.requests, hasLength(1));
      expect(find.byKey(const Key('image-attachment-preparing')), findsOne);
      expect(find.bySemanticsLabel('Preparing image…'), findsOne);
      expect(tester.widget<TextButton>(_postButton).onPressed, isNull);
      await tester.tap(_postButton);
      await pumpFrames(tester);
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

      release.complete();
      await settleRealIo(tester, until: () => _tilePaths(tester).isNotEmpty);

      expect(_tilePaths(tester), hasLength(1));
      expect(find.byKey(const Key('image-attachment-preparing')), findsNothing);
      expect(tester.widget<TextButton>(_postButton).onPressed, isNotNull);
    });

    testWidgets('whose conversion finishes after the composer was discarded '
        'is not attached and leaves no file', (tester) async {
      final release = Completer<void>();
      encoder = RecordingImageEncoder([tinyJpeg4x3])..gate = release;
      await pumpComposer(tester);
      await selectCommunity(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'a');
      await tester.pump();

      await pickFromLibrary(tester, [
        writeHeic(),
      ], until: () => encoder.requests.length == 1);

      expect(encoder.requests, hasLength(1));

      await tester.pumpWidget(const SizedBox());
      release.complete();
      // The converted file is written, then deleted once the pick is
      // found dropped.
      var written = false;
      await settleRealIo(
        tester,
        until: () {
          final files = conversionDirectory.listSync();
          written = written || files.isNotEmpty;
          return written && files.isEmpty;
        },
      );

      expect(_tilePaths(tester), isEmpty);
      expect(conversionDirectory.listSync(), isEmpty);
    });
  });

  group('alt text and reorder', () {
    late String imageA;
    late String imageB;
    late String imageC;

    setUp(() {
      UploadScript(api, {'a': tinyPng4x3, 'b': tinyJpeg4x3, 'c': tinyPng1x1});
      stubCreatePost(_createSucceeds);
      imageA = writeImage('a.png', tinyPng4x3);
      imageB = writeImage('b.jpg', tinyJpeg4x3);
      imageC = writeImage('c.png', tinyPng1x1);
    });

    testWidgets('alt set on the second image through the editor and the '
        'first tile long-press-dragged to the end: the post is created with '
        'b, c, a and alt "a cat" on b only, and the optimistic post shows '
        'the same', (tester) async {
      await pumpComposer(tester, physicalSize: const Size(1800, 2400));
      await selectCommunity(tester);
      await pickFromLibrary(tester, [imageA, imageB, imageC]);
      expect(_tilePaths(tester), [imageA, imageB, imageC]);

      final altControl = find.byKey(const Key('image-attachment-alt-1'));
      expect(altControl, findsOneWidget, reason: 'the Alt control of tile 1');
      await tester.ensureVisible(altControl);
      await tester.pump();
      await tester.tap(altControl);
      await pumpFrames(tester);
      await tester.enterText(
        find.byKey(const Key('image-alt-editor-field')),
        '  a cat  ',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('image-alt-editor-save')));
      await pumpFrames(tester);

      await longPressDrag(tester, _tile(0), _tile(2));
      expect(_tilePaths(tester), [imageB, imageC, imageA]);

      await tester.tap(_postButton);
      await pumpFrames(tester);
      await pumpFrames(tester);

      final embed = verify(
        api.createPost(
          community: anyNamed('community'),
          title: anyNamed('title'),
          content: anyNamed('content'),
          facets: anyNamed('facets'),
          embed: captureAnyNamed('embed'),
          langs: anyNamed('langs'),
          labels: anyNamed('labels'),
        ),
      ).captured.single;
      expect(
        (embed as ImagesEmbedInput).images
            .map(
              (image) => (
                (image.blob['ref'] as Map<String, dynamic>)[r'$link'],
                image.alt,
              ),
            )
            .toList(),
        [('bafkrei-b', 'a cat'), ('bafkrei-c', null), ('bafkrei-a', null)],
      );

      expect(find.byType(PostDetailScreen), findsOneWidget);
      final optimistic = tester
          .widget<PostDetailScreen>(find.byType(PostDetailScreen))
          .post
          .post
          .embed;
      expect(optimistic, isA<ImagesPostEmbed>());
      expect(
        (optimistic! as ImagesPostEmbed).images
            .map((image) => (image.localFile?.path, image.alt))
            .toList(),
        [(imageB, 'a cat'), (imageC, null), (imageA, null)],
      );
    });
  });

  group('a GIF attachment', () {
    testWidgets('marks its optimistic image as a GIF and a JPEG as not', (
      tester,
    ) async {
      UploadScript(api, {'g': animatedGif3x2, 'b': tinyJpeg4x3});
      stubCreatePost(_createSucceeds);
      final gifPath = writeImage('g.gif', animatedGif3x2);
      final jpegPath = writeImage('b.jpg', tinyJpeg4x3);

      await pumpComposer(tester);
      await selectCommunity(tester);
      await pickFromLibrary(tester, [gifPath, jpegPath]);

      await tester.tap(_postButton);
      await pumpFrames(tester);
      await pumpFrames(tester);

      expect(find.byType(PostDetailScreen), findsOneWidget);
      final optimistic = tester
          .widget<PostDetailScreen>(find.byType(PostDetailScreen))
          .post
          .post
          .embed;
      expect(optimistic, isA<ImagesPostEmbed>());
      expect(
        (optimistic! as ImagesPostEmbed).images
            .map((image) => (image.localFile?.path, image.isGif))
            .toList(),
        [(gifPath, true), (jpegPath, false)],
      );
    });
  });
}
