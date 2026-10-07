import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/providers/comments_provider.dart';
import 'package:coves_flutter/services/comments_provider_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/test_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const postUri = 'at://did:plc:author/social.coves.community.post/post';
  const postCid = 'post-cid';

  late FakeAuthProvider auth;
  late FakeVoteProvider votes;
  late MockCovesApiService api;
  late CommentsProviderCache cache;

  /// Post URIs of every getComments request, in order.
  late List<String> commentRequests;

  setUp(() {
    auth = FakeAuthProvider();
    votes = FakeVoteProvider(auth);
    api = MockCovesApiService();
    commentRequests = [];
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
    ).thenAnswer((invocation) async {
      commentRequests.add(invocation.namedArguments[#postUri] as String);
      return CommentsResponse(post: null, comments: []);
    });
    cache = CommentsProviderCache(
      authProvider: auth,
      voteProvider: votes,
      commentService: MockCommentService(),
      apiService: api,
    );
  });

  tearDown(() {
    cache.dispose();
    votes.dispose();
  });

  group('CommentsProviderCache auth changes', () {
    test('signing in after browsing signed out drops and disposes the '
        'cached providers', () async {
      final signedOutProvider = cache.acquireProvider(
        postUri: postUri,
        postCid: postCid,
      );
      cache.releaseProvider(postUri);
      expect(cache.size, 1);
      expect(cache.peekProvider(postUri), same(signedOutProvider));

      auth.setSignedInDid('did:plc:alice');

      expect(
        cache.size,
        0,
        reason:
            'a thread cached while signed out has no viewer state, so '
            'signing in must drop it',
      );
      expect(cache.peekProvider(postUri), isNull);

      final signedInProvider = cache.acquireProvider(
        postUri: postUri,
        postCid: postCid,
      );
      expect(signedInProvider, isNot(same(signedOutProvider)));

      // Control: a live provider for the same post does issue a request.
      await signedInProvider.loadComments(refresh: true);
      expect(commentRequests, [postUri]);

      // A disposed provider's loadComments returns without a request.
      await signedOutProvider.loadComments(refresh: true);
      expect(commentRequests, [
        postUri,
      ], reason: 'the provider cached while signed out must be disposed');
    });

    test('switching accounts drops and disposes the cached providers, '
        'including pinned ones', () async {
      auth.setSignedInDid('did:plc:alice');
      // Built after sign-in, so this cache starts from a signed-in identity.
      final signedInCache = CommentsProviderCache(
        authProvider: auth,
        voteProvider: votes,
        commentService: MockCommentService(),
        apiService: api,
      );
      addTearDown(signedInCache.dispose);

      // Acquired and not released, as while a PostDetailScreen holds it.
      final aliceProvider = signedInCache.acquireProvider(
        postUri: postUri,
        postCid: postCid,
      );
      expect(signedInCache.size, 1);
      expect(signedInCache.peekProvider(postUri), same(aliceProvider));

      auth.setSignedInDid('did:plc:bob');
      expect(auth.isAuthenticated, isTrue);

      expect(
        signedInCache.size,
        0,
        reason:
            "alice's thread carries alice's viewer state, so switching to "
            'bob must drop it even while it is pinned',
      );
      expect(signedInCache.peekProvider(postUri), isNull);

      final bobProvider = signedInCache.acquireProvider(
        postUri: postUri,
        postCid: postCid,
      );
      expect(bobProvider, isNot(same(aliceProvider)));

      // Control: a live provider for the same post does issue a request.
      await bobProvider.loadComments(refresh: true);
      expect(commentRequests, [postUri]);

      // A disposed provider's loadComments returns without a request.
      await aliceProvider.loadComments(refresh: true);
      expect(commentRequests, [
        postUri,
      ], reason: 'the provider cached for alice must be disposed');
    });

    test('signing out drops and disposes the cached providers, including '
        'pinned ones', () async {
      auth.setSignedInDid('did:plc:alice');
      // Built after sign-in, so this cache starts from a signed-in identity.
      final signedInCache = CommentsProviderCache(
        authProvider: auth,
        voteProvider: votes,
        commentService: MockCommentService(),
        apiService: api,
      );
      addTearDown(signedInCache.dispose);

      // Acquired and not released, as while a PostDetailScreen holds it.
      final aliceProvider = signedInCache.acquireProvider(
        postUri: postUri,
        postCid: postCid,
      );
      expect(signedInCache.size, 1);
      expect(signedInCache.peekProvider(postUri), same(aliceProvider));

      auth.setSignedInDid(null);
      expect(auth.isAuthenticated, isFalse);

      expect(
        signedInCache.size,
        0,
        reason:
            "alice's thread carries alice's viewer state, so signing out "
            'must drop it even while it is pinned',
      );
      expect(signedInCache.peekProvider(postUri), isNull);

      final signedOutProvider = signedInCache.acquireProvider(
        postUri: postUri,
        postCid: postCid,
      );
      expect(signedOutProvider, isNot(same(aliceProvider)));

      // Control: a live provider for the same post does issue a request.
      await signedOutProvider.loadComments(refresh: true);
      expect(commentRequests, [postUri]);

      // A disposed provider's loadComments returns without a request.
      await aliceProvider.loadComments(refresh: true);
      expect(commentRequests, [
        postUri,
      ], reason: 'the provider cached for alice must be disposed');
    });
  });

  group('CommentsProviderCache notifications that keep the DID', () {
    test('a notification while signed out keeps the cached provider', () async {
      final signedOutProvider = cache.acquireProvider(
        postUri: postUri,
        postCid: postCid,
      );
      expect(cache.size, 1);

      // The DID stays null, as when a signed-out auth state re-notifies.
      auth.notifyWithoutChange();
      expect(auth.did, isNull);

      expect(
        cache.size,
        1,
        reason: 'the viewer did not change, so the cache must be kept',
      );
      expect(cache.peekProvider(postUri), same(signedOutProvider));

      // Still live: a disposed provider would issue no request.
      await signedOutProvider.loadComments(refresh: true);
      expect(commentRequests, [
        postUri,
      ], reason: 'the kept provider must not have been disposed');
    });

    test('a notification that keeps the signed-in DID, such as a token '
        'refresh, keeps the cached provider', () async {
      auth.setSignedInDid('did:plc:alice');
      // Built after sign-in, so this cache starts from a signed-in identity.
      final signedInCache = CommentsProviderCache(
        authProvider: auth,
        voteProvider: votes,
        commentService: MockCommentService(),
        apiService: api,
      );
      addTearDown(signedInCache.dispose);

      // Acquired and not released, as while a PostDetailScreen holds it.
      final aliceProvider = signedInCache.acquireProvider(
        postUri: postUri,
        postCid: postCid,
      );
      expect(signedInCache.size, 1);

      auth.notifyWithoutChange();
      expect(auth.did, 'did:plc:alice');

      expect(
        signedInCache.size,
        1,
        reason:
            'a token refresh keeps the same account, so disposing the '
            'thread would break the screen still holding it',
      );
      expect(signedInCache.peekProvider(postUri), same(aliceProvider));

      // Still live: a disposed provider would issue no request.
      await aliceProvider.loadComments(refresh: true);
      expect(commentRequests, [
        postUri,
      ], reason: 'the kept provider must not have been disposed');
    });

    test('after an account switch, a notification that keeps the new DID '
        'keeps the provider cached for the new account', () async {
      auth.setSignedInDid('did:plc:alice');
      // Built after sign-in, so this cache starts from a signed-in identity.
      final signedInCache = CommentsProviderCache(
        authProvider: auth,
        voteProvider: votes,
        commentService: MockCommentService(),
        apiService: api,
      );
      addTearDown(signedInCache.dispose);

      signedInCache.acquireProvider(postUri: postUri, postCid: postCid);
      expect(signedInCache.size, 1);

      auth.setSignedInDid('did:plc:bob');
      expect(
        signedInCache.size,
        0,
        reason: 'precondition: the account switch clears the cache',
      );

      final bobProvider = signedInCache.acquireProvider(
        postUri: postUri,
        postCid: postCid,
      );
      expect(signedInCache.size, 1);

      auth.notifyWithoutChange();
      expect(auth.did, 'did:plc:bob');

      expect(
        signedInCache.size,
        1,
        reason:
            'the cache must remember bob as the current account, so a '
            'notification that keeps bob signed in is not a change',
      );
      expect(signedInCache.peekProvider(postUri), same(bobProvider));

      // Still live: a disposed provider would issue no request.
      await bobProvider.loadComments(refresh: true);
      expect(commentRequests, [
        postUri,
      ], reason: 'the kept provider must not have been disposed');
    });
  });

  group('CommentsProviderCache acquire from an auth listener that runs '
      "before the cache's", () {
    /// Builds a cache whose auth listener is registered after one that
    /// acquires the post from it on every notification, as a screen that
    /// re-acquires its provider when the account changes can. Returns the
    /// cache and the providers that listener acquired, in order.
    (CommentsProviderCache, List<CommentsProvider>) cacheAfterReacquirer() {
      late final CommentsProviderCache laterCache;
      final reacquired = <CommentsProvider>[];
      void reacquire() {
        reacquired.add(
          laterCache.acquireProvider(postUri: postUri, postCid: postCid),
        );
      }

      auth.addListener(reacquire);
      addTearDown(() => auth.removeListener(reacquire));
      laterCache = CommentsProviderCache(
        authProvider: auth,
        voteProvider: votes,
        commentService: MockCommentService(),
        apiService: api,
      );
      addTearDown(laterCache.dispose);
      return (laterCache, reacquired);
    }

    test('signing in returns a fresh provider that stays live and cached, '
        'and disposes the signed-out one', () async {
      final (laterCache, reacquired) = cacheAfterReacquirer();
      final signedOutProvider = laterCache.acquireProvider(
        postUri: postUri,
        postCid: postCid,
      );

      auth.setSignedInDid('did:plc:alice');

      expect(reacquired, hasLength(1));
      final signedInProvider = reacquired.single;
      expect(
        signedInProvider,
        isNot(same(signedOutProvider)),
        reason:
            'a provider acquired after the DID changed must be fresh for '
            'the new account, even before the cache has seen the change',
      );
      expect(
        laterCache.peekProvider(postUri),
        same(signedInProvider),
        reason: "the fresh provider must be the cache's live entry",
      );

      // A disposed provider's loadComments returns without a request.
      await signedInProvider.loadComments(refresh: true);
      expect(commentRequests, [
        postUri,
      ], reason: "the cache's own listener must not dispose the fresh one");
      await signedOutProvider.loadComments(refresh: true);
      expect(commentRequests, [
        postUri,
      ], reason: 'the provider cached while signed out must be disposed');
    });

    test('switching accounts returns a fresh provider that stays live and '
        'cached, and disposes the previous account\'s', () async {
      auth.setSignedInDid('did:plc:alice');
      // Built after sign-in, so this cache starts from a signed-in identity.
      final (laterCache, reacquired) = cacheAfterReacquirer();
      final aliceProvider = laterCache.acquireProvider(
        postUri: postUri,
        postCid: postCid,
      );

      auth.setSignedInDid('did:plc:bob');

      expect(reacquired, hasLength(1));
      final bobProvider = reacquired.single;
      expect(
        bobProvider,
        isNot(same(aliceProvider)),
        reason:
            'a provider acquired after the DID changed must be fresh for '
            'the new account, even before the cache has seen the change',
      );
      expect(
        laterCache.peekProvider(postUri),
        same(bobProvider),
        reason: "the fresh provider must be the cache's live entry",
      );

      // A disposed provider's loadComments returns without a request.
      await bobProvider.loadComments(refresh: true);
      expect(commentRequests, [
        postUri,
      ], reason: "the cache's own listener must not dispose the fresh one");
      await aliceProvider.loadComments(refresh: true);
      expect(commentRequests, [
        postUri,
      ], reason: 'the provider cached for alice must be disposed');
    });

    test('a notification that keeps the DID returns the cached provider, '
        'still live', () async {
      auth.setSignedInDid('did:plc:alice');
      final (laterCache, reacquired) = cacheAfterReacquirer();
      final aliceProvider = laterCache.acquireProvider(
        postUri: postUri,
        postCid: postCid,
      );

      auth.notifyWithoutChange();

      expect(reacquired, hasLength(1));
      expect(reacquired.single, same(aliceProvider));
      expect(laterCache.peekProvider(postUri), same(aliceProvider));

      // Still live: a disposed provider would issue no request.
      await aliceProvider.loadComments(refresh: true);
      expect(commentRequests, [
        postUri,
      ], reason: 'the kept provider must not have been disposed');
    });
  });
}
