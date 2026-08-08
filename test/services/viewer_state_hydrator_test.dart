// Direct unit tests for ViewerStateHydrator's two gates.
//
// Every method has the same two guards - "is anyone signed in?" and "is the
// target provider wired?" - and dropping either from any one method is a
// silent leak: a signed-out session would adopt the previous account's votes
// and subscriptions, or a null provider would throw mid-fetch.
//
// The call-site tests cover a few of these combinations incidentally. This
// file covers the whole grid on purpose: 7 methods x {signed in, signed out}
// x {provider wired, provider null}.
//
// Asserted with verify / verifyZeroInteractions on mocks, because the
// invariant is about what the hydrator HANDS OVER. What VoteProvider then
// decides to do with a snapshot (adopt it, reconcile it, protect an
// optimistic vote) is VoteProvider's contract and is tested there.

import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/community.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/community_subscription_provider.dart';
import 'package:coves_flutter/services/viewer_state_hydrator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/test_mocks.dart';

const String postUri = 'at://did:plc:author/social.coves.community.post/p1';
const String commentUri = 'at://did:plc:author/social.coves.comment/c1';
const String replyUri = 'at://did:plc:author/social.coves.comment/c2';
const String communityDid = 'did:plc:community';
const String voteUri = 'at://did:plc:me/social.coves.feed.vote/v1';

/// A subscription provider that records the seeds handed to it.
///
/// There is no generated mock for CommunitySubscriptionProvider, and its
/// real constructor wants an API client and an auth listener, so this
/// hand-rolled double keeps the test free of both.
class _RecordingSubscriptionProvider implements CommunitySubscriptionProvider {
  final List<({String did, bool subscribed})> seeds = [];

