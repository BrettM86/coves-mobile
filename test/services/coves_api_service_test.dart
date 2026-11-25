import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/liked_item.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CovesApiService - getComments', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late CovesApiService apiService;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'https://api.test.coves.social'));
      dioAdapter = DioAdapter(dio: dio);
      apiService = CovesApiService(
        sessionKeyOf: () => (did: 'did:plc:test', sessionId: 'session-1'),
        dio: dio,
        tokenGetter: () async => 'test-token',
      );
    });

    tearDown(() {
      apiService.dispose();
    });

    test('should successfully fetch comments', () async {
      const postUri = 'at://did:plc:test/social.coves.post.record/123';

      final mockResponse = {
        'post': {'uri': postUri},
        'cursor': 'next-cursor',
        'comments': [
          {
            'comment': {
              'uri': 'at://did:plc:test/comment/1',
              'cid': 'cid1',
              'record': {'content': 'Test comment 1'},
              'createdAt': '2025-01-01T12:00:00Z',
              'indexedAt': '2025-01-01T12:00:00Z',
              'author': {
                'did': 'did:plc:author1',
                'handle': 'user1.test',
                'displayName': 'User One',
              },
              'post': {'uri': postUri, 'cid': 'post-cid'},
              'stats': {'upvotes': 10, 'downvotes': 2, 'score': 8},
            },
            'hasMore': false,
          },
          {
            'comment': {
              'uri': 'at://did:plc:test/comment/2',
              'cid': 'cid2',
              'record': {'content': 'Test comment 2'},
              'createdAt': '2025-01-01T13:00:00Z',
              'indexedAt': '2025-01-01T13:00:00Z',
              'author': {'did': 'did:plc:author2', 'handle': 'user2.test'},
              'post': {'uri': postUri, 'cid': 'post-cid'},
              'stats': {'upvotes': 5, 'downvotes': 1, 'score': 4},
            },
            'hasMore': false,
          },
        ],
      };

      dioAdapter.onGet(
        '/xrpc/social.coves.community.comment.getComments',
        (server) => server.reply(200, mockResponse),
        queryParameters: {
          'post': postUri,
          'sort': 'hot',
          'depth': 10,
          'limit': 50,
        },
      );

      final response = await apiService.getComments(postUri: postUri);

      expect(response, isA<CommentsResponse>());
      expect(response.comments.length, 2);
      expect(response.cursor, 'next-cursor');
      expect(response.comments[0].comment.uri, 'at://did:plc:test/comment/1');
      expect(response.comments[0].comment.content, 'Test comment 1');
      expect(response.comments[1].comment.uri, 'at://did:plc:test/comment/2');
    });

    test('should handle empty comments response', () async {
      const postUri = 'at://did:plc:test/social.coves.post.record/123';

      final mockResponse = {
        'post': {'uri': postUri},
        'cursor': null,
        'comments': [],
      };

      dioAdapter.onGet(
        '/xrpc/social.coves.community.comment.getComments',
        (server) => server.reply(200, mockResponse),
        queryParameters: {
          'post': postUri,
          'sort': 'hot',
          'depth': 10,
          'limit': 50,
        },
      );

      final response = await apiService.getComments(postUri: postUri);

      expect(response.comments, isEmpty);
      expect(response.cursor, null);
    });

    test('should handle null comments array', () async {
      const postUri = 'at://did:plc:test/social.coves.post.record/123';

      final mockResponse = {
        'post': {'uri': postUri},
        'cursor': null,
        'comments': null,
      };

      dioAdapter.onGet(
        '/xrpc/social.coves.community.comment.getComments',
        (server) => server.reply(200, mockResponse),
        queryParameters: {
          'post': postUri,
          'sort': 'hot',
          'depth': 10,
          'limit': 50,
        },
      );

      final response = await apiService.getComments(postUri: postUri);

      expect(response.comments, isEmpty);
    });

    test('should fetch comments with custom sort option', () async {
      const postUri = 'at://did:plc:test/social.coves.post.record/123';

      final mockResponse = {
        'post': {'uri': postUri},
        'cursor': null,
        'comments': [
          {
            'comment': {
              'uri': 'at://did:plc:test/comment/1',
              'cid': 'cid1',
              'record': {'content': 'Newest comment'},
              'createdAt': '2025-01-01T15:00:00Z',
              'indexedAt': '2025-01-01T15:00:00Z',
              'author': {'did': 'did:plc:author', 'handle': 'user.test'},
              'post': {'uri': postUri, 'cid': 'post-cid'},
              'stats': {'upvotes': 1, 'downvotes': 0, 'score': 1},
            },
            'hasMore': false,
          },
        ],
      };

      dioAdapter.onGet(
        '/xrpc/social.coves.community.comment.getComments',
        (server) => server.reply(200, mockResponse),
        queryParameters: {
          'post': postUri,
          'sort': 'new',
          'depth': 10,
          'limit': 50,
        },
      );

      final response = await apiService.getComments(
        postUri: postUri,
        sort: 'new',
      );

      expect(response.comments.length, 1);
      expect(response.comments[0].comment.content, 'Newest comment');
    });

    test('should fetch comments with timeframe', () async {
      const postUri = 'at://did:plc:test/social.coves.post.record/123';

      final mockResponse = {
        'post': {'uri': postUri},
        'cursor': null,
        'comments': [],
      };

      dioAdapter.onGet(
        '/xrpc/social.coves.community.comment.getComments',
        (server) => server.reply(200, mockResponse),
        queryParameters: {
          'post': postUri,
          'sort': 'top',
          'timeframe': 'week',
          'depth': 10,
          'limit': 50,
        },
      );

      final response = await apiService.getComments(
        postUri: postUri,
        sort: 'top',
        timeframe: 'week',
      );

      expect(response, isA<CommentsResponse>());
    });

    test('should fetch comments with cursor for pagination', () async {
      const postUri = 'at://did:plc:test/social.coves.post.record/123';
      const cursor = 'pagination-cursor-123';

      final mockResponse = {
        'post': {'uri': postUri},
        'cursor': 'next-cursor-456',
        'comments': [
          {
            'comment': {
              'uri': 'at://did:plc:test/comment/10',
              'cid': 'cid10',
              'record': {'content': 'Paginated comment'},
              'createdAt': '2025-01-01T12:00:00Z',
              'indexedAt': '2025-01-01T12:00:00Z',
              'author': {'did': 'did:plc:author', 'handle': 'user.test'},
              'post': {'uri': postUri, 'cid': 'post-cid'},
              'stats': {'upvotes': 5, 'downvotes': 0, 'score': 5},
            },
            'hasMore': false,
          },
        ],
      };

      dioAdapter.onGet(
        '/xrpc/social.coves.community.comment.getComments',
        (server) => server.reply(200, mockResponse),
        queryParameters: {
          'post': postUri,
          'sort': 'hot',
          'depth': 10,
          'limit': 50,
          'cursor': cursor,
        },
      );

      final response = await apiService.getComments(
        postUri: postUri,
        cursor: cursor,
      );

      expect(response.comments.length, 1);
      expect(response.cursor, 'next-cursor-456');
    });

    test('should fetch comments with custom depth and limit', () async {
      const postUri = 'at://did:plc:test/social.coves.post.record/123';

      final mockResponse = {
        'post': {'uri': postUri},
        'cursor': null,
        'comments': [],
      };

      dioAdapter.onGet(
        '/xrpc/social.coves.community.comment.getComments',
        (server) => server.reply(200, mockResponse),
        queryParameters: {
          'post': postUri,
          'sort': 'hot',
          'depth': 5,
          'limit': 20,
        },
      );

      final response = await apiService.getComments(
        postUri: postUri,
        depth: 5,
        limit: 20,
      );

      expect(response, isA<CommentsResponse>());
    });

    test('should send parentRkey as a query parameter when provided', () async {
      const postUri = 'at://did:plc:test/social.coves.post.record/123';
      const parentRkey = '3kparentrkey';

      final mockResponse = {
        'post': {'uri': postUri},
        'cursor': null,
        'comments': [],
      };

      // DioAdapter matches the full query-parameter map, so this only
      // replies if 'parentRkey' actually reaches the wire with this value.
      dioAdapter.onGet(
        '/xrpc/social.coves.community.comment.getComments',
        (server) => server.reply(200, mockResponse),
        queryParameters: {
          'post': postUri,
          'sort': 'hot',
          'depth': 10,
          'limit': 50,
          'parentRkey': parentRkey,
        },
      );

      final response = await apiService.getComments(
        postUri: postUri,
        parentRkey: parentRkey,
      );

      expect(response, isA<CommentsResponse>());
    });

    test('should omit parentRkey from query when null', () async {
      const postUri = 'at://did:plc:test/social.coves.post.record/123';

      final mockResponse = {
        'post': {'uri': postUri},
        'cursor': null,
        'comments': [],
      };

      // Mock has no 'parentRkey' key — the request only matches if the
      // parameter is omitted entirely.
      dioAdapter.onGet(
        '/xrpc/social.coves.community.comment.getComments',
        (server) => server.reply(200, mockResponse),
        queryParameters: {
          'post': postUri,
          'sort': 'hot',
          'depth': 10,
          'limit': 50,
        },
      );

      final response = await apiService.getComments(postUri: postUri);

      expect(response, isA<CommentsResponse>());
    });

    test('should omit parentRkey from query when empty', () async {
      const postUri = 'at://did:plc:test/social.coves.post.record/123';

      final mockResponse = {
        'post': {'uri': postUri},
        'cursor': null,
        'comments': [],
      };

      // Mock has no 'parentRkey' key — the request only matches if the
      // empty string is dropped instead of sent as parentRkey=.
      dioAdapter.onGet(
        '/xrpc/social.coves.community.comment.getComments',
        (server) => server.reply(200, mockResponse),
        queryParameters: {
          'post': postUri,
          'sort': 'hot',
          'depth': 10,
          'limit': 50,
        },
      );

      final response = await apiService.getComments(
        postUri: postUri,
        parentRkey: '',
      );

      expect(response, isA<CommentsResponse>());
    });

    test('should handle 404 error', () async {
      const postUri = 'at://did:plc:test/social.coves.post.record/nonexistent';

      dioAdapter.onGet(
        '/xrpc/social.coves.community.comment.getComments',
        (server) => server.reply(404, {
          'error': 'NotFoundError',
          'message': 'Post not found',
        }),
        queryParameters: {
          'post': postUri,
          'sort': 'hot',
          'depth': 10,
          'limit': 50,
        },
      );

      expect(
        () => apiService.getComments(postUri: postUri),
        throwsA(isA<Exception>()),
      );
    });

    test('should handle 500 internal server error', () async {
      const postUri = 'at://did:plc:test/social.coves.post.record/123';

      dioAdapter.onGet(
        '/xrpc/social.coves.community.comment.getComments',
        (server) => server.reply(500, {
          'error': 'InternalServerError',
          'message': 'Database connection failed',
        }),
        queryParameters: {
          'post': postUri,
          'sort': 'hot',
          'depth': 10,
          'limit': 50,
        },
      );

      expect(
        () => apiService.getComments(postUri: postUri),
        throwsA(isA<Exception>()),
      );
    });

    test('should handle network timeout', () async {
      const postUri = 'at://did:plc:test/social.coves.post.record/123';

      // requestOptions must match the mocked route so the RetryInterceptor's
      // retries re-hit this mock (and keep failing with the same error type).
      final requestOptions = RequestOptions(
        path: '/xrpc/social.coves.community.comment.getComments',
        queryParameters: {
          'post': postUri,
          'sort': 'hot',
          'depth': 10,
          'limit': 50,
        },
      );

      dioAdapter.onGet(
        '/xrpc/social.coves.community.comment.getComments',
        (server) => server.throws(
          408,
          DioException.connectionTimeout(
            timeout: const Duration(seconds: 30),
            requestOptions: requestOptions,
          ),
        ),
        queryParameters: {
          'post': postUri,
          'sort': 'hot',
          'depth': 10,
          'limit': 50,
        },
      );

      // Assert retry exhaustion actually happened so fixture drift can't
      // silently disable the RetryInterceptor again.
      try {
        await apiService.getComments(postUri: postUri);
        fail('Expected NetworkException');
      } on NetworkException catch (e) {
        final dioError = e.originalError as DioException;
        expect(dioError.message, contains('failed after 2 retries'));
        expect(dioError.requestOptions.extra['retriesExhausted'], isTrue);
      }
    });

    test('should handle network connection error', () async {
      const postUri = 'at://did:plc:test/social.coves.post.record/123';

      // requestOptions must match the mocked route so the RetryInterceptor's
      // retries re-hit this mock (and keep failing with the same error type).
      final requestOptions = RequestOptions(
        path: '/xrpc/social.coves.community.comment.getComments',
        queryParameters: {
          'post': postUri,
          'sort': 'hot',
          'depth': 10,
          'limit': 50,
        },
      );

      dioAdapter.onGet(
        '/xrpc/social.coves.community.comment.getComments',
        (server) => server.throws(
          503,
          DioException.connectionError(
            reason: 'Connection refused',
            requestOptions: requestOptions,
          ),
        ),
        queryParameters: {
          'post': postUri,
          'sort': 'hot',
          'depth': 10,
          'limit': 50,
        },
      );

      // Assert retry exhaustion actually happened so fixture drift can't
      // silently disable the RetryInterceptor again.
      try {
        await apiService.getComments(postUri: postUri);
        fail('Expected NetworkException');
      } on NetworkException catch (e) {
        final dioError = e.originalError as DioException;
        expect(dioError.message, contains('failed after 2 retries'));
        expect(dioError.requestOptions.extra['retriesExhausted'], isTrue);
      }
    });

    test('should handle invalid JSON response', () async {
      const postUri = 'at://did:plc:test/social.coves.post.record/123';

      dioAdapter.onGet(
        '/xrpc/social.coves.community.comment.getComments',
        (server) => server.reply(200, 'invalid json string'),
        queryParameters: {
          'post': postUri,
          'sort': 'hot',
          'depth': 10,
          'limit': 50,
        },
      );

      expect(
        () => apiService.getComments(postUri: postUri),
        throwsA(isA<ApiException>()),
      );
    });

    test('should handle malformed JSON with missing required fields', () async {
      const postUri = 'at://did:plc:test/social.coves.post.record/123';

      final mockResponse = {
        'post': {'uri': postUri},
        'comments': [
          {
            'comment': {
              'uri': 'at://did:plc:test/comment/1',
              // Missing required 'cid' field
              'record': {'content': 'Test'},
              'createdAt': '2025-01-01T12:00:00Z',
              'indexedAt': '2025-01-01T12:00:00Z',
              'author': {'did': 'did:plc:author', 'handle': 'user.test'},
              'post': {'uri': postUri, 'cid': 'post-cid'},
              'stats': {'upvotes': 0, 'downvotes': 0, 'score': 0},
            },
            'hasMore': false,
          },
        ],
      };

      dioAdapter.onGet(
        '/xrpc/social.coves.community.comment.getComments',
        (server) => server.reply(200, mockResponse),
        queryParameters: {
          'post': postUri,
          'sort': 'hot',
          'depth': 10,
          'limit': 50,
        },
      );

      // A malformed comment (missing required field raises a TypeError
      // during parsing) is skipped rather than killing the whole thread
      // load - one bad federated record must never blank the thread.
      final response = await apiService.getComments(postUri: postUri);
      expect(response.comments, isEmpty);
    });

    test('should handle comments with nested replies', () async {
      const postUri = 'at://did:plc:test/social.coves.post.record/123';

      final mockResponse = {
        'post': {'uri': postUri},
        'cursor': null,
        'comments': [
          {
            'comment': {
              'uri': 'at://did:plc:test/comment/1',
              'cid': 'cid1',
              'record': {'content': 'Parent comment'},
              'createdAt': '2025-01-01T12:00:00Z',
              'indexedAt': '2025-01-01T12:00:00Z',
              'author': {'did': 'did:plc:author1', 'handle': 'user1.test'},
              'post': {'uri': postUri, 'cid': 'post-cid'},
              'stats': {'upvotes': 10, 'downvotes': 2, 'score': 8},
            },
            'replies': [
              {
                'comment': {
                  'uri': 'at://did:plc:test/comment/2',
                  'cid': 'cid2',
                  'record': {'content': 'Reply comment'},
                  'createdAt': '2025-01-01T13:00:00Z',
                  'indexedAt': '2025-01-01T13:00:00Z',
                  'author': {'did': 'did:plc:author2', 'handle': 'user2.test'},
                  'post': {'uri': postUri, 'cid': 'post-cid'},
                  'parent': {
                    'uri': 'at://did:plc:test/comment/1',
                    'cid': 'cid1',
                  },
                  'stats': {'upvotes': 5, 'downvotes': 0, 'score': 5},
                },
                'hasMore': false,
              },
            ],
            'hasMore': false,
          },
        ],
      };

      dioAdapter.onGet(
        '/xrpc/social.coves.community.comment.getComments',
        (server) => server.reply(200, mockResponse),
        queryParameters: {
          'post': postUri,
          'sort': 'hot',
          'depth': 10,
          'limit': 50,
        },
      );

      final response = await apiService.getComments(postUri: postUri);

      expect(response.comments.length, 1);
      expect(response.comments[0].comment.content, 'Parent comment');
      expect(response.comments[0].replies, isNotNull);
      expect(response.comments[0].replies!.length, 1);
      expect(response.comments[0].replies![0].comment.content, 'Reply comment');
    });

    test('should handle comments with viewer state', () async {
      const postUri = 'at://did:plc:test/social.coves.post.record/123';

      final mockResponse = {
        'post': {'uri': postUri},
        'cursor': null,
        'comments': [
          {
            'comment': {
              'uri': 'at://did:plc:test/comment/1',
              'cid': 'cid1',
              'record': {'content': 'Voted comment'},
              'createdAt': '2025-01-01T12:00:00Z',
              'indexedAt': '2025-01-01T12:00:00Z',
              'author': {'did': 'did:plc:author', 'handle': 'user.test'},
              'post': {'uri': postUri, 'cid': 'post-cid'},
              'stats': {'upvotes': 10, 'downvotes': 0, 'score': 10},
              'viewer': {'vote': 'upvote'},
            },
            'hasMore': false,
          },
        ],
      };

      dioAdapter.onGet(
        '/xrpc/social.coves.community.comment.getComments',
        (server) => server.reply(200, mockResponse),
        queryParameters: {
          'post': postUri,
          'sort': 'hot',
          'depth': 10,
          'limit': 50,
        },
      );

      final response = await apiService.getComments(postUri: postUri);

      expect(response.comments.length, 1);
      expect(response.comments[0].comment.viewer, isNotNull);
      expect(response.comments[0].comment.viewer!.vote, 'upvote');
    });
  });

  group('CovesApiService - getActorLikes', () {
    const endpoint = '/xrpc/social.coves.actor.getLikes';
    const actor = 'did:plc:liker';

    late Dio dio;
    late DioAdapter dioAdapter;
    late CovesApiService apiService;

    /// The query parameters of every request sent, recorded after the
    /// service's own interceptors so the adapter can answer by path alone.
    late List<Map<String, dynamic>> sentQueries;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'https://api.test.coves.social'));
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      apiService = CovesApiService(
        sessionKeyOf: () => (did: actor, sessionId: 'session-1'),
        dio: dio,
        tokenGetter: () async => 'test-token',
      );
      sentQueries = <Map<String, dynamic>>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            sentQueries.add(Map<String, dynamic>.of(options.queryParameters));
            handler.next(options);
          },
        ),
      );
    });

    tearDown(() {
      apiService.dispose();
    });

    Map<String, dynamic> postViewJson(String rkey) => {
      'uri': 'at://did:plc:community1/social.coves.community.post/$rkey',
      'cid': 'cid-$rkey',
      'rkey': rkey,
      'author': {'did': 'did:plc:author1', 'handle': 'author.test'},
      'community': {'did': 'did:plc:community1', 'name': 'testcommunity'},
      'record': {'title': 'Liked $rkey', 'content': 'body'},
      'createdAt': '2025-06-01T12:00:00Z',
      'indexedAt': '2025-06-01T12:00:01Z',
      'stats': {'upvotes': 1, 'downvotes': 0, 'score': 1, 'commentCount': 0},
    };

    Map<String, dynamic> feedViewPostJson(String rkey) => {
      r'$type': 'social.coves.actor.getLikes#likedPost',
      'post': postViewJson(rkey),
    };

    Map<String, dynamic> likedCommentJson(String rkey) => {
      r'$type': 'social.coves.actor.getLikes#likedComment',
      'comment': {
        'uri': 'at://did:plc:author1/social.coves.community.comment/$rkey',
        'cid': 'cid-$rkey',
        'record': {'content': 'Liked comment $rkey'},
        'createdAt': '2025-06-01T12:00:00Z',
        'indexedAt': '2025-06-01T12:00:01Z',
        'author': {'did': 'did:plc:author1', 'handle': 'author.test'},
        'post': {
          'uri': 'at://did:plc:community1/social.coves.community.post/root',
          'cid': 'cid-root',
        },
        'stats': {'upvotes': 1, 'downvotes': 0, 'score': 1},
      },
      'post': postViewJson('root'),
    };

    String describeLike(LikedItem item) => switch (item) {
      LikedPost(:final feedViewPost) => 'post ${feedViewPost.post.uri}',
      LikedComment(:final comment, :final post) =>
        'comment ${comment.uri} on ${post.uri}',
    };

    const likedCommentEeeOnRoot =
        'comment at://did:plc:author1/social.coves.community.comment/eee '
        'on at://did:plc:community1/social.coves.community.post/root';

    // Each row pins the exact request: the default page size, the cursor
    // only when given, and the filter only when it narrows the list.
    final rows =
        <
          ({
            String name,
            LikesFilter filter,
            String? cursor,
            Map<String, dynamic> query,
            Map<String, dynamic> body,
            List<String> expectedItems,
            String? expectedCursor,
          })
        >[
          (
            name: 'first page',
            filter: LikesFilter.all,
            cursor: null,
            query: {'actor': actor, 'limit': 15},
            body: {
              'feed': [feedViewPostJson('aaa'), feedViewPostJson('bbb')],
              'cursor': 'next-1',
            },
            expectedItems: [
              'post at://did:plc:community1/social.coves.community.post/aaa',
              'post at://did:plc:community1/social.coves.community.post/bbb',
            ],
            expectedCursor: 'next-1',
          ),
          (
            name: 'next page',
            filter: LikesFilter.all,
            cursor: 'next-1',
            query: {'actor': actor, 'limit': 15, 'cursor': 'next-1'},
            body: {
              'feed': [feedViewPostJson('ccc')],
            },
            expectedItems: [
              'post at://did:plc:community1/social.coves.community.post/ccc',
            ],
            expectedCursor: null,
          ),
          (
            name: 'posts filter',
            filter: LikesFilter.posts,
            cursor: null,
            query: {'actor': actor, 'filter': 'posts', 'limit': 15},
            body: {
              'feed': [feedViewPostJson('ddd')],
            },
            expectedItems: [
              'post at://did:plc:community1/social.coves.community.post/ddd',
            ],
            expectedCursor: null,
          ),
          (
            name: 'comments filter',
            filter: LikesFilter.comments,
            cursor: 'next-2',
            query: {
              'actor': actor,
              'filter': 'comments',
              'limit': 15,
              'cursor': 'next-2',
            },
            body: {
              'feed': [likedCommentJson('eee')],
              'cursor': 'next-3',
            },
            expectedItems: [likedCommentEeeOnRoot],
            expectedCursor: 'next-3',
          ),
        ];

    for (final row in rows) {
      test('GETs getLikes and parses the ${row.name}', () async {
        dioAdapter.onGet(endpoint, (server) => server.reply(200, row.body));

        final response = await apiService.getActorLikes(
          actor: actor,
          filter: row.filter,
          cursor: row.cursor,
        );

        expect(sentQueries, <Map<String, dynamic>>[row.query]);
        expect(response.feed.map(describeLike).toList(), row.expectedItems);
        expect(response.cursor, row.expectedCursor);
      });
    }

    // An older backend answers with bare FeedViewPosts (no $type). Every
    // item is then skipped, and an empty page with a cursor would make the
    // client walk the whole history page by page showing nothing. A
    // non-empty feed in which nothing parses is a failed page; a genuinely
    // empty feed is not.
    final unparseableRows =
        <({String name, Map<String, dynamic> body, bool throws})>[
          (
            name: 'a non-empty feed in which no item parses',
            body: {
              'feed': [
                {'post': postViewJson('aaa')},
              ],
              'cursor': 'c1',
            },
            throws: true,
          ),
          (
            name: 'an empty feed',
            body: {'feed': <Object>[], 'cursor': 'c1'},
            throws: false,
          ),
        ];
    for (final row in unparseableRows) {
      test(
        'getLikes with ${row.name} '
        '${row.throws ? 'throws ApiException' : 'returns an empty page'}',
        () async {
          dioAdapter.onGet(endpoint, (server) => server.reply(200, row.body));

          final call = apiService.getActorLikes(actor: actor);

          if (row.throws) {
            await expectLater(call, throwsA(isA<ApiException>()));
          } else {
            final response = await call;
            expect(response.feed, isEmpty);
            expect(response.cursor, 'c1');
          }
        },
      );
    }
  });
}
