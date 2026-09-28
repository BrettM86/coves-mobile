import 'dart:async';

import 'package:coves_flutter/models/coves_session.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/multi_feed_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/services/coves_auth_service.dart';
import 'package:coves_flutter/services/vote_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/test_mocks.dart';
import 'auth_provider_test.mocks.dart';

class _FakeClock {
  _FakeClock(this.value);

  DateTime value;

  DateTime call() => value;

  void advance(Duration duration) {
    value = value.add(duration);
  }
}

/// Auth state the tests drive directly: a DID change, or a restored-session
/// recovery that keeps the DID and bumps [restoredSessionRecoveryCount].
class _ControllableAuthProvider extends AuthProvider {
  _ControllableAuthProvider(this._did);

  String? _did;
  int _recoveryCount = 0;

  @override
  String? get did => _did;

  @override
  bool get isAuthenticated => _did != null;

  @override
  bool get isLoading => false;

  @override
  int get restoredSessionRecoveryCount => _recoveryCount;

  void setDid(String? did) {
    _did = did;
    notifyListeners();
  }

  void recoverRestoredSession() {
    _recoveryCount++;
    notifyListeners();
  }
}

class _UnusedVoteService implements VoteService {
  @override
  Future<VoteResponse> createVote({
    required String postUri,
    required String postCid,
    String direction = 'up',
  }) {
    throw StateError('Voting is not part of these tests');
  }
}

