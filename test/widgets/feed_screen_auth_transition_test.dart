import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/community_subscription_provider.dart';
import 'package:coves_flutter/providers/multi_feed_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/home/feed_screen.dart';
import 'package:coves_flutter/services/vote_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/test_mocks.dart';

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

class _NoNetworkSubscriptionProvider extends CommunitySubscriptionProvider {
  _NoNetworkSubscriptionProvider({
    required super.authProvider,
    required super.apiService,
  });

  @override
  Future<void> loadSubscribedCommunities() async {}
}

class _FeedRequest {
  const _FeedRequest({required this.cursor});

  final String? cursor;
}

class _NoTimerMultiFeedProvider extends MultiFeedProvider {
  _NoTimerMultiFeedProvider(
    super.authProvider, {
    required super.apiService,
    required super.voteProvider,
    required super.subscriptionProvider,
  });

  @override
  void startTimeUpdates() {}
}

class _Harness {
  _Harness(String? did) : authProvider = _MutableAuthProvider(did) {
    when(
      apiService.getDiscover(
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((invocation) {
      discoverRequests.add(
        _FeedRequest(cursor: invocation.namedArguments[#cursor] as String?),
      );
      return _discoverResponses.removeAt(0).future;
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
        _FeedRequest(cursor: invocation.namedArguments[#cursor] as String?),
      );
      return _timelineResponses.removeAt(0).future;
    });

    voteProvider = VoteProvider(
      voteService: _UnusedVoteService(),
      authProvider: authProvider,
    );
    subscriptionProvider = _NoNetworkSubscriptionProvider(
      authProvider: authProvider,
      apiService: apiService,
    );
    blockProvider = BlockProvider(
      apiService: apiService,
      authProvider: authProvider,
    );
    feedProvider = _NoTimerMultiFeedProvider(
      authProvider,
      apiService: apiService,
      voteProvider: voteProvider,
      subscriptionProvider: subscriptionProvider,
    );
  }

  final _MutableAuthProvider authProvider;
  final MockCovesApiService apiService = MockCovesApiService();
  final List<Completer<TimelineResponse>> _discoverResponses = [];
  final List<Completer<TimelineResponse>> _timelineResponses = [];
  final List<_FeedRequest> discoverRequests = [];
  final List<_FeedRequest> timelineRequests = [];
  late final VoteProvider voteProvider;
  late final CommunitySubscriptionProvider subscriptionProvider;
  late final BlockProvider blockProvider;
  late final MultiFeedProvider feedProvider;

  Completer<TimelineResponse> queueDiscover() {
    final response = Completer<TimelineResponse>();
    _discoverResponses.add(response);
    return response;
  }

  Completer<TimelineResponse> queueTimeline() {
    final response = Completer<TimelineResponse>();
    _timelineResponses.add(response);
    return response;
  }

  Widget widget() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<MultiFeedProvider>.value(value: feedProvider),
        ChangeNotifierProvider<VoteProvider>.value(value: voteProvider),
        ChangeNotifierProvider<CommunitySubscriptionProvider>.value(
          value: subscriptionProvider,
        ),
        ChangeNotifierProvider<BlockProvider>.value(value: blockProvider),
      ],
      child: MaterialApp(theme: AppTheme.dark, home: const FeedScreen()),
    );
  }

  void dispose() {
    subscriptionProvider.dispose();
    blockProvider.dispose();
    voteProvider.dispose();
    feedProvider.dispose();
    authProvider.dispose();
  }
}

TimelineResponse _page(String id, String cursor) {
  return TimelineResponse(feed: [_post(id)], cursor: cursor);
}

FeedViewPost _post(String id) {
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
      stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
    ),
  );
}

