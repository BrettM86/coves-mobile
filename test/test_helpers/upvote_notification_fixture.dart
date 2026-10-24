const aliceUpvoter = <String, dynamic>{
  'did': 'did:plc:alice',
  'handle': 'alice.test',
  'displayName': 'Alice',
  'avatar': 'https://cdn.test/alice.png',
};
const bobUpvoter = <String, dynamic>{
  'did': 'did:plc:bob',
  'handle': 'bob.test',
};
const carolUpvoter = <String, dynamic>{
  'did': 'did:plc:carol',
  'handle': 'carol.test',
  'displayName': 'Carol',
  'avatar': 'https://cdn.test/carol.png',
};
const didOnlyUpvoter = <String, dynamic>{'did': 'did:plc:ghost'};

const postUri = 'at://did:plc:me/social.coves.community.postv2/3kpost';
const commentUri = 'at://did:plc:me/social.coves.community.comment/3kcomment';
const postSubject = <String, dynamic>{'uri': postUri, 'cid': 'bafysubject'};
const commentSubject = <String, dynamic>{
  'uri': commentUri,
  'cid': 'bafysubject',
};

Map<String, dynamic> upvoteWire({
  List<Map<String, dynamic>>? upvoters,
  int? count,
  Map<String, dynamic> subject = postSubject,
  Map<String, dynamic> rootPost = const {'uri': postUri, 'cid': 'bafyroot'},
}) => {
  'reason': 'upvote',
  'sortAt': '2026-10-01T12:00:00.000Z',
  'isRead': true,
  'rootPost': rootPost,
  'subject': subject,
  'upvoteCount': ?count,
  'recentUpvoters': ?upvoters,
};
