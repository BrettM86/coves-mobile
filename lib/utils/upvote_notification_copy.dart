import 'dart:math';

import '../models/notification.dart';
import 'moderation_copy.dart';

typedef UpvoteSentencePart = ({String text, bool bold});

List<UpvoteSentencePart> upvoteNotificationSentence(
  NotificationView notification,
) {
  final upvoters = notification.recentUpvoters;
  final namedCount = upvoters.length;
  final count = max(notification.upvoteCount ?? 0, namedCount);
  final subject = notification.subject;
  final object =
      subject != null &&
          moderationSubjectUriKind(subject.uri) == ModerationSubjectKind.comment
      ? 'your comment'
      : 'your post';

  final parts = <UpvoteSentencePart>[];
  if (namedCount == 0) {
    parts.add((text: '$count ${count == 1 ? 'person' : 'people'}', bold: true));
  } else if (count == namedCount) {
    for (var index = 0; index < namedCount; index++) {
      if (index > 0) {
        parts.add((
          text: index == namedCount - 1 ? ' and ' : ', ',
          bold: false,
        ));
      }
      parts.add((text: upvoters[index].name, bold: true));
    }
  } else {
    final remaining = count - 1;
    parts.addAll([
      (text: upvoters.first.name, bold: true),
      (text: ' and ', bold: false),
      (text: '$remaining ${remaining == 1 ? 'other' : 'others'}', bold: true),
    ]);
  }
  parts.add((text: ' liked $object', bold: false));
  return parts;
}
