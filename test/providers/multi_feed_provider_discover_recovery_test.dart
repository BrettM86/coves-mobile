import 'dart:async';

import 'package:coves_flutter/models/feed_state.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/multi_feed_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/vote_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/test_mocks.dart';

typedef _FeedAnswer = Future<TimelineResponse> Function();
typedef _DisposedMutation = FutureOr<void> Function(MultiFeedProvider provider);

class _FeedRequest {
  const _FeedRequest({required this.sort, this.timeframe, this.cursor});

  final String sort;
  final String? timeframe;
  final String? cursor;
}

class _FakeClock {
  _FakeClock(this.value);

  DateTime value;

  DateTime call() => value;

  void advance(Duration duration) {
    value = value.add(duration);
  }
}

class _MutableAuthProvider extends AuthProvider {
  _MutableAuthProvider(this._did);

  String? _did;

  @override
  String? get did => _did;

  @override
  bool get isAuthenticated => _did != null;

  @override
  bool get isLoading => false;

  void setDid(String? did) {
    _did = did;
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

class _Harness {
  _Harness({DateTime Function()? clock, AuthProvider? authProvider}) {
    this.authProvider = authProvider ?? MockAuthProvider();
    if (this.authProvider case final MockAuthProvider mockAuthProvider) {
      when(mockAuthProvider.isAuthenticated).thenReturn(true);
      when(mockAuthProvider.did).thenReturn('did:plc:viewer');
    }

    when(
      apiService.getDiscover(
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((invocation) {
      discoverRequests.add(
        _FeedRequest(
          sort: invocation.namedArguments[#sort] as String,
          timeframe: invocation.namedArguments[#timeframe] as String?,
          cursor: invocation.namedArguments[#cursor] as String?,
        ),
      );
      if (_discoverAnswers.isEmpty) {
        throw StateError('Unexpected Discover request');
      }
      return _discoverAnswers.removeAt(0)();
    });

    when(
      apiService.getTimeline(
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((invocation) {
      timelineRequests.add(
        _FeedRequest(
          sort: invocation.namedArguments[#sort] as String,
          timeframe: invocation.namedArguments[#timeframe] as String?,
          cursor: invocation.namedArguments[#cursor] as String?,
        ),
      );
      if (_timelineAnswers.isEmpty) {
        throw StateError('Unexpected Timeline request');
      }
      return _timelineAnswers.removeAt(0)();
    });

    voteProvider = VoteProvider(
      voteService: _UnusedVoteService(),
      authProvider: this.authProvider,
    );
    provider = MultiFeedProvider(
      this.authProvider,
      apiService: apiService,
      voteProvider: voteProvider,
      clock: clock,
    );
  }

  late final AuthProvider authProvider;
  final MockCovesApiService apiService = MockCovesApiService();
  final List<_FeedAnswer> _discoverAnswers = [];
  final List<_FeedAnswer> _timelineAnswers = [];
  final List<_FeedRequest> discoverRequests = [];
  final List<_FeedRequest> timelineRequests = [];
  late final VoteProvider voteProvider;
  late final MultiFeedProvider provider;

  void discoverPage(TimelineResponse response) {
    _discoverAnswers.add(() async => response);
  }

  void discoverError(Exception error, {bool synchronous = false}) {
    _discoverAnswers.add(
      synchronous ? () => throw error : () => Future.error(error),
    );
  }

  void discoverFuture(Future<TimelineResponse> future) {
    _discoverAnswers.add(() => future);
  }

  void timelinePage(TimelineResponse response) {
    _timelineAnswers.add(() async => response);
  }

  void timelineError(Exception error) {
    _timelineAnswers.add(() => Future.error(error));
  }

  void timelineFuture(Future<TimelineResponse> future) {
    _timelineAnswers.add(() => future);
  }

  Future<void> seedDiscover({
    List<FeedViewPost>? posts,
    String? cursor = 'stale-cursor',
  }) async {
    discoverPage(
      TimelineResponse(feed: posts ?? [feedPost('stale')], cursor: cursor),
    );
    await provider.loadFeed(FeedType.discover, refresh: true);
  }

  Future<void> seedForYou({
    List<FeedViewPost>? posts,
    String? cursor = 'timeline-cursor',
  }) async {
    timelinePage(
      TimelineResponse(feed: posts ?? [feedPost('timeline')], cursor: cursor),
    );
    await provider.loadFeed(FeedType.forYou, refresh: true);
  }

  void dispose() {
    provider.dispose();
    voteProvider.dispose();
  }
}

FeedViewPost feedPost(String id, {String? vote, String? voteUri}) {
  final uri = 'at://did:plc:author/social.coves.community.post/$id';
  return FeedViewPost(
    post: PostView(
      uri: uri,
      cid: 'cid-$id',
      rkey: id,
      author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
      community: CommunityRef(did: 'did:plc:community', name: 'testcove'),
      createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
      indexedAt: DateTime.parse('2026-01-01T00:00:00Z'),
      record: PostRecord(title: 'Post $id', content: 'Body $id'),
      stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
      viewer: ViewerState(vote: vote, voteUri: voteUri),
    ),
  );
}

ApiException invalidCursor() => ApiException(
  'That cursor is no longer valid',
  statusCode: 400,
  errorCode: 'InvalidCursor',
);

ApiException discoverUnavailable(int? retryAfterSeconds) => ApiException(
  'Discover is temporarily unavailable',
  statusCode: 503,
  errorCode: 'DiscoverUnavailable',
  retryAfterSeconds: retryAfterSeconds,
);

List<String?> _cursors(List<_FeedRequest> requests) {
  return requests.map((request) => request.cursor).toList();
}

List<String> postIds(MultiFeedProvider provider) {
  return provider
      .getState(FeedType.discover)
      .posts
      .map((post) => post.post.rkey)
      .toList();
}

void expectStateMatches(FeedState actual, FeedState expected) {
  expect(actual.posts, orderedEquals(expected.posts));
  expect(actual.cursor, expected.cursor);
  expect(actual.hasMore, expected.hasMore);
  expect(actual.isLoading, expected.isLoading);
  expect(actual.isLoadingMore, expected.isLoadingMore);
  expect(actual.error, expected.error);
  expect(actual.loadMoreError, expected.loadMoreError);
  expect(actual.scrollPosition, expected.scrollPosition);
  expect(actual.lastRefreshTime, expected.lastRefreshTime);
}

void expectInitialState(MultiFeedProvider provider, FeedType type) {
  expectStateMatches(provider.getState(type), FeedState.initial());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Discover Hot InvalidCursor recovery', () {
    test('retries page one exactly once and replaces the stale page', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await harness.seedDiscover(posts: [feedPost('stale'), feedPost('kept')]);

      harness
        ..discoverError(invalidCursor())
        ..discoverPage(
          TimelineResponse(
            feed: [
              feedPost(
                'kept',
                vote: 'up',
                voteUri: 'at://did:plc:viewer/social.coves.feed.vote/v1',
              ),
              feedPost('fresh'),
              feedPost('fresh'),
            ],
            cursor: 'fresh-cursor',
          ),
        );

      await harness.provider.loadMore(FeedType.discover);

      expect(_cursors(harness.discoverRequests), [null, 'stale-cursor', null]);
      expect(postIds(harness.provider), ['kept', 'fresh']);
      final state = harness.provider.getState(FeedType.discover);
      expect(state.cursor, 'fresh-cursor');
      expect(state.hasMore, isTrue);
      expect(state.error, isNull);
      expect(state.loadMoreError, isNull);
      expect(
        harness.voteProvider.isLiked(
          'at://did:plc:author/social.coves.community.post/kept',
        ),
        isTrue,
        reason: 'the replacement response must still hydrate viewer state',
      );

      harness.discoverPage(
        TimelineResponse(feed: [feedPost('next')], cursor: 'after-next'),
      );
      await harness.provider.loadMore(FeedType.discover);

      expect(harness.discoverRequests.last.cursor, 'fresh-cursor');
      expect(postIds(harness.provider), ['kept', 'fresh', 'next']);
      expect(harness.provider.getState(FeedType.discover).cursor, 'after-next');
    });

    for (final recoveryFailure in <(String, Exception)>[
      ('ordinary failure', ApiException('page one failed', statusCode: 500)),
      ('second InvalidCursor', invalidCursor()),
    ]) {
      test('${recoveryFailure.$1} does not recurse and '
          'manual retry targets page one', () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        await harness.seedDiscover();
        harness
          ..discoverError(invalidCursor())
          ..discoverError(recoveryFailure.$2);

        await harness.provider.loadMore(FeedType.discover);

        expect(_cursors(harness.discoverRequests), [
          null,
          'stale-cursor',
          null,
        ], reason: 'the page-one recovery must not recursively recover');
        expect(postIds(harness.provider), ['stale']);
        final failedState = harness.provider.getState(FeedType.discover);
        expect(failedState.cursor, isNull);
        expect(failedState.hasMore, isTrue);
        expect(failedState.error, isNull);
        expect(failedState.loadMoreError, isNotNull);

        harness.discoverPage(
          TimelineResponse(feed: [feedPost('retried')], cursor: 'next'),
        );
        await harness.provider.retryLoadMore(FeedType.discover);

        expect(harness.discoverRequests.last.cursor, isNull);
        expect(postIds(harness.provider), ['retried']);
        expect(harness.provider.getState(FeedType.discover).cursor, 'next');
        expect(
          harness.provider.getState(FeedType.discover).loadMoreError,
          isNull,
        );
      });
    }
  });

  group('load-more errors require explicit retry', () {
    test(
      'ordinary Discover failure blocks scroll until retry succeeds',
      () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        await harness.seedDiscover();
        harness.discoverError(ApiException('offline'));

        await harness.provider.loadMore(FeedType.discover);

        expect(
          harness.provider.getState(FeedType.discover).loadMoreError,
          'offline',
        );
        harness
          ..discoverPage(
            TimelineResponse(
              feed: [feedPost('retried')],
              cursor: 'retry-cursor',
            ),
          )
          ..discoverPage(TimelineResponse(feed: [feedPost('later')]));

        await harness.provider.loadMore(FeedType.discover);
        await harness.provider.loadMore(FeedType.discover);

        expect(_cursors(harness.discoverRequests), [
          null,
          'stale-cursor',
        ], reason: 'scroll must not retry while its footer error is visible');
        expect(
          harness.provider.getState(FeedType.discover).loadMoreError,
          'offline',
        );

        await harness.provider.retryLoadMore(FeedType.discover);

        expect(harness.discoverRequests.last.cursor, 'stale-cursor');
        expect(postIds(harness.provider), ['stale', 'retried']);
        expect(
          harness.provider.getState(FeedType.discover).loadMoreError,
          isNull,
        );

        await harness.provider.loadMore(FeedType.discover);

        expect(harness.discoverRequests.last.cursor, 'retry-cursor');
        expect(postIds(harness.provider), ['stale', 'retried', 'later']);
      },
    );

    test(
      'ordinary For You failure blocks scroll until explicit retry',
      () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        harness.timelinePage(
          TimelineResponse(
            feed: [feedPost('timeline')],
            cursor: 'timeline-next',
          ),
        );
        await harness.provider.loadFeed(FeedType.forYou, refresh: true);
        harness.timelineError(ApiException('offline'));

        await harness.provider.loadMore(FeedType.forYou);

        expect(
          harness.provider.getState(FeedType.forYou).loadMoreError,
          'offline',
        );
        harness
          ..timelinePage(
            TimelineResponse(
              feed: [feedPost('timeline-retried')],
              cursor: 'timeline-after-retry',
            ),
          )
          ..timelinePage(
            TimelineResponse(
              feed: [feedPost('unexpected-automatic')],
              cursor: 'unexpected-cursor',
            ),
          );

        await harness.provider.loadMore(FeedType.forYou);
        await harness.provider.loadMore(FeedType.forYou);

        expect(_cursors(harness.timelineRequests), [
          null,
          'timeline-next',
        ], reason: 'scroll must not retry while its footer error is visible');

        await harness.provider.retryLoadMore(FeedType.forYou);

        expect(harness.timelineRequests.last.cursor, 'timeline-next');
        final state = harness.provider.getState(FeedType.forYou);
        expect(state.posts.map((post) => post.post.rkey), [
          'timeline',
          'timeline-retried',
        ]);
        expect(state.cursor, 'timeline-after-retry');
        expect(state.loadMoreError, isNull);
      },
    );

    test(
      'failed InvalidCursor recovery blocks scroll and retries page one',
      () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        await harness.seedDiscover();
        harness
          ..discoverError(invalidCursor())
          ..discoverError(ApiException('page one failed'));

        await harness.provider.loadMore(FeedType.discover);

        expect(_cursors(harness.discoverRequests), [
          null,
          'stale-cursor',
          null,
        ]);
        expect(postIds(harness.provider), ['stale']);
        expect(
          harness.provider.getState(FeedType.discover).loadMoreError,
          'page one failed',
        );
        harness
          ..discoverPage(
            TimelineResponse(
              feed: [feedPost('retried-page-one')],
              cursor: 'new-cursor',
            ),
          )
          ..discoverPage(
            TimelineResponse(
              feed: [feedPost('unexpected-automatic')],
              cursor: 'unexpected-cursor',
            ),
          );

        await harness.provider.loadMore(FeedType.discover);
        await harness.provider.loadMore(FeedType.discover);

        expect(_cursors(harness.discoverRequests), [
          null,
          'stale-cursor',
          null,
        ], reason: 'scroll must not retry a failed page-one recovery');

        await harness.provider.retryLoadMore(FeedType.discover);

        expect(harness.discoverRequests.last.cursor, isNull);
        expect(postIds(harness.provider), ['retried-page-one']);
        final state = harness.provider.getState(FeedType.discover);
        expect(state.cursor, 'new-cursor');
        expect(state.loadMoreError, isNull);
      },
    );

    test(
      'failed recovery then failed refresh blocks scroll and Retry replaces',
      () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        await harness.seedDiscover();
        harness
          ..discoverError(invalidCursor())
          ..discoverError(ApiException('recovery failed'));

        await harness.provider.loadMore(FeedType.discover);

        harness.discoverError(ApiException('refresh failed'));
        await harness.provider.loadFeed(FeedType.discover, refresh: true);

        var state = harness.provider.getState(FeedType.discover);
        expect(postIds(harness.provider), ['stale']);
        expect(state.error, 'refresh failed');
        expect(state.cursor, isNull);

        harness
          ..discoverPage(
            TimelineResponse(
              feed: [feedPost('retried-page-one')],
              cursor: 'recovered-cursor',
            ),
          )
          ..discoverError(ApiException('unexpected automatic request'));

        await harness.provider.loadMore(FeedType.discover);
        await harness.provider.retry(FeedType.discover);

        expect(_cursors(harness.discoverRequests), [
          null,
          'stale-cursor',
          null,
          null,
          null,
        ]);
        expect(postIds(harness.provider), ['retried-page-one']);
        state = harness.provider.getState(FeedType.discover);
        expect(state.cursor, 'recovered-cursor');
        expect(state.error, isNull);
        expect(state.loadMoreError, isNull);
      },
    );

    for (final scenario in <({String sort, String? timeframe})>[
      (sort: 'new', timeframe: null),
      (sort: 'hot', timeframe: 'day'),
    ]) {
      test('${scenario.sort}/${scenario.timeframe} change then failed refresh '
          'blocks scroll and Retry replaces', () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        await harness.seedDiscover();

        harness.provider.setSort(
          scenario.sort,
          newTimeframe: scenario.timeframe,
        );
        harness.discoverError(ApiException('refresh failed'));
        await harness.provider.loadFeed(FeedType.discover, refresh: true);

        var state = harness.provider.getState(FeedType.discover);
        expect(postIds(harness.provider), ['stale']);
        expect(state.error, 'refresh failed');
        expect(state.cursor, isNull);

        harness
          ..discoverPage(
            TimelineResponse(
              feed: [feedPost('replacement')],
              cursor: 'replacement-cursor',
            ),
          )
          ..discoverError(ApiException('unexpected automatic request'));

        await harness.provider.loadMore(FeedType.discover);
        await harness.provider.retry(FeedType.discover);

        expect(_cursors(harness.discoverRequests), [null, null, null]);
        expect(harness.discoverRequests.last.sort, scenario.sort);
        expect(harness.discoverRequests.last.timeframe, scenario.timeframe);
        expect(postIds(harness.provider), ['replacement']);
        state = harness.provider.getState(FeedType.discover);
        expect(state.cursor, 'replacement-cursor');
        expect(state.error, isNull);
        expect(state.loadMoreError, isNull);
      });
    }
  });

  group('InvalidCursor recovery scope', () {
    for (final sort in ['new', 'top']) {
      test('does not recover Discover $sort pagination', () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        harness.provider.setSort(sort);
        await harness.seedDiscover();
        harness.discoverError(invalidCursor());

        await harness.provider.loadMore(FeedType.discover);

        expect(_cursors(harness.discoverRequests), [null, 'stale-cursor']);
        expect(harness.discoverRequests.last.sort, sort);
        expect(postIds(harness.provider), ['stale']);
      });
    }

    test('does not recover For You pagination', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.timelinePage(
        TimelineResponse(feed: [feedPost('timeline')], cursor: 'timeline-next'),
      );
      await harness.provider.loadFeed(FeedType.forYou, refresh: true);
      harness.timelineError(invalidCursor());

      await harness.provider.loadMore(FeedType.forYou);

      expect(_cursors(harness.timelineRequests), [null, 'timeline-next']);
      expect(harness.discoverRequests, isEmpty);
      expect(
        harness.provider.getState(FeedType.forYou).posts.single.post.rkey,
        'timeline',
      );
    });

    test('does not recover an initial request', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.discoverError(invalidCursor());

      await harness.provider.loadFeed(FeedType.discover, refresh: true);

      expect(_cursors(harness.discoverRequests), [null]);
      expect(harness.provider.getState(FeedType.discover).error, isNotNull);
    });

    test('does not recover a refresh request', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await harness.seedDiscover();
      harness.discoverError(invalidCursor());

      await harness.provider.loadFeed(FeedType.discover, refresh: true);

      expect(_cursors(harness.discoverRequests), [null, null]);
      expect(postIds(harness.provider), ['stale']);
    });

    for (final wrongError in <(String, ApiException)>[
      (
        'wrong status',
        ApiException('conflict', statusCode: 409, errorCode: 'InvalidCursor'),
      ),
      (
        'wrong code',
        ApiException('bad request', statusCode: 400, errorCode: 'OtherError'),
      ),
    ]) {
      test('does not recover ${wrongError.$1}', () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        await harness.seedDiscover();
        harness.discoverError(wrongError.$2);

        await harness.provider.loadMore(FeedType.discover);

        expect(_cursors(harness.discoverRequests), [null, 'stale-cursor']);
        expect(postIds(harness.provider), ['stale']);
      });
    }
  });

  group('Discover Hot availability cooldown', () {
    test(
      'blocks automatic and manual retries until the original deadline',
      () async {
        final clock = _FakeClock(DateTime.utc(2026, 9, 13, 12));
        final harness = _Harness(clock: clock.call);
        addTearDown(harness.dispose);
        await harness.seedDiscover();
        harness.discoverError(discoverUnavailable(30));

        await harness.provider.loadMore(FeedType.discover);

        var state = harness.provider.getState(FeedType.discover);
        expect(postIds(harness.provider), ['stale']);
        expect(state.cursor, 'stale-cursor');
        expect(state.error, isNull);
        expect(state.loadMoreError, contains('30 seconds'));

        clock.advance(const Duration(milliseconds: 1200));
        await harness.provider.loadMore(FeedType.discover);
        await harness.provider.retryLoadMore(FeedType.discover);

        expect(_cursors(harness.discoverRequests), [null, 'stale-cursor']);
        state = harness.provider.getState(FeedType.discover);
        expect(state.loadMoreError, contains('29 seconds'));

        clock.advance(const Duration(milliseconds: 28800));
        harness.discoverPage(TimelineResponse(feed: [feedPost('next')]));
        await harness.provider.retryLoadMore(FeedType.discover);

        expect(_cursors(harness.discoverRequests), [
          null,
          'stale-cursor',
          'stale-cursor',
        ]);
        expect(postIds(harness.provider), ['stale', 'next']);
        expect(harness.provider.getState(FeedType.discover).hasMore, isFalse);
        expect(
          harness.provider.getState(FeedType.discover).loadMoreError,
          isNull,
        );
      },
    );

    for (final retryAfter in <int?>[0, null]) {
      test('Retry-After $retryAfter is immediately retryable', () async {
        final clock = _FakeClock(DateTime.utc(2026, 9, 13, 12));
        final harness = _Harness(clock: clock.call);
        addTearDown(harness.dispose);
        await harness.seedDiscover();
        harness.discoverError(discoverUnavailable(retryAfter));
        await harness.provider.loadMore(FeedType.discover);

        harness.discoverPage(TimelineResponse(feed: [feedPost('next')]));
        await harness.provider.retryLoadMore(FeedType.discover);

        expect(_cursors(harness.discoverRequests), [
          null,
          'stale-cursor',
          'stale-cursor',
        ]);
        expect(postIds(harness.provider), ['stale', 'next']);
      });
    }

    test(
      'a timed recovery failure keeps page one as the retry target',
      () async {
        final clock = _FakeClock(DateTime.utc(2026, 9, 13, 12));
        final harness = _Harness(clock: clock.call);
        addTearDown(harness.dispose);
        await harness.seedDiscover();
        harness
          ..discoverError(invalidCursor())
          ..discoverError(discoverUnavailable(30));

        await harness.provider.loadMore(FeedType.discover);

        expect(_cursors(harness.discoverRequests), [
          null,
          'stale-cursor',
          null,
        ]);
        expect(postIds(harness.provider), ['stale']);
        var state = harness.provider.getState(FeedType.discover);
        expect(state.cursor, isNull);
        expect(state.hasMore, isTrue);
        expect(state.loadMoreError, contains('30 seconds'));

        clock.advance(const Duration(seconds: 30));
        harness.discoverPage(
          TimelineResponse(feed: [feedPost('recovered')], cursor: 'new-cursor'),
        );
        await harness.provider.retryLoadMore(FeedType.discover);

        expect(harness.discoverRequests.last.cursor, isNull);
        expect(postIds(harness.provider), ['recovered']);
        state = harness.provider.getState(FeedType.discover);
        expect(state.cursor, 'new-cursor');
        expect(state.loadMoreError, isNull);
      },
    );

    for (final scenario in <({String name, bool pageOne, String? target})>[
      (name: 'retained cursor', pageOne: false, target: 'stale-cursor'),
      (name: 'page one', pageOne: true, target: null),
    ]) {
      test(
        '${scenario.name} stays gated from scroll at the exact deadline',
        () async {
          final clock = _FakeClock(DateTime.utc(2026, 9, 13, 12));
          final harness = _Harness(clock: clock.call);
          addTearDown(harness.dispose);
          await harness.seedDiscover();
          if (scenario.pageOne) {
            harness
              ..discoverError(invalidCursor())
              ..discoverError(discoverUnavailable(30));
          } else {
            harness.discoverError(discoverUnavailable(30));
          }
          await harness.provider.loadMore(FeedType.discover);
          final requestCount = scenario.pageOne ? 3 : 2;

          clock.advance(const Duration(seconds: 29));
          await harness.provider.loadMore(FeedType.discover);
          await harness.provider.retryLoadMore(FeedType.discover);

          expect(harness.discoverRequests.length, requestCount);
          expect(
            harness.provider.getState(FeedType.discover).loadMoreError,
            contains('1 second'),
          );

          clock.advance(const Duration(seconds: 1));
          harness.discoverPage(
            TimelineResponse(
              feed: [feedPost('deadline-retry')],
              cursor: 'after-deadline',
            ),
          );

          await harness.provider.loadMore(FeedType.discover);

          expect(
            harness.discoverRequests.length,
            requestCount,
            reason: 'deadline expiry must not turn scroll into an API retry',
          );

          await harness.provider.retryLoadMore(FeedType.discover);

          expect(harness.discoverRequests.length, requestCount + 1);
          expect(harness.discoverRequests.last.cursor, scenario.target);
          expect(
            postIds(harness.provider),
            scenario.pageOne ? ['deadline-retry'] : ['stale', 'deadline-retry'],
          );
          expect(
            harness.provider.getState(FeedType.discover).loadMoreError,
            isNull,
          );
        },
      );
    }
  });

  group('request generation invalidation', () {
    for (final resetKind in ['reset', 'resetAll']) {
      for (final completionKind in ['success', 'failure']) {
        test('$resetKind ignores late recovery $completionKind', () async {
          final harness = _Harness();
          addTearDown(harness.dispose);
          await harness.seedDiscover();
          final recovery = Completer<TimelineResponse>();
          harness
            ..discoverError(invalidCursor(), synchronous: true)
            ..discoverFuture(recovery.future);

          final pending = harness.provider.loadMore(FeedType.discover);
          expect(_cursors(harness.discoverRequests), [
            null,
            'stale-cursor',
            null,
          ]);

          if (resetKind == 'reset') {
            harness.provider.reset(FeedType.discover);
          } else {
            harness.provider.resetAll();
          }
          if (completionKind == 'success') {
            recovery.complete(
              TimelineResponse(feed: [feedPost('late')], cursor: 'late-cursor'),
            );
          } else {
            recovery.completeError(ApiException('late failure'));
          }
          await pending;

          final state = harness.provider.getState(FeedType.discover);
          expect(state.posts, isEmpty);
          expect(state.cursor, isNull);
          expect(state.error, isNull);
          expect(state.loadMoreError, isNull);
          expect(state.isLoadingMore, isFalse);
        });
      }
    }

    for (final completionKind in ['success', 'failure']) {
      test('sort change ignores late recovery $completionKind', () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        await harness.seedDiscover();
        final recovery = Completer<TimelineResponse>();
        harness
          ..discoverError(invalidCursor(), synchronous: true)
          ..discoverFuture(recovery.future);

        final pending = harness.provider.loadMore(FeedType.discover);
        expect(_cursors(harness.discoverRequests), [
          null,
          'stale-cursor',
          null,
        ]);
        harness.provider.setSort('new');

        if (completionKind == 'success') {
          recovery.complete(
            TimelineResponse(feed: [feedPost('late')], cursor: 'late-cursor'),
          );
        } else {
          recovery.completeError(ApiException('late failure'));
        }
        await pending;

        final state = harness.provider.getState(FeedType.discover);
        expect(harness.provider.sort, 'new');
        expect(postIds(harness.provider), ['stale']);
        expect(state.error, isNull);
        expect(state.loadMoreError, isNull);
        expect(state.isLoadingMore, isFalse);
      });
    }

    for (final resetKind in ['reset', 'resetAll']) {
      test('$resetKind clears a pending cooldown', () async {
        final clock = _FakeClock(DateTime.utc(2026, 9, 13, 12));
        final harness = _Harness(clock: clock.call);
        addTearDown(harness.dispose);
        await harness.seedDiscover();
        harness.discoverError(discoverUnavailable(30));
        await harness.provider.loadMore(FeedType.discover);

        if (resetKind == 'reset') {
          harness.provider.reset(FeedType.discover);
        } else {
          harness.provider.resetAll();
        }
        harness.discoverPage(TimelineResponse(feed: [feedPost('fresh')]));
        await harness.provider.retryLoadMore(FeedType.discover);

        expect(harness.discoverRequests.last.cursor, isNull);
        expect(postIds(harness.provider), ['fresh']);
      });
    }

    test(
      'sort change clears a pending cooldown without extending it',
      () async {
        final clock = _FakeClock(DateTime.utc(2026, 9, 13, 12));
        final harness = _Harness(clock: clock.call);
        addTearDown(harness.dispose);
        await harness.seedDiscover();
        harness.discoverError(discoverUnavailable(30));
        await harness.provider.loadMore(FeedType.discover);

        harness.provider.setSort('hot', newTimeframe: 'day');
        harness.discoverPage(TimelineResponse(feed: [feedPost('fresh')]));
        await harness.provider.retryLoadMore(FeedType.discover);

        expect(harness.discoverRequests.length, 3);
        expect(harness.discoverRequests.last.timeframe, 'day');
      },
    );

    for (final staleCompletion in ['success', 'failure']) {
      test(
        'a stale load-more $staleCompletion cannot overwrite a newer page',
        () async {
          final harness = _Harness();
          addTearDown(harness.dispose);
          await harness.seedDiscover();
          final stale = Completer<TimelineResponse>();
          harness.discoverFuture(stale.future);

          final staleRequest = harness.provider.loadMore(FeedType.discover);
          harness.provider.reset(FeedType.discover);
          harness.discoverPage(
            TimelineResponse(feed: [feedPost('newer')], cursor: 'newer-cursor'),
          );
          await harness.provider.loadFeed(FeedType.discover, refresh: true);

          if (staleCompletion == 'success') {
            stale.complete(
              TimelineResponse(
                feed: [feedPost('older')],
                cursor: 'older-cursor',
              ),
            );
          } else {
            stale.completeError(ApiException('older failure'));
          }
          await staleRequest;

          final state = harness.provider.getState(FeedType.discover);
          expect(postIds(harness.provider), ['newer']);
          expect(state.cursor, 'newer-cursor');
          expect(state.error, isNull);
          expect(state.loadMoreError, isNull);
          expect(state.isLoading, isFalse);
          expect(state.isLoadingMore, isFalse);
        },
      );
    }
  });

  group('auth identity boundaries', () {
    for (final initialDid in <String?>['did:plc:first', null]) {
      final sessionName = initialDid == null ? 'anonymous' : 'authenticated';

      for (final type in FeedType.values) {
        test(
          '$type ignores a late completion from an $sessionName session',
          () async {
            final authProvider = _MutableAuthProvider(initialDid);
            final harness = _Harness(authProvider: authProvider);
            addTearDown(harness.dispose);

            final seed = TimelineResponse(
              feed: [feedPost('stale')],
              cursor: 'stale-cursor',
            );
            if (type == FeedType.forYou && initialDid != null) {
              harness.timelinePage(seed);
            } else {
              harness.discoverPage(seed);
            }
            await harness.provider.loadFeed(type, refresh: true);

            final late = Completer<TimelineResponse>();
            if (type == FeedType.forYou && initialDid != null) {
              harness.timelineFuture(late.future);
            } else {
              harness.discoverFuture(late.future);
            }
            final pending = harness.provider.loadMore(type);

            authProvider.setDid('did:plc:second');
            final stateAfterIdentityChange = harness.provider.getState(type);
            late.complete(
              TimelineResponse(
                feed: [
                  feedPost(
                    'late',
                    vote: 'up',
                    voteUri:
                        'at://did:plc:first/social.coves.feed.vote/late-vote',
                  ),
                ],
                cursor: 'late-cursor',
              ),
            );
            await pending;

            expectStateMatches(
              harness.provider.getState(type),
              stateAfterIdentityChange,
            );
            expect(
              harness.voteProvider.isLiked(
                'at://did:plc:author/social.coves.community.post/late',
              ),
              isFalse,
              reason: 'viewer state belongs to the previous auth identity',
            );
          },
        );
      }
    }

    test(
      'DID-to-DID clears both feeds and permits a new page-one request',
      () async {
        final authProvider = _MutableAuthProvider('did:plc:first');
        final harness = _Harness(authProvider: authProvider);
        addTearDown(harness.dispose);
        await harness.seedDiscover();
        await harness.seedForYou();
        final stale = Completer<TimelineResponse>();
        harness.discoverFuture(stale.future);

        final staleRequest = harness.provider.loadMore(FeedType.discover);
        expect(
          harness.provider.getState(FeedType.discover).isLoadingMore,
          isTrue,
        );

        authProvider.setDid('did:plc:second');

        expectInitialState(harness.provider, FeedType.discover);
        expectInitialState(harness.provider, FeedType.forYou);

        harness.discoverPage(
          TimelineResponse(
            feed: [feedPost('second-session')],
            cursor: 'second-cursor',
          ),
        );
        await harness.provider.loadFeed(FeedType.discover);

        expect(harness.discoverRequests.last.cursor, isNull);
        expect(postIds(harness.provider), ['second-session']);

        stale.complete(
          TimelineResponse(feed: [feedPost('first-session-late')]),
        );
        await staleRequest;

        expect(postIds(harness.provider), ['second-session']);
        expect(
          harness.provider.getState(FeedType.discover).isLoadingMore,
          isFalse,
        );
      },
    );

    test(
      'sign-out clears both feeds, switches to Discover, and loads page one',
      () async {
        final authProvider = _MutableAuthProvider('did:plc:first');
        final harness = _Harness(authProvider: authProvider);
        addTearDown(harness.dispose);
        await harness.seedDiscover();
        await harness.seedForYou();
        harness.provider.setCurrentFeed(FeedType.forYou);
        final stale = Completer<TimelineResponse>();
        harness.timelineFuture(stale.future);

        final staleRequest = harness.provider.loadMore(FeedType.forYou);
        expect(
          harness.provider.getState(FeedType.forYou).isLoadingMore,
          isTrue,
        );

        authProvider.setDid(null);

        expect(harness.provider.currentFeedType, FeedType.discover);
        expectInitialState(harness.provider, FeedType.discover);
        expectInitialState(harness.provider, FeedType.forYou);

        harness.discoverPage(
          TimelineResponse(
            feed: [feedPost('anonymous')],
            cursor: 'anon-cursor',
          ),
        );
        await harness.provider.loadFeed(FeedType.discover);

        expect(harness.discoverRequests.last.cursor, isNull);
        expect(postIds(harness.provider), ['anonymous']);

        stale.complete(TimelineResponse(feed: [feedPost('signed-out-late')]));
        await staleRequest;

        expectInitialState(harness.provider, FeedType.forYou);
        expect(postIds(harness.provider), ['anonymous']);
      },
    );

    test(
      'sign-in clears anonymous state and permits an authenticated page one',
      () async {
        final authProvider = _MutableAuthProvider(null);
        final harness = _Harness(authProvider: authProvider);
        addTearDown(harness.dispose);
        await harness.seedDiscover();
        harness.discoverPage(
          TimelineResponse(
            feed: [feedPost('anonymous-for-you-fallback')],
            cursor: 'anonymous-fallback-cursor',
          ),
        );
        await harness.provider.loadFeed(FeedType.forYou, refresh: true);
        final stale = Completer<TimelineResponse>();
        harness.discoverFuture(stale.future);

        final staleRequest = harness.provider.loadFeed(
          FeedType.discover,
          refresh: true,
        );
        expect(harness.provider.getState(FeedType.discover).isLoading, isTrue);

        authProvider.setDid('did:plc:second');

        expect(harness.provider.currentFeedType, FeedType.discover);
        expectInitialState(harness.provider, FeedType.discover);
        expectInitialState(harness.provider, FeedType.forYou);

        harness.timelinePage(
          TimelineResponse(
            feed: [feedPost('authenticated')],
            cursor: 'authenticated-cursor',
          ),
        );
        await harness.provider.loadFeed(FeedType.forYou);

        expect(harness.timelineRequests.last.cursor, isNull);
        expect(
          harness.provider
              .getState(FeedType.forYou)
              .posts
              .map((post) => post.post.rkey),
          ['authenticated'],
        );

        stale.complete(TimelineResponse(feed: [feedPost('anonymous-late')]));
        await staleRequest;

        expectInitialState(harness.provider, FeedType.discover);
        expect(
          harness.provider
              .getState(FeedType.forYou)
              .posts
              .map((post) => post.post.rkey),
          ['authenticated'],
        );
      },
    );
  });

  group('dispose boundaries', () {
    test('dispose makes a pending original response inert', () async {
      final harness = _Harness();
      addTearDown(harness.voteProvider.dispose);
      final response = Completer<TimelineResponse>();
      harness.discoverFuture(response.future);

      final pending = harness.provider.loadFeed(
        FeedType.discover,
        refresh: true,
      );
      harness.provider.dispose();
      final stateAfterDispose = harness.provider.getState(FeedType.discover);

      response.complete(
        TimelineResponse(
          feed: [
            feedPost(
              'late',
              vote: 'up',
              voteUri: 'at://did:plc:viewer/social.coves.feed.vote/late-vote',
            ),
          ],
          cursor: 'late-cursor',
        ),
      );
      Object? completionError;
      try {
        await pending;
      } on Object catch (error) {
        completionError = error;
      }

      expect(completionError, isNull, reason: 'must not notify after dispose');
      expectStateMatches(
        harness.provider.getState(FeedType.discover),
        stateAfterDispose,
      );
      expect(
        harness.voteProvider.isLiked(
          'at://did:plc:author/social.coves.community.post/late',
        ),
        isFalse,
      );
      expect(harness.provider.currentTime, isNull);
      harness.provider.stopTimeUpdates();
    });

    test('dispose makes a pending recovery response inert', () async {
      final harness = _Harness();
      addTearDown(harness.voteProvider.dispose);
      await harness.seedDiscover();
      final recovery = Completer<TimelineResponse>();
      harness
        ..discoverError(invalidCursor(), synchronous: true)
        ..discoverFuture(recovery.future);

      final pending = harness.provider.loadMore(FeedType.discover);
      expect(harness.discoverRequests.last.cursor, isNull);
      harness.provider.dispose();
      final stateAfterDispose = harness.provider.getState(FeedType.discover);

      recovery.complete(
        TimelineResponse(
          feed: [
            feedPost(
              'late-recovery',
              vote: 'up',
              voteUri: 'at://did:plc:viewer/social.coves.feed.vote/late-vote',
            ),
          ],
          cursor: 'late-cursor',
        ),
      );
      Object? completionError;
      try {
        await pending;
      } on Object catch (error) {
        completionError = error;
      }

      expect(completionError, isNull, reason: 'must not notify after dispose');
      expectStateMatches(
        harness.provider.getState(FeedType.discover),
        stateAfterDispose,
      );
      expect(
        harness.voteProvider.isLiked(
          'at://did:plc:author/social.coves.community.post/late-recovery',
        ),
        isFalse,
      );
      expect(harness.provider.currentTime, isNull);
      harness.provider.stopTimeUpdates();
    });

    final disposedMutations = <({String name, _DisposedMutation invoke})>[
      (name: 'retry', invoke: (provider) => provider.retry(FeedType.discover)),
      (name: 'setSort', invoke: (provider) => provider.setSort('new')),
      (
        name: 'clearError',
        invoke: (provider) => provider.clearError(FeedType.discover),
      ),
      (name: 'reset', invoke: (provider) => provider.reset(FeedType.discover)),
      (name: 'resetAll', invoke: (provider) => provider.resetAll()),
      (
        name: 'setCurrentFeed',
        invoke: (provider) => provider.setCurrentFeed(FeedType.discover),
      ),
      (
        name: 'saveScrollPosition',
        invoke: (provider) =>
            provider.saveScrollPosition(FeedType.discover, 999),
      ),
    ];

    for (final mutation in disposedMutations) {
      test(
        'retained ${mutation.name} callback is inert after dispose',
        () async {
          final harness = _Harness();
          addTearDown(harness.voteProvider.dispose);
          await harness.seedDiscover();
          await harness.seedForYou();
          harness.provider
            ..saveScrollPosition(FeedType.discover, 42)
            ..setCurrentFeed(FeedType.forYou);
          harness.discoverError(ApiException('visible error'));
          await harness.provider.loadFeed(FeedType.discover, refresh: true);
          var notifications = 0;
          harness.provider.addListener(() => notifications++);
          FutureOr<void> retainedCallback() =>
              mutation.invoke(harness.provider);

          harness.provider.dispose();
          final discoverAfterDispose = harness.provider.getState(
            FeedType.discover,
          );
          final forYouAfterDispose = harness.provider.getState(FeedType.forYou);
          final currentFeedAfterDispose = harness.provider.currentFeedType;
          final sortAfterDispose = harness.provider.sort;
          final timeframeAfterDispose = harness.provider.timeframe;
          final discoverRequestCount = harness.discoverRequests.length;
          final timelineRequestCount = harness.timelineRequests.length;

          Object? callbackError;
          try {
            await retainedCallback();
          } on Object catch (error) {
            callbackError = error;
          }

          expect(
            callbackError,
            isNull,
            reason: 'a retained callback must not notify after disposal',
          );
          expect(notifications, 0);
          expectStateMatches(
            harness.provider.getState(FeedType.discover),
            discoverAfterDispose,
          );
          expectStateMatches(
            harness.provider.getState(FeedType.forYou),
            forYouAfterDispose,
          );
          expect(harness.provider.currentFeedType, currentFeedAfterDispose);
          expect(harness.provider.sort, sortAfterDispose);
          expect(harness.provider.timeframe, timeframeAfterDispose);
          expect(harness.discoverRequests.length, discoverRequestCount);
          expect(harness.timelineRequests.length, timelineRequestCount);
        },
      );
    }
  });

  group('sort refresh boundaries', () {
    for (final scenario in <({String sort, String? timeframe})>[
      (sort: 'new', timeframe: null),
      (sort: 'hot', timeframe: 'day'),
    ]) {
      test(
        'effective $scenario starts page one and replaces old posts',
        () async {
          final harness = _Harness();
          addTearDown(harness.dispose);
          await harness.seedDiscover();

          harness.provider.setSort(
            scenario.sort,
            newTimeframe: scenario.timeframe,
          );
          harness.discoverPage(
            TimelineResponse(feed: [feedPost('fresh')], cursor: 'fresh-cursor'),
          );
          await harness.provider.loadMore(FeedType.discover);

          expect(harness.discoverRequests.last.cursor, isNull);
          expect(harness.discoverRequests.last.sort, scenario.sort);
          expect(harness.discoverRequests.last.timeframe, scenario.timeframe);
          expect(postIds(harness.provider), ['fresh']);
          expect(
            harness.provider.getState(FeedType.discover).cursor,
            'fresh-cursor',
          );
        },
      );
    }

    for (final scenario in <({String sort, String? timeframe})>[
      (sort: 'new', timeframe: null),
      (sort: 'hot', timeframe: 'day'),
    ]) {
      test('effective $scenario revives an exhausted feed '
          'for page-one replacement', () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        await harness.seedDiscover(cursor: null);
        expect(harness.provider.getState(FeedType.discover).hasMore, isFalse);

        harness.provider.setSort(
          scenario.sort,
          newTimeframe: scenario.timeframe,
        );

        var state = harness.provider.getState(FeedType.discover);
        expect(state.cursor, isNull);
        expect(state.hasMore, isTrue);

        harness.discoverPage(
          TimelineResponse(
            feed: [feedPost('replacement')],
            cursor: 'replacement-cursor',
          ),
        );
        await harness.provider.loadMore(FeedType.discover);

        expect(harness.discoverRequests.length, 2);
        expect(harness.discoverRequests.last.cursor, isNull);
        expect(harness.discoverRequests.last.sort, scenario.sort);
        expect(harness.discoverRequests.last.timeframe, scenario.timeframe);
        expect(postIds(harness.provider), ['replacement']);
        state = harness.provider.getState(FeedType.discover);
        expect(state.cursor, 'replacement-cursor');
        expect(state.hasMore, isTrue);
      });
    }

    for (final timeframe in <String?>[null, 'day']) {
      test('no-op hot/$timeframe preserves the active cooldown', () async {
        final clock = _FakeClock(DateTime.utc(2026, 9, 13, 12));
        final harness = _Harness(clock: clock.call);
        addTearDown(harness.dispose);
        harness.provider.setSort('hot', newTimeframe: timeframe);
        await harness.seedDiscover();
        harness.discoverError(discoverUnavailable(30));
        await harness.provider.loadMore(FeedType.discover);
        final requestCount = harness.discoverRequests.length;

        harness.provider.setSort('hot', newTimeframe: timeframe);
        harness.discoverPage(TimelineResponse(feed: [feedPost('too-early')]));
        await harness.provider.retryLoadMore(FeedType.discover);

        expect(harness.discoverRequests.length, requestCount);
        expect(
          harness.provider.getState(FeedType.discover).loadMoreError,
          contains('30 seconds'),
        );
      });
    }
  });

  group('stale original error boundaries', () {
    for (final boundary in ['reset', 'sort']) {
      test('$boundary prevents a stale InvalidCursor recovery', () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        await harness.seedDiscover();
        final original = Completer<TimelineResponse>();
        harness.discoverFuture(original.future);

        final pending = harness.provider.loadMore(FeedType.discover);
        if (boundary == 'reset') {
          harness.provider.reset(FeedType.discover);
        } else {
          harness.provider.setSort('new');
        }
        original.completeError(invalidCursor());
        await pending;

        expect(
          harness.discoverRequests.length,
          2,
          reason: 'the stale cursor error must not launch page-one recovery',
        );
      });

      test(
        '$boundary prevents a stale error from installing cooldown',
        () async {
          final clock = _FakeClock(DateTime.utc(2026, 9, 13, 12));
          final harness = _Harness(clock: clock.call);
          addTearDown(harness.dispose);
          await harness.seedDiscover();
          final original = Completer<TimelineResponse>();
          harness.discoverFuture(original.future);

          final pending = harness.provider.loadMore(FeedType.discover);
          if (boundary == 'reset') {
            harness.provider.reset(FeedType.discover);
          } else {
            harness.provider.setSort('new');
          }
          original.completeError(discoverUnavailable(30));
          await pending;

          final requestCount = harness.discoverRequests.length;
          harness.discoverPage(
            TimelineResponse(feed: [feedPost('current-session')]),
          );
          await harness.provider.retryLoadMore(FeedType.discover);

          expect(
            harness.discoverRequests.length,
            requestCount + 1,
            reason: 'a stale error must not gate current work',
          );
        },
      );
    }
  });
}