Future<void> _completeInitialAuthenticatedMount(
  WidgetTester tester,
  _Harness harness, {
  required FeedType visibleFeed,
}) async {
  harness.feedProvider.setCurrentFeed(visibleFeed);
  final discover = harness.queueDiscover();
  final timeline = harness.queueTimeline();

  await tester.pumpWidget(harness.widget());
  await tester.pump();

  expect(harness.discoverRequests.length, 1);
  expect(harness.timelineRequests.length, 1);
  expect(harness.discoverRequests.single.cursor, isNull);
  expect(harness.timelineRequests.single.cursor, isNull);

  discover.complete(_page('old-discover', 'old-discover-cursor'));
  timeline.complete(_page('old-for-you', 'old-for-you-cursor'));
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FeedScreen auth identity transitions', () {
    testWidgets(
      'DID-to-DID reloads visible For You and preloads Discover from page one',
      (tester) async {
        final harness = _Harness('did:plc:first');
        addTearDown(harness.dispose);
        await _completeInitialAuthenticatedMount(
          tester,
          harness,
          visibleFeed: FeedType.forYou,
        );
        final nextTimeline = harness.queueTimeline();
        final nextDiscover = harness.queueDiscover();

        harness.authProvider.setDid('did:plc:second');
        await tester.pump();

        expect(harness.feedProvider.currentFeedType, FeedType.forYou);
        expect(harness.feedProvider.getState(FeedType.forYou).posts, isEmpty);
        expect(harness.timelineRequests.length, 2);
        expect(harness.timelineRequests.last.cursor, isNull);
        expect(harness.discoverRequests.length, 2);
        expect(harness.discoverRequests.last.cursor, isNull);

        nextTimeline.complete(_page('second-for-you', 'second-timeline'));
        nextDiscover.complete(_page('second-discover', 'second-discover'));
        await tester.pump();
        await tester.pump();

        expect(
          harness.feedProvider
              .getState(FeedType.forYou)
              .posts
              .map((post) => post.post.rkey),
          ['second-for-you'],
        );
      },
    );

    testWidgets('sign-out reloads visible Discover from page one only', (
      tester,
    ) async {
      final harness = _Harness('did:plc:first');
      addTearDown(harness.dispose);
      await _completeInitialAuthenticatedMount(
        tester,
        harness,
        visibleFeed: FeedType.forYou,
      );
      final anonymousDiscover = harness.queueDiscover();

      harness.authProvider.setDid(null);
      await tester.pump();

      expect(harness.feedProvider.currentFeedType, FeedType.discover);
      expect(harness.feedProvider.getState(FeedType.discover).posts, isEmpty);
      expect(harness.discoverRequests.length, 2);
      expect(harness.discoverRequests.last.cursor, isNull);
      expect(harness.timelineRequests.length, 1);

      anonymousDiscover.complete(_page('anonymous', 'anonymous-cursor'));
      await tester.pump();
      await tester.pump();

      expect(
        harness.feedProvider
            .getState(FeedType.discover)
            .posts
            .map((post) => post.post.rkey),
        ['anonymous'],
      );
    });

    testWidgets(
      'anonymous-to-authenticated reloads visible Discover and preloads '
      'For You from page one',
      (tester) async {
        final harness = _Harness(null);
        addTearDown(harness.dispose);
        final anonymousDiscover = harness.queueDiscover();

        await tester.pumpWidget(harness.widget());
        await tester.pump();
        expect(harness.discoverRequests.length, 1);
        expect(harness.timelineRequests, isEmpty);
        anonymousDiscover.complete(
          _page('old-anonymous', 'old-anonymous-cursor'),
        );
        await tester.pump();
        await tester.pump();

        final authenticatedDiscover = harness.queueDiscover();
        final authenticatedTimeline = harness.queueTimeline();
        harness.authProvider.setDid('did:plc:second');
        await tester.pump();

        expect(harness.feedProvider.currentFeedType, FeedType.discover);
        expect(harness.feedProvider.getState(FeedType.discover).posts, isEmpty);
        expect(harness.discoverRequests.length, 2);
        expect(harness.discoverRequests.last.cursor, isNull);
        expect(harness.timelineRequests.length, 1);
        expect(harness.timelineRequests.last.cursor, isNull);

        authenticatedDiscover.complete(
          _page('authenticated-discover', 'authenticated-discover-cursor'),
        );
        authenticatedTimeline.complete(
          _page('authenticated-for-you', 'authenticated-timeline-cursor'),
        );
        await tester.pump();
        await tester.pump();

        expect(
          harness.feedProvider
              .getState(FeedType.discover)
              .posts
              .map((post) => post.post.rkey),
          ['authenticated-discover'],
        );
        expect(
          harness.feedProvider
              .getState(FeedType.forYou)
              .posts
              .map((post) => post.post.rkey),
          ['authenticated-for-you'],
        );
      },
    );
  });
}
