// B4: CommentsProvider.updateComment validates, sends the stored record to
// the service, and patches the loaded tree locally without a refetch (the
// AppView learns about edits through Jetstream, so an immediate read can
// still return the old text).

import 'dart:async';

import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/facet.dart';
import 'package:coves_flutter/models/moderation.dart';
import 'package:coves_flutter/models/moderation_subject_state.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/providers/comments_provider.dart';
import 'package:coves_flutter/providers/user_profile_provider.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/comment_change_broadcast.dart';
import 'package:coves_flutter/services/comment_service.dart';
import 'package:coves_flutter/services/post_change_broadcast.dart';
import 'package:coves_flutter/services/profile_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/comment_removal_fixtures.dart';
import '../test_helpers/fake_providers.dart' show unchangingSessionKey;
import '../test_helpers/test_mocks.dart';

const _viewerDid = 'did:plc:commenter';
const _outsideUri =
    'at://did:plc:commenter/social.coves.community.comment/outside';

const _recordEmbed = <String, dynamic>{
  r'$type': 'social.coves.embed.images',
  'images': [
    {
      'image': {
        r'$type': 'blob',
        'ref': {r'$link': 'bafkreiimage'},
        'mimeType': 'image/jpeg',
        'size': 12345,
      },
      'alt': 'a cat',
    },
  ],
};

const _viewEmbed = <String, dynamic>{
  r'$type': 'social.coves.embed.images#view',
  'images': [
    {
      'thumb': 'https://cdn.coves.test/thumb/bafkreiimage',
      'fullsize': 'https://cdn.coves.test/full/bafkreiimage',
      'alt': 'a cat',
    },
  ],
};

const _labels = <String, dynamic>{
  r'$type': 'com.atproto.label.defs#selfLabels',
  'values': [
    {'val': 'nudity'},
  ],
};

const _oldBold = RichTextFacet(
  index: ByteSlice(byteStart: 0, byteEnd: 4),
  features: [BoldFacetFeature()],
);

const _newItalic = RichTextFacet(
  index: ByteSlice(byteStart: 0, byteEnd: 6),
  features: [ItalicFacetFeature()],
);

CommentView _ownComment({
  required String uri,
  required String text,
  String? parentUri,
  CommentStats stats = const CommentStats(score: 3, replyCount: 2),
}) {
  return fixtureComment(
    uri: uri,
    authorDid: _viewerDid,
    text: text,
    parentUri: parentUri,
    stats: stats,
    capabilities: const {ModerationCapability.remove},
    facets: const [_oldBold],
    recordEmbed: _recordEmbed,
    langs: const ['en', 'fr'],
    labels: _labels,
    viewEmbed: _viewEmbed,
  );
}

/// [R(C(C1)), S] where R (top level) and C (nested) are the viewer's own
/// formatted comments carrying a record embed, langs and labels.
/// [rootStats] serves R's stats as the server has them at some later point.
List<ThreadViewComment> _threads({
  CommentStats rootStats = const CommentStats(score: 3, replyCount: 2),
}) => [
  ThreadViewComment(
    comment: _ownComment(uri: rootUri, text: 'Root body', stats: rootStats),
    replies: [
      ThreadViewComment(
        comment: _ownComment(
          uri: targetUri,
          text: 'Nested body',
          parentUri: rootUri,
        ),
        replies: [
          ThreadViewComment(
            comment: fixtureComment(
              uri: reply1Uri,
              authorDid: 'did:plc:replier',
              text: reply1Text,
              parentUri: targetUri,
            ),
          ),
        ],
      ),
    ],
  ),
  ThreadViewComment(
    comment: fixtureComment(
      uri: siblingUri,
      authorDid: 'did:plc:siblingauthor',
      text: siblingText,
    ),
  ),
];

/// Depth-first `uri|content|cid` of every loaded node.
List<String> _flatten(List<ThreadViewComment> threads) {
  final out = <String>[];
  void visit(ThreadViewComment node) {
    out.add('${node.comment.uri}|${node.comment.content}|${node.comment.cid}');
    (node.replies ?? const <ThreadViewComment>[]).forEach(visit);
  }

  threads.forEach(visit);
  return out;
}

