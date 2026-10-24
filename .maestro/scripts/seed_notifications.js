// Section I fixture: the second local account (account A, ACTOR_HANDLE)
// replies to, mentions and upvotes the signed-in account B (mari), so B
// has fresh unread notifications of every row kind.
//
// Runs on the host through Maestro's runScript, against the local PDS on
// localhost:3001 and the AppView on localhost:8081 (the ports the QA loop
// reverses). Writes go straight to A's repo with createRecord; the AppView
// indexes them through the dev Jetstream (coves-dev-jetstream, port 6008)
// and fans out B's notifications. With Jetstream stopped the records land
// on the PDS but no notification appears.
//
// Account A must be known to the AppView: create it with the AppView's
// social.coves.actor.signup (see QA_LOOP.md Section I). An account made
// with the PDS's createAccount is never indexed, so its comments and votes
// are dropped.
//
// - reply:   a comment on B's "QA thread post"
// - mention: a comment on the newest Discover post B did not write, whose
//            text starts with an @mention facet for B
// - upvote:  A's upvote on the "QA thread post"; A's earlier vote on it is
//            deleted first so every run produces a new upvote event
// - nsfw:    a reply on the "QA thread post" and a mention on the Discover
//            post, both self-labelled nsfw, so B has two concealed rows.
//            They are written first, so the plain rows above stay on top.
//
// Env: ACTOR_HANDLE, ACTOR_PASSWORD, RECIPIENT_HANDLE.
// Output: output.seedTag (the text both comments carry, for the flows).

var PDS = 'http://localhost:3001/xrpc/';
var APPVIEW = 'http://localhost:8081/xrpc/';
var POST_COLLECTION = 'social.coves.community.postv2';
var THREAD_POST_TITLE = 'QA thread post';

function expectOk(response, step) {
  if (!response.ok) {
    throw new Error(step + ' failed with HTTP ' + response.status);
  }
  return json(response.body);
}

function postJson(path, body, accessJwt) {
  var headers = { 'Content-Type': 'application/json' };
  if (accessJwt) headers['Authorization'] = 'Bearer ' + accessJwt;
  return http.post(PDS + path, { headers: headers, body: JSON.stringify(body) });
}

var session = expectOk(
  postJson('com.atproto.server.createSession', {
    identifier: ACTOR_HANDLE,
    password: ACTOR_PASSWORD,
  }),
  'createSession'
);
var actorDid = session.did;
var accessJwt = session.accessJwt;

var recipientDid = expectOk(
  http.get(PDS + 'com.atproto.identity.resolveHandle?handle=' + RECIPIENT_HANDLE),
  'resolveHandle'
).did;

var recipientPosts = expectOk(
  http.get(
    PDS + 'com.atproto.repo.listRecords?repo=' + recipientDid +
      '&collection=' + POST_COLLECTION + '&limit=100'
  ),
  'listRecords recipient posts'
).records;
var threadPost = null;
for (var i = 0; i < recipientPosts.length; i++) {
  if ((recipientPosts[i].value.title || '').indexOf(THREAD_POST_TITLE) === 0) {
    threadPost = { uri: recipientPosts[i].uri, cid: recipientPosts[i].cid };
    break;
  }
}
if (!threadPost) throw new Error('recipient has no "' + THREAD_POST_TITLE + '"');

var discover = expectOk(
  http.get(APPVIEW + 'social.coves.feed.getDiscover?limit=25'),
  'getDiscover'
).feed;
var otherPost = null;
for (var j = 0; j < discover.length; j++) {
  var candidate = discover[j].post;
  if (candidate.author.did !== recipientDid) {
    otherPost = { uri: candidate.uri, cid: candidate.cid };
    break;
  }
}
if (!otherPost) throw new Error('no Discover post by another author');

var seedTag = 'QA notification ' + new Date().toISOString();
var now = new Date().toISOString();
// Written oldest first, so whether the AppView orders by createdAt or by
// indexing time the list reads: plain rows, nsfw mention, nsfw reply.
var nsfwReplyAt = new Date(Date.now() - 2000).toISOString();
var nsfwMentionAt = new Date(Date.now() - 1000).toISOString();

function createRecord(collection, record) {
  return expectOk(
    postJson(
      'com.atproto.repo.createRecord',
      { repo: actorDid, collection: collection, record: record },
      accessJwt
    ),
    'createRecord ' + collection
  );
}

var mentionText = '@' + RECIPIENT_HANDLE;
var mentionFacets = [
  {
    index: { byteStart: 0, byteEnd: mentionText.length },
    features: [
      { $type: 'social.coves.richtext.facet#mention', did: recipientDid },
    ],
  },
];
var nsfwLabels = {
  $type: 'com.atproto.label.defs#selfLabels',
  values: [{ val: 'nsfw' }],
};

createRecord('social.coves.community.comment', {
  $type: 'social.coves.community.comment',
  reply: { root: threadPost, parent: threadPost },
  content: seedTag + ' nsfw reply',
  labels: nsfwLabels,
  createdAt: nsfwReplyAt,
});

createRecord('social.coves.community.comment', {
  $type: 'social.coves.community.comment',
  reply: { root: otherPost, parent: otherPost },
  content: mentionText + ' ' + seedTag + ' nsfw mention',
  facets: mentionFacets,
  labels: nsfwLabels,
  createdAt: nsfwMentionAt,
});

createRecord('social.coves.community.comment', {
  $type: 'social.coves.community.comment',
  reply: { root: threadPost, parent: threadPost },
  content: seedTag + ' reply',
  createdAt: now,
});

createRecord('social.coves.community.comment', {
  $type: 'social.coves.community.comment',
  reply: { root: otherPost, parent: otherPost },
  content: mentionText + ' ' + seedTag + ' mention',
  facets: mentionFacets,
  createdAt: now,
});

var votes = expectOk(
  http.get(
    PDS + 'com.atproto.repo.listRecords?repo=' + actorDid +
      '&collection=social.coves.feed.vote&limit=100'
  ),
  'listRecords votes'
).records;
for (var k = 0; k < votes.length; k++) {
  if (votes[k].value.subject && votes[k].value.subject.uri === threadPost.uri) {
    var rkey = votes[k].uri.split('/').pop();
    expectOk(
      postJson(
        'com.atproto.repo.deleteRecord',
        { repo: actorDid, collection: 'social.coves.feed.vote', rkey: rkey },
        accessJwt
      ),
      'deleteRecord vote'
    );
  }
}
createRecord('social.coves.feed.vote', {
  $type: 'social.coves.feed.vote',
  subject: threadPost,
  direction: 'up',
  createdAt: new Date().toISOString(),
});

output.seedTag = seedTag;
