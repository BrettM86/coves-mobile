import 'package:coves_flutter/services/api_exceptions.dart';

/// One failure an error-site wiring test drives, with the copy the user must
/// see and the raw text that must not leak into the UI.
typedef ErrorCopyRow = ({
  String name,
  Exception error,
  String expected,
  String? rawText,
});

/// The four failures every error-site wiring test drives: a 500 wrapper and
/// an HTML 4xx body (both show [fallback]), a 401 and a short plain 4xx.
List<ErrorCopyRow> errorCopyRows(String fallback) => [
  (
    name: '500 wrapper',
    error: ApiException(
      'Unexpected error: FormatException: Unexpected character',
      statusCode: 500,
    ),
    expected: fallback,
    rawText: 'Unexpected error',
  ),
  (
    name: '401',
    error: AuthenticationException('Session expired'),
    expected: 'Please sign in to continue.',
    rawText: null,
  ),
  (
    name: 'HTML 4xx body',
    error: ApiException(
      '<html><body>502 Bad Gateway</body></html>',
      statusCode: 403,
    ),
    expected: fallback,
    rawText: '<html>',
  ),
  (
    name: 'short plain 4xx',
    error: ApiException('You are banned from this community', statusCode: 403),
    expected: 'You are banned from this community',
    rawText: null,
  ),
];
