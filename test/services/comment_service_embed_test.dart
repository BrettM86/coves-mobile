import 'package:coves_flutter/models/coves_session.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/post_embed_input.dart';
import 'package:coves_flutter/services/comment_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

const _rootUri = 'at://did:plc:author/social.coves.community.post/root';
const _commentPath = '/xrpc/social.coves.community.comment.create';

void main() {
  late Dio dio;
  late List<RequestOptions> requests;
  late CommentService service;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://api.test.coves.social'));
    requests = [];
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          handler.next(options);
        },
      ),
    );
    DioAdapter(dio: dio).onPost(
      _commentPath,
      (server) => server.reply(200, {
        'uri': 'at://did:plc:test/social.coves.community.comment/new',
        'cid': 'bafy-new',
      }),
      data: Matchers.any,
    );
    service = CommentService(
      sessionKeyOf: () => (did: 'did:plc:test', sessionId: 'session-1'),
      sessionGetter: () async => const CovesSession(
        token: 'test-token',
        did: 'did:plc:test',
        sessionId: 'session-1',
        handle: 'test.user',
      ),
      dio: dio,
    );
  });

  Future<Map<String, dynamic>> send({ImagesEmbedInput? embed}) async {
    await service.createComment(
      rootUri: _rootUri,
      rootCid: 'bafy-root',
      parentUri: _rootUri,
      parentCid: 'bafy-root',
      content: '',
      embed: embed,
    );
    expect(requests.last.path, _commentPath);
    return requests.last.data as Map<String, dynamic>;
  }

  test('B2 an images embed is sent as social.coves.embed.images with the '
      'blob map unchanged, empty content and no facets; without one no embed '
      'key is sent', () async {
    final body = await send(
      embed: ImagesEmbedInput(
        images: [
          EmbedImageInput(
            blob: const {
              r'$type': 'blob',
              'ref': {r'$link': 'bafkrei-reply'},
              'mimeType': 'image/jpeg',
              'size': 48213,
            },
            alt: 'a cat on a keyboard',
            aspectRatio: EmbedAspectRatio(width: 4, height: 3),
          ),
        ],
      ),
    );

    expect(body['content'], '');
    expect(body.containsKey('facets'), isFalse);
    expect(body['embed'], {
      r'$type': 'social.coves.embed.images',
      'images': [
        {
          'image': {
            r'$type': 'blob',
            'ref': {r'$link': 'bafkrei-reply'},
            'mimeType': 'image/jpeg',
            'size': 48213,
          },
          'alt': 'a cat on a keyboard',
          'aspectRatio': {'width': 4, 'height': 3},
        },
      ],
    });

    final withoutEmbed = await send();
    expect(withoutEmbed.containsKey('embed'), isFalse);
  });
}
