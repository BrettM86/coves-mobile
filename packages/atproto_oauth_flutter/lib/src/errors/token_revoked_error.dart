/// Exception thrown when a token has been successfully revoked.
class TokenRevokedError implements Exception {
  /// Subject identifier for the revoked token
  final String sub;

  /// Error message
  final String message;

  /// Optional cause of the error
  final Object? cause;

  TokenRevokedError(this.sub, {String? message, this.cause})
    : message = message ?? 'The session for "$sub" was successfully revoked';

  @override
  String toString() {
    if (cause != null) {
      return 'TokenRevokedError: $message (caused by: $cause)';
    }
    return 'TokenRevokedError: $message';
  }
}
