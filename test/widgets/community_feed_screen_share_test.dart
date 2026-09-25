import 'dart:async';

import 'package:coves_flutter/models/community.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/community_subscription_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/community/community_feed_screen.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/link_sharer.dart';
import 'package:coves_flutter/services/streamable_service.dart';
import 'package:coves_flutter/widgets/share_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/test_mocks.dart';
import '../test_helpers/theme_pump.dart';

/// A `LinkSharer` that records dispatches instead of opening a native sheet.
class RecordingLinkSharer implements LinkSharer {
  final List<String> sharedUrls = [];

  @override
  Future<void> shareLink(
    String url, {
    required Rect sharePositionOrigin,
  }) async {
    sharedUrls.add(url);
  }
}

/// An `AuthProvider` reporting a signed-in viewer, with no secure storage or
/// network behind it.
class SignedInAuthProvider extends AuthProvider {
  @override
  bool get isAuthenticated => true;

  @override
  bool get isLoading => false;

  @override
  String? get did => 'did:plc:viewer999';
}

/// The community app bar shares the community's web link, for a local
/// community, a remote one, and a viewer who is signed out.
void main() {
  // Literals, never produced by the code under test.
  const localCommunityUrl = 'https://coves.social/c/gaming';
  const remoteCommunityUrl = 'https://coves.social/c/comicstrips@lemmy.world';
  const didCommunityUrl = 'https://coves.social/c/did%3Aplc%3Acommunity456';

  const communityDid = 'did:plc:community456';

  late MockCovesApiService mockApiService;
  late RecordingLinkSharer linkSharer;

  setUp(() {
    mockApiService = MockCovesApiService();
    linkSharer = RecordingLinkSharer();
  });

  CommunityView communityView({required String name, String? origin}) {
    return CommunityView(
      did: communityDid,
      name: name,
      origin: origin,
      displayName: name,
    );
  }

  void stubCommunity(CommunityView view) {
    when(
      mockApiService.getCommunity(community: anyNamed('community')),
    ).thenAnswer((_) async => view);
  }

  /// An empty first page with no cursor: the feed never pages on its own and
  /// renders no post cards, so the screen holds exactly one share button.
  void stubEmptyFeed() {
    when(
      mockApiService.getCommunityFeed(
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((_) async => TimelineResponse(feed: const []));
  }

  Widget communityApp(AuthProvider auth) {
    final votes = FakeVoteProvider(auth);
    addTearDown(votes.dispose);
    final subscriptions = FakeSubscriptionProvider(
      authProvider: auth,
      apiService: mockApiService,
    );
    addTearDown(subscriptions.dispose);
    final blocks = BlockProvider(
      apiService: mockApiService,
      authProvider: auth,
    );
    addTearDown(blocks.dispose);

    return MultiProvider(
      providers: [
        Provider<CovesApiService>.value(value: mockApiService),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<VoteProvider>.value(value: votes),
        ChangeNotifierProvider<CommunitySubscriptionProvider>.value(
          value: subscriptions,
        ),
        ChangeNotifierProvider<BlockProvider>.value(value: blocks),
        Provider<StreamableService>(create: (_) => StreamableService()),
        Provider<LinkSharer>.value(value: linkSharer),
      ],
      child: const CommunityFeedScreen(identifier: communityDid),
    );
  }

  /// Pumps the screen until the community and its (empty) feed have landed.
  ///
  /// [auth] defaults to a signed-in viewer; the signed-out case passes its
  /// own.
  Future<void> pumpCommunityFeed(
    WidgetTester tester, {
    AuthProvider? auth,
  }) async {
    final authProvider = auth ?? SignedInAuthProvider();
    addTearDown(authProvider.dispose);

    await pumpUnderAppTheme(tester, communityApp(authProvider));
    await tester.pumpAndSettle();
  }

  Future<void> tapShareButton(WidgetTester tester) async {
    final shareButton = find.byType(ShareButton);
    expect(shareButton, findsOneWidget);

    await tester.tap(shareButton);
    await tester.pumpAndSettle();
  }

  group('loaded community', () {
    testWidgets('shares a local community by its bare name', (tester) async {
      stubCommunity(communityView(name: 'Gaming', origin: 'coves.social'));
      stubEmptyFeed();

      await pumpCommunityFeed(tester);

      await tapShareButton(tester);

      expect(linkSharer.sharedUrls, [localCommunityUrl]);
      expect(find.text("Couldn't create link"), findsNothing);
    });

    testWidgets('shares a remote community as name@origin', (tester) async {
      stubCommunity(communityView(name: 'ComicStrips', origin: 'lemmy.world'));
      stubEmptyFeed();

      await pumpCommunityFeed(tester);

      await tapShareButton(tester);

      expect(linkSharer.sharedUrls, [remoteCommunityUrl]);
    });

    testWidgets('falls back to the DID when the origin is missing', (
      tester,
    ) async {
      stubCommunity(communityView(name: 'Gaming'));
      stubEmptyFeed();

      await pumpCommunityFeed(tester);

      await tapShareButton(tester);

      expect(linkSharer.sharedUrls, [didCommunityUrl]);
    });

    testWidgets('a signed-out viewer can share it', (tester) async {
      stubCommunity(communityView(name: 'Gaming', origin: 'coves.social'));
      stubEmptyFeed();

      await pumpCommunityFeed(tester, auth: FakeAuthProvider());

      await tapShareButton(tester);

      expect(linkSharer.sharedUrls, [localCommunityUrl]);
      expect(find.text("Couldn't create link"), findsNothing);
    });
  });

  group('community that is not loaded', () {
    testWidgets('offers no share button while the community is loading', (
      tester,
    ) async {
      // Never completes: the screen stays in its loading state, and the feed
      // load that follows it never starts.
      final pending = Completer<CommunityView>();
      when(
        mockApiService.getCommunity(community: anyNamed('community')),
      ).thenAnswer((_) => pending.future);

      final auth = SignedInAuthProvider();
      addTearDown(auth.dispose);

      await pumpUnderAppTheme(tester, communityApp(auth));
      // The load starts in a post-frame callback; the second frame renders
      // the loading state it produced.
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // The loading and error states swap the collapsing header for a plain
      // app bar that carries no actions at all.
      expect(find.byType(ShareButton), findsNothing);
      expect(linkSharer.sharedUrls, isEmpty);
    });

    testWidgets('offers no share button when the community failed to load', (
      tester,
    ) async {
      when(
        mockApiService.getCommunity(community: anyNamed('community')),
      ).thenThrow(NotFoundException('Community not found'));
      stubEmptyFeed();

      await pumpCommunityFeed(tester);

      expect(find.text('Community not found'), findsOneWidget);

      expect(find.byType(ShareButton), findsNothing);
      expect(linkSharer.sharedUrls, isEmpty);
    });

    testWidgets('offers no share button on the frame before the load starts', (
      tester,
    ) async {
      stubCommunity(communityView(name: 'Gaming', origin: 'coves.social'));
      stubEmptyFeed();

      final auth = SignedInAuthProvider();
      addTearDown(auth.dispose);

      // The first frame is built before the post-frame callback sets the
      // loading flag, so the collapsing header renders with no community.
      await pumpUnderAppTheme(tester, communityApp(auth));

      // The header carries no share button until the community is known:
      // guessing a link from the route identifier is not an option, and a
      // button that reports "Couldn't create link" is a dead control.
      expect(find.byType(ShareButton), findsNothing);
      expect(linkSharer.sharedUrls, isEmpty);

      await tester.pumpAndSettle();
    });
  });
}
