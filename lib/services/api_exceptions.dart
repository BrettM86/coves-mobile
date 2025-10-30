/// API Exception Types
///
/// Custom exception classes for different types of API failures.
/// This allows better error handling and user-friendly error messages.
library;

/// Base class for all API exceptions
class ApiException implements Exception {

  ApiException(this.message, {this.statusCode, this.originalError});
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
