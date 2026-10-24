import '../utils/notification_timestamp.dart';
import '../utils/removal_copy.dart';
import 'post.dart';

enum NotificationReason { postReply, commentReply, mention, upvote }

enum NotificationReferenceStatus {
  deleted,
  removedByModerator,
  removedByServerAdmin,
  unknown,
}

class NotificationActor {
  const NotificationActor({
    required this.did,
    this.handle,
    this.displayName,
    this.avatar,
  });

  factory NotificationActor.fromJson(Map<String, dynamic> json) =>
      NotificationActor(
        did: json['did'] as String,
        handle: json['handle'] is String ? json['handle'] as String : null,
        displayName: json['displayName'] is String
            ? json['displayName'] as String
            : null,
        avatar: json['avatar'] is String ? json['avatar'] as String : null,
      );

  final String did;
  final String? handle;
  final String? displayName;
  final String? avatar;

  String get name => displayName ?? handle ?? 'Unknown user';

  String? get handleLine => handle == null ? null : '@$handle';
}

class NotificationReference {
  const NotificationReference({
    required this.uri,
    required this.cid,
    this.status,
    this.title,
    this.preview,
    this.excerpt,
    this.createdAt,
    this.labels,
    this.thumbnail,
    this.thumbnailAlt,
    this.community,
    this.author,
    this.stats,
  });

  factory NotificationReference.fromJson(Map<String, dynamic> json) {
    final status = json['status'];
    final community = json['community'];
    final viewer = community is Map<String, dynamic>
        ? community['viewer']
        : null;
    return NotificationReference(
      uri: json['uri'] as String,
      cid: json['cid'] as String,
      status: status is String
          ? switch (status) {
              'deleted' => NotificationReferenceStatus.deleted,
              'removedByModerator' =>
                NotificationReferenceStatus.removedByModerator,
              'removedByServerAdmin' =>
                NotificationReferenceStatus.removedByServerAdmin,
              _ => NotificationReferenceStatus.unknown,
            }
          : null,
      title: json['title'] is String ? json['title'] as String : null,
      preview: json['preview'] is String ? json['preview'] as String : null,
      excerpt: json['excerpt'] is String ? json['excerpt'] as String : null,
      createdAt: _timestamp(json['createdAt']),
      labels: json['labels'] is Map<String, dynamic>
          ? json['labels'] as Map<String, dynamic>
          : null,
      thumbnail: json['thumbnail'] is String
          ? json['thumbnail'] as String
          : null,
      thumbnailAlt: json['thumbnailAlt'] is String
          ? json['thumbnailAlt'] as String
          : null,
      community:
          community is Map<String, dynamic> &&
              community['did'] is String &&
              community['name'] is String
          ? CommunityRef(
              did: community['did'] as String,
              name: community['name'] as String,
              origin: community['origin'] is String
                  ? community['origin'] as String
                  : null,
              handle: community['handle'] is String
                  ? community['handle'] as String
                  : null,
              avatar: community['avatar'] is String
                  ? community['avatar'] as String
                  : null,
              viewer: viewer is Map<String, dynamic>
                  ? CommunityRefViewerState(
                      subscribed: viewer['subscribed'] is bool
                          ? viewer['subscribed'] as bool
                          : null,
                    )
                  : null,
            )
          : null,
      author: _author(json['author']),
      stats: _stats(json['stats']),
    );
  }

  static final _didPattern = RegExp(r'^did:[a-z]+:[a-zA-Z0-9._:%-]+$');

  static String? _timestamp(Object? value) =>
      value is String && isNotificationTimestamp(value) ? value : null;

  /// A post author needs a valid DID and a handle to be shown.
  static NotificationActor? _author(Object? value) {
    if (value is! Map<String, dynamic>) {
      return null;
    }
    final did = value['did'];
    if (did is! String ||
        !_didPattern.hasMatch(did) ||
        value['handle'] is! String) {
      return null;
    }
    return NotificationActor.fromJson(value);
  }

  static PostStats? _stats(Object? value) {
    if (value is! Map<String, dynamic>) {
      return null;
    }
    final score = value['score'];
    final upvotes = value['upvotes'];
    final downvotes = value['downvotes'];
    final commentCount = value['commentCount'];
    if (score is! int ||
        upvotes is! int ||
        upvotes < 0 ||
        downvotes is! int ||
        downvotes < 0 ||
        commentCount is! int ||
        commentCount < 0) {
      return null;
    }
    return PostStats(
      upvotes: upvotes,
      downvotes: downvotes,
      score: score,
      commentCount: commentCount,
    );
  }

  final String uri;
  final String cid;
  final NotificationReferenceStatus? status;
  final String? title;
  final String? preview;
  final String? excerpt;
  final String? createdAt;
  final Map<String, dynamic>? labels;
  final String? thumbnail;
  final String? thumbnailAlt;
  final CommunityRef? community;
  final NotificationActor? author;
  final PostStats? stats;

