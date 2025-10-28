/// Exception thrown when the requested authentication method cannot be satisfied.
class AuthMethodUnsatisfiableError implements Exception {
  final String? message;

  AuthMethodUnsatisfiableError([this.message]);

  @override
  String toString() {
    if (message != null) {
      return 'AuthMethodUnsatisfiableError: $message';
    }
    return 'AuthMethodUnsatisfiableError';
  }
}
