/// API Exception Types
///
/// Custom exception classes for different types of API failures.
/// This allows better error handling and user-friendly error messages.
///
/// [ApiException.fromDioError] is the single canonical mapping from
/// [DioException] to these types, and [mapDioException] is the entry point
/// services use (it adds the redacted debug logging). Services must not
/// hand-roll their own status-code switches; substituting friendlier
/// message *copy* for an expected status is fine (see
/// `CommentService.deleteComment`), but the exception types must stay
/// within this taxonomy.
library;

import 'dart:io';

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
  /// [FederationException] (the PDS may be unreachable), cancelled
  /// requests → a plain [ApiException].
  factory ApiException.fromDioError(DioException error) {
    final response = error.response;
    final statusCode = response?.statusCode;

    if (response != null && statusCode != null) {
      // Handle both JSON error responses and plain text responses.
      // Read the fields defensively — a hostile or buggy server can put
      // non-string values in either, and a TypeError thrown here would
      // escape the whole ApiException taxonomy.
      String? message;
      final data = response.data;
      if (data is Map<String, dynamic>) {
        final rawMessage = data['message'];
        final rawError = data['error'];
        if (rawMessage is String && rawMessage.isNotEmpty) {
          message = rawMessage;
        } else if (rawError is String && rawError.isNotEmpty) {
          message = rawError;
        }
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
        if (_isDnsFailure(error)) {
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
          'Bad response from server: ${error.message ?? 'no details'}',
          originalError: error,
        );
      case DioExceptionType.unknown:
        // Dio uses `unknown` for more than transport failures (decode
        // errors, interceptor throws, ...). Classify by the wrapped error
        // so a truncated 200 body isn't blamed on the user's connection.
        final inner = error.error;
        if (inner is FormatException) {
          return ApiException(
            'Failed to parse server response',
            originalError: error,
          );
        }
        if (inner is IOException) {
          return NetworkException(
            'Network error: ${error.message ?? inner}',
            originalError: error,
          );
        }
        return ApiException(
          'Unknown error: ${error.message ?? inner ?? 'no details'}',
          originalError: error,
        );
    }
  }

  /// True when a connection error is a DNS resolution failure. Prefers the
  /// typed [SocketException] over Dio's message text, which varies by
  /// platform; the substring check remains as a fallback.
  static bool _isDnsFailure(DioException error) {
    final inner = error.error;
    if (inner is SocketException &&
        inner.message.contains('Failed host lookup')) {
      return true;
    }
    return error.message?.contains('Failed host lookup') ?? false;
  }

  final String message;
  final int? statusCode;

  /// The underlying error, typically the mapped [DioException].
  ///
  /// May embed the full request — including a live Authorization header —
  /// so never log or serialize this field. Log [message], or pass response
  /// data through [redactBearerTokens] first.
  final dynamic originalError;

  @override
  String toString() => message;
}

/// Maps [error] to a typed [ApiException] after logging it in debug builds
/// (response data is passed through [redactBearerTokens] first).
/// [operation] labels the log line, e.g. 'fetch timeline'.
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
