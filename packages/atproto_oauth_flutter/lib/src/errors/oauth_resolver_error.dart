/// Error class for OAuth resolution failures.
///
/// This error is thrown when OAuth metadata resolution fails, including:
/// - Authorization server metadata discovery
/// - Protected resource metadata discovery
/// - Identity resolution (handle → DID → PDS)
class OAuthResolverError implements Exception {
  /// The error message
  final String message;

  /// Optional underlying cause
  final Object? cause;

  /// Creates an OAuth resolver error.
  OAuthResolverError(this.message, {this.cause});

  /// Creates an OAuthResolverError from another error.
  ///
  /// If [cause] is already an OAuthResolverError, returns it unchanged.
  /// Otherwise, wraps the error with an appropriate message.
  ///
  /// For validation errors, extracts the first error details.
  static OAuthResolverError from(
    Object cause, [
    String? message,
  ]) {
    if (cause is OAuthResolverError) return cause;

    String? validationReason;

    // Check if it's a validation error (would be FormatException or similar in Dart)
    if (cause is FormatException) {
      validationReason = cause.message;
    }

    final fullMessage = (message ?? 'Unable to resolve OAuth metadata') +
        (validationReason != null ? ' ($validationReason)' : '');

    return OAuthResolverError(fullMessage, cause: cause);
  }

  @override
  String toString() {
    if (cause != null) {
      return 'OAuthResolverError: $message (caused by: $cause)';
    }
    return 'OAuthResolverError: $message';
  }
}
