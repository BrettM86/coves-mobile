// Characterization net for the comment-tree algebra now extracted into
// lib/models/comment_thread_tree.dart (merge, node replacement, lookup,
// membership, and the subtree-construction decision).
//
// Every test drives that algebra through CommentsProvider's public surface
// (loadComments / loadMoreReplies / comments) with a faked CovesApiService,
// matching comments_provider_test.dart's idioms. It was written this way
// while the algebra was still private to the provider, and it stays that way
// on purpose: asserting through the provider proves the extracted type is
// wired up correctly, not merely correct in isolation. Direct unit tests of
// the tree type are complementary, not a replacement.
//
// The merge has FOUR branches and they disagree with each other in ways that
// look like bugs and are not:
//
//   * fresh replies empty + existing replies present  -> keep the existing
//     branch AND existing.hasMore AND existing.repliesCursor   (T2)
//   * fresh replies empty + existing replies empty    -> return fresh
//     VERBATIM, which DROPS existing.repliesCursor             (T3)
//   * recursive branch -> repliesCursor from existing but hasMore from
//     FRESH, the opposite of the truncation branch above       (T7)
//   * leftover existing children are appended when fresh.hasMore is true and
//     DROPPED when it is false                                 (T5/T6)
//
// T2/T3/T7 are only observable at NESTED depth: for the node the request was
// anchored at, the caller's outer copyWith overwrites hasMore and
// repliesCursor from the response cursor, masking whatever the merge chose.

import 'dart:async';

import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/comments_provider.dart';
import 'package:coves_flutter/services/comment_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/test_mocks.dart';

const String commentBase = 'at://did:plc:author/social.coves.community.comment';
const String rootUri = '$commentBase/root';
const String otherRootUri = '$commentBase/otherroot';
const String childUri = '$commentBase/child';
const String siblingUri = '$commentBase/sibling';
const String grandchildUri = '$commentBase/grandchild';
const String greatGrandUri = '$commentBase/greatgrand';
const String orphanUri = '$commentBase/orphan';
const String replyAUri = '$commentBase/replya';
const String replyBUri = '$commentBase/replyb';

/// The rkey the provider derives from an AT-URI: its last path segment.
String rkeyOf(String uri) => uri.split('/').last;

CommentView buildView(String uri, {String content = 'body', int score = 0}) {
  return CommentView(
    uri: uri,
    cid: 'cid-$uri',
    record: CommentRecord(content: content),
    createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
    indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
    author: AuthorView(did: 'did:plc:author', handle: 'test.user'),
    post: CommentRef(
      uri: 'at://did:plc:test/social.coves.post.record/123',
      cid: 'post-cid',
    ),
    stats: CommentStats(score: score, upvotes: score),
  );
}

ThreadViewComment node(
  String uri, {
  String content = 'body',
  int score = 0,
  List<ThreadViewComment>? replies,
  bool hasMore = false,
}) {
  return ThreadViewComment(
    comment: buildView(uri, content: content, score: score),
    replies: replies,
    hasMore: hasMore,
  );
}

