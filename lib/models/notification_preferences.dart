/// Notification reasons enabled for the signed-in account
/// (`social.coves.notification.defs#preferences`).
class NotificationPreferences {
  const NotificationPreferences({
    required this.postReply,
    required this.commentReply,
    required this.mention,
    required this.upvote,
  });

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      postReply: json['postReply'] as bool,
      commentReply: json['commentReply'] as bool,
      mention: json['mention'] as bool,
      upvote: json['upvote'] as bool,
    );
  }

  final bool postReply;
  final bool commentReply;
  final bool mention;
  final bool upvote;
}
