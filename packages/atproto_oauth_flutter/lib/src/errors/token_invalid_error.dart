/// Exception thrown when a token is invalid.
class TokenInvalidError implements Exception {
  /// Subject identifier for the invalid token
  final String sub;

  /// Error message
  final String message;

  /// Optional cause of the error
  final Object? cause;

  TokenInvalidError(this.sub, {String? message, this.cause})
    : message = message ?? 'The session for "$sub" is invalid';

  @override
  String toString() {
    if (cause != null) {
      return 'TokenInvalidError: $message (caused by: $cause)';
    }
    return 'TokenInvalidError: $message';
  }
}