List<String> repliesOf(ThreadViewComment? parent) =>
    (parent?.replies ?? const <ThreadViewComment>[])
        .map((r) => r.comment.uri)
        .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testPostUri = 'at://did:plc:test/social.coves.post.record/123';
  const testPostCid = 'test-post-cid';

  late MockAuthProvider mockAuthProvider;
  late MockCovesApiService mockApiService;
  late CommentsProvider provider;

  /// Queued subtree responses, keyed by the rkey the provider will send.
  ///
  /// Strictly one queued response per expected fetch, consumed in order: a
  /// test that under-enqueues fails loudly rather than silently replaying
  /// the previous page.
  late Map<String, List<Future<CommentsResponse>>> subtreeQueues;

  void enqueueSubtree(String uri, CommentsResponse response) {
    (subtreeQueues[rkeyOf(uri)] ??= <Future<CommentsResponse>>[]).add(
      Future<CommentsResponse>.value(response),
    );
  }

  void enqueueSubtreeFuture(String uri, Future<CommentsResponse> response) {
    (subtreeQueues[rkeyOf(uri)] ??= <Future<CommentsResponse>>[]).add(response);
  }

  /// Answers the top-level thread fetch (the one with no parentRkey).
  void stubInitialTree(List<ThreadViewComment> comments) {
    when(
      mockApiService.getComments(
        postUri: anyNamed('postUri'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        depth: anyNamed('depth'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer(
      (_) async => CommentsResponse(post: {}, comments: comments),
    );
  }

  setUp(() {
    mockAuthProvider = MockAuthProvider();
    mockApiService = MockCovesApiService();
    subtreeQueues = <String, List<Future<CommentsResponse>>>{};

    when(mockAuthProvider.isAuthenticated).thenReturn(true);
    when(
      mockAuthProvider.getAccessToken(),
    ).thenAnswer((_) async => 'test-token');

    // One stub for every subtree fetch; the rkey selects the response.
    when(
      mockApiService.getComments(
        postUri: anyNamed('postUri'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        depth: anyNamed('depth'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
        parentRkey: argThat(isNotNull, named: 'parentRkey'),
      ),
    ).thenAnswer((invocation) {
      final rkey = invocation.namedArguments[#parentRkey] as String;
      final queue = subtreeQueues[rkey];
      if (queue == null || queue.isEmpty) {
        return Future<CommentsResponse>.error(
          StateError('no subtree response queued for rkey "$rkey"'),
        );
      }
      return queue.removeAt(0);
    });

    provider = CommentsProvider(
      mockAuthProvider,
      postUri: testPostUri,
      postCid: testPostCid,
      apiService: mockApiService,
    );
  });

  tearDown(() {
    provider.dispose();
  });

  /// Gives [uri]'s node a stored repliesCursor the only way production can:
  /// by completing one real load-more page against it.
  Future<void> seedRepliesCursor(
    String uri, {
    required List<ThreadViewComment> replies,
    required String cursor,
  }) async {
    enqueueSubtree(
      uri,
      CommentsResponse(
        post: {},
        comments: [node(uri, replies: replies)],
        cursor: cursor,
      ),
    );
    await provider.loadMoreReplies(uri);
  }

  group('merge algebra', () {
    test('T1 fresh wins for node content and stats', () async {
      stubInitialTree([
        node(rootUri, content: 'stale', score: 1, replies: [node(childUri)]),
      ]);
      await provider.loadComments(refresh: true);

      enqueueSubtree(
        rootUri,
        CommentsResponse(
          post: {},
          comments: [
            node(
              rootUri,
              content: 'fresh',
              score: 42,
              replies: [node(childUri)],
            ),
          ],
        ),
      );
      await provider.loadMoreReplies(rootUri);

      final merged = provider.comments.single;
      expect(merged.comment.record?.content, 'fresh');
      expect(merged.comment.stats.score, 42);
    });

    test('T2 truncated fresh node keeps the existing branch, its hasMore '
        'and its repliesCursor', () async {
      stubInitialTree([
        node(
          rootUri,
          replies: [
            node(childUri, hasMore: true, replies: [node(grandchildUri)]),
          ],
        ),
      ]);
      await provider.loadComments(refresh: true);

      await seedRepliesCursor(
        childUri,
        replies: [node(grandchildUri)],
        cursor: 'child-cursor',
      );

      // The ancestor refetch truncates the child at the depth cutoff: no
      // replies, and hasMore false so "true" below can only be the
      // existing node's.
      enqueueSubtree(
        rootUri,
        CommentsResponse(
          post: {},
          comments: [
            node(rootUri, replies: [node(childUri)]),
          ],
        ),
      );
      await provider.loadMoreReplies(rootUri);

      final child = provider.comments.single.replies!.single;
      expect(repliesOf(child), [grandchildUri]);
      expect(child.hasMore, isTrue);
      expect(child.repliesCursor, 'child-cursor');
    });

    test('T3 when BOTH reply lists are empty the fresh node is returned '
        'verbatim, dropping the existing repliesCursor', () async {
      stubInitialTree([
        node(rootUri, replies: [node(childUri, hasMore: true)]),
      ]);
      await provider.loadComments(refresh: true);

      // The child ends up with a cursor but still no loaded replies.
      await seedRepliesCursor(
        childUri,
        replies: const [],
        cursor: 'child-cursor',
      );
      expect(provider.comments.single.replies!.single.repliesCursor,
          'child-cursor');

      enqueueSubtree(
        rootUri,
        CommentsResponse(
          post: {},
          comments: [
            node(rootUri, replies: [node(childUri)]),
          ],
        ),
      );
      await provider.loadMoreReplies(rootUri);

      final child = provider.comments.single.replies!.single;
      // Same input shape as T2 except the existing branch was empty - and
      // the answer for the cursor is the opposite one.
      expect(child.repliesCursor, isNull);
      expect(child.hasMore, isFalse);
    });

    test('T4 children present in both are merged recursively so '
        'grandchildren survive', () async {
      stubInitialTree([
        node(
          rootUri,
          replies: [
            node(
              childUri,
              replies: [
                node(grandchildUri, replies: [node(greatGrandUri)]),
              ],
            ),
          ],
        ),
      ]);
      await provider.loadComments(refresh: true);

      // Fresh response truncates two levels down: the grandchild comes back
      // with no replies at all.
      enqueueSubtree(
        rootUri,
        CommentsResponse(
          post: {},
          comments: [
            node(
              rootUri,
              replies: [
                node(childUri, replies: [node(grandchildUri)]),
              ],
            ),
          ],
        ),
      );
      await provider.loadMoreReplies(rootUri);

      final grandchild =
          provider.comments.single.replies!.single.replies!.single;
      expect(grandchild.comment.uri, grandchildUri);
      expect(repliesOf(grandchild), [greatGrandUri]);
    });

    test('T5 fresh.hasMore true appends leftover existing children after '
        'the fresh ordering', () async {
      stubInitialTree([
        node(rootUri, replies: [node(replyAUri), node(replyBUri)]),
      ]);
      await provider.loadComments(refresh: true);

      // A sibling-truncated page: only reply B, but more are promised.
      enqueueSubtree(
        rootUri,
        CommentsResponse(
          post: {},
          comments: [
            node(rootUri, hasMore: true, replies: [node(replyBUri)]),
          ],
        ),
      );
      await provider.loadMoreReplies(rootUri);

      expect(repliesOf(provider.comments.single), [replyBUri, replyAUri]);
    });

    test('T6 fresh.hasMore false DROPS leftover existing children', () async {
      stubInitialTree([
        node(rootUri, replies: [node(replyAUri), node(replyBUri)]),
      ]);
      await provider.loadComments(refresh: true);

      // A complete listing: absence now means deletion.
      enqueueSubtree(
        rootUri,
        CommentsResponse(
          post: {},
          comments: [
            node(rootUri, replies: [node(replyBUri)]),
          ],
        ),
      );
      await provider.loadMoreReplies(rootUri);

      expect(repliesOf(provider.comments.single), [replyBUri]);
    });

    test('T7 on the recursive branch repliesCursor comes from existing but '
        'hasMore comes from fresh', () async {
      stubInitialTree([
        node(
          rootUri,
          replies: [
            node(childUri, hasMore: true, replies: [node(grandchildUri)]),
          ],
        ),
      ]);
      await provider.loadComments(refresh: true);

      await seedRepliesCursor(
        childUri,
        replies: [node(grandchildUri)],
        cursor: 'child-cursor',
      );
      expect(provider.comments.single.replies!.single.hasMore, isTrue);

      // This time the fresh child DOES carry replies, so the recursive
      // branch runs instead of the truncation branch of T2.
      enqueueSubtree(
        rootUri,
        CommentsResponse(
          post: {},
          comments: [
            node(
              rootUri,
              replies: [
                node(childUri, replies: [node(grandchildUri)]),
              ],
            ),
          ],
        ),
      );
      await provider.loadMoreReplies(rootUri);

      final child = provider.comments.single.replies!.single;
      // Cursor kept from the existing node...
      expect(child.repliesCursor, 'child-cursor');
      // ...but hasMore taken from fresh, discarding the existing true.
      // T2 answered the same question the other way round.
      expect(child.hasMore, isFalse);
    });
  });

  group('node replacement and lookup', () {
    test('T8 a node absent from the top-level tree leaves the list instance '
        'untouched while still returning the subtree', () async {
      stubInitialTree([node(rootUri)]);
      await provider.loadComments(refresh: true);
      final before = provider.comments;

      enqueueSubtree(
        orphanUri,
        CommentsResponse(
          post: {},
          comments: [
            node(orphanUri, replies: [node(replyAUri)]),
          ],
        ),
      );
      final result = await provider.loadMoreReplies(orphanUri);

      expect(result, isNotNull);
      expect(result!.comment.uri, orphanUri);
      expect(repliesOf(result), [replyAUri]);
      // Same list instance: nothing was merged, and callers detect that
      // through identity rather than a flag.
      expect(identical(before, provider.comments), isTrue);
    });

    test('T9 replacing a node with an instance already in the tree reports '
        'no change and hands the same subtree back', () {
      // Not reachable through loadMoreReplies - every subtree it builds is
      // a fresh copyWith, so the replacement is never an instance already
      // in the tree. This pins the model-level identity contract that the
      // list-level replace relies on to decide whether anything changed.
      final child = node(childUri);
      final root = node(rootUri, replies: [child, node(siblingUri)]);

      expect(identical(root.replaceDescendant(child), root), isTrue);
    });

    test('T10 replaces a nested descendant and preserves sibling branches '
        'by identity', () async {
      final sibling = node(siblingUri);
      final otherRoot = node(otherRootUri);
      stubInitialTree([
        node(rootUri, replies: [node(childUri), sibling]),
        otherRoot,
      ]);
      await provider.loadComments(refresh: true);

      enqueueSubtree(
        childUri,
        CommentsResponse(
          post: {},
          comments: [
            node(childUri, replies: [node(grandchildUri)]),
          ],
        ),
      );
      await provider.loadMoreReplies(childUri);

      final updatedRoot = provider.comments.first;
      expect(repliesOf(updatedRoot), [childUri, siblingUri]);
      expect(repliesOf(updatedRoot.replies!.first), [grandchildUri]);
      // Untouched branches keep reference identity.
      expect(identical(updatedRoot.replies![1], sibling), isTrue);
      expect(identical(provider.comments[1], otherRoot), isTrue);
    });

    test('T11 the node lookup reaches every depth of the tree', () async {
      stubInitialTree([
        node(
          rootUri,
          replies: [
            node(childUri, replies: [node(grandchildUri, hasMore: true)]),
          ],
        ),
      ]);
      await provider.loadComments(refresh: true);

      // Anchored three levels down: found, so it merges in place rather
      // than falling through to the "not in tree" path of T8.
      enqueueSubtree(
        grandchildUri,
        CommentsResponse(
          post: {},
          comments: [
            node(grandchildUri, replies: [node(greatGrandUri)]),
          ],
        ),
      );
      await provider.loadMoreReplies(grandchildUri);

      final grandchild =
          provider.comments.single.replies!.single.replies!.single;
      expect(repliesOf(grandchild), [greatGrandUri]);
    });
  });

  group('subtree construction from the response', () {
    test('T12 a cursor page appends new direct replies deduplicated by URI '
        'and takes hasMore/repliesCursor from the response cursor', () async {
      stubInitialTree([node(rootUri, hasMore: true)]);
      await provider.loadComments(refresh: true);

      enqueueSubtree(
        rootUri,
        CommentsResponse(
          post: {},
          comments: [
            node(rootUri, replies: [node(replyAUri)]),
          ],
          cursor: 'page-2',
        ),
      );
      enqueueSubtree(
        rootUri,
        CommentsResponse(
          post: {},
          comments: [
            // The server re-sends reply A alongside the new reply B.
            node(rootUri, replies: [node(replyAUri), node(replyBUri)]),
          ],
          cursor: 'page-3',
        ),
      );

      await provider.loadMoreReplies(rootUri);
      await provider.loadMoreReplies(rootUri);

      // The stored cursor was sent back, which is what selects this branch.
      verify(
        mockApiService.getComments(
          postUri: anyNamed('postUri'),
          sort: anyNamed('sort'),
          timeframe: anyNamed('timeframe'),
          depth: anyNamed('depth'),
          limit: anyNamed('limit'),
          cursor: 'page-2',
          parentRkey: argThat(equals('root'), named: 'parentRkey'),
        ),
      ).called(1);

      final merged = provider.comments.single;
      expect(repliesOf(merged), [replyAUri, replyBUri]);
      expect(merged.hasMore, isTrue);
      expect(merged.repliesCursor, 'page-3');
    });

    test('T13 a first page with an existing node merges, then takes '
        'hasMore/repliesCursor from the response cursor', () async {
      stubInitialTree([
        node(rootUri, replies: [node(replyAUri)]),
      ]);
      await provider.loadComments(refresh: true);

      enqueueSubtree(
        rootUri,
        CommentsResponse(
          post: {},
          comments: [
            node(rootUri, hasMore: true, replies: [node(replyBUri)]),
          ],
          cursor: 'page-2',
        ),
      );
      await provider.loadMoreReplies(rootUri);

      final merged = provider.comments.single;
      // Merged, not replaced: reply A survived as a leftover.
      expect(repliesOf(merged), [replyBUri, replyAUri]);
      expect(merged.hasMore, isTrue);
      expect(merged.repliesCursor, 'page-2');
    });

    test('T14 a first page with no existing node takes the fresh subtree '
        'plus the response cursor state', () async {
      stubInitialTree([node(rootUri)]);
      await provider.loadComments(refresh: true);

      enqueueSubtree(
        orphanUri,
        CommentsResponse(
          post: {},
          comments: [
            node(orphanUri, replies: [node(replyAUri)]),
          ],
          cursor: 'page-2',
        ),
      );
      final result = await provider.loadMoreReplies(orphanUri);

      expect(repliesOf(result), [replyAUri]);
      expect(result!.hasMore, isTrue);
      expect(result.repliesCursor, 'page-2');
    });
  });

  group('behaviour that must stay with the provider', () {
    test('an empty response clears the node pagination state and returns '
        'null, keeping the loaded replies', () async {
      stubInitialTree([node(rootUri, hasMore: true)]);
      await provider.loadComments(refresh: true);

      enqueueSubtree(
        rootUri,
        CommentsResponse(
          post: {},
          comments: [
            node(rootUri, replies: [node(replyAUri)]),
          ],
          cursor: 'page-2',
        ),
      );
      await provider.loadMoreReplies(rootUri);
      expect(provider.comments.single.repliesCursor, 'page-2');

      enqueueSubtree(rootUri, CommentsResponse(post: {}, comments: const []));
      final result = await provider.loadMoreReplies(rootUri);

      // Returning null is what drives the create-comment retry loop.
      expect(result, isNull);
      final cleared = provider.comments.single;
      expect(cleared.hasMore, isFalse);
      expect(cleared.repliesCursor, isNull);
      expect(repliesOf(cleared), [replyAUri]);
    });

    test('an empty response is a genuine no-op when the node has neither '
        'hasMore nor a repliesCursor', () async {
      stubInitialTree([node(rootUri)]);
      await provider.loadComments(refresh: true);
      final before = provider.comments;

      enqueueSubtree(rootUri, CommentsResponse(post: {}, comments: const []));
      final result = await provider.loadMoreReplies(rootUri);

      expect(result, isNull);
      expect(identical(before, provider.comments), isTrue);
    });

    test('an empty response is accepted without the anchoring check the '
        'non-empty path applies', () async {
      // The anchoring guard reads response.comments.first, so it can only
      // run after the empty-response branch has already returned. An empty
      // response therefore clears pagination state no matter which comment
      // the server thought it was answering about.
      stubInitialTree([node(rootUri, hasMore: true)]);
      await provider.loadComments(refresh: true);

      enqueueSubtree(rootUri, CommentsResponse(post: {}, comments: const []));
      expect(await provider.loadMoreReplies(rootUri), isNull);
      expect(provider.comments.single.hasMore, isFalse);

      // Contrast: a NON-empty response anchored elsewhere is discarded and
      // leaves the tree alone.
      stubInitialTree([node(rootUri, hasMore: true)]);
      await provider.loadComments(refresh: true);

      enqueueSubtree(
        rootUri,
        CommentsResponse(
          post: {},
          comments: [
            node(orphanUri, replies: [node(replyAUri)]),
          ],
        ),
      );
      expect(await provider.loadMoreReplies(rootUri), isNull);
      expect(provider.comments.single.hasMore, isTrue);
      expect(provider.comments.single.replies, isNull);
    });

    test('the request cursor is captured before the fetch while the '
        'existing node is looked up after it, so the two can disagree',
        () async {
      stubInitialTree([
        node(rootUri, replies: [node(childUri, hasMore: true)]),
      ]);
      await provider.loadComments(refresh: true);

      await seedRepliesCursor(
        childUri,
        replies: [node(replyAUri)],
        cursor: 'child-cursor',
      );

      // Start a cursor page for the child, then strand it mid-flight.
      final gate = Completer<CommentsResponse>();
      enqueueSubtreeFuture(childUri, gate.future);
      final pending = provider.loadMoreReplies(childUri);

      // The ancestor refetch delivers a complete listing without the child,
      // so the child is dropped from the tree while its page is in flight.
      enqueueSubtree(
        rootUri,
        CommentsResponse(
          post: {},
          comments: [
            node(rootUri, replies: [node(siblingUri)]),
          ],
        ),
      );
      await provider.loadMoreReplies(rootUri);
      expect(repliesOf(provider.comments.single), [siblingUri]);

      gate.complete(
        CommentsResponse(
          post: {},
          comments: [
            node(childUri, replies: [node(replyBUri)]),
          ],
        ),
      );
      final result = await pending;

      // The cursor WAS sent, so the request believed it was paginating...
      verify(
        mockApiService.getComments(
          postUri: anyNamed('postUri'),
          sort: anyNamed('sort'),
          timeframe: anyNamed('timeframe'),
          depth: anyNamed('depth'),
          limit: anyNamed('limit'),
          cursor: 'child-cursor',
          parentRkey: argThat(equals('child'), named: 'parentRkey'),
        ),
      ).called(1);

      // ...but by the time the response landed the node was gone, so the
      // first-page branch ran: reply A was NOT appended.
      expect(repliesOf(result), [replyBUri]);
      expect(provider.comments.single.replies!.single.comment.uri, siblingUri);
    });

    test('a subtree whose tree was refreshed mid-flight is discarded whole',
        () async {
      stubInitialTree([
        node(rootUri, replies: [node(childUri, hasMore: true)]),
      ]);
      await provider.loadComments(refresh: true);

      final gate = Completer<CommentsResponse>();
      enqueueSubtreeFuture(childUri, gate.future);
      final pending = provider.loadMoreReplies(childUri);

      await provider.refreshComments();

      gate.complete(
        CommentsResponse(
          post: {},
          comments: [
            node(childUri, replies: [node(replyAUri)]),
          ],
        ),
      );

      expect(await pending, isNull);
      // No state, no error, no merge: the tree is the refreshed one.
      expect(provider.comments.single.replies!.single.replies, isNull);
    });
  });

  group('tree membership drives the create-comment verification path', () {
    late MockCommentService mockCommentService;
    late CommentsProvider creatingProvider;

    const newCommentUri = '$commentBase/created';

    /// Counts the top-level thread fetches (the ones with no parentRkey).
    void expectTopLevelFetches(int count) {
      verify(
        mockApiService.getComments(
          postUri: anyNamed('postUri'),
          sort: anyNamed('sort'),
          timeframe: anyNamed('timeframe'),
          depth: anyNamed('depth'),
          limit: anyNamed('limit'),
          cursor: anyNamed('cursor'),
        ),
      ).called(count);
    }

    setUp(() {
      mockCommentService = MockCommentService();
      when(
        mockCommentService.createComment(
          rootUri: anyNamed('rootUri'),
          rootCid: anyNamed('rootCid'),
          parentUri: anyNamed('parentUri'),
          parentCid: anyNamed('parentCid'),
          content: anyNamed('content'),
          contentFacets: anyNamed('contentFacets'),
        ),
      ).thenAnswer(
        (_) async => const CreateCommentResponse(
          uri: newCommentUri,
          cid: 'cid-created',
        ),
      );

      creatingProvider = CommentsProvider(
        mockAuthProvider,
        postUri: testPostUri,
        postCid: testPostCid,
        apiService: mockApiService,
        commentService: mockCommentService,
        // No backoff: the verification loops run once and stop.
        indexingRetryDelays: const [],
      );
    });

    tearDown(() {
      creatingProvider.dispose();
    });

    test('a parent nested deep in the tree counts as present and takes the '
        'refresh path', () async {
      final parent = node(grandchildUri);
      stubInitialTree([
        node(
          rootUri,
          replies: [
            node(childUri, replies: [parent]),
          ],
        ),
      ]);
      await creatingProvider.loadComments(refresh: true);
      enqueueSubtree(
        grandchildUri,
        CommentsResponse(post: {}, comments: [node(grandchildUri)]),
      );

      await creatingProvider.createComment(
        content: 'hello',
        parentComment: parent,
      );

      // Initial load plus the refresh the present-parent path performs.
      expectTopLevelFetches(2);
    });

    test('a parent absent from the tree skips the refresh and verifies '
        'against the returned subtree instead', () async {
      stubInitialTree([node(rootUri)]);
      await creatingProvider.loadComments(refresh: true);
      enqueueSubtree(
        orphanUri,
        CommentsResponse(post: {}, comments: [node(orphanUri)]),
      );

      await creatingProvider.createComment(
        content: 'hello',
        parentComment: node(orphanUri),
      );

      // Only the initial load: no refresh, because a refresh could never
      // surface a reply below the depth cap.
      expectTopLevelFetches(1);
    });
  });
}
