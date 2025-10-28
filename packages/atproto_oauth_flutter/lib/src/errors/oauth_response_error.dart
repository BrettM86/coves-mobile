import 'package:dio/dio.dart';

import '../util.dart';

/// Error class for OAuth protocol errors returned by the server.
///
/// OAuth servers return errors as JSON with standard fields:
/// - error: The error code (required)
/// - error_description: Human-readable description (optional)
/// - error_uri: URI with more information (optional)
///
/// See: https://datatracker.ietf.org/doc/html/rfc6749#section-5.2
class OAuthResponseError implements Exception {
  /// The HTTP response that contained the error
  final Response response;

  /// The parsed response body (usually JSON)
  final dynamic payload;

  /// The OAuth error code (e.g., "invalid_request", "invalid_grant")
  final String? error;

  /// The human-readable error description
  final String? errorDescription;

  /// Creates an OAuth response error from a Dio response.
  ///
  /// Automatically extracts the error and error_description fields
  /// from the response payload if it's a JSON object.
  OAuthResponseError(this.response, this.payload)
      : error = _extractError(payload),
        errorDescription = _extractErrorDescription(payload);

  /// HTTP status code from the response
  int get status => response.statusCode ?? 0;

  /// HTTP headers from the response
  Headers get headers => response.headers;

  /// Extracts the error code from the payload
  static String? _extractError(dynamic payload) {
    if (payload is Map<String, dynamic>) {
      return ifString(payload['error']);
    }
    return null;
  }

  /// Extracts the error description from the payload
  static String? _extractErrorDescription(dynamic payload) {
    if (payload is Map<String, dynamic>) {
      return ifString(payload['error_description']);
    }
    return null;
  }

  @override
  String toString() {
    final errorCode = error ?? 'unknown';
    final description = errorDescription != null ? ': $errorDescription' : '';
    return 'OAuth "$errorCode" error$description';
  }
}
