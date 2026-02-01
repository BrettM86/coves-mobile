/// User-Friendly Error Messages
///
/// Centralized utility for converting API exceptions to user-friendly messages.
/// Uses type-based matching against the ApiException hierarchy for reliable
/// error handling across the app.
library;

import '../services/api_exceptions.dart';

/// Converts an exception to a user-friendly error message.
///
/// Uses type-based matching for reliability:
/// - [AuthenticationException] → Sign-in prompt
/// - [NetworkException] → Connection issues
/// - [ServerException] → Server problems
/// - [NotFoundException] → Resource not found
/// - [ValidationException] → Shows the validation message
/// - [FederationException] → atProto federation issues
/// - Other [ApiException] → Uses fallback
/// - Unknown exceptions → Uses fallback
///
/// Prefer using [ErrorMessage] context-specific methods when available:
/// ```dart
/// try {
///   await voteProvider.toggleVote(...);
/// } on Exception catch (e) {
///   if (mounted) {
///     messenger.showSnackBar(
///       SnackBar(content: Text(ErrorMessage.vote(e))),
///     );
///   }
/// }
/// ```
String getErrorMessage(Object error, {String? fallback}) {
  final defaultFallback = fallback ?? 'Something went wrong. Please try again.';

  if (error is AuthenticationException) {
    return 'Please sign in to continue.';
  }

  if (error is NetworkException) {
    return 'No connection. Please check your internet.';
  }

  if (error is ServerException) {
    return 'Server error. Please try again later.';
  }

  if (error is NotFoundException) {
    return 'Content not found. It may have been removed.';
  }

  if (error is ValidationException) {
    // Validation errors have user-facing messages
    return error.message;
  }

  if (error is FederationException) {
    return 'Could not reach the server. Please try again.';
  }

  if (error is ApiException) {
    return defaultFallback;
  }

  return defaultFallback;
}

/// Context-specific error messages for common operations.
///
/// Provides operation-appropriate fallback messages when the exception
/// type doesn't give enough context.
abstract final class ErrorMessage {
  /// Error message for vote operations
  static String vote(Object error) => getErrorMessage(
    error,
    fallback: 'Could not update your vote. Please try again.',
  );

  /// Error message for comment operations
  static String comment(Object error) => getErrorMessage(
    error,
    fallback: 'Could not post comment. Please try again.',
  );

  /// Error message for post creation
  static String createPost(Object error) => getErrorMessage(
    error,
    fallback: 'Could not create post. Please try again.',
  );

  /// Error message for post deletion
  static String deletePost(Object error) => getErrorMessage(
    error,
    fallback: 'Could not delete post. Please try again.',
  );

  /// Error message for feed loading
  static String loadFeed(Object error) => getErrorMessage(
    error,
    fallback: 'Could not load feed. Pull to refresh.',
  );

  /// Error message for profile operations
  static String profile(Object error) => getErrorMessage(
    error,
    fallback: 'Could not load profile. Please try again.',
  );

  /// Error message for subscription operations (join/leave community)
  static String subscription(Object error) => getErrorMessage(
    error,
    fallback: 'Could not update subscription. Please try again.',
  );

  /// Error message for report operations
  static String report(Object error) => getErrorMessage(
    error,
    fallback: 'Could not submit report. Please try again.',
  );

  /// Error message for save/bookmark operations
  static String save(Object error) => getErrorMessage(
    error,
    fallback: 'Could not save. Please try again.',
  );

  /// Error message for community operations
  static String community(Object error) => getErrorMessage(
    error,
    fallback: 'Could not load community. Please try again.',
  );
}

/// Returns true if the error is an authentication error.
///
/// Use this to check if the error requires a sign-in action:
/// ```dart
/// } on Exception catch (e) {
///   if (mounted) {
///     ScaffoldMessenger.of(context).showSnackBar(
///       SnackBar(
///         content: Text(ErrorMessage.vote(e)),
///         action: isAuthError(e)
///             ? SnackBarAction(
///                 label: 'Sign In',
///                 onPressed: () => context.push('/login'),
///               )
///             : null,
///       ),
///     );
///   }
/// }
/// ```
bool isAuthError(Object error) => error is AuthenticationException;
