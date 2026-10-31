// B5: UserProfileProvider.updateComment sends the stored record to the
// service and patches the profile's comment list so the edit survives
// loading further pages.

import 'dart:async';

import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/facet.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/providers/user_profile_provider.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/comment_service.dart';
import 'package:coves_flutter/services/post_change_broadcast.dart';
import 'package:coves_flutter/services/profile_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/comment_removal_fixtures.dart';
import '../test_helpers/fake_providers.dart' show unchangingSessionKey;
import '../test_helpers/test_mocks.dart';

const _profileDid = 'did:plc:profileowner';

String _uri(String id) =>
    'at://did:plc:profileowner/social.coves.community.comment/$id';

const _recordEmbed = <String, dynamic>{
  r'$type': 'social.coves.embed.external',
  'external': {
    'uri': 'https://example.test/article',
    'thumb': {
      r'$type': 'blob',
      'ref': {r'$link': 'bafkreithumb'},
      'mimeType': 'image/png',
      'size': 999,
    },
  },
};

const _labels = <String, dynamic>{
  r'$type': 'com.atproto.label.defs#selfLabels',
  'values': [
    {'val': 'graphic-media'},
  ],
};

const _oldBold = RichTextFacet(
  index: ByteSlice(byteStart: 0, byteEnd: 5),
  features: [BoldFacetFeature()],
);

const _newItalic = RichTextFacet(
  index: ByteSlice(byteStart: 0, byteEnd: 6),
  features: [ItalicFacetFeature()],
);

CommentView _comment(
  String id,
  String text, {
  bool formatted = false,
  CommentStats stats = const CommentStats(score: 3, replyCount: 2),
}) => fixtureComment(
  uri: _uri(id),
  authorDid: _profileDid,
  text: text,
  stats: stats,
  facets: formatted ? const [_oldBold] : null,
  recordEmbed: formatted ? _recordEmbed : null,
  langs: formatted ? const ['en'] : null,
  labels: formatted ? _labels : null,
);

List<String> _rows(CommentsState state) => [
  for (final c in state.comments) '${c.uri}|${c.content}|${c.cid}',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAuthProvider auth;
  late MockCovesApiService api;
  late MockCommentService service;
  late ProfileCache profileCache;
  late UserProfileProvider provider;

  setUp(() async {
    auth = MockAuthProvider();
    api = MockCovesApiService();
    service = MockCommentService();
    when(auth.isAuthenticated).thenReturn(false);
    when(auth.did).thenReturn(null);
    when(
      api.getProfile(actor: anyNamed('actor')),
    ).thenAnswer((_) async => UserProfile(did: _profileDid, handle: 'me.test'));
    when(
      api.getActorComments(
        actor: anyNamed('actor'),
        community: anyNamed('community'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((invocation) async {
      final cursor = invocation.namedArguments[#cursor] as String?;
      return cursor == null
          ? ActorCommentsResponse(
              comments: [
                _comment('a', 'First', formatted: true),
                _comment('b', 'Second'),
              ],
              cursor: 'page-2',
            )
          : ActorCommentsResponse(comments: [_comment('c', 'Third')]);
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

    profileCache = ProfileCache(auth);
    provider = UserProfileProvider(
      auth,
      apiService: api,
      commentService: service,
      profileCache: profileCache,
      postChangeBroadcast: PostChangeBroadcast(),
      sessionKeyOf: unchangingSessionKey,
    );
    await provider.loadProfile(_profileDid);
    await provider.loadComments(refresh: true);
    expect(_rows(provider.commentsState), [
      '${_uri('a')}|First|cid-a',
      '${_uri('b')}|Second|cid-b',
    ]);
  });

  tearDown(() {
    provider.dispose();
    profileCache.dispose();
  });

  CommentView first() => provider.commentsState.comments.first;

  test('passes the stored record to the service', () async {
    await provider.updateComment(
      comment: first(),
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
    expect(captured[0], _uri('a'));
    expect(captured[1], 'Edited');
    expect(captured[2], const [_newItalic]);
    final record = captured[3] as CommentRecord;
    expect(record.embed, _recordEmbed);
    expect(record.langs, ['en']);
    expect(record.labels, _labels);
  });

  test('patches the comment in commentsState and the edit survives loading '
      'the next page', () async {
    final updated = await provider.updateComment(
      comment: first(),
      content: 'Edited',
      facets: const [_newItalic],
    );

    expect(updated.content, 'Edited');
    expect(updated.contentFacets, const [_newItalic]);
    expect(updated.cid, 'cid-new');
    expect(_rows(provider.commentsState), [
      '${_uri('a')}|Edited|cid-new',
      '${_uri('b')}|Second|cid-b',
    ]);
    expect(first().contentFacets, const [_newItalic]);
    expect(first().record!.embed, _recordEmbed);

    await provider.loadMoreComments();

    expect(_rows(provider.commentsState), [
      '${_uri('a')}|Edited|cid-new',
      '${_uri('b')}|Second|cid-b',
      '${_uri('c')}|Third|cid-c',
    ]);
    expect(first().contentFacets, const [_newItalic]);
  });

  test('a formatted comment saved with no facets ends with none', () async {
    await provider.updateComment(comment: first(), content: 'First plain');

    expect(first().content, 'First plain');
    expect(first().contentFacets, anyOf(isNull, isEmpty));
  });

  test('a service failure leaves the list unchanged and propagates', () async {
    final failure = NotFoundException('comment not found');
    when(
      service.updateComment(
        uri: anyNamed('uri'),
        content: anyNamed('content'),
        facets: anyNamed('facets'),
        record: anyNamed('record'),
      ),
    ).thenThrow(failure);

    await expectLater(
      provider.updateComment(comment: first(), content: 'Edited'),
      throwsA(same(failure)),
    );
    expect(_rows(provider.commentsState), [
      '${_uri('a')}|First|cid-a',
      '${_uri('b')}|Second|cid-b',
    ]);
    expect(first().contentFacets, const [_oldBold]);
  });

  test('F1 an item replaced with newer stats while the save is pending keeps '
      'those stats and takes the new content and cid', () async {
    final pending = Completer<UpdateCommentResponse>();
    when(
      service.updateComment(
        uri: anyNamed('uri'),
        content: anyNamed('content'),
        facets: anyNamed('facets'),
        record: anyNamed('record'),
      ),
    ).thenAnswer((_) => pending.future);
    final save = provider.updateComment(comment: first(), content: 'Edited');
    await pumpEventQueue();

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
          _comment(
            'a',
            'First',
            formatted: true,
            stats: const CommentStats(score: 9, replyCount: 7),
          ),
          _comment('b', 'Second'),
        ],
      ),
    );
    await provider.loadComments(refresh: true);
    expect(first().stats.score, 9);

    pending.complete(UpdateCommentResponse(uri: _uri('a'), cid: 'cid-new'));
    await save;

    expect(first().content, 'Edited');
    expect(first().cid, 'cid-new');
    expect(first().stats.score, 9);
    expect(first().stats.replyCount, 7);
  });

  test('F3 a comment with no stored record throws and never calls the '
      'service', () async {
    final withoutRecord = CommentView(
      uri: _uri('a'),
      cid: 'cid-a',
      createdAt: DateTime.utc(2025),
      indexedAt: DateTime.utc(2025),
      author: AuthorView(did: _profileDid, handle: 'me.test'),
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
    expect(_rows(provider.commentsState), [
      '${_uri('a')}|First|cid-a',
      '${_uri('b')}|Second|cid-b',
    ]);
  });
}
