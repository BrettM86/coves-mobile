// Shared fixtures for the comment-removal tests (chunk 11).
//
// The thread: post P; root R (live); C, a reply of R by another author that
// carries the `remove` token, with two loaded replies C1 and C2, hasMore and
// a replies cursor; sibling root S.

import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/moderation.dart';
import 'package:coves_flutter/models/moderation_subject_state.dart';
import 'package:coves_flutter/models/post.dart';

const removalPostUri = 'at://did:plc:postauthor/social.coves.community.post/p';
const removalPostCid = 'cid-p';

const rootUri = 'at://did:plc:rootauthor/social.coves.community.comment/r';
const targetUri = 'at://did:plc:commenter/social.coves.community.comment/c';
const targetCid = 'cid-c';
const reply1Uri = 'at://did:plc:replier/social.coves.community.comment/c1';
const reply2Uri = 'at://did:plc:replier/social.coves.community.comment/c2';
const siblingUri =
    'at://did:plc:siblingauthor/social.coves.community.comment/s';

const targetAuthorDid = 'did:plc:commenter';
const adminDid = 'did:plc:admin';

const rootText = 'Root comment R';
const targetText = 'Comment C to remove';
const reply1Text = 'Reply C1';
const reply2Text = 'Reply C2';
const siblingText = 'Sibling comment S';

const targetRepliesCursor = 'c-replies-cursor';

/// The server that recorded the local removal.
const localRemovalServiceDid = 'did:web:coves.test';

/// The removal action's authority; differs from [localRemovalServiceDid] so
/// a test can tell which one the placeholder took.
const actionAuthorityDid = 'did:plc:actionauthority';

/// The one content label the mutation response carries.
const removalContentLabel = 'graphic-media';

CommentView fixtureComment({
  required String uri,
  required String authorDid,
  required String text,
  String? parentUri,
  Set<ModerationCapability> capabilities = const {},
}) {
  return CommentView(
    uri: uri,
    cid: 'cid-${uri.split('/').last}',
    record: CommentRecord(content: text),
    createdAt: DateTime.utc(2025),
    indexedAt: DateTime.utc(2025),
    author: AuthorView(
      did: authorDid,
      handle: '${authorDid.split(':').last}.coves.test',
    ),
    post: CommentRef(uri: removalPostUri, cid: removalPostCid),
    parent: parentUri == null
        ? null
        : CommentRef(uri: parentUri, cid: 'cid-${parentUri.split('/').last}'),
    stats: const CommentStats(score: 3, replyCount: 2),
    viewer: CommentViewerState(moderation: capabilities),
  );
}

/// C live: the remove token, replies C1 and C2, more replies to load.
///
/// [authorDid] lets a test make C the viewer's own comment; [text] serves
/// C's content as the server has it at some later point; [withReplies]
/// false serves C with no replies, as the server omits an empty `replies`.
ThreadViewComment liveTarget({
  String authorDid = targetAuthorDid,
  String text = targetText,
  bool withReplies = true,
}) {
  return ThreadViewComment(
    comment: fixtureComment(
      uri: targetUri,
      authorDid: authorDid,
      text: text,
      parentUri: rootUri,
      capabilities: const {ModerationCapability.remove},
    ),
    replies: withReplies
        ? [
            ThreadViewComment(
              comment: fixtureComment(
                uri: reply1Uri,
                authorDid: 'did:plc:replier',
                text: reply1Text,
                parentUri: targetUri,
              ),
            ),
            ThreadViewComment(
              comment: fixtureComment(
                uri: reply2Uri,
                authorDid: 'did:plc:replier',
                text: reply2Text,
                parentUri: targetUri,
              ),
            ),
          ]
        : null,
    hasMore: withReplies,
    repliesCursor: withReplies ? targetRepliesCursor : null,
  );
}

/// R live, with C live as its only loaded reply.
///
/// [text] and [targetBody] serve R's and C's content as the server has it
/// at some later point.
ThreadViewComment liveRoot({
  String text = rootText,
  String targetBody = targetText,
}) {
  return ThreadViewComment(
    comment: fixtureComment(
      uri: rootUri,
      authorDid: 'did:plc:rootauthor',
      text: text,
    ),
    replies: [liveTarget(text: targetBody)],
  );
}

ThreadViewComment liveSibling() {
  return ThreadViewComment(
    comment: fixtureComment(
      uri: siblingUri,
      authorDid: 'did:plc:siblingauthor',
      text: siblingText,
    ),
  );
}

/// The thread as the server serves it: [R(C(C1, C2)), S].
List<ThreadViewComment> liveThreads({String targetBody = targetText}) => [
  liveRoot(targetBody: targetBody),
  liveSibling(),
];

/// C's content after the author edited it on the server.
const serverTargetText = 'Comment C as the server has it now';

/// R's content after the author edited it on the server.
const editedRootText = 'Root comment R, edited on the server';