  /// Whether the author self-labelled this reference NSFW. Malformed labels
  /// read as not sensitive, as they do on posts.
  bool get isSensitive => parseSelfLabels(labels).contains('nsfw');

  String? get placeholderCopy => switch (status) {
    null => null,
    NotificationReferenceStatus.deleted => RemovalCopy.deletedByUser,
    NotificationReferenceStatus.removedByModerator =>
      RemovalCopy.removedByCommunityModerator,
    NotificationReferenceStatus.removedByServerAdmin =>
      RemovalCopy.removedByServerAdmin,
    NotificationReferenceStatus.unknown => RemovalCopy.removedByModerator,
  };
}

class NotificationView {
  const NotificationView({
    required this.reason,
    required this.sortAt,
    required this.isRead,
    required this.rootPost,
    this.subject,
    this.record,
    this.author,
    this.upvoteCount,
    this.recentUpvoters = const [],
  });

  String get identity => switch (reason) {
    NotificationReason.postReply => 'postReply|${record!.uri}',
    NotificationReason.commentReply => 'commentReply|${record!.uri}',
    NotificationReason.mention => 'mention|${record!.uri}',
    NotificationReason.upvote => 'upvote|${subject!.uri}',
  };

  /// This notification with [isRead] replaced and every other field kept.
  NotificationView withReadState({required bool isRead}) => NotificationView(
    reason: reason,
    sortAt: sortAt,
    isRead: isRead,
    rootPost: rootPost,
    subject: subject,
    record: record,
    author: author,
    upvoteCount: upvoteCount,
    recentUpvoters: recentUpvoters,
  );

  static NotificationView? tryFromJson(Map<String, dynamic> json) {
    final reason = switch (json['reason']) {
      'postReply' => NotificationReason.postReply,
      'commentReply' => NotificationReason.commentReply,
      'mention' => NotificationReason.mention,
      'upvote' => NotificationReason.upvote,
      _ => null,
    };
    if (reason == null ||
        json['sortAt'] is! String ||
        json['isRead'] is! bool) {
      return null;
    }

    NotificationReference? reference(value) {
      if (value is! Map<String, dynamic> ||
          value['uri'] is! String ||
          value['cid'] is! String) {
        return null;
      }
      return NotificationReference.fromJson(value);
    }

    final rootPost = reference(json['rootPost']);
    final subject = reference(json['subject']);
    final record = reference(json['record']);
    if (rootPost == null ||
        (reason == NotificationReason.upvote
            ? subject == null
            : record == null)) {
      return null;
    }

    NotificationActor? actor(value) {
      if (value is! Map<String, dynamic> || value['did'] is! String) {
        return null;
      }
      return NotificationActor.fromJson(value);
    }

    final upvoters = json['recentUpvoters'];
    return NotificationView(
      reason: reason,
      sortAt: json['sortAt'] as String,
      isRead: json['isRead'] as bool,
      rootPost: rootPost,
      subject: subject,
      record: record,
      author: actor(json['author']),
      upvoteCount: json['upvoteCount'] is int
          ? json['upvoteCount'] as int
          : null,
      recentUpvoters: upvoters is List
          ? [for (final value in upvoters) ?actor(value)]
          : const [],
    );
  }

  final NotificationReason reason;
  final String sortAt;
  final bool isRead;
  final NotificationReference rootPost;
  final NotificationReference? subject;
  final NotificationReference? record;
  final NotificationActor? author;
  final int? upvoteCount;
  final List<NotificationActor> recentUpvoters;
}

class NotificationPage {
  const NotificationPage({
    required this.notifications,
    this.cursor,
    this.seenAt,
    this.latestSortAt,
  });

  factory NotificationPage.fromJson(Map<String, dynamic> json) {
    final rows = json['notifications'];
    if (rows is! List) {
      throw const FormatException('Expected notifications array');
    }
    String? latestSortAt;
    for (final row in rows) {
      if (row is! Map<String, dynamic>) {
        continue;
      }
      final sortAt = row['sortAt'];
      if (sortAt is! String) {
        continue;
      }
      try {
        final comparison = compareNotificationTimestamps(
          sortAt,
          latestSortAt ?? sortAt,
        );
        if (latestSortAt == null || comparison > 0) {
          latestSortAt = sortAt;
        }
      } on FormatException {
        // A row with an unparseable sortAt cannot define the seen boundary.
      }
    }
    return NotificationPage(
      notifications: [
        for (final row in rows)
          if (row is Map<String, dynamic>) ?NotificationView.tryFromJson(row),
      ],
      cursor: json['cursor'] is String ? json['cursor'] as String : null,
      seenAt: json['seenAt'] is String ? json['seenAt'] as String : null,
      latestSortAt: latestSortAt,
    );
  }

  final List<NotificationView> notifications;
  final String? cursor;
  final String? seenAt;

  /// The newest parseable `sortAt` across every row the server sent,
  /// including rows [notifications] dropped (unknown reason, missing
  /// reference). The server counts unread across all of them, so this is
  /// the boundary that marks the page seen. Null when no row had one.
  final String? latestSortAt;
}
