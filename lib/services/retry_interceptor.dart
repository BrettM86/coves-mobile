import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Retry interceptor for transient network errors
///
/// Handles intermittent connection issues common on mobile networks:
/// - Connection timeouts (TCP SYN not acknowledged)
/// - Send/receive timeouts
/// - Connection errors (network switch, NAT issues)
///
/// Uses exponential backoff between retries to avoid overwhelming
/// the server during transient issues.
class RetryInterceptor extends Interceptor {
  RetryInterceptor({
    required this.dio,
    this.maxRetries = 2,
    this.initialDelay = const Duration(milliseconds: 500),
    this.serviceName = 'API',
  })  : assert(maxRetries >= 0, 'maxRetries must be non-negative'),
        assert(initialDelay > Duration.zero, 'initialDelay must be positive'),
        assert(serviceName.isNotEmpty, 'serviceName must not be empty');

  /// Key used in request extras to track retry count
  static const _retryCountKey = 'retryCount';

  final Dio dio;
  final int maxRetries;
  final Duration initialDelay;
  final String serviceName;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // Only retry on transient network errors, not HTTP errors
    if (!_shouldRetry(err)) {
      return handler.next(err);
    }

    // Check current retry count
    final retryCount = err.requestOptions.extra[_retryCountKey] as int? ?? 0;

    if (retryCount >= maxRetries) {
      if (kDebugMode) {
        debugPrint(
          '❌ $serviceName: Max retries ($maxRetries) exceeded for '
          '${err.requestOptions.path}',
        );
      }
      // Add retry context to the error for better user feedback
      final enhancedError = DioException(
        requestOptions: err.requestOptions,
        response: err.response,
        type: err.type,
        error: err.error,
        stackTrace: err.stackTrace,
        message: '${err.message ?? _errorTypeDescription(err.type)} '
            '(failed after $maxRetries retries)',
      );
      enhancedError.requestOptions.extra['retriesExhausted'] = true;
      enhancedError.requestOptions.extra['totalRetries'] = maxRetries;
      return handler.next(enhancedError);
    }

    // Calculate delay with exponential backoff
    final delay = initialDelay * (1 << retryCount); // 500ms, 1s, 2s, ...

    if (kDebugMode) {
      debugPrint(
        '🔄 $serviceName: Retry ${retryCount + 1}/$maxRetries for '
        '${err.requestOptions.path} after ${delay.inMilliseconds}ms '
        '(${_errorTypeDescription(err.type)})',
      );
    }

    // Wait before retrying
    await Future<void>.delayed(delay);

    // Update retry count
    err.requestOptions.extra[_retryCountKey] = retryCount + 1;

    try {
      // Retry the request
      final response = await dio.fetch(err.requestOptions);
      return handler.resolve(response);
    } on DioException catch (e) {
      // Let the interceptor chain handle the new error (may retry again)
      return handler.next(e);
    }
  }

  /// HTTP methods that are safe to retry after an ambiguous failure:
  /// they don't mutate server state, so a duplicate delivery is harmless.
  static const _idempotentMethods = {'GET', 'HEAD', 'OPTIONS'};

  /// Determine if the error is retryable
  ///
  /// Only retry on transient network errors, not:
  /// - HTTP errors (4xx, 5xx) - server responded, retry won't help
  /// - Request cancellation - intentional
  /// - Bad certificate - security issue
  /// - Ambiguous failures on mutating methods - see below
  bool _shouldRetry(DioException err) {
    // Never retry mutating requests (POST etc.) when the failure is
    // ambiguous about whether the server already processed the request:
    // - receiveTimeout: the request was fully sent; only the response
    //   was lost
    // - connectionError: dio raises this for resets both before AND after
    //   the request went out, so the server may have processed it
    // Retrying would double-submit: a vote toggle fired twice silently
    // reverts the user's vote, a comment posts twice, etc.
    // connectionTimeout/sendTimeout stay retryable: the request never
    // fully reached the server, so it cannot have been processed.
    if (!_idempotentMethods.contains(err.requestOptions.method) &&
        (err.type == DioExceptionType.receiveTimeout ||
            err.type == DioExceptionType.connectionError)) {
      return false;
    }

    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.badResponse:
      case DioExceptionType.badCertificate:
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
        return false;
    }
  }

  String _errorTypeDescription(DioExceptionType type) {
    switch (type) {
      case DioExceptionType.connectionTimeout:
        return 'connection timeout';
      case DioExceptionType.sendTimeout:
        return 'send timeout';
      case DioExceptionType.receiveTimeout:
        return 'receive timeout';
      case DioExceptionType.connectionError:
        return 'connection error';
      default:
        return type.toString();
    }
  }
}
