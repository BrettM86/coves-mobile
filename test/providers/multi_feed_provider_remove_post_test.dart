// MultiFeedProvider.removePost drops a deleted post from every loaded feed
// in place: Discover and For You both lose it, nothing else about either
// feed changes, and nothing is refetched.

import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/multi_feed_provider.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/test_mocks.dart';

const String myDid = 'did:plc:me';
const String deletedPostUri =
    'at://did:plc:community/social.coves.community.post/deleted';
const String keptPostUri =
    'at://did:plc:community/social.coves.community.post/kept';
const String otherPostUri =
    'at://did:plc:community/social.coves.community.post/other';
const String discoverCursor = 'discover-page-2';

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

/// Everything in a feed's state except its posts.
Map<String, Object?> _nonPostFields(MultiFeedProvider provider, FeedType type) {
  final state = provider.getState(type);
  return {
    'cursor': state.cursor,
    'hasMore': state.hasMore,
    'isLoading': state.isLoading,
    'isLoadingMore': state.isLoadingMore,
    'error': state.error,
    'loadMoreError': state.loadMoreError,
    'scrollPosition': state.scrollPosition,
    'lastRefreshTime': state.lastRefreshTime,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAuthProvider authProvider;
  late MockCovesApiService apiService;
  late FakeVoteProvider voteProvider;
  late FakeSubscriptionProvider subscriptionProvider;
  late MultiFeedProvider provider;
  late int discoverFetches;
  late int timelineFetches;

  setUp(() async {
    authProvider = FakeAuthProvider(signedInDid: myDid);
    apiService = MockCovesApiService();
    discoverFetches = 0;
    timelineFetches = 0;

    // Discover: page one has a next page, and loading it fails, so the
    // feed carries a cursor, hasMore and a loadMoreError.
    when(
      apiService.getDiscover(
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((invocation) async {
      discoverFetches++;
      if (invocation.namedArguments[#cursor] == discoverCursor) {
        throw ApiException('Server error', statusCode: 500);
      }
      return TimelineResponse(
        feed: [_post(deletedPostUri), _post(keptPostUri), _post(otherPostUri)],
        cursor: discoverCursor,
      );
    });
    // For You: a single, final page with the deleted post in the middle.
    when(
      apiService.getTimeline(
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((_) async {
      timelineFetches++;
      return TimelineResponse(
        feed: [_post(otherPostUri), _post(deletedPostUri), _post(keptPostUri)],
      );
    });

    voteProvider = FakeVoteProvider(authProvider);
    subscriptionProvider = FakeSubscriptionProvider(
      authProvider: authProvider,
      apiService: apiService,
    );
    provider = MultiFeedProvider(
      authProvider,
      apiService: apiService,
      voteProvider: voteProvider,
      subscriptionProvider: subscriptionProvider,
      clock: () => DateTime.utc(2026, 9, 29, 12),
    );

    await provider.loadFeed(FeedType.discover, refresh: true);
    await provider.loadFeed(FeedType.forYou, refresh: true);
    await provider.loadMore(FeedType.discover);
    provider.saveScrollPosition(FeedType.discover, 320);

    // The fixture is what the tests below rely on.
    expect(_uris(provider.getState(FeedType.discover).posts), [
      deletedPostUri,
      keptPostUri,
      otherPostUri,
    ]);
    expect(_uris(provider.getState(FeedType.forYou).posts), [
      otherPostUri,
      deletedPostUri,
      keptPostUri,
    ]);
    expect(provider.getState(FeedType.discover).cursor, discoverCursor);
    expect(provider.getState(FeedType.discover).hasMore, isTrue);
    expect(provider.getState(FeedType.discover).loadMoreError, isNotNull);
    expect(provider.getState(FeedType.forYou).hasMore, isFalse);
  });

  tearDown(() {
    provider.dispose();
    subscriptionProvider.dispose();
    voteProvider.dispose();
    authProvider.dispose();
  });

  test('removes the post from both feeds in place, notifying once and '
      'fetching nothing', () {
    var notifications = 0;
    provider.addListener(() => notifications++);
    final discoverPostsBefore = provider.getState(FeedType.discover).posts;
    final forYouPostsBefore = provider.getState(FeedType.forYou).posts;
    final discoverFieldsBefore = _nonPostFields(provider, FeedType.discover);
    final forYouFieldsBefore = _nonPostFields(provider, FeedType.forYou);
    final discoverFetchesBefore = discoverFetches;
    final timelineFetchesBefore = timelineFetches;

    provider.removePost(deletedPostUri);

    expect(_uris(provider.getState(FeedType.discover).posts), [
      keptPostUri,
      otherPostUri,
    ]);
    expect(_uris(provider.getState(FeedType.forYou).posts), [
      otherPostUri,
      keptPostUri,
    ]);
    expect(notifications, 1);
    expect(_nonPostFields(provider, FeedType.discover), discoverFieldsBefore);
    expect(_nonPostFields(provider, FeedType.forYou), forYouFieldsBefore);

    // The lists handed out before the removal are replaced, not mutated.
    expect(_uris(discoverPostsBefore), [
      deletedPostUri,
      keptPostUri,
      otherPostUri,
    ]);
    expect(_uris(forYouPostsBefore), [
      otherPostUri,
      deletedPostUri,
      keptPostUri,
    ]);

    expect(discoverFetches, discoverFetchesBefore);
    expect(timelineFetches, timelineFetchesBefore);
  });

  test('a uri that is in no loaded feed changes nothing and does not '
      'notify', () {
    var notifications = 0;
    provider.addListener(() => notifications++);
    final discoverFieldsBefore = _nonPostFields(provider, FeedType.discover);
    final forYouFieldsBefore = _nonPostFields(provider, FeedType.forYou);

    provider.removePost(
      'at://did:plc:community/social.coves.community.post/not-loaded',
    );

    expect(notifications, 0);
    expect(_uris(provider.getState(FeedType.discover).posts), [
      deletedPostUri,
      keptPostUri,
      otherPostUri,
    ]);
    expect(_uris(provider.getState(FeedType.forYou).posts), [
      otherPostUri,
      deletedPostUri,
      keptPostUri,
    ]);
    expect(_nonPostFields(provider, FeedType.discover), discoverFieldsBefore);
    expect(_nonPostFields(provider, FeedType.forYou), forYouFieldsBefore);
  });
}
