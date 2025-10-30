/// Error thrown when identity resolution fails.
///
/// This error is thrown when resolving an atProto handle or DID fails,
/// including cases such as:
/// - Invalid handle format
/// - Handle doesn't resolve to a DID
/// - DID document is malformed or missing required fields
/// - Bi-directional resolution fails (handle in DID doc doesn't match)
class IdentityResolverError extends Error {
  /// The error message describing what went wrong
  final String message;

  /// Optional underlying cause of the error
  final Object? cause;

  IdentityResolverError(this.message, [this.cause]);

  @override
  String toString() {
    if (cause != null) {
      return 'IdentityResolverError: $message\nCaused by: $cause';
    }
    return 'IdentityResolverError: $message';
  }
}

/// Error thrown when a DID is invalid or malformed.
class InvalidDidError extends IdentityResolverError {
  /// The invalid DID that was provided
  final String did;

  InvalidDidError(this.did, String message, [Object? cause])
    : super('Invalid DID "$did": $message', cause);
}

/// Error thrown when a handle is invalid or malformed.
class InvalidHandleError extends IdentityResolverError {
  /// The invalid handle that was provided
  final String handle;

  InvalidHandleError(this.handle, String message, [Object? cause])
    : super('Invalid handle "$handle": $message', cause);
}

/// Error thrown when handle resolution fails.
class HandleResolverError extends IdentityResolverError {
  HandleResolverError(super.message, [super.cause]);
}

/// Error thrown when DID resolution fails.
class DidResolverError extends IdentityResolverError {
  DidResolverError(super.message, [super.cause]);
}
