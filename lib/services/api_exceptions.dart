/// API Exception Types
///
/// Custom exception classes for different types of API failures.
/// This allows better error handling and user-friendly error messages.
///
/// [ApiException.fromDioError] is the single canonical mapping from
/// [DioException] to these types — services must not hand-roll their own
/// status-code switches.
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'log_redaction.dart';

/// Base class for all API exceptions
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.originalError});

  /// Canonical mapping from [DioException] to a typed [ApiException].
  ///
  /// When the server responded, the message is taken from the XRPC error
  /// body (human-readable `message` preferred over the machine `error`
  /// code, plain-text bodies used as-is) and the status code picks the
  /// type: 401 → [AuthenticationException], 404 → [NotFoundException],
  /// 5xx → [ServerException], anything else → [ApiException].
  ///
  /// Without a response, the Dio error type picks the type: timeouts and
  /// connection failures → [NetworkException], DNS resolution failures →
  /// [FederationException] (the PDS may be unreachable).
  factory ApiException.fromDioError(DioException error) {
    final response = error.response;
    final statusCode = response?.statusCode;

    if (response != null && statusCode != null) {
      // Handle both JSON error responses and plain text responses
      String? message;
      final data = response.data;
      if (data is Map<String, dynamic>) {
        message = data['message'] as String? ?? data['error'] as String?;
      } else if (data is String && data.isNotEmpty) {
        message = data;
      }

      if (statusCode == 401) {
        return AuthenticationException(
          message ?? 'Authentication failed. Token expired or invalid',
          originalError: error,
        );
      }
      if (statusCode == 404) {
        return NotFoundException(
          message ?? 'Resource not found. PDS or content may not exist',
          originalError: error,
        );
      }
      if (statusCode >= 500) {
        return ServerException(
          message ?? 'Server error. Please try again later',
          statusCode: statusCode,
          originalError: error,
        );
      }
      return ApiException(
        message ?? 'Request failed with status $statusCode',
        statusCode: statusCode,
        originalError: error,
      );
    }

    // Network-level errors (no response from server)
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return NetworkException(
          'Connection timeout. Please check your internet connection',
          originalError: error,
        );
      case DioExceptionType.connectionError:
        // Could be federation issue if it's a PDS connection failure
        if (error.message?.contains('Failed host lookup') ?? false) {
          return FederationException(
            'Failed to connect to PDS. Server may be unreachable',
            originalError: error,
          );
        }
        return NetworkException(
          'Network error. Please check your internet connection',
          originalError: error,
        );
      case DioExceptionType.badCertificate:
        return NetworkException('SSL certificate error', originalError: error);
      case DioExceptionType.cancel:
        return ApiException('Request cancelled', originalError: error);
      case DioExceptionType.badResponse:
        // Response missing or without a status code
        return ApiException(
          'Bad response from server: ${error.message}',
          originalError: error,
        );
      case DioExceptionType.unknown:
        return NetworkException(
          'Network error: ${error.message ?? 'unknown'}',
          originalError: error,
        );
    }
  }

  final String message;
  final int? statusCode;
  final dynamic originalError;

  @override
  String toString() => message;
}

/// Maps [error] to a typed [ApiException] after logging it (with bearer
/// tokens redacted) in debug builds. [operation] labels the log line,
/// e.g. 'fetch timeline'.
ApiException mapDioException(DioException error, {required String operation}) {
  if (kDebugMode) {
    debugPrint('❌ Failed to $operation: ${error.message}');
    if (error.response != null) {
      debugPrint('   Status: ${error.response?.statusCode}');
      // Response data can echo credentials — redact before printing
      debugPrint(redactBearerTokens('   Data: ${error.response?.data}'));
    }
  }
  return ApiException.fromDioError(error);
}

/// Authentication failure (401)
/// Token expired, invalid, or missing
class AuthenticationException extends ApiException {
  AuthenticationException(super.message, {super.originalError})
    : super(statusCode: 401);
}

/// Resource not found (404)
/// PDS, community, post, or user not found
class NotFoundException extends ApiException {
  NotFoundException(super.message, {super.originalError})
    : super(statusCode: 404);
}

/// Server error (500+)
/// Backend or PDS server failure
class ServerException extends ApiException {
  ServerException(super.message, {super.statusCode, super.originalError});
}

/// Network connectivity failure
/// No internet, connection refused, timeout
class NetworkException extends ApiException {
  NetworkException(super.message, {super.originalError})
    : super(statusCode: null);
}

/// Federation error
/// atProto PDS unreachable or DID resolution failure
class FederationException extends ApiException {
  FederationException(super.message, {super.originalError})
    : super(statusCode: null);
}

/// Validation error
/// Client-side validation failure (empty content, exceeds limits, etc.)
class ValidationException extends ApiException {
  ValidationException(super.message) : super(statusCode: null);
}
