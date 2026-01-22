import 'package:coves_flutter/models/community.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CovesApiService - listCommunities', () {
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

    test('should successfully fetch communities', () async {
      final mockResponse = {
        'communities': [
          {
            'did': 'did:plc:community1',
            'name': 'test-community-1',
            'displayName': 'Test Community 1',
            'subscriberCount': 100,
            'memberCount': 50,
          },
          {
            'did': 'did:plc:community2',
            'name': 'test-community-2',
            'displayName': 'Test Community 2',
            'subscriberCount': 200,
            'memberCount': 100,
          },
        ],
        'cursor': 'next-cursor',
      };

      dioAdapter.onGet(
        '/xrpc/social.coves.community.list',
        (server) => server.reply(200, mockResponse),
        queryParameters: {
          'limit': 50,
          'sort': 'popular',
        },
      );

      final response = await apiService.listCommunities();

      expect(response, isA<CommunitiesResponse>());
      expect(response.communities.length, 2);
      expect(response.cursor, 'next-cursor');
      expect(response.communities[0].did, 'did:plc:community1');
      expect(response.communities[0].name, 'test-community-1');
      expect(response.communities[1].did, 'did:plc:community2');
    });

    test('should handle empty communities response', () async {
      final mockResponse = {
        'communities': [],
        'cursor': null,
      };

      dioAdapter.onGet(
        '/xrpc/social.coves.community.list',
        (server) => server.reply(200, mockResponse),
        queryParameters: {
          'limit': 50,
          'sort': 'popular',
        },
      );

      final response = await apiService.listCommunities();

      expect(response.communities, isEmpty);
      expect(response.cursor, null);
    });

    test('should handle null communities array', () async {
      final mockResponse = {
        'communities': null,
        'cursor': null,
      };

      dioAdapter.onGet(
        '/xrpc/social.coves.community.list',
        (server) => server.reply(200, mockResponse),
        queryParameters: {
          'limit': 50,
          'sort': 'popular',
        },
      );

      final response = await apiService.listCommunities();

      expect(response.communities, isEmpty);
    });

    test('should fetch communities with custom limit', () async {
      final mockResponse = {
        'communities': [],
        'cursor': null,
      };

      dioAdapter.onGet(
        '/xrpc/social.coves.community.list',
        (server) => server.reply(200, mockResponse),
        queryParameters: {
          'limit': 25,
          'sort': 'popular',
        },
      );

      final response = await apiService.listCommunities(limit: 25);

      expect(response, isA<CommunitiesResponse>());
    });

    test('should fetch communities with cursor for pagination', () async {
      const cursor = 'pagination-cursor-123';

      final mockResponse = {
        'communities': [
          {
            'did': 'did:plc:community3',
            'name': 'paginated-community',
          },
        ],
        'cursor': 'next-cursor-456',
      };

      dioAdapter.onGet(
        '/xrpc/social.coves.community.list',
        (server) => server.reply(200, mockResponse),
        queryParameters: {
          'limit': 50,
          'sort': 'popular',
          'cursor': cursor,
        },
      );

      final response = await apiService.listCommunities(cursor: cursor);

      expect(response.communities.length, 1);
      expect(response.cursor, 'next-cursor-456');
    });

    test('should fetch communities with custom sort', () async {
      final mockResponse = {
        'communities': [],
        'cursor': null,
      };

      dioAdapter.onGet(
        '/xrpc/social.coves.community.list',
        (server) => server.reply(200, mockResponse),
        queryParameters: {
          'limit': 50,
          'sort': 'new',
        },
      );

      final response = await apiService.listCommunities(sort: 'new');

      expect(response, isA<CommunitiesResponse>());
    });

    test('should handle 401 unauthorized error', () async {
      dioAdapter.onGet(
        '/xrpc/social.coves.community.list',
        (server) => server.reply(401, {
          'error': 'Unauthorized',
          'message': 'Invalid token',
        }),
        queryParameters: {
          'limit': 50,
          'sort': 'popular',
        },
      );

      expect(
        () => apiService.listCommunities(),
        throwsA(isA<AuthenticationException>()),
      );
    });

    test('should handle 500 server error', () async {
      dioAdapter.onGet(
        '/xrpc/social.coves.community.list',
        (server) => server.reply(500, {
          'error': 'InternalServerError',
          'message': 'Database error',
        }),
        queryParameters: {
          'limit': 50,
          'sort': 'popular',
        },
      );

      expect(
        () => apiService.listCommunities(),
        throwsA(isA<ServerException>()),
      );
    });

    test('should handle network timeout', () async {
      dioAdapter.onGet(
        '/xrpc/social.coves.community.list',
        (server) => server.throws(
          408,
          DioException.connectionTimeout(
            timeout: const Duration(seconds: 30),
            requestOptions: RequestOptions(),
          ),
        ),
        queryParameters: {
          'limit': 50,
          'sort': 'popular',
        },
      );

      expect(
        () => apiService.listCommunities(),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  group('CovesApiService - createPost', () {
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

    test('should successfully create a post with all fields', () async {
      final mockResponse = {
        'uri': 'at://did:plc:user/social.coves.community.post/123',
        'cid': 'bafyreicid123',
      };

      dioAdapter.onPost(
        '/xrpc/social.coves.community.post.create',
        (server) => server.reply(200, mockResponse),
        data: {
          'community': 'did:plc:community1',
          'title': 'Test Post Title',
          'content': 'Test post content',
          'embed': {
            r'$type': 'social.coves.embed.external',
            'external': {
              'uri': 'https://example.com/article',
              'title': 'Article Title',
            },
          },
          'langs': ['en'],
          'labels': {
            'values': [
              {'val': 'nsfw'},
            ],
          },
        },
      );

      final response = await apiService.createPost(
        community: 'did:plc:community1',
        title: 'Test Post Title',
        content: 'Test post content',
        embed: ExternalEmbedInput(
          uri: 'https://example.com/article',
          title: 'Article Title',
        ),
        langs: ['en'],
        labels: const SelfLabels(values: [SelfLabel(val: 'nsfw')]),
      );

      expect(response, isA<CreatePostResponse>());
      expect(response.uri, 'at://did:plc:user/social.coves.community.post/123');
      expect(response.cid, 'bafyreicid123');
    });

    test('should successfully create a minimal post', () async {
      final mockResponse = {
        'uri': 'at://did:plc:user/social.coves.community.post/456',
        'cid': 'bafyreicid456',
      };

      dioAdapter.onPost(
        '/xrpc/social.coves.community.post.create',
        (server) => server.reply(200, mockResponse),
        data: {
          'community': 'did:plc:community1',
          'title': 'Just a title',
        },
      );

      final response = await apiService.createPost(
        community: 'did:plc:community1',
        title: 'Just a title',
      );

      expect(response, isA<CreatePostResponse>());
      expect(response.uri, 'at://did:plc:user/social.coves.community.post/456');
    });

    test('should successfully create a link post', () async {
      final mockResponse = {
        'uri': 'at://did:plc:user/social.coves.community.post/789',
        'cid': 'bafyreicid789',
      };

      dioAdapter.onPost(
        '/xrpc/social.coves.community.post.create',
        (server) => server.reply(200, mockResponse),
        data: {
          'community': 'did:plc:community1',
          'embed': {
            'uri': 'https://example.com/article',
          },
        },
      );

      final response = await apiService.createPost(
        community: 'did:plc:community1',
        embed: ExternalEmbedInput(uri: 'https://example.com/article'),
      );

      expect(response, isA<CreatePostResponse>());
    });

    test('should handle 401 unauthorized error', () async {
      dioAdapter.onPost(
        '/xrpc/social.coves.community.post.create',
        (server) => server.reply(401, {
          'error': 'Unauthorized',
          'message': 'Authentication required',
        }),
        data: {
          'community': 'did:plc:community1',
          'title': 'Test',
        },
      );

      expect(
        () => apiService.createPost(
          community: 'did:plc:community1',
          title: 'Test',
        ),
        throwsA(isA<AuthenticationException>()),
      );
    });

    test('should handle 404 community not found', () async {
      dioAdapter.onPost(
        '/xrpc/social.coves.community.post.create',
        (server) => server.reply(404, {
          'error': 'NotFound',
          'message': 'Community not found',
        }),
        data: {
          'community': 'did:plc:nonexistent',
          'title': 'Test',
        },
      );

      expect(
        () => apiService.createPost(
          community: 'did:plc:nonexistent',
          title: 'Test',
        ),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('should handle 400 validation error', () async {
      dioAdapter.onPost(
        '/xrpc/social.coves.community.post.create',
        (server) => server.reply(400, {
          'error': 'ValidationError',
          'message': 'Title exceeds maximum length',
        }),
        data: {
          'community': 'did:plc:community1',
          'title': 'a' * 1000, // Very long title
        },
      );

      expect(
        () => apiService.createPost(
          community: 'did:plc:community1',
          title: 'a' * 1000,
        ),
        throwsA(isA<ApiException>()),
      );
    });

    test('should handle 500 server error', () async {
      dioAdapter.onPost(
        '/xrpc/social.coves.community.post.create',
        (server) => server.reply(500, {
          'error': 'InternalServerError',
          'message': 'Database error',
        }),
        data: {
          'community': 'did:plc:community1',
          'title': 'Test',
        },
      );

      expect(
        () => apiService.createPost(
          community: 'did:plc:community1',
          title: 'Test',
        ),
        throwsA(isA<ServerException>()),
      );
    });

    test('should handle network timeout', () async {
      dioAdapter.onPost(
        '/xrpc/social.coves.community.post.create',
        (server) => server.throws(
          408,
          DioException.connectionTimeout(
            timeout: const Duration(seconds: 30),
            requestOptions: RequestOptions(),
          ),
        ),
        data: {
          'community': 'did:plc:community1',
          'title': 'Test',
        },
      );

      expect(
        () => apiService.createPost(
          community: 'did:plc:community1',
          title: 'Test',
        ),
        throwsA(isA<NetworkException>()),
      );
    });
  });
}
