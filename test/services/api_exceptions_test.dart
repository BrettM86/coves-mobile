import 'dart:io';

import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the canonical DioException → ApiException mapper.
///
/// This is the single mapping used by CovesApiService, VoteService, and
/// CommentService — behavior asserted here holds for every endpoint that
/// delegates to it (CommentService.deleteComment substitutes its own
/// message copy for 403/404 but keeps the taxonomy).
void main() {
  DioException responseError(
    int statusCode,
    Object? data, {
    DioExceptionType type = DioExceptionType.badResponse,
  }) {
    return DioException(
      requestOptions: RequestOptions(path: '/test'),
      type: type,
      response: Response(
        requestOptions: RequestOptions(path: '/test'),
        statusCode: statusCode,
        data: data,
      ),
    );
  }

  DioException networkError(DioExceptionType type, {String? message}) {
    return DioException(
      requestOptions: RequestOptions(path: '/test'),
      type: type,
      message: message,
    );
  }

  group('ApiException.fromDioError - responses with status codes', () {
    test('maps 401 to AuthenticationException', () {
      final exception = ApiException.fromDioError(
        responseError(401, {'message': 'Unauthorized'}),
      );

      expect(exception, isA<AuthenticationException>());
      expect(exception.statusCode, 401);
      expect(exception.message, 'Unauthorized');
    });

    test('maps 404 to NotFoundException', () {
      final exception = ApiException.fromDioError(
        responseError(404, {'message': 'Post not found'}),
      );

      expect(exception, isA<NotFoundException>());
      expect(exception.statusCode, 404);
      expect(exception.message, 'Post not found');
    });

    test('maps 5xx to ServerException', () {
      final exception = ApiException.fromDioError(
        responseError(500, {'error': 'Internal server error'}),
      );

      expect(exception, isA<ServerException>());
      expect(exception.statusCode, 500);
      expect(exception.message, 'Internal server error');
    });

    test('maps other status codes to plain ApiException', () {
      final exception = ApiException.fromDioError(
        responseError(400, {'message': 'Invalid post URI'}),
      );

      expect(exception, isA<ApiException>());
      expect(exception, isNot(isA<AuthenticationException>()));
      expect(exception.statusCode, 400);
      expect(exception.message, 'Invalid post URI');
    });

    test('prefers human-readable message over XRPC error code', () {
      final exception = ApiException.fromDioError(
        responseError(400, {
          'error': 'InvalidRequest',
          'message': 'title too long',
        }),
      );

      expect(exception.message, 'title too long');
    });

    test('falls back to the XRPC error code when message is absent', () {
      final exception = ApiException.fromDioError(
        responseError(400, {'error': 'InvalidRequest'}),
      );

      expect(exception.message, 'InvalidRequest');
    });

    test('uses plain-text response bodies as the message', () {
      final exception = ApiException.fromDioError(
        responseError(502, 'upstream unavailable'),
      );

      expect(exception, isA<ServerException>());
      expect(exception.message, 'upstream unavailable');
    });

    test('uses a default message when the body has none', () {
      final exception = ApiException.fromDioError(
        responseError(400, <String, dynamic>{}),
      );

      expect(exception.message, 'Request failed with status 400');
    });

    test('does not throw on non-string message/error fields', () {
      // A hostile or buggy server can return structured values here; the
      // mapper must never let a TypeError escape the taxonomy.
      final exception = ApiException.fromDioError(
        responseError(400, {
          'message': {'detail': 'structured'},
          'error': 400,
        }),
      );

      expect(exception, isA<ApiException>());
      expect(exception.message, 'Request failed with status 400');
    });

    test('treats empty-string message as absent', () {
      final exception = ApiException.fromDioError(
        responseError(401, {'message': '', 'error': 'ExpiredToken'}),
      );

      expect(exception, isA<AuthenticationException>());
      expect(exception.message, 'ExpiredToken');
    });

    test('uses the default message for non-Map, non-String bodies', () {
      final exception = ApiException.fromDioError(
        responseError(400, ['unexpected', 'list']),
      );

      expect(exception.message, 'Request failed with status 400');
    });

    test('maps by status code regardless of DioExceptionType', () {
      final exception = ApiException.fromDioError(
        responseError(
          401,
          {'message': 'Token expired'},
          type: DioExceptionType.unknown,
        ),
      );

      expect(exception, isA<AuthenticationException>());
    });
  });

  group('ApiException.fromDioError - network-level errors', () {
    test('maps timeouts to NetworkException', () {
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        final exception = ApiException.fromDioError(networkError(type));

        expect(exception, isA<NetworkException>());
        expect(exception.message, contains('timeout'));
      }
    });

    test('maps connection errors to NetworkException', () {
      final exception = ApiException.fromDioError(
        networkError(DioExceptionType.connectionError),
      );

      expect(exception, isA<NetworkException>());
      expect(exception.message, contains('Network error'));
    });

    test('maps DNS resolution failures to FederationException', () {
      final exception = ApiException.fromDioError(
        networkError(
          DioExceptionType.connectionError,
          message: 'Failed host lookup: pds.example.com',
        ),
      );

      expect(exception, isA<FederationException>());
    });

    test('detects DNS failure via the typed SocketException too', () {
      // Dio's message text varies by platform; the typed inner error is
      // the reliable signal.
      final exception = ApiException.fromDioError(
        DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.connectionError,
          error: const SocketException("Failed host lookup: 'x.example'"),
        ),
      );

      expect(exception, isA<FederationException>());
    });

    test('maps bad certificates to NetworkException', () {
      final exception = ApiException.fromDioError(
        networkError(DioExceptionType.badCertificate),
      );

      expect(exception, isA<NetworkException>());
      expect(exception.message, contains('certificate'));
    });

    test('maps cancelled requests to ApiException', () {
      final exception = ApiException.fromDioError(
        networkError(DioExceptionType.cancel),
      );

      expect(exception.message, contains('cancelled'));
    });

    test('maps unknown errors wrapping an IOException to NetworkException',
        () {
      final exception = ApiException.fromDioError(
        DioException(
          requestOptions: RequestOptions(path: '/test'),
          error: const SocketException('Connection reset by peer'),
        ),
      );

      expect(exception, isA<NetworkException>());
      expect(exception.message, contains('Network error'));
    });

    test(
        'maps unknown errors wrapping a FormatException to a parse '
        'ApiException, not a network error', () {
      // A truncated 200 body must not tell the user to check their
      // connection.
      final exception = ApiException.fromDioError(
        DioException(
          requestOptions: RequestOptions(path: '/test'),
          error: const FormatException('Unexpected end of input'),
        ),
      );

      expect(exception, isA<ApiException>());
      expect(exception, isNot(isA<NetworkException>()));
      expect(exception.message, 'Failed to parse server response');
    });

    test('maps bare unknown errors to a plain ApiException', () {
      final exception = ApiException.fromDioError(
        networkError(DioExceptionType.unknown),
      );

      expect(exception, isA<ApiException>());
      expect(exception, isNot(isA<NetworkException>()));
      expect(exception.message, contains('Unknown error'));
    });
  });

  group('mapDioException', () {
    late List<String> logLines;
    late DebugPrintCallback originalDebugPrint;

    setUp(() {
      logLines = <String>[];
      originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        logLines.add(message ?? '');
      };
    });

    tearDown(() {
      debugPrint = originalDebugPrint;
    });

    test('returns the same mapping as fromDioError', () {
      final error = responseError(404, {'message': 'gone'});

      final exception = mapDioException(error, operation: 'test op');

      expect(exception, isA<NotFoundException>());
      expect(exception.message, 'gone');
    });

    test('redacts tokens echoed in the logged response body', () {
      const token = 'abc!def.secret~token';
      final error = responseError(500, {
        'error': 'InternalServerError',
        'message': 'debug echo: Bearer $token from upstream',
      });

      mapDioException(error, operation: 'test op');

      final output = logLines.join('\n');
      expect(output, contains('Data:'));
      expect(output, contains('Bearer [REDACTED]'));
      expect(output, isNot(contains(token)));
    });
  });
}
