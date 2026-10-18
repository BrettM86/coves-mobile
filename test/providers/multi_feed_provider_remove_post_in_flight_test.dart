// A post removed while a load-more for its feed is in flight stays removed
// when that page lands: the page is appended to the feed as it is now, not
// to the snapshot taken when the request started.
//
// The pending page also contains the removed post and a new survivor.

import 'dart:async';

import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/multi_feed_provider.dart';
import 'package:coves_flutter/services/post_change_broadcast.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/test_mocks.dart';

const String myDid = 'did:plc:me';
const String removedPostUri =
    'at://did:plc:community/social.coves.community.post/removed';
const String keptPostUri =
    'at://did:plc:community/social.coves.community.post/kept';
const String pageTwoPostUri =
    'at://did:plc:community/social.coves.community.post/page-two';
const String pageTwoCursor = 'page-2';

FeedViewPost _post(String uri) {
  return FeedViewPost(
    post: PostView(
      uri: uri,
      cid: 'cid-${uri.split('/').last}',
      rkey: uri.split('/').last,
      author: AuthorView(did: myDid, handle: 'me.coves.test'),
      community: CommunityRef(did: 'did:plc:community', name: 'testcove'),
      createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
      indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
      record: const PostRecord(title: 'Title', content: 'Body'),
      stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
    ),
  );
}

List<String> _uris(List<FeedViewPost> posts) =>
    posts.map((post) => post.post.uri).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAuthProvider authProvider;
  late MockCovesApiService apiService;
  late FakeVoteProvider voteProvider;
  late FakeSubscriptionProvider subscriptionProvider;
  late MultiFeedProvider provider;
  late PostChangeBroadcast broadcast;

  setUp(() {
    authProvider = FakeAuthProvider(signedInDid: myDid);
    apiService = MockCovesApiService();
    voteProvider = FakeVoteProvider(authProvider);
    subscriptionProvider = FakeSubscriptionProvider(
      authProvider: authProvider,
      apiService: apiService,
    );
    broadcast = PostChangeBroadcast();
    provider = MultiFeedProvider(
      authProvider,
      apiService: apiService,
      voteProvider: voteProvider,
      subscriptionProvider: subscriptionProvider,
      clock: () => DateTime.utc(2026, 9, 29, 12),
      postChangeBroadcast: broadcast,
      sessionKeyOf: unchangingSessionKey,
    );
  });

  tearDown(() {
    provider.dispose();
    subscriptionProvider.dispose();
    voteProvider.dispose();
    authProvider.dispose();
  });

  /// Answers [feedType]'s page requests with [answer], given the requested
  /// cursor. Discover is served by getDiscover, For You (signed in) by
  /// getTimeline.
  void stubFeed(
    FeedType feedType,
    Future<TimelineResponse> Function(String? cursor) answer,
  ) {
    if (feedType == FeedType.discover) {
      when(
        apiService.getDiscover(
          sort: anyNamed('sort'),
          timeframe: anyNamed('timeframe'),
          limit: anyNamed('limit'),
          cursor: anyNamed('cursor'),
        ),
      ).thenAnswer(
        (invocation) => answer(invocation.namedArguments[#cursor] as String?),
      );
    } else {
      when(
        apiService.getTimeline(
          sort: anyNamed('sort'),
          timeframe: anyNamed('timeframe'),
          limit: anyNamed('limit'),
          cursor: anyNamed('cursor'),
        ),
      ).thenAnswer(
        (invocation) => answer(invocation.namedArguments[#cursor] as String?),
      );
    }
  }

  // Discover's page two points at a further page; For You's page two is the
  // last one. Either way the feed's cursor and hasMore come from page two.
  final cases = <({FeedType feedType, String? pageThreeCursor})>[
    (feedType: FeedType.discover, pageThreeCursor: 'page-3'),
    (feedType: FeedType.forYou, pageThreeCursor: null),
  ];

  for (final scenario in cases) {
    final feedType = scenario.feedType;
    final pageThreeCursor = scenario.pageThreeCursor;

    test('B4 ${feedType.name}: a post removed while load-more is in flight '
        'does not come back when the page lands', () async {
      final pageTwo = Completer<TimelineResponse>();
      final requestedCursors = <String?>[];
      stubFeed(feedType, (cursor) {
        requestedCursors.add(cursor);
        if (cursor == null) {
          return Future.value(
            TimelineResponse(
              feed: [_post(removedPostUri), _post(keptPostUri)],
              cursor: pageTwoCursor,
            ),
          );
        }
        return pageTwo.future;
      });

      await provider.loadFeed(feedType, refresh: true);
      expect(_uris(provider.getState(feedType).posts), [
        removedPostUri,
        keptPostUri,
      ]);
      expect(provider.getState(feedType).cursor, pageTwoCursor);
      expect(provider.getState(feedType).hasMore, isTrue);

      // Page two is requested and held open.
      final loadMore = provider.loadMore(feedType);
      expect(requestedCursors, [null, pageTwoCursor]);
      expect(provider.getState(feedType).isLoadingMore, isTrue);

      // The post is removed while page two is pending, and disappears now.
      broadcast.removePost(removedPostUri);
      expect(_uris(provider.getState(feedType).posts), [
        'at://did:plc:community/social.coves.community.post/kept',
      ]);

      pageTwo.complete(
        TimelineResponse(
          feed: [_post(removedPostUri), _post(pageTwoPostUri)],
          cursor: pageThreeCursor,
        ),
      );
      await loadMore;

      final state = provider.getState(feedType);
      expect(_uris(state.posts), [
        'at://did:plc:community/social.coves.community.post/kept',
        'at://did:plc:community/social.coves.community.post/page-two',
      ]);
      expect(state.cursor, pageThreeCursor);
      expect(state.hasMore, pageThreeCursor != null);
      expect(state.isLoadingMore, isFalse);
      expect(state.loadMoreError, isNull);
      expect(requestedCursors, [null, pageTwoCursor]);
    });
  }

  test('B4 discover: a post removed before its page is loaded does not '
      'appear when the in-flight page lands', () async {
    final pageTwo = Completer<TimelineResponse>();
    stubFeed(FeedType.discover, (cursor) {
      if (cursor == null) {
        return Future.value(
          TimelineResponse(feed: [_post(keptPostUri)], cursor: pageTwoCursor),
        );
      }
      return pageTwo.future;
    });

    await provider.loadFeed(FeedType.discover, refresh: true);
    expect(_uris(provider.getState(FeedType.discover).posts), [keptPostUri]);

    final loadMore = provider.loadMore(FeedType.discover);
    expect(provider.getState(FeedType.discover).isLoadingMore, isTrue);

    broadcast.removePost(removedPostUri);
    expect(_uris(provider.getState(FeedType.discover).posts), [keptPostUri]);

    pageTwo.complete(
      TimelineResponse(
        feed: [_post(removedPostUri), _post(pageTwoPostUri)],
        cursor: 'page-3',
      ),
    );
    await loadMore;

    expect(_uris(provider.getState(FeedType.discover).posts), [
      'at://did:plc:community/social.coves.community.post/kept',
      'at://did:plc:community/social.coves.community.post/page-two',
    ]);
  });
}
