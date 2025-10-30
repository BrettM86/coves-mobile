/// Error class for OAuth callback failures.
///
/// This error is thrown when an OAuth authorization callback contains
/// error parameters or fails to parse correctly.
///
/// See: https://datatracker.ietf.org/doc/html/rfc6749#section-4.1.2.1
class OAuthCallbackError implements Exception {
  /// The URL parameters from the callback
  final Map<String, String> params;

  /// The state parameter from the callback (if present)
  final String? state;

  /// The error message
  final String message;

  /// Optional underlying cause
  final Object? cause;

  /// Creates an OAuth callback error from parameters.
  ///
  /// The [params] should contain the parsed query parameters from the callback URL.
  /// The [message] defaults to the error_description from params, or a generic message.
  OAuthCallbackError(this.params, {String? message, this.state, this.cause})
    : message =
          message ?? params['error_description'] ?? 'OAuth callback error';

  /// Creates an OAuthCallbackError from another error.
  ///
  /// If [err] is already an OAuthCallbackError, returns it unchanged.
  /// Otherwise, wraps the error with the given params and state.
  static OAuthCallbackError from(
    Object err,
    Map<String, String> params, [
    String? state,
  ]) {
    if (err is OAuthCallbackError) return err;
    final message = err is Exception ? err.toString() : null;
    return OAuthCallbackError(
      params,
      message: message,
      state: state,
      cause: err,
    );
  }

  @override
  String toString() {
    return 'OAuthCallbackError: $message';
  }
}