/// Every feed request gets its own completer, so a test decides when (and
/// in what order) each response lands.
class _Harness {
  _Harness(this.authProvider) {
    when(
      apiService.getDiscover(
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((_) {
      final request = Completer<TimelineResponse>();
      discoverRequests.add(request);
      return request.future;
    });
    when(
      apiService.getTimeline(
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((_) {
      final request = Completer<TimelineResponse>();
      timelineRequests.add(request);
      return request.future;
    });

    voteProvider = VoteProvider(
      voteService: _UnusedVoteService(),
      authProvider: authProvider,
    );
    provider = MultiFeedProvider(
      authProvider,
      apiService: apiService,
      voteProvider: voteProvider,
      clock: clock.call,
    );
  }

  final AuthProvider authProvider;
  final MockCovesApiService apiService = MockCovesApiService();
  final _FakeClock clock = _FakeClock(DateTime.utc(2026, 9, 27, 12));
  final List<Completer<TimelineResponse>> discoverRequests = [];
  final List<Completer<TimelineResponse>> timelineRequests = [];
  late final VoteProvider voteProvider;
  late final MultiFeedProvider provider;

  /// Completes the most recent Discover and For You requests.
  Future<void> answerLatest({
    required List<FeedViewPost> discover,
    required List<FeedViewPost> forYou,
  }) async {
    discoverRequests.last.complete(TimelineResponse(feed: discover));
    timelineRequests.last.complete(TimelineResponse(feed: forYou));
    await pumpEventQueue();
  }

  List<String> postIds(FeedType type) =>
      provider.getState(type).posts.map((post) => post.post.rkey).toList();

  void dispose() {
    provider.dispose();
    voteProvider.dispose();
  }
}

const _votedPostId = 'voted';
const _votedPostUri =
    'at://did:plc:author/social.coves.community.post/$_votedPostId';

FeedViewPost _feedPost(String id, {String? vote}) {
  return FeedViewPost(
    post: PostView(
      uri: 'at://did:plc:author/social.coves.community.post/$id',
      cid: 'cid-$id',
      rkey: id,
      author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
      community: CommunityRef(did: 'did:plc:community', name: 'testcove'),
      createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
      indexedAt: DateTime.parse('2026-01-01T00:00:00Z'),
      record: PostRecord(title: 'Post $id', content: 'Body $id'),
      stats: PostStats(upvotes: 1, downvotes: 0, score: 1, commentCount: 0),
      viewer: ViewerState(
        vote: vote,
        voteUri: vote == null
            ? null
            : 'at://did:plc:viewer/social.coves.feed.vote/$id',
      ),
    ),
  );
}

/// What OptionalAuth serves for a rejected token: the post, no viewer vote.
FeedViewPost _anonymousPost() => _feedPost(_votedPostId);

/// The same post read with a working token: the viewer's upvote is there.
FeedViewPost _authenticatedPost() => _feedPost(_votedPostId, vote: 'up');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('loadInitialFeeds reuse', () {
    test('a second call while page one is in flight makes no '
        'request', () async {
      final harness = _Harness(_ControllableAuthProvider('did:plc:viewer'));
      addTearDown(harness.dispose);

      harness.provider.loadInitialFeeds();
      expect(harness.discoverRequests, hasLength(1));
      expect(harness.timelineRequests, hasLength(1));

      harness.provider.loadInitialFeeds();
      expect(harness.discoverRequests, hasLength(1));
      expect(harness.timelineRequests, hasLength(1));

      await harness.answerLatest(
        discover: [_feedPost('discover')],
        forYou: [_feedPost('for-you')],
      );
      expect(harness.postIds(FeedType.discover), ['discover']);
      expect(harness.postIds(FeedType.forYou), ['for-you']);
    });

    test('reuses page one inside the reuse window and refetches '
        'after it', () async {
      final harness = _Harness(_ControllableAuthProvider('did:plc:viewer'));
      addTearDown(harness.dispose);

      harness.provider.loadInitialFeeds();
      await harness.answerLatest(
        discover: [_feedPost('discover')],
        forYou: [_feedPost('for-you')],
      );

      harness.clock.advance(
        MultiFeedProvider.initialLoadReuseWindow - const Duration(seconds: 1),
      );
      harness.provider.loadInitialFeeds();
      expect(harness.discoverRequests, hasLength(1));
      expect(harness.timelineRequests, hasLength(1));

      harness.clock.advance(const Duration(seconds: 1));
      harness.provider.loadInitialFeeds();
      expect(harness.discoverRequests, hasLength(2));
      expect(harness.timelineRequests, hasLength(2));
    });

    test('an anonymous viewer loads only Discover', () async {
      final harness = _Harness(_ControllableAuthProvider(null));
      addTearDown(harness.dispose);

      harness.provider.loadInitialFeeds();

      expect(harness.discoverRequests, hasLength(1));
      expect(harness.timelineRequests, isEmpty);
    });
  });

  group('loadInitialFeeds across a DID change', () {
    test(
      'refetches for the new DID and ignores the old in-flight load',
      () async {
        final authProvider = _ControllableAuthProvider('did:plc:first');
        final harness = _Harness(authProvider);
        addTearDown(harness.dispose);

        harness.provider.loadInitialFeeds();
        final firstDiscover = harness.discoverRequests.single;
        final firstForYou = harness.timelineRequests.single;

        authProvider.setDid('did:plc:second');
        harness.provider.loadInitialFeeds();
        expect(harness.discoverRequests, hasLength(2));
        expect(harness.timelineRequests, hasLength(2));

        firstDiscover.complete(
          TimelineResponse(feed: [_feedPost('first-discover')]),
        );
        firstForYou.complete(
          TimelineResponse(feed: [_feedPost('first-for-you')]),
        );
        await pumpEventQueue();
        expect(harness.postIds(FeedType.discover), isEmpty);
        expect(harness.postIds(FeedType.forYou), isEmpty);
        expect(harness.provider.getState(FeedType.discover).isLoading, isTrue);

        await harness.answerLatest(
          discover: [_feedPost('second-discover')],
          forYou: [_feedPost('second-for-you')],
        );
        expect(harness.postIds(FeedType.discover), ['second-discover']);
        expect(harness.postIds(FeedType.forYou), ['second-for-you']);
      },
    );

    test('a screen listener that runs before the provider does not reuse '
        'the previous DID\'s fresh page', () async {
      final authProvider = _ControllableAuthProvider('did:plc:first');
      late final _Harness harness;
      // Registered before the provider's own listener, so it sees the new
      // DID first.
      authProvider.addListener(() => harness.provider.loadInitialFeeds());
      harness = _Harness(authProvider);
      addTearDown(harness.dispose);

      harness.provider.loadInitialFeeds();
      await harness.answerLatest(
        discover: [_feedPost('first-discover')],
        forYou: [_feedPost('first-for-you')],
      );

      authProvider.setDid('did:plc:second');

      expect(harness.discoverRequests, hasLength(2));
      expect(harness.timelineRequests, hasLength(2));
      await harness.answerLatest(
        discover: [_feedPost('second-discover')],
        forYou: [_feedPost('second-for-you')],
      );
      expect(harness.postIds(FeedType.discover), ['second-discover']);
      expect(harness.postIds(FeedType.forYou), ['second-for-you']);
    });
  });

  group('restored-session recovery', () {
    test('discards the restored page one still in flight and refetches it '
        'with the recovered token', () async {
      final authProvider = _ControllableAuthProvider('did:plc:viewer');
      final harness = _Harness(authProvider);
      addTearDown(harness.dispose);

      // Bootstrap prefetch with the restored (rejected) token.
      harness.provider.loadInitialFeeds();
      final staleDiscover = harness.discoverRequests.single;
      final staleForYou = harness.timelineRequests.single;

      authProvider.recoverRestoredSession();

      expect(harness.discoverRequests, hasLength(2));
      expect(harness.timelineRequests, hasLength(2));

      // The anonymous responses land after the recovery: not published.
      staleDiscover.complete(TimelineResponse(feed: [_anonymousPost()]));
      staleForYou.complete(TimelineResponse(feed: [_anonymousPost()]));
      await pumpEventQueue();
      expect(harness.postIds(FeedType.discover), isEmpty);
      expect(harness.provider.getState(FeedType.discover).isLoading, isTrue);
      expect(harness.provider.getState(FeedType.forYou).isLoading, isTrue);

      await harness.answerLatest(
        discover: [_authenticatedPost()],
        forYou: [_authenticatedPost()],
      );
      expect(harness.postIds(FeedType.discover), [_votedPostId]);
      expect(harness.postIds(FeedType.forYou), [_votedPostId]);
      expect(harness.voteProvider.isLiked(_votedPostUri), isTrue);

      // The feed screen mounting afterwards reuses the authenticated page.
      harness.provider.loadInitialFeeds();
      expect(harness.discoverRequests, hasLength(2));
      expect(harness.timelineRequests, hasLength(2));
    });

    test('refetches a restored page one that already landed, inside the '
        'reuse window, and re-seeds the viewer vote', () async {
      final authProvider = _ControllableAuthProvider('did:plc:viewer');
      final harness = _Harness(authProvider);
      addTearDown(harness.dispose);

      harness.provider.loadInitialFeeds();
      await harness.answerLatest(
        discover: [_anonymousPost()],
        forYou: [_anonymousPost()],
      );
      expect(harness.voteProvider.isLiked(_votedPostUri), isFalse);

      harness.clock.advance(const Duration(seconds: 1));
      authProvider.recoverRestoredSession();

      expect(harness.discoverRequests, hasLength(2));
      expect(harness.timelineRequests, hasLength(2));
      expect(
        harness.provider.getState(FeedType.discover).lastRefreshTime,
        isNull,
        reason: 'the anonymous page must not count as fresh',
      );

      // The feed screen mounting now must not start a second refetch.
      harness.provider.loadInitialFeeds();
      expect(harness.discoverRequests, hasLength(2));
      expect(harness.timelineRequests, hasLength(2));

      await harness.answerLatest(
        discover: [_authenticatedPost()],
        forYou: [_authenticatedPost()],
      );
      expect(harness.voteProvider.isLiked(_votedPostUri), isTrue);
    });

    test('a screen listener that runs before the provider causes no '
        'second refetch', () async {
      final authProvider = _ControllableAuthProvider('did:plc:viewer');
      late final _Harness harness;
      authProvider.addListener(() => harness.provider.loadInitialFeeds());
      harness = _Harness(authProvider);
      addTearDown(harness.dispose);

      harness.provider.loadInitialFeeds();
      await harness.answerLatest(
        discover: [_anonymousPost()],
        forYou: [_anonymousPost()],
      );

      authProvider.recoverRestoredSession();

      expect(harness.discoverRequests, hasLength(2));
      expect(harness.timelineRequests, hasLength(2));
      await harness.answerLatest(
        discover: [_authenticatedPost()],
        forYou: [_authenticatedPost()],
      );
      expect(harness.voteProvider.isLiked(_votedPostUri), isTrue);
    });

    test('does not start feed loads that were never requested', () {
      // A gate screen is still up: startup skipped the prefetch.
      final authProvider = _ControllableAuthProvider('did:plc:viewer');
      final harness = _Harness(authProvider);
      addTearDown(harness.dispose);

      authProvider.recoverRestoredSession();

      expect(harness.discoverRequests, isEmpty);
      expect(harness.timelineRequests, isEmpty);
    });
  });

  group('restored-session recovery driven by a timeline 401', () {
    const restoredSession = CovesSession(
      token: 'restored_sealed_token',
      did: 'did:plc:viewer',
      sessionId: 'session-viewer',
    );
    const refreshedSession = CovesSession(
      token: 'refreshed_sealed_token',
      did: 'did:plc:viewer',
      sessionId: 'session-viewer',
    );

    for (final discoverLandsBeforeRecovery in [true, false]) {
      test('drops the anonymous Discover page that lands '
          '${discoverLandsBeforeRecovery ? 'before' : 'after'} the '
          'refresh, while the startup probe is still pending', () async {
        final authService = MockCovesAuthService();
        final validationGate = Completer<SessionValidationResult>();
        final refreshGate = Completer<CovesSession>();
        when(authService.initialize()).thenAnswer((_) async {});
        when(
          authService.restoreSession(),
        ).thenAnswer((_) async => restoredSession);
        when(
          authService.validateSession(),
        ).thenAnswer((_) => validationGate.future);
        when(authService.refreshToken()).thenAnswer((_) => refreshGate.future);

        final authProvider = AuthProvider(authService: authService);
        await authProvider.initialize();
        final harness = _Harness(authProvider);
        addTearDown(harness.dispose);

        // Bootstrap prefetch with the restored (rejected) token.
        harness.provider.loadInitialFeeds();
        final staleDiscover = harness.discoverRequests.single;
        final staleForYou = harness.timelineRequests.single;

        // The timeline 401 sends the auth interceptor to refresh.
        final interceptorRefresh = authProvider.refreshToken();

        if (discoverLandsBeforeRecovery) {
          staleDiscover.complete(TimelineResponse(feed: [_anonymousPost()]));
          await pumpEventQueue();
          expect(harness.postIds(FeedType.discover), [_votedPostId]);
        }

        refreshGate.complete(refreshedSession);
        expect(await interceptorRefresh, isTrue);
        await pumpEventQueue();

        expect(harness.discoverRequests, hasLength(2));
        expect(harness.timelineRequests, hasLength(2));

        if (!discoverLandsBeforeRecovery) {
          staleDiscover.complete(TimelineResponse(feed: [_anonymousPost()]));
        }
        staleForYou.complete(TimelineResponse(feed: [_anonymousPost()]));
        await pumpEventQueue();
        expect(harness.postIds(FeedType.discover), isEmpty);
        expect(harness.provider.getState(FeedType.discover).isLoading, isTrue);

        // The probe's rejection arrives after the token was already
        // replaced: no second refresh, no second refetch.
        validationGate.complete(SessionValidationResult.invalid);
        await pumpEventQueue();
        verify(authService.refreshToken()).called(1);
        expect(harness.discoverRequests, hasLength(2));
        expect(harness.timelineRequests, hasLength(2));

        await harness.answerLatest(
          discover: [_authenticatedPost()],
          forYou: [_authenticatedPost()],
        );
        expect(harness.postIds(FeedType.discover), [_votedPostId]);
        expect(harness.voteProvider.isLiked(_votedPostUri), isTrue);
      });
    }
  });
}
