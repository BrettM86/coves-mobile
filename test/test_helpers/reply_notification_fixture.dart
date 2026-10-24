/// A reply/mention notification as delivered by listNotifications.
Map<String, dynamic> replyNotificationWire({
  String reason = 'postReply',
  required Map<String, dynamic> rootPost,
  required Map<String, dynamic> record,
  required Map<String, dynamic> author,
}) => {
  'reason': reason,
  'sortAt': '2026-10-06T12:00:00.000Z',
  'isRead': true,
  'rootPost': rootPost,
  'record': record,
  'author': author,
  if (reason != 'mention')
    'subject': {'uri': rootPost['uri'], 'cid': 'bafysubject'},
};

/// Compact live row with no remote images, for list and session tests.
Map<String, dynamic> replyNotificationWireFor({
  required String recordUri,
  required String rootUri,
  String reason = 'postReply',
}) => replyNotificationWire(
  reason: reason,
  rootPost: {
    'uri': rootUri,
    'cid': 'bafyroot',
    'title': 'A post about keyboards',
  },
  record: {
    'uri': recordUri,
    'cid': 'bafyrecord',
    'excerpt': recordUri,
    'createdAt': '2026-10-06T12:00:00.000Z',
  },
  author: {'did': 'did:plc:writer', 'handle': 'writer.test'},
);

/// The self-labels object of a reference its author marked as sensitive.
const nsfwLabels = <String, dynamic>{
  'values': [
    {'val': 'nsfw'},
  ],
};
