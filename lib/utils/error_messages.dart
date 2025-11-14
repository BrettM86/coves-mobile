/// Utility class for transforming technical error messages into
/// user-friendly ones
class ErrorMessages {
  /// Transform technical error messages into user-friendly ones
  static String getUserFriendly(String error) {
    final lowerError = error.toLowerCase();

    if (lowerError.contains('socketexception') ||
        lowerError.contains('network') ||
        lowerError.contains('connection refused')) {
      return 'Please check your internet connection';
    } else if (lowerError.contains('timeoutexception') ||
        lowerError.contains('timeout')) {
      return 'Request timed out. Please try again';
    } else if (lowerError.contains('401') ||
        lowerError.contains('unauthorized')) {
      return 'Authentication failed. Please sign in again';
    } else if (lowerError.contains('404') || lowerError.contains('not found')) {
      return 'Content not found';
    } else if (lowerError.contains('500') ||
        lowerError.contains('internal server')) {
      return 'Server error. Please try again later';
    }

    // Fallback to generic message for unknown errors
    return 'Something went wrong. Please try again';
  }
}
