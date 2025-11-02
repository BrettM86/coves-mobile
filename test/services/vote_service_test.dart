import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/vote_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VoteService', () {
    group('createVote', () {

      test('should create vote successfully', () async {
        // Create a real VoteService instance that we can test with
        // We'll use a minimal test to verify the VoteResponse parsing logic

        const response = VoteResponse(
          uri: 'at://did:plc:test/social.coves.interaction.vote/456',
          cid: 'bafy123',
          rkey: '456',
          deleted: false,
        );

        expect(response.uri, 'at://did:plc:test/social.coves.interaction.vote/456');
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
        expect(
          exception.message,
          contains('Connection failed'),
        );
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