  @override
  void setInitialSubscriptionState({
    required String communityDid,
    required bool isSubscribed,
  }) {
    seeds.add((did: communityDid, subscribed: isSubscribed));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PostView buildPost() {
  return PostView(
    uri: postUri,
    cid: 'cid-p1',
    rkey: 'p1',
    author: AuthorView(did: 'did:plc:author', handle: 'test.user'),
    community: CommunityRef(
      did: communityDid,
      name: 'testcove',
      viewer: CommunityRefViewerState(subscribed: true),
    ),
    createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
    indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
    record: const PostRecord(title: 'T', content: 'B'),
    stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
    viewer: ViewerState(vote: 'up', voteUri: voteUri),
  );
}

CommentView buildComment(String uri) {
  return CommentView(
    uri: uri,
    cid: 'cid-$uri',
    record: const CommentRecord(content: 'body'),
    createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
    indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
    author: AuthorView(did: 'did:plc:author', handle: 'test.user'),
    post: CommentRef(uri: postUri, cid: 'post-cid'),
    stats: const CommentStats(score: 1, upvotes: 1),
    viewer: CommentViewerState(vote: 'up', voteUri: voteUri),
  );
}

CommunityView buildCommunity() {
  return CommunityView(
    did: communityDid,
    name: 'testcove',
    viewer: CommunityViewerState(subscribed: true),
  );
}

void main() {
  late MockAuthProvider mockAuthProvider;
  late MockVoteProvider mockVoteProvider;
  late _RecordingSubscriptionProvider subscriptions;

  setUp(() {
    mockAuthProvider = MockAuthProvider();
    mockVoteProvider = MockVoteProvider();
    subscriptions = _RecordingSubscriptionProvider();
  });

  ViewerStateHydrator buildHydrator({
    required bool authenticated,
    bool wired = true,
  }) {
    when(mockAuthProvider.isAuthenticated).thenReturn(authenticated);
    return ViewerStateHydrator(
      authProvider: mockAuthProvider,
      voteProvider: wired ? mockVoteProvider : null,
      subscriptionProvider: wired ? subscriptions : null,
    );
  }

  final feed = [FeedViewPost(post: buildPost())];
  final comments = [buildComment(commentUri)];
  final tree = [
    ThreadViewComment(
      comment: buildComment(commentUri),
      replies: [ThreadViewComment(comment: buildComment(replyUri))],
    ),
  ];
  final communities = [buildCommunity()];

  /// Every method, keyed by name, so the grid below stays one line each.
  final invocations = <String, void Function(ViewerStateHydrator)>{
    'hydrateFeed': (h) => h.hydrateFeed(feed),
    'hydrateFeedVotesOnly': (h) => h.hydrateFeedVotesOnly(feed),
    'hydratePost': (h) => h.hydratePost(buildPost()),
    'hydrateComments': (h) => h.hydrateComments(comments),
    'hydrateCommentTree': (h) => h.hydrateCommentTree(tree),
    'hydrateCommunityListSubscriptions': (h) =>
        h.hydrateCommunityListSubscriptions(communities),
    'hydrateCommunitySubscription': (h) =>
        h.hydrateCommunitySubscription(buildCommunity()),
  };

  group('signed out: every method hands over nothing', () {
    for (final entry in invocations.entries) {
      test('${entry.key} touches neither provider', () {
        entry.value(buildHydrator(authenticated: false));

        // A leak here is another account's viewer state landing in a
        // signed-out session.
        verifyZeroInteractions(mockVoteProvider);
        expect(subscriptions.seeds, isEmpty);
      });
    }
  });

  group('provider absent: every method is a no-op rather than a crash', () {
    for (final entry in invocations.entries) {
      test('${entry.key} does not throw with both providers null', () {
        final hydrator = buildHydrator(authenticated: true, wired: false);

        expect(() => entry.value(hydrator), returnsNormally);
        verifyZeroInteractions(mockVoteProvider);
        expect(subscriptions.seeds, isEmpty);
      });
    }
  });

  group('signed in and wired: the positive controls', () {
    test('hydrateFeed hands over both the vote and the subscription', () {
      buildHydrator(authenticated: true).hydrateFeed(feed);

      verify(
        mockVoteProvider.applyServerVoteState(
          postUri: postUri,
          voteDirection: 'up',
          voteUri: voteUri,
        ),
      ).called(1);
      expect(subscriptions.seeds, [(did: communityDid, subscribed: true)]);
    });

    test('hydrateFeedVotesOnly hands over the vote and NOT the '
        'subscription', () {
      buildHydrator(authenticated: true).hydrateFeedVotesOnly(feed);

      verify(
        mockVoteProvider.applyServerVoteState(
          postUri: postUri,
          voteDirection: 'up',
          voteUri: voteUri,
        ),
      ).called(1);
      // Divergence D1, asserted at the source rather than through a caller.
      expect(subscriptions.seeds, isEmpty);
    });

    test('hydratePost hands over the single post vote', () {
      buildHydrator(authenticated: true).hydratePost(buildPost());

      verify(
        mockVoteProvider.applyServerVoteState(
          postUri: postUri,
          voteDirection: 'up',
          voteUri: voteUri,
        ),
      ).called(1);
      expect(subscriptions.seeds, isEmpty);
    });

    test('hydrateComments hands over each flat comment vote', () {
      buildHydrator(authenticated: true).hydrateComments(comments);

      verify(
        mockVoteProvider.applyServerVoteState(
          postUri: commentUri,
          voteDirection: 'up',
          voteUri: voteUri,
        ),
      ).called(1);
    });

    test('hydrateCommentTree recurses into replies', () {
      buildHydrator(authenticated: true).hydrateCommentTree(tree);

      verify(
        mockVoteProvider.applyServerVoteState(
          postUri: commentUri,
          voteDirection: 'up',
          voteUri: voteUri,
        ),
      ).called(1);
      verify(
        mockVoteProvider.applyServerVoteState(
          postUri: replyUri,
          voteDirection: 'up',
          voteUri: voteUri,
        ),
      ).called(1);
    });

    test('hydrateCommunityListSubscriptions seeds each community', () {
      buildHydrator(
        authenticated: true,
      ).hydrateCommunityListSubscriptions(communities);

      expect(subscriptions.seeds, [(did: communityDid, subscribed: true)]);
      verifyZeroInteractions(mockVoteProvider);
    });

    test('hydrateCommunitySubscription seeds the single community', () {
      buildHydrator(
        authenticated: true,
      ).hydrateCommunitySubscription(buildCommunity());

      expect(subscriptions.seeds, [(did: communityDid, subscribed: true)]);
      verifyZeroInteractions(mockVoteProvider);
    });
  });

  group('the null-direction contract', () {
    test('a null vote direction is still handed over, not filtered out', () {
      // This is how a vote removed on another device gets cleared. A guard
      // that skipped nulls would strand the local vote forever.
      final post = PostView(
        uri: postUri,
        cid: 'cid-p1',
        rkey: 'p1',
        author: AuthorView(did: 'did:plc:author', handle: 'test.user'),
        community: CommunityRef(did: communityDid, name: 'testcove'),
        createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
        indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
        record: const PostRecord(title: 'T', content: 'B'),
        stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
      );

      buildHydrator(authenticated: true).hydratePost(post);

      verify(
        mockVoteProvider.applyServerVoteState(
          postUri: postUri,
          voteDirection: argThat(isNull, named: 'voteDirection'),
          voteUri: argThat(isNull, named: 'voteUri'),
        ),
      ).called(1);
    });
  });
}
