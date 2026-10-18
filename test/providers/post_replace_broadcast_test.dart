import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/providers/multi_feed_provider.dart';
import 'package:coves_flutter/providers/user_profile_provider.dart';
import 'package:coves_flutter/services/post_change_broadcast.dart';
import 'package:coves_flutter/services/profile_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/test_mocks.dart';

const _postPrefix = 'at://did:plc:me/social.coves.community.post/';

PostView _post(String id, {String title = 'Original', int score = 1}) {
  return PostView(
    uri: '$_postPrefix$id',
    cid: 'cid-$id',
    rkey: id,
    author: AuthorView(did: 'did:plc:me', handle: 'me.test'),
    community: CommunityRef(did: 'did:plc:community', name: 'test'),
    createdAt: DateTime.utc(2025),
    indexedAt: DateTime.utc(2025),
    record: PostRecord(title: title, content: 'Body'),
    stats: PostStats(
      upvotes: score,
      downvotes: 0,
      score: score,
      commentCount: 0,
    ),
  );
}

List<String> _uris(List<FeedViewPost> posts) =>
    posts.map((item) => item.post.uri).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAuthProvider auth;
  late MockCovesApiService api;
  late MockCommentService comments;
  late FakeVoteProvider votes;
  late FakeSubscriptionProvider subscriptions;
  late ProfileCache cache;
  late PostChangeBroadcast broadcast;
  late MultiFeedProvider feeds;
  late UserProfileProvider profile;
  late FeedViewPost a;
  late FeedViewPost discoverP;
  late FeedViewPost b;
  late FeedViewPost forYouP;
  late FeedViewPost c;
  late FeedViewPost profileP;
  late FeedViewPost d;
  var profileDisposed = false;

  setUp(() async {
    auth = FakeAuthProvider(signedInDid: 'did:plc:me');
    api = MockCovesApiService();
    comments = MockCommentService();
    votes = FakeVoteProvider(auth);
    subscriptions = FakeSubscriptionProvider(
      authProvider: auth,
      apiService: api,
    );
    cache = ProfileCache(auth);
    broadcast = PostChangeBroadcast();
    profileDisposed = false;

    a = FeedViewPost(post: _post('a'));
    discoverP = FeedViewPost(
      post: _post('p'),
      reason: FeedReason(type: 'discover', data: {'source': 'discover'}),
    );
    b = FeedViewPost(post: _post('b'));
    forYouP = FeedViewPost(
      post: _post('p'),
      reason: FeedReason(type: 'forYou', data: {'source': 'forYou'}),
    );
    c = FeedViewPost(post: _post('c'));
    profileP = FeedViewPost(
      post: _post('p'),
      reason: FeedReason(type: 'profile', data: {'source': 'profile'}),
    );
    d = FeedViewPost(post: _post('d'));

    when(
      api.getDiscover(
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((_) async => TimelineResponse(feed: [a, discoverP, b]));
    when(
      api.getTimeline(
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((_) async => TimelineResponse(feed: [forYouP, c]));
    when(api.getProfile(actor: anyNamed('actor'))).thenAnswer(
      (_) async => UserProfile(did: 'did:plc:me', handle: 'me.test'),
    );
    when(
      api.getAuthorPosts(
        actor: anyNamed('actor'),
        filter: anyNamed('filter'),
        community: anyNamed('community'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((_) async => TimelineResponse(feed: [profileP, d]));

    feeds = MultiFeedProvider(
      auth,
      apiService: api,
      voteProvider: votes,
      subscriptionProvider: subscriptions,
      postChangeBroadcast: broadcast,
      sessionKeyOf: unchangingSessionKey,
    );
    profile = UserProfileProvider(
      auth,
      apiService: api,
      commentService: comments,
      profileCache: cache,
      postChangeBroadcast: broadcast,
      sessionKeyOf: unchangingSessionKey,
    );
    await feeds.loadFeed(FeedType.discover, refresh: true);
    await feeds.loadFeed(FeedType.forYou, refresh: true);
    await profile.loadProfile('did:plc:me');
    await profile.loadPosts(refresh: true);
    expect(_uris(feeds.getState(FeedType.discover).posts), [
      'at://did:plc:me/social.coves.community.post/a',
      'at://did:plc:me/social.coves.community.post/p',
      'at://did:plc:me/social.coves.community.post/b',
    ]);
    expect(_uris(profile.postsState.posts), [
      'at://did:plc:me/social.coves.community.post/p',
      'at://did:plc:me/social.coves.community.post/d',
    ]);
  });

  tearDown(() {
    if (!profileDisposed) {
      profile.dispose();
    }
    feeds.dispose();
    cache.dispose();
    subscriptions.dispose();
    votes.dispose();
    auth.dispose();
  });

  test('B7 replace swaps every loaded copy in place preserving reason and '
      'neighbors', () {
    final replacement = _post('p', title: 'Updated title', score: 7);
    var feedNotifications = 0;
    feeds.addListener(() => feedNotifications++);

    broadcast.replacePost(replacement);

    expect(feedNotifications, 1);
    final discover = feeds.getState(FeedType.discover).posts;
    final forYou = feeds.getState(FeedType.forYou).posts;
    final author = profile.postsState.posts;
    expect(_uris(discover), [
      'at://did:plc:me/social.coves.community.post/a',
      'at://did:plc:me/social.coves.community.post/p',
      'at://did:plc:me/social.coves.community.post/b',
    ]);
    expect(_uris(forYou), [
      'at://did:plc:me/social.coves.community.post/p',
      'at://did:plc:me/social.coves.community.post/c',
    ]);
    expect(_uris(author), [
      'at://did:plc:me/social.coves.community.post/p',
      'at://did:plc:me/social.coves.community.post/d',
    ]);
    expect(identical(discover[1].post, replacement), isTrue);
    expect(identical(forYou[0].post, replacement), isTrue);
    expect(identical(author[0].post, replacement), isTrue);
    expect(discover[1].post.record?.title, 'Updated title');
    expect(forYou[0].post.stats.score, 7);
    expect(author[0].post.record?.title, 'Updated title');
    expect(identical(discover[1].reason, discoverP.reason), isTrue);
    expect(identical(forYou[0].reason, forYouP.reason), isTrue);
    expect(identical(author[0].reason, profileP.reason), isTrue);
    expect(identical(discover[0], a), isTrue);
    expect(identical(discover[2], b), isTrue);
    expect(identical(forYou[1], c), isTrue);
    expect(identical(author[1], d), isTrue);
  });

  test('B7 a feed without the post does not stop a later feed that holds '
      'it from replacing', () async {
    when(
      api.getDiscover(
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((_) async => TimelineResponse(feed: [a, b]));
    await feeds.loadFeed(FeedType.discover, refresh: true);
    expect(_uris(feeds.getState(FeedType.discover).posts), [
      'at://did:plc:me/social.coves.community.post/a',
      'at://did:plc:me/social.coves.community.post/b',
    ]);
    var feedNotifications = 0;
    feeds.addListener(() => feedNotifications++);
    final replacement = _post('p', title: 'Updated title', score: 7);

    broadcast.replacePost(replacement);

    final forYou = feeds.getState(FeedType.forYou).posts;
    expect(identical(forYou[0].post, replacement), isTrue);
    expect(identical(forYou[0].reason, forYouP.reason), isTrue);
    expect(identical(forYou[1], c), isTrue);
    expect(feedNotifications, 1);
  });

  test('B7 disposed profile is skipped while live home feeds replace', () {
    var profileNotifications = 0;
    profile
      ..addListener(() => profileNotifications++)
      ..dispose();
    profileDisposed = true;
    final replacement = _post('p', title: 'Updated title', score: 7);

    expect(() => broadcast.replacePost(replacement), returnsNormally);
    expect(profileNotifications, 0);
    expect(
      identical(feeds.getState(FeedType.discover).posts[1].post, replacement),
      isTrue,
    );
    expect(
      identical(feeds.getState(FeedType.forYou).posts[0].post, replacement),
      isTrue,
    );
  });

  test('B7 replacing an unloaded uri notifies neither owner', () {
    var feedNotifications = 0;
    var profileNotifications = 0;
    feeds.addListener(() => feedNotifications++);
    profile.addListener(() => profileNotifications++);

    broadcast.replacePost(_post('not-loaded', title: 'Updated title'));

    expect(feedNotifications, 0);
    expect(profileNotifications, 0);
    expect(
      identical(feeds.getState(FeedType.discover).posts[1], discoverP),
      isTrue,
    );
    expect(identical(profile.postsState.posts[0], profileP), isTrue);

    // A subsequent matching event must still reach both owners.
    broadcast.replacePost(_post('p', title: 'Visible update'));
    expect(
      feeds.getState(FeedType.discover).posts[1].post.record?.title,
      'Visible update',
    );
    expect(profile.postsState.posts[0].post.record?.title, 'Visible update');
  });
}