FeedViewPost removalPost() {
  return FeedViewPost(
    post: PostView(
      uri: removalPostUri,
      cid: removalPostCid,
      rkey: 'p',
      author: AuthorView(
        did: 'did:plc:postauthor',
        handle: 'postauthor.coves.test',
      ),
      community: CommunityRef(did: 'did:plc:community', name: 'testcove'),
      createdAt: DateTime.utc(2025),
      indexedAt: DateTime.utc(2025),
      record: const PostRecord(title: 'Post P', content: 'Post P body'),
      stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 5),
    ),
  );
}

/// C's moderation state before the removal, as getSubjectState serves it.
ModerationSubjectState targetClearState() {
  return const ModerationSubjectState(
    subject: targetUri,
    version: 'v1',
    moderation: ModerationView(state: ModerationState.clear),
    recordState: ModerationRecordState.present,
    currentSubject: StrongRef(uri: targetUri, cid: targetCid),
  );
}

/// A removeContent response body for C as the backend writes it
/// (`writeMutationResult`): `state.moderation` carries the state and the
/// content labels but no `sources`.
Map<String, dynamic> removeContentJson({
  String outcome = 'applied',
  bool withLocalRemoval = true,
  bool withAction = true,
}) {
  return {
    'outcome': outcome,
    'state': {
      'subject': targetUri,
      'version': 'v2',
      'moderation': {
        'state': 'removed',
        'contentLabels': [
          {'value': removalContentLabel},
        ],
      },
      'recordState': 'present',
      'currentSubject': {'uri': targetUri, 'cid': targetCid},
      if (withLocalRemoval)
        'localRemoval': {
          'serviceDid': localRemovalServiceDid,
          'actionId': 'removal-1',
        },
    },
    if (withAction)
      'action': {
        'action': {
          'ref': {
            'serviceDid': localRemovalServiceDid,
            'actionId': 'removal-1',
          },
          'action': 'remove',
          'createdAt': '2026-10-01T12:00:00.000Z',
          'authorityDid': actionAuthorityDid,
          'scope': {'kind': 'instance'},
          'origin': 'local',
          'reason': 'social.coves.moderation.defs#reasonSpam',
        },
        'actorDid': adminDid,
      },
  };
}

/// C's moderation state once it is removed, as getSubjectState serves it
/// (the state half of [removeContentJson]).
ModerationSubjectState targetRemovedState() => ModerationSubjectState.fromJson(
  removeContentJson()['state'] as Map<String, dynamic>,
);

/// C as the server serves it after an instance removal (chunk 14): the
/// removed placeholder with no record, the `handle.invalid` author and the
/// instance-scoped removal, carrying the `restore` token unless
/// [restoreToken] is false. [moderation] replaces the served removal.
CommentView serverRemovedTarget({
  bool restoreToken = true,
  ModerationView? moderation,
}) {
  return CommentView(
    uri: targetUri,
    cid: targetCid,
    isDeleted: true,
    deletionReason: 'moderator',
    createdAt: DateTime.utc(2025),
    indexedAt: DateTime.utc(2025),
    author: AuthorView(did: targetAuthorDid, handle: 'handle.invalid'),
    post: CommentRef(uri: removalPostUri, cid: removalPostCid),
    parent: CommentRef(uri: rootUri, cid: 'cid-r'),
    stats: const CommentStats(replyCount: 2),
    viewer: CommentViewerState(
      moderation: restoreToken
          ? const {ModerationCapability.restore}
          : const {},
    ),
    moderation:
        moderation ??
        const ModerationView(
          state: ModerationState.removed,
          sources: [
            ModerationSource(
              authorityDid: localRemovalServiceDid,
              scope: ModerationScope(kind: ModerationScopeKind.instance),
            ),
          ],
        ),
  );
}

/// C's subtree as the server serves it while C is removed: the placeholder
/// ([serverRemovedTarget]) with C1 and C2 loaded and more replies to load.
ThreadViewComment serverRemovedTargetThread({bool restoreToken = true}) {
  final live = liveTarget();
  return ThreadViewComment(
    comment: serverRemovedTarget(restoreToken: restoreToken),
    replies: live.replies,
    hasMore: live.hasMore,
    repliesCursor: live.repliesCursor,
  );
}

/// The thread as the server serves it while C is removed:
/// [R(placeholder C(C1, C2)), S], C carrying the `restore` token.
List<ThreadViewComment> threadsWithRemovedTarget() {
  return [
    ThreadViewComment(
      comment: liveRoot().comment,
      replies: [serverRemovedTargetThread()],
    ),
    liveSibling(),
  ];
}

/// A restoreContent response body for C: an applied restore whose
/// resulting state is [moderationState] and [recordState]; a present record
/// carries its current version.
Map<String, dynamic> restoreContentJson({
  String moderationState = 'clear',
  String recordState = 'present',
}) {
  return {
    'outcome': 'applied',
    'state': {
      'subject': targetUri,
      'version': 'v3',
      'moderation': {'state': moderationState},
      'recordState': recordState,
      if (recordState == 'present')
        'currentSubject': {'uri': targetUri, 'cid': targetCid},
    },
  };
}
