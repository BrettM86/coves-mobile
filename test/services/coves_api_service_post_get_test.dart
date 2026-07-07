import 'package:coves_flutter/models/post_get_result.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const endpoint = '/xrpc/social.coves.community.post.get';

  const uri1 = 'at://did:plc:community1/social.coves.community.post/aaa111';
  const uri2 = 'at://did:plc:community2/social.coves.community.post/bbb222';
  const uri3 = 'at://did:plc:community3/social.coves.community.post/ccc333';

  /// Realistic #postView fixture matching PostView.fromJson's required
  /// fields (same shape as feed posts' `.post`).
  Map<String, dynamic> postViewJson(String uri) => {
    'uri': uri,
    'cid': 'bafyreic1234',
    'rkey': uri.split('/').last,
    'author': {
      'did': 'did:plc:author1',
      'handle': 'author.test',
      'displayName': 'Author One',
    },
    'community': {
      'did': 'did:plc:community1',
      'name': 'testcommunity',
      'handle': 'testcommunity.coves.social',
    },
    'record': {
      'title': 'Test Post Title',
      'content': 'Test post content',
    },
    'createdAt': '2025-06-01T12:00:00Z',
    'indexedAt': '2025-06-01T12:00:01Z',
    'stats': {
      'upvotes': 10,
      'downvotes': 2,
      'score': 8,
      'commentCount': 3,
    },
  };

  group('CovesApiService - getPosts', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late CovesApiService apiService;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'https://api.test.coves.social'));
      dioAdapter = DioAdapter(dio: dio);
      apiService = CovesApiService(
        dio: dio,
        tokenGetter: () async => 'test-token',
      );
    });

    tearDown(() {
      apiService.dispose();
    });

    test('should parse a postView success result', () async {
      dioAdapter.onGet(
        endpoint,
        (server) => server.reply(200, {
          'posts': [postViewJson(uri1)],
        }),
        queryParameters: {
          'uris': [uri1],
        },
      );

      final results = await apiService.getPosts(uris: [uri1]);

      expect(results.length, 1);
      expect(results[0], isA<PostGetSuccess>());
      final success = results[0] as PostGetSuccess;
      expect(success.uri, uri1);
      expect(success.post.uri, uri1);
      expect(success.post.cid, 'bafyreic1234');
      expect(success.post.author.handle, 'author.test');
      expect(success.post.community.name, 'testcommunity');
      expect(success.post.title, 'Test Post Title');
      expect(success.post.stats.score, 8);
    });

    test('should parse a notFoundPost result', () async {
      dioAdapter.onGet(
        endpoint,
        (server) => server.reply(200, {
          'posts': [
            {'uri': uri1, 'notFound': true},
          ],
        }),
        queryParameters: {
          'uris': [uri1],
        },
      );

      final results = await apiService.getPosts(uris: [uri1]);

      expect(results.length, 1);
      expect(results[0], isA<PostGetNotFound>());
      expect(results[0].uri, uri1);
    });

    test('should parse a blockedPost result', () async {
      dioAdapter.onGet(
        endpoint,
        (server) => server.reply(200, {
          'posts': [
            {
              'uri': uri1,
              'blocked': true,
              'blockedBy': 'author',
              'author': {'did': 'did:plc:blockedauthor'},
            },
          ],
        }),
        queryParameters: {
          'uris': [uri1],
        },
      );

      final results = await apiService.getPosts(uris: [uri1]);

      expect(results.length, 1);
      expect(results[0], isA<PostGetBlocked>());
      final blocked = results[0] as PostGetBlocked;
      expect(blocked.uri, uri1);
      expect(blocked.blockedBy, BlockedBy.author);
    });

    test('should preserve order in a mixed batch', () async {
      dioAdapter.onGet(
        endpoint,
        (server) => server.reply(200, {
          'posts': [
            postViewJson(uri1),
            {'uri': uri2, 'notFound': true},
            {'uri': uri3, 'blocked': true, 'blockedBy': 'moderator'},
          ],
        }),
        queryParameters: {
          'uris': [uri1, uri2, uri3],
        },
      );

      final results = await apiService.getPosts(uris: [uri1, uri2, uri3]);

      expect(results.length, 3);
      expect(results[0], isA<PostGetSuccess>());
      expect(results[0].uri, uri1);
      expect(results[1], isA<PostGetNotFound>());
      expect(results[1].uri, uri2);
      expect(results[2], isA<PostGetBlocked>());
      expect(results[2].uri, uri3);
      expect((results[2] as PostGetBlocked).blockedBy, BlockedBy.moderator);
    });

    test(
      r'should discriminate via booleans when $type is missing '
      r'(backend omits $type) and via $type when present',
      () {
        // Backend reality: no $type, booleans discriminate
        expect(
          PostGetResult.fromJson({'uri': uri1, 'notFound': true}),
          isA<PostGetNotFound>(),
        );
        expect(
          PostGetResult.fromJson({
            'uri': uri1,
            'blocked': true,
            'blockedBy': 'community',
          }),
          isA<PostGetBlocked>(),
        );
        // No discriminators at all -> parsed as postView
        expect(
          PostGetResult.fromJson(postViewJson(uri1)),
          isA<PostGetSuccess>(),
        );

        // Defensive: standard atproto $type discriminators also work
        expect(
          PostGetResult.fromJson({
            r'$type': 'social.coves.community.post.get#notFoundPost',
            'uri': uri1,
            'notFound': true,
          }),
          isA<PostGetNotFound>(),
        );
        final blocked = PostGetResult.fromJson({
          r'$type': 'social.coves.community.post.get#blockedPost',
          'uri': uri1,
          'blocked': true,
          'blockedBy': 'author',
        });
        expect(blocked, isA<PostGetBlocked>());
        expect((blocked as PostGetBlocked).blockedBy, BlockedBy.author);
      },
    );

    test('should default blockedBy to unknown when omitted', () {
      final result = PostGetResult.fromJson({'uri': uri1, 'blocked': true});
      expect(result, isA<PostGetBlocked>());
      expect((result as PostGetBlocked).blockedBy, BlockedBy.unknown);
    });

    test('should throw ArgumentError for empty uris', () async {
      expect(
        () => apiService.getPosts(uris: []),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should throw ArgumentError for more than maxPostGetUris uris', () {
      final uris = List.generate(
        CovesApiService.maxPostGetUris + 1,
        (i) => 'at://did:plc:test/social.coves.community.post/$i',
      );
      expect(
        () => apiService.getPosts(uris: uris),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should throw ServerException on 500 error', () async {
      dioAdapter.onGet(
        endpoint,
        (server) => server.reply(500, {'error': 'Internal server error'}),
        queryParameters: {
          'uris': [uri1],
        },
      );

      expect(
        () => apiService.getPosts(uris: [uri1]),
        throwsA(isA<ServerException>()),
      );
    });

    test('should not crash if response omits an input URI', () async {
      // Defensive: server returned fewer entries than requested
      dioAdapter.onGet(
        endpoint,
        (server) => server.reply(200, {
          'posts': [postViewJson(uri1)],
        }),
        queryParameters: {
          'uris': [uri1, uri2],
        },
      );

      final results = await apiService.getPosts(uris: [uri1, uri2]);

      expect(results.length, 1);
      expect(results[0].uri, uri1);
    });

    test(
      'should degrade a malformed entry to PostGetNotFound '
      'while the rest of the batch parses',
      () async {
        dioAdapter.onGet(
          endpoint,
          (server) => server.reply(200, {
            'posts': [
              postViewJson(uri1),
              // Malformed postView: missing required fields (cid, author,
              // community, record, ...) so PostView.fromJson throws.
              {'uri': uri2},
              {'uri': uri3, 'notFound': true},
            ],
          }),
          queryParameters: {
            'uris': [uri1, uri2, uri3],
          },
        );

        final results = await apiService.getPosts(uris: [uri1, uri2, uri3]);

        expect(results.length, 3);
        expect(results[0], isA<PostGetSuccess>());
        expect(results[0].uri, uri1);
        expect(results[1], isA<PostGetNotFound>());
        expect(results[1].uri, uri2);
        expect(results[2], isA<PostGetNotFound>());
        expect(results[2].uri, uri3);
      },
    );

    test(
      'should fall back to the input URI when a malformed entry has no uri',
      () async {
        dioAdapter.onGet(
          endpoint,
          (server) => server.reply(200, {
            'posts': [
              // No uri at all; the input URI at the same index is used.
              {'cid': 'bafyreicbroken'},
            ],
          }),
          queryParameters: {
            'uris': [uri1],
          },
        );

        final results = await apiService.getPosts(uris: [uri1]);

        expect(results.length, 1);
        expect(results[0], isA<PostGetNotFound>());
        expect(results[0].uri, uri1);
      },
    );

    test(
      'should serialize uris as repeated params (uris=a&uris=b, no brackets)',
      () async {
        // Capture the final request URI via an interceptor; the query string
        // is built from RequestOptions using its listFormat, so this asserts
        // the exact on-the-wire serialization atproto requires.
        Uri? capturedUri;
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              capturedUri = options.uri;
              handler.next(options);
            },
          ),
        );

        dioAdapter.onGet(
          endpoint,
          (server) => server.reply(200, {
            'posts': [
              {'uri': uri1, 'notFound': true},
              {'uri': uri2, 'notFound': true},
            ],
          }),
          queryParameters: {
            'uris': [uri1, uri2],
          },
        );

        await apiService.getPosts(uris: [uri1, uri2]);

        expect(capturedUri, isNotNull);
        final query = capturedUri!.query;
        expect(query, contains('uris=${Uri.encodeQueryComponent(uri1)}'));
        expect(query, contains('uris=${Uri.encodeQueryComponent(uri2)}'));
        expect(query, isNot(contains('uris%5B%5D')));
        expect(query, isNot(contains('uris[]')));
        expect(capturedUri!.queryParametersAll['uris'], [uri1, uri2]);
      },
    );
  });

  group('CovesApiService - getPost', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late CovesApiService apiService;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'https://api.test.coves.social'));
      dioAdapter = DioAdapter(dio: dio);
      apiService = CovesApiService(
        dio: dio,
        tokenGetter: () async => 'test-token',
      );
    });

    tearDown(() {
      apiService.dispose();
    });

    test('should return the first result for a single URI', () async {
      dioAdapter.onGet(
        endpoint,
        (server) => server.reply(200, {
          'posts': [postViewJson(uri1)],
        }),
        queryParameters: {
          'uris': [uri1],
        },
      );

      final result = await apiService.getPost(uri1);

      expect(result, isA<PostGetSuccess>());
      expect(result.uri, uri1);
    });

    test('should return PostGetNotFound when response is empty', () async {
      dioAdapter.onGet(
        endpoint,
        (server) => server.reply(200, {'posts': <dynamic>[]}),
        queryParameters: {
          'uris': [uri1],
        },
      );

      final result = await apiService.getPost(uri1);

      expect(result, isA<PostGetNotFound>());
      expect(result.uri, uri1);
    });

    test(
      'should return PostGetNotFound when the response entry uri '
      'does not match the requested uri',
      () async {
        dioAdapter.onGet(
          endpoint,
          (server) => server.reply(200, {
            'posts': [postViewJson(uri2)],
          }),
          queryParameters: {
            'uris': [uri1],
          },
        );

        final result = await apiService.getPost(uri1);

        expect(result, isA<PostGetNotFound>());
        expect(result.uri, uri1);
      },
    );

    test(
      'should pick the matching entry when a mismatched one comes first',
      () async {
        dioAdapter.onGet(
          endpoint,
          (server) => server.reply(200, {
            'posts': [postViewJson(uri2), postViewJson(uri1)],
          }),
          queryParameters: {
            'uris': [uri1],
          },
        );

        final result = await apiService.getPost(uri1);

        expect(result, isA<PostGetSuccess>());
        expect(result.uri, uri1);
      },
    );
  });
}
