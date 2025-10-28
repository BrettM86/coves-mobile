/// Exception thrown when a token refresh operation fails.
class TokenRefreshError implements Exception {
  /// Subject identifier for the token that failed to refresh
  final String sub;

  /// Error message
  final String message;

  /// Optional cause of the error
  final Object? cause;

  TokenRefreshError(this.sub, this.message, {this.cause});

  @override
  String toString() {
    if (cause != null) {
      return 'TokenRefreshError: $message (caused by: $cause)';
    }
    return 'TokenRefreshError: $message';
  }
}
