/// User-Friendly Error Messages
///
/// Centralized utility for converting API exceptions to user-friendly messages.
/// Uses type-based matching against the ApiException hierarchy for reliable
/// error handling across the app.
library;

import '../services/api_exceptions.dart';

/// Longest trimmed 4xx server message [getErrorMessage] shows to the user.
const _maximumServerMessageLength = 200;

/// Converts an exception to a user-friendly error message.
///
/// Uses type-based matching for reliability:
/// - [AuthenticationException] → Sign-in prompt
/// - [NetworkException] → Connection issues
/// - [ServerException] → Server problems
/// - [NotFoundException] → Resource not found
/// - [ValidationException] → Shows the validation message
/// - [FederationException] → atProto federation issues
/// - Other [ApiException] with a 4xx status other than 401 or 404 → Shows the
///   server's message, trimmed, or the fallback when that message is blank,
///   is only the machine error code, is the [requestFailedMessageForStatus]
///   diagnostic that stands in for a body with no message, starts with `<`,
///   contains a line break, or is longer than 200 characters
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
    final statusCode = error.statusCode;
    final message = error.message.trim();
    if (statusCode != null &&
        statusCode >= 400 &&
        statusCode <= 499 &&
        statusCode != 401 &&
        statusCode != 404 &&
        message.isNotEmpty &&
        // A message equal to the error code means the body carried only the
        // machine code, not a human-readable message.
        message != error.errorCode &&
        // A body with no message leaves fromDioError's status diagnostic.
        message != requestFailedMessageForStatus(statusCode) &&
        // A plain-text body is used as-is, so a proxy's HTML page or a long
        // or multi-line body would otherwise render verbatim.
        !message.startsWith('<') &&
        !message.contains('\n') &&
        !message.contains('\r') &&
        message.length <= _maximumServerMessageLength) {
      return message;
    }
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
  static String loadFeed(Object error) =>
      getErrorMessage(error, fallback: 'Could not load feed. Pull to refresh.');

  /// Error message for post search
  static String searchPosts(Object error) => getErrorMessage(
    error,
    fallback: 'Could not search posts. Pull to refresh.',
  );

  /// Error message for profile operations
  static String profile(Object error) => getErrorMessage(
    error,
    fallback: 'Could not load profile. Please try again.',
  );

  /// Error message for subscription operations (join/leave community)
  ///
  /// A [NotFoundException] gets the fallback: a leave 404s when the
  /// subscription isn't indexed yet, and "content removed" copy would wrongly
  /// imply the community was deleted.
  static String subscription(Object error) {
    const fallback = 'Could not update subscription. Please try again.';
    return error is NotFoundException
        ? fallback
        : getErrorMessage(error, fallback: fallback);
  }

  /// Error message for block operations
  static String block(Object error) => getErrorMessage(
    error,
    fallback: 'Could not update block. Please try again.',
  );

  /// Error message for report operations
  static String report(Object error) => getErrorMessage(
    error,
    fallback: 'Could not submit report. Please try again.',
  );

  /// Error message for save/bookmark operations
  static String save(Object error) =>
      getErrorMessage(error, fallback: 'Could not save. Please try again.');

  /// Error message for loading ([isLoad]) or updating notification
  /// preferences
  static String notificationPreferences(Object error, {bool isLoad = false}) =>
      getErrorMessage(
        error,
        fallback: isLoad
            ? "Couldn't load notification settings. Try again."
            : "Couldn't update notification settings. Try again.",
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
