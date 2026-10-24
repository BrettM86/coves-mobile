import '../models/notification.dart';
import 'moderation_copy.dart';

String notificationRoute(NotificationView notification) {
  final route = '/post/${Uri.encodeComponent(notification.rootPost.uri)}';
  final reference = notification.reason == NotificationReason.upvote
      ? notification.subject
      : notification.record;
  if (reference == null ||
      moderationSubjectUriKind(reference.uri) !=
          ModerationSubjectKind.comment) {
    return route;
  }
  return '$route?comment=${Uri.encodeComponent(reference.uri)}';
}
