// e10_formatted_comment: checks the comment record the flow just posted,
// read from the author's repo on the local PDS.
//
// Runs on the host through Maestro's runScript against the local PDS on
// localhost:3001 (the port the QA loop reverses; PDS_URL overrides it).
// Finds the author's newest social.coves.community.comment whose content
// starts with STAMP, then asserts:
// - the content is trimmed (no leading newline/spaces, no trailing
//   spaces/newline) and reads exactly as the flow typed it;
// - the facets are exactly the expected ones, in order, as
//   serializeFormatting and composeFormattedRichText write them: sorted by
//   byteStart then byteEnd (task 08), UTF-8 byte offsets, one facet per
//   distinct range with its features in lexicon union order (quote before
//   heading, quote before code block), block facets ending before the
//   line's newline, default attributes omitted (quote level 1, no spoiler
//   reason, no code block language), heading level always written.
// Throws with the actual record on any mismatch.
//
// Env: AUTHOR_HANDLE, MENTION_HANDLE, COMMUNITY_HANDLE (the community's
// account handle), STAMP, TAG; optional PDS_URL.
// Output: output.e10FacetsOk = true, output.e10CommentUri,
// output.e10PostUri (the reply root, for the web check).

var PDS =
  (typeof PDS_URL !== 'undefined' && PDS_URL ? PDS_URL : 'http://localhost:3001') +
  '/xrpc/';
var COLLECTION = 'social.coves.community.comment';
var FACET = 'social.coves.richtext.facet#';

function expectOk(response, step) {
  if (!response.ok) {
    throw new Error(step + ' failed with HTTP ' + response.status);
  }
  return json(response.body);
}

function resolveDid(handle) {
  return expectOk(
    http.get(PDS + 'com.atproto.identity.resolveHandle?handle=' + handle),
    'resolveHandle ' + handle
  ).did;
}

// UTF-8 length of a UTF-16 string, counting a surrogate pair as 4 bytes.
function utf8Length(text) {
  var bytes = 0;
  for (var i = 0; i < text.length; i++) {
    var unit = text.charCodeAt(i);
    if (unit < 0x80) {
      bytes += 1;
    } else if (unit < 0x800) {
      bytes += 2;
    } else if (unit >= 0xd800 && unit <= 0xdbff) {
      bytes += 4;
      i++;
    } else {
      bytes += 3;
    }
  }
  return bytes;
}

// The byte range of the first occurrence of [piece] in [content].
function byteRange(content, piece) {
  var start = content.indexOf(piece);
  if (start < 0) throw new Error('expected text missing: ' + piece);
  return {
    byteStart: utf8Length(content.substring(0, start)),
    byteEnd: utf8Length(content.substring(0, start + piece.length)),
  };
}

// JSON with sorted keys, so equal objects compare equal as strings.
function canonical(value) {
  if (Array.isArray(value)) {
    return '[' + value.map(canonical).join(',') + ']';
  }
  if (value !== null && typeof value === 'object') {
    return (
      '{' +
      Object.keys(value)
        .sort()
        .map(function (key) {
          return JSON.stringify(key) + ':' + canonical(value[key]);
        })
        .join(',') +
      '}'
    );
  }
  return JSON.stringify(value);
}

var authorDid = resolveDid(AUTHOR_HANDLE);
var mentionDid = resolveDid(MENTION_HANDLE);
var communityDid = resolveDid(COMMUNITY_HANDLE);

var records = expectOk(
  http.get(
    PDS + 'com.atproto.repo.listRecords?repo=' + authorDid +
      '&collection=' + COLLECTION + '&limit=50'
  ),
  'listRecords comments'
).records;
var record = null;
for (var i = 0; i < records.length; i++) {
  if ((records[i].value.content || '').indexOf(STAMP) >= 0) {
    record = records[i];
    break;
  }
}
if (!record) throw new Error('no comment by ' + AUTHOR_HANDLE + ' with ' + STAMP);

var mention = '@' + MENTION_HANDLE;
var communityByName = '!science';
var communityByAddress = '!science@coves.social';
var lines = [
  STAMP + ' plain bold, italic, struck, secret, snippet, hi ' + mention +
    ' in ' + communityByName + ' and ' + communityByAddress,
  'Quoted heading ' + TAG,
  'Between the blocks ' + TAG,
  'Code line one ' + TAG,
  'Code line two ' + TAG,
];
var expectedContent = lines.join('\n');
var content = record.value.content;
if (content !== expectedContent) {
  throw new Error(
    'content mismatch\nexpected: ' + JSON.stringify(expectedContent) +
      '\nactual:   ' + JSON.stringify(content)
  );
}

function facet(piece, features) {
  return { index: byteRange(content, piece), features: features };
}
function feature(name, attributes) {
  var value = { $type: FACET + name };
  for (var key in attributes || {}) value[key] = attributes[key];
  return value;
}

// In task 08 order: ascending byteStart, then byteEnd
var expectedFacets = [
  facet('bold', [feature('bold')]),
  facet('italic', [feature('italic')]),
  facet('struck', [feature('strikethrough')]),
  facet('secret', [feature('spoiler')]),
  facet('snippet', [feature('code')]),
  facet(mention, [feature('mention', { did: mentionDid })]),
  // The first '!science' is the by-name mention
  facet(communityByName, [feature('mention', { did: communityDid })]),
  facet(communityByAddress, [feature('mention', { did: communityDid })]),
  facet(lines[1], [feature('blockquote'), feature('heading', { level: 1 })]),
  facet(lines[3] + '\n' + lines[4], [
    feature('blockquote'),
    feature('codeBlock'),
  ]),
];

var actualFacets = record.value.facets || [];
var problems = [];
if (actualFacets.length !== expectedFacets.length) {
  problems.push(
    'expected ' + expectedFacets.length + ' facets, got ' + actualFacets.length
  );
}
// Compared position by position, so a correctly grouped set written out of
// order fails. Index and features only: a facet-level $type the AppView may
// add is not part of the contract under test
var facetCount = Math.max(actualFacets.length, expectedFacets.length);
for (var j = 0; j < facetCount; j++) {
  var expectedKey =
    j < expectedFacets.length ? canonical(expectedFacets[j]) : '(none)';
  var actualKey =
    j < actualFacets.length
      ? canonical({ index: actualFacets[j].index, features: actualFacets[j].features })
      : '(none)';
  if (actualKey !== expectedKey) {
    problems.push(
      'facet ' + j + ': expected ' + expectedKey + ', got ' + actualKey
    );
  }
}
if (problems.length > 0) {
  throw new Error(
    problems.join('\n') + '\nactual facets: ' + JSON.stringify(actualFacets)
  );
}

console.log('e10 comment ' + record.uri + ' has the expected content and facets');
console.log('e10 reply root ' + record.value.reply.root.uri);
output.e10CommentUri = record.uri;
output.e10PostUri = record.value.reply.root.uri;
output.e10FacetsOk = true;
