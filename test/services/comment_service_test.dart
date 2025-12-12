import 'package:coves_flutter/models/coves_session.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/comment_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'comment_service_test.mocks.dart';

@GenerateMocks([Dio])
void main() {
  group('CommentService', () {
    group('CreateCommentResponse', () {
      test('should create response with uri and cid', () {
        const response = CreateCommentResponse(
          uri: 'at://did:plc:test/social.coves.community.comment/123',
          cid: 'bafy123',
        );

        expect(
          response.uri,
          'at://did:plc:test/social.coves.community.comment/123',
        );
        expect(response.cid, 'bafy123');
      });
    });

    group('createComment', () {
      late MockDio mockDio;
      late CommentService commentService;
      late CovesSession testSession;

      setUp(() {
        mockDio = MockDio();
        testSession = CovesSession(
          token: 'test-token',
          did: 'did:plc:test',
          sessionId: 'test-session-id',
          handle: 'test.user',
        );

        // Setup default interceptors behavior
        when(mockDio.interceptors).thenReturn(Interceptors());

        commentService = CommentService(
          sessionGetter: () async => testSession,
          tokenRefresher: () async => true,
          signOutHandler: () async {},
          dio: mockDio,
        );
      });

      test('should create comment successfully', () async {
        when(
          mockDio.post<Map<String, dynamic>>(
            '/xrpc/social.coves.community.comment.create',
            data: anyNamed('data'),
          ),
        ).thenAnswer(
          (_) async => Response(
            requestOptions: RequestOptions(path: ''),
            statusCode: 200,
            data: {
              'uri': 'at://did:plc:test/social.coves.community.comment/abc123',
              'cid': 'bafy123',
            },
          ),
        );

        final response = await commentService.createComment(
          rootUri: 'at://did:plc:author/social.coves.post.record/post123',
          rootCid: 'rootCid123',
          parentUri: 'at://did:plc:author/social.coves.post.record/post123',
          parentCid: 'parentCid123',
          content: 'This is a test comment',
        );

        expect(
          response.uri,
          'at://did:plc:test/social.coves.community.comment/abc123',
        );
        expect(response.cid, 'bafy123');

        verify(
          mockDio.post<Map<String, dynamic>>(
            '/xrpc/social.coves.community.comment.create',
            data: {
              'reply': {
                'root': {
                  'uri': 'at://did:plc:author/social.coves.post.record/post123',
                  'cid': 'rootCid123',
                },
                'parent': {
                  'uri': 'at://did:plc:author/social.coves.post.record/post123',
                  'cid': 'parentCid123',
                },
              },
              'content': 'This is a test comment',
            },
          ),
        ).called(1);
      });

      test('should throw AuthenticationException when no session', () async {
        final serviceWithoutSession = CommentService(
          sessionGetter: () async => null,
          tokenRefresher: () async => true,
          signOutHandler: () async {},
          dio: mockDio,
        );

        expect(
          () => serviceWithoutSession.createComment(
            rootUri: 'at://did:plc:author/post/123',
            rootCid: 'rootCid',
            parentUri: 'at://did:plc:author/post/123',
            parentCid: 'parentCid',
            content: 'Test comment',
          ),
          throwsA(isA<AuthenticationException>()),
        );
      });

      test('should throw ApiException on network error', () async {
        when(
          mockDio.post<Map<String, dynamic>>(
            '/xrpc/social.coves.community.comment.create',
            data: anyNamed('data'),
          ),
        ).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: ''),
            type: DioExceptionType.connectionError,
            message: 'Connection failed',
          ),
        );

        expect(
          () => commentService.createComment(
            rootUri: 'at://did:plc:author/post/123',
            rootCid: 'rootCid',
            parentUri: 'at://did:plc:author/post/123',
            parentCid: 'parentCid',
            content: 'Test comment',
          ),
          throwsA(isA<ApiException>()),
        );
      });

      test('should throw AuthenticationException on 401 response', () async {
        when(
          mockDio.post<Map<String, dynamic>>(
            '/xrpc/social.coves.community.comment.create',
            data: anyNamed('data'),
          ),
        ).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: ''),
            type: DioExceptionType.badResponse,
            response: Response(
              requestOptions: RequestOptions(path: ''),
              statusCode: 401,
              data: {'error': 'Unauthorized'},
            ),
          ),
        );

        expect(
          () => commentService.createComment(
            rootUri: 'at://did:plc:author/post/123',
            rootCid: 'rootCid',
            parentUri: 'at://did:plc:author/post/123',
            parentCid: 'parentCid',
            content: 'Test comment',
          ),
          throwsA(isA<AuthenticationException>()),
        );
      });

      test(
        'should throw ApiException on invalid response (null data)',
        () async {
          when(
            mockDio.post<Map<String, dynamic>>(
              '/xrpc/social.coves.community.comment.create',
              data: anyNamed('data'),
            ),
          ).thenAnswer(
            (_) async => Response(
              requestOptions: RequestOptions(path: ''),
              statusCode: 200,
              data: null,
            ),
          );

          expect(
            () => commentService.createComment(
              rootUri: 'at://did:plc:author/post/123',
              rootCid: 'rootCid',
              parentUri: 'at://did:plc:author/post/123',
              parentCid: 'parentCid',
              content: 'Test comment',
            ),
            throwsA(
              isA<ApiException>().having(
                (e) => e.message,
                'message',
                contains('no data'),
              ),
            ),
          );
        },
      );

      test(
        'should throw ApiException on invalid response (missing uri)',
        () async {
          when(
            mockDio.post<Map<String, dynamic>>(
              '/xrpc/social.coves.community.comment.create',
              data: anyNamed('data'),
            ),
          ).thenAnswer(
            (_) async => Response(
              requestOptions: RequestOptions(path: ''),
              statusCode: 200,
              data: {'cid': 'bafy123'},
            ),
          );

          expect(
            () => commentService.createComment(
              rootUri: 'at://did:plc:author/post/123',
              rootCid: 'rootCid',
              parentUri: 'at://did:plc:author/post/123',
              parentCid: 'parentCid',
              content: 'Test comment',
            ),
            throwsA(
              isA<ApiException>().having(
                (e) => e.message,
                'message',
                contains('missing uri'),
              ),
            ),
          );
        },
      );

      test(
        'should throw ApiException on invalid response (empty uri)',
        () async {
          when(
            mockDio.post<Map<String, dynamic>>(
              '/xrpc/social.coves.community.comment.create',
              data: anyNamed('data'),
            ),
          ).thenAnswer(
            (_) async => Response(
              requestOptions: RequestOptions(path: ''),
              statusCode: 200,
              data: {'uri': '', 'cid': 'bafy123'},
            ),
          );

          expect(
            () => commentService.createComment(
              rootUri: 'at://did:plc:author/post/123',
              rootCid: 'rootCid',
              parentUri: 'at://did:plc:author/post/123',
              parentCid: 'parentCid',
              content: 'Test comment',
            ),
            throwsA(
              isA<ApiException>().having(
                (e) => e.message,
                'message',
                contains('missing uri'),
              ),
            ),
          );
        },
      );

      test('should throw ApiException on server error', () async {
        when(
          mockDio.post<Map<String, dynamic>>(
            '/xrpc/social.coves.community.comment.create',
            data: anyNamed('data'),
          ),
        ).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: ''),
            type: DioExceptionType.badResponse,
            response: Response(
              requestOptions: RequestOptions(path: ''),
              statusCode: 500,
              data: {'error': 'Internal server error'},
            ),
            message: 'Internal server error',
          ),
        );

        expect(
          () => commentService.createComment(
            rootUri: 'at://did:plc:author/post/123',
            rootCid: 'rootCid',
            parentUri: 'at://did:plc:author/post/123',
            parentCid: 'parentCid',
            content: 'Test comment',
          ),
          throwsA(isA<ApiException>()),
        );
      });

      test('should send correct parent for nested reply', () async {
        when(
          mockDio.post<Map<String, dynamic>>(
            '/xrpc/social.coves.community.comment.create',
            data: anyNamed('data'),
          ),
        ).thenAnswer(
          (_) async => Response(
            requestOptions: RequestOptions(path: ''),
            statusCode: 200,
            data: {
              'uri': 'at://did:plc:test/social.coves.community.comment/reply1',
              'cid': 'bafyReply',
            },
          ),
        );

        await commentService.createComment(
          rootUri: 'at://did:plc:author/social.coves.post.record/post123',
          rootCid: 'postCid',
          parentUri:
              'at://did:plc:commenter/social.coves.community.comment/comment1',
          parentCid: 'commentCid',
          content: 'This is a nested reply',
        );

        verify(
          mockDio.post<Map<String, dynamic>>(
            '/xrpc/social.coves.community.comment.create',
            data: {
              'reply': {
                'root': {
                  'uri': 'at://did:plc:author/social.coves.post.record/post123',
                  'cid': 'postCid',
                },
                'parent': {
                  'uri':
                      'at://did:plc:commenter/social.coves.community.comment/'
                      'comment1',
                  'cid': 'commentCid',
                },
              },
              'content': 'This is a nested reply',
            },
          ),
        ).called(1);
      });
    });
  });
}
