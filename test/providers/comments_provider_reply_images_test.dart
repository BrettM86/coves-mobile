import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/post_embed_input.dart';
import 'package:coves_flutter/providers/comments_provider.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/comment_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/test_mocks.dart';

const _postUri = 'at://did:plc:test/social.coves.post.record/123';
const _postCid = 'test-post-cid';

const _blob = <String, dynamic>{
  r'$type': 'blob',
  'ref': {r'$link': 'bafkrei-reply'},
  'mimeType': 'image/png',
  'size': 1234,
};

const _oneImage = ImagesEmbedInput(
  images: [EmbedImageInput(blob: _blob, alt: 'a cat')],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAuthProvider auth;
  late MockCovesApiService api;
  late MockCommentService commentService;
  late CommentsProvider provider;

  setUp(() {
    auth = MockAuthProvider();
    api = MockCovesApiService();
    commentService = MockCommentService();
    when(auth.isAuthenticated).thenReturn(true);
    when(
      api.getComments(
        postUri: anyNamed('postUri'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        depth: anyNamed('depth'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((_) async => CommentsResponse(post: {}, comments: []));
    when(
      commentService.createComment(
        rootUri: anyNamed('rootUri'),
        rootCid: anyNamed('rootCid'),
        parentUri: anyNamed('parentUri'),
        parentCid: anyNamed('parentCid'),
        content: anyNamed('content'),
        contentFacets: anyNamed('contentFacets'),
        embed: anyNamed('embed'),
      ),
    ).thenAnswer(
      (_) async => const CreateCommentResponse(
        uri: 'at://did:plc:test/social.coves.community.comment/new',
        cid: 'bafy-new',
      ),
    );
    provider = CommentsProvider(
      auth,
      postUri: _postUri,
      postCid: _postCid,
      apiService: api,
      voteProvider: MockVoteProvider(),
      commentService: commentService,
      indexingRetryDelays: const [Duration.zero],
    );
  });

  tearDown(() => provider.dispose());

  /// The content, facets and embed of the one createComment call made.
  ({String content, List<RichTextFacet>? facets, ImagesEmbedInput? embed})
  sent() {
    final captured = verify(
      commentService.createComment(
        rootUri: anyNamed('rootUri'),
        rootCid: anyNamed('rootCid'),
        parentUri: anyNamed('parentUri'),
        parentCid: anyNamed('parentCid'),
        content: captureAnyNamed('content'),
        contentFacets: captureAnyNamed('contentFacets'),
        embed: captureAnyNamed('embed'),
      ),
    ).captured;
    expect(captured, hasLength(3), reason: 'exactly one createComment call');
    return (
      content: captured[0] as String,
      facets: captured[1] as List<RichTextFacet>?,
      embed: captured[2] as ImagesEmbedInput?,
    );
  }

  void verifyNotSent() {
    verifyNever(
      commentService.createComment(
        rootUri: anyNamed('rootUri'),
        rootCid: anyNamed('rootCid'),
        parentUri: anyNamed('parentUri'),
        parentCid: anyNamed('parentCid'),
        content: anyNamed('content'),
        contentFacets: anyNamed('contentFacets'),
        embed: anyNamed('embed'),
      ),
    );
  }

  final mentionFacet = RichTextFacet.fromJson({
    'index': {'byteStart': 0, 'byteEnd': 4},
    'features': [
      {r'$type': 'social.coves.richtext.facet#mention', 'did': 'did:plc:bob'},
    ],
  });

  group('B1 image-only replies', () {
    final imageOnlyRows =
        <({String name, String content, List<RichTextFacet>? facets})>[
          (name: 'blank content', content: '  ', facets: null),
          (
            name: 'blank content with facets',
            content: '  ',
            facets: [mentionFacet],
          ),
        ];

    for (final row in imageOnlyRows) {
      test('B1 ${row.name} and one image is sent as empty content with no '
          'facets and the embed', () async {
        await expectLater(
          provider.createComment(
            content: row.content,
            contentFacets: row.facets,
            embed: _oneImage,
          ),
          completes,
        );

        final call = sent();
        expect(call.content, '');
        expect(call.facets ?? const <RichTextFacet>[], isEmpty);
        expect(call.embed, same(_oneImage));
      });
    }

    final refusedRows = <({String name, ImagesEmbedInput? embed})>[
      (name: 'no embed', embed: null),
      (
        name: 'an embed with no images',
        embed: const ImagesEmbedInput(images: []),
      ),
    ];

    for (final row in refusedRows) {
      test('B1 empty content with ${row.name} is refused and nothing is '
          'sent', () async {
        await expectLater(
          provider.createComment(content: '', embed: row.embed),
          throwsA(isA<ValidationException>()),
        );
        verifyNotSent();
      });
    }

    test('B1 text and one image are both sent, the text trimmed', () async {
      await provider.createComment(
        content: '  Look at this  ',
        embed: _oneImage,
      );

      final call = sent();
      expect(call.content, 'Look at this');
      expect(call.embed, same(_oneImage));
    });
  });
}
