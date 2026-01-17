import 'dart:async';

import 'package:coves_flutter/services/retry_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  group('RetryInterceptor', () {
    late Dio dio;
    late RetryInterceptor interceptor;

    setUp(() {
      dio = Dio();
      interceptor = RetryInterceptor(
        dio: dio,
        maxRetries: 2,
        initialDelay: const Duration(milliseconds: 1), // Fast for tests
        serviceName: 'TestService',
      );
    });

    group('constructor validation', () {
      test('should reject negative maxRetries', () {
        expect(
          () => RetryInterceptor(dio: dio, maxRetries: -1),
          throwsA(isA<AssertionError>()),
        );
      });

      test('should reject zero initialDelay', () {
        expect(
          () => RetryInterceptor(dio: dio, initialDelay: Duration.zero),
          throwsA(isA<AssertionError>()),
        );
      });

      test('should reject empty serviceName', () {
        expect(
          () => RetryInterceptor(dio: dio, serviceName: ''),
          throwsA(isA<AssertionError>()),
        );
      });

      test('should accept valid parameters', () {
        expect(
          () => RetryInterceptor(
            dio: dio,
            maxRetries: 0,
            initialDelay: const Duration(milliseconds: 1),
            serviceName: 'Test',
          ),
          returnsNormally,
        );
      });
    });

    group('retry decision logic', () {
      // Helper: Run onError and return the retryCount (null if no retry attempted)
      // Uses runZonedGuarded to properly catch the async exception from handler.next()
      Future<int?> getRetryCount(DioException error) async {
        final completer = Completer<int?>();

        runZonedGuarded(
          () async {
            final handler = ErrorInterceptorHandler();
            await interceptor.onError(error, handler);
            // If we get here without exception, return the retryCount
            completer.complete(error.requestOptions.extra['retryCount'] as int?);
          },
          (e, stack) {
            // Exception thrown (expected from handler.next())
            // Complete with the retryCount that was set before the exception
            if (!completer.isCompleted) {
              completer
                  .complete(error.requestOptions.extra['retryCount'] as int?);
            }
          },
        );

        return completer.future;
      }

      test('should NOT retry POST requests with receiveTimeout', () async {
        // CRITICAL TEST: POST + receiveTimeout should NOT retry because
        // the server may have already processed the request.
        final error = DioException(
          type: DioExceptionType.receiveTimeout,
          requestOptions:
              RequestOptions(path: '/create-comment', method: 'POST'),
        );

        final retryCount = await getRetryCount(error);

        expect(
          retryCount,
          isNull,
          reason: 'POST + receiveTimeout must NOT retry (prevents duplicates)',
        );
      });

      test('should NOT retry on HTTP errors (badResponse)', () async {
        final requestOptions = RequestOptions(path: '/test', method: 'GET');
        final error = DioException(
          type: DioExceptionType.badResponse,
          requestOptions: requestOptions,
          response: Response(requestOptions: requestOptions, statusCode: 500),
        );

        final retryCount = await getRetryCount(error);

        expect(retryCount, isNull, reason: 'HTTP errors should not be retried');
      });

      test('should NOT retry on cancel', () async {
        final error = DioException(
          type: DioExceptionType.cancel,
          requestOptions: RequestOptions(path: '/test', method: 'GET'),
        );

        final retryCount = await getRetryCount(error);

        expect(
          retryCount,
          isNull,
          reason: 'Cancelled requests should not retry',
        );
      });

      test('should NOT retry on badCertificate', () async {
        final error = DioException(
          type: DioExceptionType.badCertificate,
          requestOptions: RequestOptions(path: '/test', method: 'GET'),
        );

        final retryCount = await getRetryCount(error);

        expect(
          retryCount,
          isNull,
          reason: 'Certificate errors should not retry',
        );
      });
    });

    group('integration: POST receiveTimeout prevents duplicates', () {
      test('POST + receiveTimeout results in exactly 1 request', () async {
        // This is the critical integration test that verifies our fix
        // prevents duplicate comments/votes from being created.
        final mockDio = Dio();
        final dioAdapter = DioAdapter(dio: mockDio);
        var callCount = 0;

        mockDio.interceptors.add(
          RetryInterceptor(
            dio: mockDio,
            maxRetries: 2,
            initialDelay: const Duration(milliseconds: 1),
            serviceName: 'TestService',
          ),
        );

        dioAdapter.onPost(
          '/create-comment',
          (server) {
            callCount++;
            server.throws(
              0,
              DioException(
                type: DioExceptionType.receiveTimeout,
                requestOptions:
                    RequestOptions(path: '/create-comment', method: 'POST'),
              ),
            );
          },
          data: Matchers.any,
        );

        try {
          await mockDio.post('/create-comment', data: {'text': 'hello'});
        } catch (e) {
          expect(e, isA<DioException>());
        }

        // CRITICAL ASSERTION: Only 1 call made, no retry
        // This prevents duplicate comments/votes from being created
        expect(
          callCount,
          equals(1),
          reason: 'POST + receiveTimeout must NOT retry to prevent duplicates',
        );
      });
    });
  });
}