const _originalTree = [
  '$rootUri|Root body|cid-r',
  '$targetUri|Nested body|cid-c',
  '$reply1Uri|$reply1Text|cid-c1',
  '$siblingUri|$siblingText|cid-s',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAuthProvider auth;
  late MockCovesApiService api;
  late MockCommentService service;
  late CommentsProvider provider;
  late int getCommentsCalls;

  setUp(() async {
    auth = MockAuthProvider();
    api = MockCovesApiService();
    service = MockCommentService();
    getCommentsCalls = 0;
    when(auth.isAuthenticated).thenReturn(true);
    when(auth.did).thenReturn(_viewerDid);
    when(
      api.getComments(
        postUri: anyNamed('postUri'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        depth: anyNamed('depth'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
        parentRkey: anyNamed('parentRkey'),
      ),
    ).thenAnswer((_) async {
      getCommentsCalls++;
      return CommentsResponse(post: null, comments: _threads());
    });
    when(
      service.updateComment(
        uri: anyNamed('uri'),
        content: anyNamed('content'),
        facets: anyNamed('facets'),
        record: anyNamed('record'),
      ),
    ).thenAnswer(
      (invocation) async => UpdateCommentResponse(
        uri: invocation.namedArguments[#uri] as String,
        cid: 'cid-new',
      ),
    );

    provider = CommentsProvider(
      auth,
      postUri: removalPostUri,
      postCid: removalPostCid,
      apiService: api,
      commentService: service,
    );
    await provider.loadComments(refresh: true);
    expect(_flatten(provider.comments), _originalTree);
  });

  tearDown(() => provider.dispose());

  ThreadViewComment node(String uri) =>
      provider.comments.map((t) => t.findByUri(uri)).nonNulls.single;

  group('validation', () {
    for (final row in [
      (name: 'whitespace-only', content: '   \n  '),
      (name: 'too long', content: 'a' * 10001),
    ]) {
      test('${row.name} content throws ValidationException without calling '
          'the service', () async {
        await expectLater(
          provider.updateComment(
            comment: node(rootUri).comment,
            content: row.content,
          ),
          throwsA(isA<ValidationException>()),
        );
        verifyNever(
          service.updateComment(
            uri: anyNamed('uri'),
            content: anyNamed('content'),
            facets: anyNamed('facets'),
            record: anyNamed('record'),
          ),
        );
      });
    }
  });

  test('passes the stored record with its raw embed, langs and labels to the '
      'service', () async {
    await provider.updateComment(
      comment: node(targetUri).comment,
      content: 'Edited',
      facets: const [_newItalic],
    );

    final captured = verify(
      service.updateComment(
        uri: captureAnyNamed('uri'),
        content: captureAnyNamed('content'),
        facets: captureAnyNamed('facets'),
        record: captureAnyNamed('record'),
      ),
    ).captured;
    expect(captured[0], targetUri);
    expect(captured[1], 'Edited');
    expect(captured[2], const [_newItalic]);
    final record = captured[3] as CommentRecord;
    expect(record.embed, _recordEmbed);
    expect(record.langs, ['en', 'fr']);
    expect(record.labels, _labels);
  });

  for (final row
      in <
        ({String name, String uri, List<String> replyUris, String? parentUri})
      >[
        (
          name: 'top-level',
          uri: rootUri,
          replyUris: [targetUri],
          parentUri: null,
        ),
        (
          name: 'nested reply',
          uri: targetUri,
          replyUris: [reply1Uri],
          parentUri: rootUri,
        ),
      ]) {
    test(
      'a ${row.name} edit patches the node in place and returns it',
      () async {
        final updated = await provider.updateComment(
          comment: node(row.uri).comment,
          content: 'Edited',
          facets: const [_newItalic],
        );

        void expectEdited(CommentView view) {
          expect(view.uri, row.uri);
          expect(view.content, 'Edited');
          expect(view.contentFacets, const [_newItalic]);
          expect(view.cid, 'cid-new');
          expect(view.record!.embed, _recordEmbed);
          expect(view.record!.langs, ['en', 'fr']);
          expect(view.record!.labels, _labels);
          expect(view.embed, _viewEmbed);
          expect(view.author!.did, _viewerDid);
          expect(view.parent?.uri, row.parentUri);
          expect(view.stats.score, 3);
          expect(view.stats.replyCount, 2);
          expect(view.viewer!.moderation, {ModerationCapability.remove});
        }

        expectEdited(updated);
        final patched = node(row.uri);
        expectEdited(patched.comment);
        expect(
          patched.replies!.map((r) => r.comment.uri).toList(),
          row.replyUris,
        );
      },
    );
  }

  for (final row in <({String name, List<RichTextFacet>? facets})>[
    (name: 'null', facets: null),
    (name: 'empty', facets: const []),
  ]) {
    test('a formatted comment saved with ${row.name} facets ends with no '
        'facets', () async {
      final updated = await provider.updateComment(
        comment: node(rootUri).comment,
        content: 'Root body plain',
        facets: row.facets,
      );

      expect(updated.contentFacets, anyOf(isNull, isEmpty));
      expect(node(rootUri).comment.content, 'Root body plain');
      expect(node(rootUri).comment.contentFacets, anyOf(isNull, isEmpty));
    });
  }

  test('does not refetch comments after the update', () async {
    expect(getCommentsCalls, 1);

    await provider.updateComment(
      comment: node(rootUri).comment,
      content: 'Edited',
    );
    await pumpEventQueue();

    expect(node(rootUri).comment.content, 'Edited');
    expect(getCommentsCalls, 1);
  });

  test('a comment outside the loaded tree is still updated and returned; the '
      'tree is unchanged', () async {
    final outside = _ownComment(uri: _outsideUri, text: 'Outside body');

    final updated = await provider.updateComment(
      comment: outside,
      content: 'Outside edited',
    );

    expect(updated.uri, _outsideUri);
    expect(updated.content, 'Outside edited');
    expect(updated.cid, 'cid-new');
    expect(updated.record!.embed, _recordEmbed);
    expect(updated.embed, _viewEmbed);
    expect(_flatten(provider.comments), _originalTree);
  });

  test('a service failure leaves the tree unchanged and propagates', () async {
    final failure = ApiException(
      'the comment changed while you were editing',
      statusCode: 409,
      errorCode: 'ConcurrentModification',
    );
    when(
      service.updateComment(
        uri: anyNamed('uri'),
        content: anyNamed('content'),
        facets: anyNamed('facets'),
        record: anyNamed('record'),
      ),
    ).thenThrow(failure);

    await expectLater(
      provider.updateComment(comment: node(rootUri).comment, content: 'Edited'),
      throwsA(same(failure)),
    );
    expect(_flatten(provider.comments), _originalTree);
    expect(node(rootUri).comment.contentFacets, const [_oldBold]);
  });

  void serveThreads(List<ThreadViewComment> threads) {
    when(
      api.getComments(
        postUri: anyNamed('postUri'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        depth: anyNamed('depth'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
        parentRkey: anyNamed('parentRkey'),
      ),
    ).thenAnswer((_) async => CommentsResponse(post: null, comments: threads));
  }

  /// Holds every service update until the returned completer completes.
  Completer<UpdateCommentResponse> holdUpdates() {
    final pending = Completer<UpdateCommentResponse>();
    when(
      service.updateComment(
        uri: anyNamed('uri'),
        content: anyNamed('content'),
        facets: anyNamed('facets'),
        record: anyNamed('record'),
      ),
    ).thenAnswer((_) => pending.future);
    return pending;
  }

  void markTargetRemoved(CommentsProvider target) {
    final result = ModerationMutationResult.fromJson(removeContentJson());
    target.markCommentRemoved(
      commentUri: targetUri,
      state: result.state,
      action: result.action,
    );
  }

  group('F1 the edited view derives from the current node', () {
    test('a node replaced with newer stats while the save is pending keeps '
        'those stats and takes the new content and cid', () async {
      final pending = holdUpdates();
      final save = provider.updateComment(
        comment: node(rootUri).comment,
        content: 'Edited',
      );
      await pumpEventQueue();

      serveThreads(
        _threads(rootStats: const CommentStats(score: 9, replyCount: 7)),
      );
      await provider.refreshComments();
      expect(node(rootUri).comment.stats.score, 9);

      pending.complete(
        const UpdateCommentResponse(uri: rootUri, cid: 'cid-new'),
      );
      await save;

      final patched = node(rootUri).comment;
      expect(patched.content, 'Edited');
      expect(patched.cid, 'cid-new');
      expect(patched.stats.score, 9);
      expect(patched.stats.replyCount, 7);
    });

    test('a comment removed by a moderator while the save is pending stays '
        'the removed placeholder', () async {
      final pending = holdUpdates();
      final save = provider.updateComment(
        comment: node(targetUri).comment,
        content: 'Edited',
      );
      await pumpEventQueue();

      markTargetRemoved(provider);
      expect(node(targetUri).comment.isDeleted, isTrue);

      pending.complete(
        const UpdateCommentResponse(uri: targetUri, cid: 'cid-new'),
      );
      await save;

      final after = node(targetUri).comment;
      expect(after.isDeleted, isTrue);
      expect(after.record, isNull);
      expect(after.content, '');
      expect(after.moderation?.state, ModerationState.removed);
    });
  });

  group('F2 edits propagate through the comment change broadcast', () {
    const profileStats = CommentStats(score: 20);

    late CommentChangeBroadcast broadcast;
    late CommentsProvider thread;
    late ProfileCache profileCache;
    late UserProfileProvider profile;

    setUp(() async {
      broadcast = CommentChangeBroadcast();
      thread = CommentsProvider(
        auth,
        postUri: removalPostUri,
        postCid: removalPostCid,
        apiService: api,
        commentService: service,
        commentChangeBroadcast: broadcast,
      );
      await thread.loadComments(refresh: true);

      when(api.getProfile(actor: anyNamed('actor'))).thenAnswer(
        (_) async => UserProfile(did: _viewerDid, handle: 'commenter.test'),
      );
      when(
        api.getActorComments(
          actor: anyNamed('actor'),
          community: anyNamed('community'),
          limit: anyNamed('limit'),
          cursor: anyNamed('cursor'),
        ),
      ).thenAnswer(
        (_) async => ActorCommentsResponse(
          comments: [
            _ownComment(
              uri: targetUri,
              text: 'Nested body',
              parentUri: rootUri,
              stats: profileStats,
            ),
          ],
        ),
      );
      profileCache = ProfileCache(auth);
      profile = UserProfileProvider(
        auth,
        apiService: api,
        commentService: service,
        profileCache: profileCache,
        postChangeBroadcast: PostChangeBroadcast(),
        sessionKeyOf: unchangingSessionKey,
        commentChangeBroadcast: broadcast,
      );
      await profile.loadProfile(_viewerDid);
      await profile.loadComments(refresh: true);
      expect(profile.commentsState.comments.single.stats.score, 20);
    });

    tearDown(() {
      thread.dispose();
      profile.dispose();
      profileCache.dispose();
    });

    ThreadViewComment threadNode(String uri) =>
        thread.comments.map((t) => t.findByUri(uri)).nonNulls.single;

    test('(a) a profile edit patches the thread node, which keeps its own '
        'stats and replies', () async {
      await profile.updateComment(
        comment: profile.commentsState.comments.single,
        content: 'Edited from profile',
      );

      final patched = threadNode(targetUri);
      expect(patched.comment.content, 'Edited from profile');
      expect(patched.comment.cid, 'cid-new');
      expect(patched.comment.stats.score, 3);
      expect(patched.comment.stats.replyCount, 2);
      expect(patched.replies!.map((r) => r.comment.uri).toList(), [reply1Uri]);
    });

    test('(b) a thread edit patches the profile list item, which keeps its '
        'own stats', () async {
      await thread.updateComment(
        comment: threadNode(targetUri).comment,
        content: 'Edited in thread',
      );

      final patched = profile.commentsState.comments.single;
      expect(patched.content, 'Edited in thread');
      expect(patched.cid, 'cid-new');
      expect(patched.stats.score, 20);
      expect(patched.stats.replyCount, 0);
    });

    test('(c) a broadcast for a comment the thread holds as a removed '
        'placeholder leaves it a placeholder; a live one is patched', () async {
      markTargetRemoved(thread);

      broadcast
        ..replaceComment(
          _ownComment(
            uri: targetUri,
            text: 'Nested body',
            parentUri: rootUri,
          ).withEditedRecord(
            record: const CommentRecord(content: 'Broadcast edit C'),
            cid: 'cid-bc',
          ),
        )
        ..replaceComment(
          _ownComment(uri: rootUri, text: 'Root body').withEditedRecord(
            record: const CommentRecord(content: 'Broadcast edit R'),
            cid: 'cid-br',
          ),
        );

      final root = threadNode(rootUri).comment;
      expect(root.content, 'Broadcast edit R');
      expect(root.cid, 'cid-br');
      final target = threadNode(targetUri).comment;
      expect(target.isDeleted, isTrue);
      expect(target.record, isNull);
      expect(target.moderation?.state, ModerationState.removed);
    });
  });

  test('F3 a comment with no stored record throws and never calls the '
      'service', () async {
    final withoutRecord = CommentView(
      uri: rootUri,
      cid: 'cid-r',
      createdAt: DateTime.utc(2025),
      indexedAt: DateTime.utc(2025),
      author: AuthorView(did: _viewerDid, handle: 'commenter.coves.test'),
      post: CommentRef(uri: removalPostUri, cid: removalPostCid),
      stats: const CommentStats(score: 3, replyCount: 2),
    );

    await expectLater(
      provider.updateComment(comment: withoutRecord, content: 'Edited'),
      throwsA(isA<ApiException>()),
    );
    verifyNever(
      service.updateComment(
        uri: anyNamed('uri'),
        content: anyNamed('content'),
        facets: anyNamed('facets'),
        record: anyNamed('record'),
      ),
    );
    expect(_flatten(provider.comments), _originalTree);
  });
}
