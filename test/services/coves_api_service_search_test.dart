import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

/// One served post, shaped like the XRPC feedViewPost the endpoint returns.
Map<String, dynamic> feedItem({required String rkey, required String title}) {
  return {
    'post': {
      'uri': 'at://did:plc:author/social.coves.community.post/$rkey',
      'cid': 'cid-$rkey',
      'rkey': rkey,
      'author': {'did': 'did:plc:author', 'handle': 'author.test'},
      'community': {'did': 'did:plc:abc', 'name': 'test-community'},
      'createdAt': '2024-01-01T00:00:00.000Z',
      'indexedAt': '2024-01-01T00:00:00.000Z',
      'record': {'title': title, 'content': 'Body'},
      'stats': {'upvotes': 0, 'downvotes': 0, 'score': 0, 'commentCount': 0},
    },
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CovesApiService - searchPosts', () {
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

    test('sends every supplied parameter and parses the response', () async {
      dioAdapter.onGet(
        '/xrpc/social.coves.feed.searchPosts',
        (server) => server.reply(200, {
          'feed': [feedItem(rkey: 's1', title: 'Linux kernel flaw')],
          'cursor': 'next-cursor',
        }),
        queryParameters: {
          'q': 'linux',
          'community': 'did:plc:abc',
          'sort': 'relevance',
          'limit': 15,
          'cursor': 'c1',
        },
      );

      final response = await apiService.searchPosts(
        q: 'linux',
        community: 'did:plc:abc',
        cursor: 'c1',
      );

      expect(response, isA<TimelineResponse>());
      expect(response.feed, hasLength(1));
      expect(response.feed.single.post.rkey, 's1');
      expect(response.feed.single.post.title, 'Linux kernel flaw');
      expect(response.cursor, 'next-cursor');
    });

    test('omits the null optional parameters from the query string', () async {
      // The adapter matches the query parameters exactly, so this stub can
      // only reply when `community`, `timeframe` and `cursor` are absent
      // from the request. Getting a parsed response back IS the assertion
      // that they were omitted rather than sent as nulls.
      dioAdapter.onGet(
        '/xrpc/social.coves.feed.searchPosts',
        (server) => server.reply(200, {
          'feed': [feedItem(rkey: 's2', title: 'Minimal query')],
          'cursor': null,
        }),
        queryParameters: {'q': 'linux', 'sort': 'relevance', 'limit': 15},
      );

      final response = await apiService.searchPosts(q: 'linux');

      expect(response.feed, hasLength(1));
      expect(response.feed.single.post.title, 'Minimal query');
      expect(response.cursor, isNull);
    });

    test('surfaces a 404 CommunityNotFound as NotFoundException carrying '
        'the server message', () async {
      dioAdapter.onGet(
        '/xrpc/social.coves.feed.searchPosts',
        (server) => server.reply(404, {
          'error': 'CommunityNotFound',
          'message': 'community not found',
        }),
        queryParameters: {
          'q': 'linux',
          'community': 'did:plc:missing',
          'sort': 'relevance',
          'limit': 15,
        },
      );

      await expectLater(
        () => apiService.searchPosts(q: 'linux', community: 'did:plc:missing'),
        throwsA(
          isA<NotFoundException>().having(
            (e) => e.message,
            'message',
            'community not found',
          ),
        ),
      );
    });
  });
}
