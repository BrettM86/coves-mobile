// e11_edit_comment: checks an edited comment at both ends of the indexing
// pipeline, so a client-side patch alone cannot pass.
//
// Runs on the host through Maestro's runScript. Finds the author's comment
// containing STAMP in their repo on the local PDS, asserts its content and
// facets, then polls the AppView's getComments until it serves that record's
// cid, and asserts the same content and facets there.
//
// The comment is expected to be ASCII, with BOLD_TEXT bold and, when set,
// ITALIC_TEXT italic. Throws with the actual values on any mismatch.
//
// Env: AUTHOR_HANDLE, STAMP, CONTENT, BOLD_TEXT; optional ITALIC_TEXT,
// PDS_URL, APPVIEW_URL.
// Output: output.e11RecordOk = true, output.e11Cid (the indexed cid).

var PDS =
  (typeof PDS_URL !== 'undefined' && PDS_URL ? PDS_URL : 'http://localhost:3001') +
  '/xrpc/';
var APPVIEW =
  (typeof APPVIEW_URL !== 'undefined' && APPVIEW_URL
    ? APPVIEW_URL
    : 'http://localhost:8081') + '/xrpc/';
var COLLECTION = 'social.coves.community.comment';
var FACET = 'social.coves.richtext.facet#';
var INDEX_TIMEOUT_MS = 30000;

function expectOk(response, step) {
  if (!response.ok) {
    throw new Error(step + ' failed with HTTP ' + response.status);
  }
  return json(response.body);
}

function facet(piece, name) {
  var start = CONTENT.indexOf(piece);
  if (start < 0) throw new Error('expected text missing: ' + piece);
  return {
    index: { byteStart: start, byteEnd: start + piece.length },
    features: [{ $type: FACET + name }],
  };
}

var expectedFacets = [facet(BOLD_TEXT, 'bold')];
if (typeof ITALIC_TEXT !== 'undefined' && ITALIC_TEXT) {
  expectedFacets.push(facet(ITALIC_TEXT, 'italic'));
}

// Index and features only: a facet-level $type is not under test
function assertRecord(where, record) {
  if (record.content !== CONTENT) {
    throw new Error(
      where + ' content mismatch\nexpected: ' + JSON.stringify(CONTENT) +
        '\nactual:   ' + JSON.stringify(record.content)
    );
  }
  var actual = (record.facets || []).map(function (f) {
    return JSON.stringify({
      index: { byteStart: f.index.byteStart, byteEnd: f.index.byteEnd },
      features: f.features,
    });
  });
  var expected = expectedFacets.map(function (f) {
    return JSON.stringify(f);
  });
  if (actual.join('\n') !== expected.join('\n')) {
    throw new Error(
      where + ' facets mismatch\nexpected: ' + expected.join(' ') +
        '\nactual:   ' + actual.join(' ')
    );
  }
}

var authorDid = expectOk(
  http.get(PDS + 'com.atproto.identity.resolveHandle?handle=' + AUTHOR_HANDLE),
  'resolveHandle'
).did;
var records = expectOk(
  http.get(
    PDS + 'com.atproto.repo.listRecords?repo=' + authorDid +
      '&collection=' + COLLECTION + '&limit=50'
  ),
  'listRecords'
).records;
var stored = null;
for (var i = 0; i < records.length; i++) {
  if ((records[i].value.content || '').indexOf(STAMP) >= 0) {
    stored = records[i];
    break;
  }
}
if (!stored) throw new Error('no comment with ' + STAMP + ' on the PDS');
assertRecord('PDS', stored.value);

var commentsUrl =
  APPVIEW + 'social.coves.community.comment.getComments?post=' +
  encodeURIComponent(stored.value.reply.root.uri) + '&sort=new&limit=50';
var deadline = Date.now() + INDEX_TIMEOUT_MS;
var indexed = null;
var seenCid = null;
while (!indexed && Date.now() < deadline) {
  var threads = expectOk(http.get(commentsUrl), 'getComments').comments;
  for (var j = 0; j < threads.length; j++) {
    var comment = threads[j].comment;
    if (comment.uri === stored.uri) {
      seenCid = comment.cid;
      if (comment.cid === stored.cid) indexed = comment;
    }
  }
}
if (!indexed) {
  throw new Error(
    'AppView did not serve ' + stored.cid + ' within ' + INDEX_TIMEOUT_MS +
      'ms; last saw ' + seenCid
  );
}
assertRecord('AppView', indexed.record);

console.log('e11 comment ' + stored.uri + ' matches on PDS and AppView');
output.e11Cid = stored.cid;
output.e11RecordOk = true;
