/// API Exception Types
///
/// Custom exception classes for different types of API failures.
/// This allows better error handling and user-friendly error messages.
library;

import 'package:dio/dio.dart';

/// Base class for all API exceptions
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.originalError});

  /// Create ApiException from DioException
  factory ApiException.fromDioError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return NetworkException(
          'Request timeout. Please check your connection.',
          originalError: error,
        );
      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode;
        final message =
            error.response?.data?['message'] as String? ??
            error.response?.data?['error'] as String? ??
            'Server error';

        if (statusCode == 401) {
          return AuthenticationException(message, originalError: error);
        } else if (statusCode == 404) {
          return NotFoundException(message, originalError: error);
        } else if (statusCode != null && statusCode >= 500) {
          return ServerException(
            message,
            statusCode: statusCode,
            originalError: error,
          );
        }
        return ApiException(
          message,
          statusCode: statusCode,
          originalError: error,
        );
      case DioExceptionType.cancel:
        return ApiException('Request was cancelled', originalError: error);
      case DioExceptionType.connectionError:
        return NetworkException(
          'Connection failed. Please check your internet.',
          originalError: error,
        );
      case DioExceptionType.badCertificate:
        return NetworkException('SSL certificate error', originalError: error);
      case DioExceptionType.unknown:
        return NetworkException('Network error occurred', originalError: error);
    }
  }
  final String message;
  final int? statusCode;
  final dynamic originalError;

  @override
  String toString() => message;
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
