// B2 + B3: CommentService.updateComment request shape, response parsing and
// error mapping. The update procedure replaces the whole record, so the
// stored record's embed/langs/labels are resent verbatim.

import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/coves_session.dart';
import 'package:coves_flutter/models/facet.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/comment_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'comment_service_test.mocks.dart';

const _updatePath = '/xrpc/social.coves.community.comment.update';
const _commentUri = 'at://did:plc:test/social.coves.community.comment/e1';

const _session = CovesSession(
  token: 'test-token',
  did: 'did:plc:test',
  sessionId: 'test-session-id',
  handle: 'test.user',
);

const _recordEmbed = <String, dynamic>{
  r'$type': 'social.coves.embed.images',
  'images': [
    {
      'image': {
        r'$type': 'blob',
        'ref': {r'$link': 'bafkreiimage'},
        'mimeType': 'image/jpeg',
        'size': 12345,
      },
      'alt': 'a cat',
    },
  ],
};

const _recordLabels = <String, dynamic>{
  r'$type': 'com.atproto.label.defs#selfLabels',
  'values': [
    {'val': 'nudity'},
  ],
};

const _boldFacet = RichTextFacet(
  index: ByteSlice(byteStart: 0, byteEnd: 3),
  features: [BoldFacetFeature()],
);

void main() {
  late MockDio dio;
  late CommentService service;

  setUp(() {
    dio = MockDio();
    when(dio.interceptors).thenReturn(Interceptors());
    service = CommentService(
      sessionKeyOf: () => (did: 'did:plc:test', sessionId: 'test-session-id'),
      sessionGetter: () async => _session,
      tokenRefresher: () async => true,
      signOutHandler: () async {},
      dio: dio,
    );
  });

  void answerUpdate(Map<String, dynamic> body) {
    when(dio.post<Map<String, dynamic>>(_updatePath, data: anyNamed('data')))
        .thenAnswer(
          (_) async => Response(
            requestOptions: RequestOptions(path: _updatePath),
            statusCode: 200,
            data: body,
          ),
        );
  }

  Object? sentBody() => verify(
    dio.post<Map<String, dynamic>>(_updatePath, data: captureAnyNamed('data')),
  ).captured.single;

  group('B2 request and response', () {
    test(
      'sends uri, content, facets and the record embed/langs/labels verbatim',
      () async {
        answerUpdate({'uri': _commentUri, 'cid': 'cid-new'});

        final response = await service.updateComment(
          uri: _commentUri,
          content: 'New body',
          facets: const [_boldFacet],
          record: const CommentRecord(
            content: 'Old body',
            embed: _recordEmbed,
            langs: ['en', 'fr'],
            labels: _recordLabels,
          ),
        );

        expect(response.uri, _commentUri);
        expect(response.cid, 'cid-new');
        expect(sentBody(), {
          'uri': _commentUri,
          'content': 'New body',
          'facets': [
            {
              'index': {'byteStart': 0, 'byteEnd': 3},
              'features': [
                {r'$type': 'social.coves.richtext.facet#bold'},
              ],
            },
          ],
          'embed': {
            r'$type': 'social.coves.embed.images',
            'images': [
              {
                'image': {
                  r'$type': 'blob',
                  'ref': {r'$link': 'bafkreiimage'},
                  'mimeType': 'image/jpeg',
                  'size': 12345,
                },
                'alt': 'a cat',
              },
            ],
          },
          'langs': ['en', 'fr'],
          'labels': {
            r'$type': 'com.atproto.label.defs#selfLabels',
            'values': [
              {'val': 'nudity'},
            ],
          },
        });
      },
    );

    for (final row in [
      (name: 'null facets', facets: null),
      (name: 'empty facets', facets: const <RichTextFacet>[]),
    ]) {
      test('omits facets/embed/langs/labels keys for ${row.name} and a '
          'plain record', () async {
        answerUpdate({'uri': _commentUri, 'cid': 'cid-new'});

        await service.updateComment(
          uri: _commentUri,
          content: 'New body',
          facets: row.facets,
          record: const CommentRecord(content: 'Old body'),
        );

        expect(sentBody(), {'uri': _commentUri, 'content': 'New body'});
      });
    }

    test('a response without cid throws ApiException', () async {
      answerUpdate({'uri': _commentUri});

      await expectLater(
        service.updateComment(
          uri: _commentUri,
          content: 'New body',
          record: const CommentRecord(content: 'Old body'),
        ),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('B3 error mapping', () {
    DioException statusError(int statusCode, Map<String, dynamic> body) =>
        DioException(
          requestOptions: RequestOptions(path: _updatePath),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: _updatePath),
            statusCode: statusCode,
            data: body,
          ),
        );

    for (final row in [
      (
        name: '403 NotAuthorized',
        status: 403,
        body: {'error': 'NotAuthorized', 'message': 'Not authorized'},
        matcher: isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 403)
            .having((e) => e.errorCode, 'errorCode', 'NotAuthorized')
            .having((e) => e.message, 'message', 'Not authorized'),
      ),
      (
        name: '404 CommentNotFound',
        status: 404,
        body: {'error': 'CommentNotFound', 'message': 'comment not found'},
        matcher: isA<NotFoundException>(),
      ),
      (
        name: '409 ConcurrentModification',
        status: 409,
        body: {
          'error': 'ConcurrentModification',
          'message': 'the comment changed while you were editing',
        },
        matcher: isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 409)
            .having((e) => e.errorCode, 'errorCode', 'ConcurrentModification'),
      ),
    ]) {
      test('${row.name} maps to the typed exception', () async {
        when(
          dio.post<Map<String, dynamic>>(_updatePath, data: anyNamed('data')),
        ).thenThrow(statusError(row.status, row.body));

        await expectLater(
          service.updateComment(
            uri: _commentUri,
            content: 'New body',
            record: const CommentRecord(content: 'Old body'),
          ),
          throwsA(row.matcher),
        );
      });
    }

    test('no session throws AuthenticationException', () async {
      final signedOut = CommentService(
        sessionKeyOf: () => null,
        sessionGetter: () async => null,
        tokenRefresher: () async => true,
        signOutHandler: () async {},
        dio: dio,
      );

      await expectLater(
        signedOut.updateComment(
          uri: _commentUri,
          content: 'New body',
          record: const CommentRecord(content: 'Old body'),
        ),
        throwsA(isA<AuthenticationException>()),
      );
    });
  });
}
