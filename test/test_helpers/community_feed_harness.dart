// Shared harness for CommunityFeedScreen widget tests: the provider tree the
// screen needs, wired to a MockCovesApiService, plus community and post
// fixtures.

import 'package:coves_flutter/models/community.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/community_subscription_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/community/community_feed_screen.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/post_change_broadcast.dart';
import 'package:coves_flutter/services/streamable_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'fake_providers.dart';
import 'test_mocks.dart';
import 'theme_pump.dart';

const String communityFeedTestDid = 'did:plc:community';
const String communityFeedTestHandle = 'testcove';

CommunityView buildFeedTestCommunity() {
  return CommunityView(
    did: communityFeedTestDid,
    name: communityFeedTestHandle,
    displayName: 'Test Cove',
  );
}

FeedViewPost buildFeedTestPost({required String rkey, required String title}) {
  return FeedViewPost(
    post: PostView(
      uri: 'at://did:plc:author/social.coves.community.post/$rkey',
      cid: 'cid-$rkey',
      rkey: rkey,
      author: AuthorView(did: 'did:plc:author', handle: 'test.user'),
      community: CommunityRef(
        did: communityFeedTestDid,
        name: communityFeedTestHandle,
      ),
      createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
      indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
      record: PostRecord(title: title, content: 'Body'),
      stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
    ),
  );
}

/// Pumps the screen for [communityFeedTestDid] signed out, without settling,
/// so the caller decides when requests land.
Future<void> pumpCommunityFeedScreen(
  WidgetTester tester,
  MockCovesApiService apiService,
) async {
  final auth = FakeAuthProvider();
  final votes = FakeVoteProvider(auth);
  addTearDown(votes.dispose);
  final subscriptions = FakeSubscriptionProvider(
    authProvider: auth,
    apiService: apiService,
  );
  addTearDown(subscriptions.dispose);
  final blocks = BlockProvider(apiService: apiService, authProvider: auth);
  addTearDown(blocks.dispose);

  await pumpUnderAppTheme(
    tester,
    MultiProvider(
      providers: [
        Provider<CovesApiService>.value(value: apiService),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<VoteProvider>.value(value: votes),
        ChangeNotifierProvider<CommunitySubscriptionProvider>.value(
          value: subscriptions,
        ),
        ChangeNotifierProvider<BlockProvider>.value(value: blocks),
        Provider<StreamableService>(create: (_) => StreamableService()),
        Provider<PostChangeBroadcast>(create: (_) => PostChangeBroadcast()),
        viewerAuthorityRegistration(auth: auth, apiService: apiService),
        unloadedMultiFeedProvider(auth: auth, apiService: apiService),
      ],
      child: const CommunityFeedScreen(identifier: communityFeedTestDid),
    ),
  );
  // Runs the post-frame callback that starts the community and feed loads.
  await tester.pump();
}
