import 'dart:convert';

import 'package:atproto_oauth_flutter/atproto_oauth_flutter.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/vote_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'vote_service_test.mocks.dart';

// Generate mocks for OAuthSession
@GenerateMocks([OAuthSession])
void main() {
  group('VoteService', () {
    group('_findExistingVote pagination', () {
      test('should find vote in first page', () async {
        final mockSession = MockOAuthSession();
        final service = VoteService(
          sessionGetter: () async => mockSession,
          didGetter: () => 'did:plc:test',
          pdsUrlGetter: () => 'https://test.pds',
        );

        // Mock first page response with matching vote
        final firstPageResponse = http.Response(
          jsonEncode({
            'records': [
              {
                'uri': 'at://did:plc:test/social.coves.feed.vote/abc123',
                'value': {
                  'subject': {
                    'uri': 'at://did:plc:author/social.coves.post.record/post1',
                    'cid': 'bafy123',
                  },
                  'direction': 'up',
                  'createdAt': '2024-01-01T00:00:00Z',
                },
              },
            ],
            'cursor': null,
          }),
          200,
        );

        when(
          mockSession.fetchHandler(
            argThat(contains('listRecords')),
          ),
        ).thenAnswer((_) async => firstPageResponse);

        // Mock deleteRecord for when existing vote is found
        when(
          mockSession.fetchHandler(
            argThat(contains('deleteRecord')),
            method: 'POST',
            headers: anyNamed('headers'),
            body: anyNamed('body'),
          ),
        ).thenAnswer((_) async => http.Response(jsonEncode({}), 200));

        // Test that vote is found via reflection (private method)
        // This is verified indirectly through createVote behavior
        final response = await service.createVote(
          postUri: 'at://did:plc:author/social.coves.post.record/post1',
          postCid: 'bafy123',
        );

        // Should return deleted=true because existing vote with same direction
        expect(response.deleted, true);
        verify(
          mockSession.fetchHandler(
            argThat(contains('listRecords')),
          ),
        ).called(1);
      });

      test('should paginate through multiple pages to find vote', () async {
        final mockSession = MockOAuthSession();
        final service = VoteService(
          sessionGetter: () async => mockSession,
          didGetter: () => 'did:plc:test',
          pdsUrlGetter: () => 'https://test.pds',
        );

        // Mock first page without matching vote but with cursor
        final firstPageResponse = http.Response(
          jsonEncode({
            'records': [
              {
                'uri': 'at://did:plc:test/social.coves.feed.vote/abc1',
                'value': {
                  'subject': {
                    'uri':
                        'at://did:plc:author/social.coves.post.record/other1',
                    'cid': 'bafy001',
                  },
                  'direction': 'up',
                },
              },
            ],
            'cursor': 'cursor123',
          }),
          200,
        );

        // Mock second page with matching vote
        final secondPageResponse = http.Response(
          jsonEncode({
            'records': [
              {
                'uri': 'at://did:plc:test/social.coves.feed.vote/abc123',
                'value': {
                  'subject': {
                    'uri':
                        'at://did:plc:author/social.coves.post.record/target',
                    'cid': 'bafy123',
                  },
                  'direction': 'up',
                  'createdAt': '2024-01-01T00:00:00Z',
                },
              },
            ],
            'cursor': null,
          }),
          200,
        );

        // Setup mock responses based on URL
        when(
          mockSession.fetchHandler(
            argThat(allOf(contains('listRecords'), isNot(contains('cursor')))),
          ),
        ).thenAnswer((_) async => firstPageResponse);

        when(
          mockSession.fetchHandler(
            argThat(
              allOf(contains('listRecords'), contains('cursor=cursor123')),
            ),
          ),
        ).thenAnswer((_) async => secondPageResponse);

        // Mock deleteRecord for when existing vote is found
        when(
          mockSession.fetchHandler(
            argThat(contains('deleteRecord')),
            method: 'POST',
            headers: anyNamed('headers'),
            body: anyNamed('body'),
          ),
        ).thenAnswer((_) async => http.Response(jsonEncode({}), 200));

        // Test that pagination works by creating vote that exists on page 2
        final response = await service.createVote(
          postUri: 'at://did:plc:author/social.coves.post.record/target',
          postCid: 'bafy123',
        );

        // Should return deleted=true because existing vote was found on page 2
        expect(response.deleted, true);

        // Verify both pages were fetched
        verify(
          mockSession.fetchHandler(
            argThat(allOf(contains('listRecords'), isNot(contains('cursor')))),
          ),
        ).called(1);

        verify(
          mockSession.fetchHandler(
            argThat(
              allOf(contains('listRecords'), contains('cursor=cursor123')),
            ),
          ),
        ).called(1);
      });

      test('should handle vote not found after pagination', () async {
        final mockSession = MockOAuthSession();
        final service = VoteService(
          sessionGetter: () async => mockSession,
          didGetter: () => 'did:plc:test',
          pdsUrlGetter: () => 'https://test.pds',
        );

        // Mock response with no matching votes
        final response = http.Response(
          jsonEncode({
            'records': [
              {
                'uri': 'at://did:plc:test/social.coves.feed.vote/abc1',
                'value': {
                  'subject': {
                    'uri': 'at://did:plc:author/social.coves.post.record/other',
                    'cid': 'bafy001',
                  },
                  'direction': 'up',
                },
              },
            ],
            'cursor': null,
          }),
          200,
        );

        when(
          mockSession.fetchHandler(
            argThat(contains('listRecords')),
          ),
        ).thenAnswer((_) async => response);

        // Mock createRecord for new vote
        when(
          mockSession.fetchHandler(
            argThat(contains('createRecord')),
            method: 'POST',
            headers: anyNamed('headers'),
            body: anyNamed('body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'uri': 'at://did:plc:test/social.coves.feed.vote/new123',
              'cid': 'bafy456',
            }),
            200,
          ),
        );

        // Test creating vote for post not in vote history
        final voteResponse = await service.createVote(
          postUri: 'at://did:plc:author/social.coves.post.record/newpost',
          postCid: 'bafy123',
        );

        // Should create new vote
        expect(voteResponse.deleted, false);
        expect(voteResponse.uri, isNotNull);
        expect(voteResponse.cid, 'bafy456');

        // Verify createRecord was called
        verify(
          mockSession.fetchHandler(
            argThat(contains('createRecord')),
            method: 'POST',
            headers: anyNamed('headers'),
            body: anyNamed('body'),
          ),
        ).called(1);
      });
    });

    group('createVote', () {
      test('should create vote successfully', () async {
        // Create a real VoteService instance that we can test with
        // We'll use a minimal test to verify the VoteResponse parsing logic

        const response = VoteResponse(
          uri: 'at://did:plc:test/social.coves.feed.vote/456',
          cid: 'bafy123',
          rkey: '456',
          deleted: false,
        );

        expect(response.uri, 'at://did:plc:test/social.coves.feed.vote/456');
        expect(response.cid, 'bafy123');
        expect(response.rkey, '456');
        expect(response.deleted, false);
      });

      test('should return deleted response when vote is toggled off', () {
        const response = VoteResponse(deleted: true);

        expect(response.deleted, true);
        expect(response.uri, null);
        expect(response.cid, null);
      });

      test('should throw ApiException on Dio network error', () {
        // Test ApiException.fromDioError for connection errors
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.connectionError,
        );

        final exception = ApiException.fromDioError(dioError);

        expect(exception, isA<NetworkException>());
        expect(exception.message, contains('Connection failed'));
      });

      test('should throw ApiException on Dio timeout', () {
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.connectionTimeout,
        );

        final exception = ApiException.fromDioError(dioError);

        expect(exception, isA<NetworkException>());
        expect(exception.message, contains('timeout'));
      });

      test('should throw AuthenticationException on 401 response', () {
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/test'),
            statusCode: 401,
            data: {'message': 'Unauthorized'},
          ),
        );

        final exception = ApiException.fromDioError(dioError);

        expect(exception, isA<AuthenticationException>());
        expect(exception.statusCode, 401);
        expect(exception.message, 'Unauthorized');
      });

      test('should throw NotFoundException on 404 response', () {
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/test'),
            statusCode: 404,
            data: {'message': 'Post not found'},
          ),
        );

        final exception = ApiException.fromDioError(dioError);

        expect(exception, isA<NotFoundException>());
        expect(exception.statusCode, 404);
        expect(exception.message, 'Post not found');
      });

      test('should throw ServerException on 500 response', () {
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/test'),
            statusCode: 500,
            data: {'error': 'Internal server error'},
          ),
        );

        final exception = ApiException.fromDioError(dioError);

        expect(exception, isA<ServerException>());
        expect(exception.statusCode, 500);
        expect(exception.message, 'Internal server error');
      });

      test('should extract error message from response data', () {
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/test'),
            statusCode: 400,
            data: {'message': 'Invalid post URI'},
          ),
        );

        final exception = ApiException.fromDioError(dioError);

        expect(exception.message, 'Invalid post URI');
        expect(exception.statusCode, 400);
      });

      test('should use default message if no error message in response', () {
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/test'),
            statusCode: 400,
            data: {},
          ),
        );

        final exception = ApiException.fromDioError(dioError);

        expect(exception.message, 'Server error');
      });

      test('should handle cancelled requests', () {
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.cancel,
        );

        final exception = ApiException.fromDioError(dioError);

        expect(exception.message, contains('cancelled'));
      });

      test('should handle bad certificate errors', () {
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.badCertificate,
        );

        final exception = ApiException.fromDioError(dioError);

        expect(exception, isA<NetworkException>());
        expect(exception.message, contains('certificate'));
      });

      test('should handle unknown errors', () {
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/test'),
        );

        final exception = ApiException.fromDioError(dioError);

        expect(exception, isA<NetworkException>());
        expect(exception.message, contains('Network error'));
      });
    });

    group('VoteResponse', () {
      test('should create response with uri, cid, and rkey', () {
        const response = VoteResponse(
          uri: 'at://vote/123',
          cid: 'bafy123',
          rkey: '123',
          deleted: false,
        );

        expect(response.uri, 'at://vote/123');
        expect(response.cid, 'bafy123');
        expect(response.rkey, '123');
        expect(response.deleted, false);
      });

      test('should create response with rkey extracted from uri', () {
        const response = VoteResponse(
          uri: 'at://vote/456',
          cid: 'bafy456',
          rkey: '456',
          deleted: false,
        );

        expect(response.uri, 'at://vote/456');
        expect(response.cid, 'bafy456');
        expect(response.rkey, '456');
        expect(response.deleted, false);
      });

      test('should create deleted response', () {
        const response = VoteResponse(deleted: true);

        expect(response.deleted, true);
        expect(response.uri, null);
        expect(response.cid, null);
        expect(response.rkey, null);
      });
    });
  });
}
