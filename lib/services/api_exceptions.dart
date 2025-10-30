/// API Exception Types
///
/// Custom exception classes for different types of API failures.
/// This allows better error handling and user-friendly error messages.

/// Base class for all API exceptions
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic originalError;

  ApiException(this.message, {this.statusCode, this.originalError});

  @override
  String toString() => message;
}

/// Authentication failure (401)
/// Token expired, invalid, or missing
class AuthenticationException extends ApiException {
  AuthenticationException(String message, {dynamic originalError})
      : super(message, statusCode: 401, originalError: originalError);
}

/// Resource not found (404)
/// PDS, community, post, or user not found
class NotFoundException extends ApiException {
  NotFoundException(String message, {dynamic originalError})
      : super(message, statusCode: 404, originalError: originalError);
}

/// Server error (500+)
/// Backend or PDS server failure
class ServerException extends ApiException {
  ServerException(String message, {int? statusCode, dynamic originalError})
      : super(message, statusCode: statusCode, originalError: originalError);
}

/// Network connectivity failure
/// No internet, connection refused, timeout
class NetworkException extends ApiException {
  NetworkException(String message, {dynamic originalError})
      : super(message, statusCode: null, originalError: originalError);
}

/// Federation error
/// atProto PDS unreachable or DID resolution failure
class FederationException extends ApiException {
  FederationException(String message, {dynamic originalError})
      : super(message, statusCode: null, originalError: originalError);
}
