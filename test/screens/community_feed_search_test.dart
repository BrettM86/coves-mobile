// OUTER acceptance test for in-community post search.
//
// Observes the feature from outside the screen: the user picks a sort,
// opens search, submits a query, and the feed is replaced by the search
// results without the community feed being re-fetched. Closing search
// restores the feed at the sort that was selected before it opened.
//
// Everything here is pinned through the API calls the screen makes and the
// post titles it renders, plus three ValueKeys for the controls that have
// no stable text of their own.

import 'dart:convert';

import 'package:coves_flutter/models/community.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/community_subscription_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/community/community_feed_screen.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/streamable_service.dart';
import 'package:coves_flutter/widgets/icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/test_mocks.dart';
import '../test_helpers/theme_pump.dart';

const String communityDid = 'did:plc:community';
const String communityHandle = 'testcove';

/// The search button, field and close button carry no stable text, so the
/// acceptance test addresses them by key.
const ValueKey<String> searchButtonKey = ValueKey<String>(
  'community_feed_search_button',
);
const ValueKey<String> searchFieldKey = ValueKey<String>(
  'community_feed_search_field',
);
const ValueKey<String> searchCloseKey = ValueKey<String>(
  'community_feed_search_close',
);

CommunityView buildCommunity() {
  return CommunityView(
    did: communityDid,
    name: communityHandle,
    displayName: 'Test Cove',
  );
}

FeedViewPost buildFeedPost({required String rkey, required String title}) {
  return FeedViewPost(
    post: PostView(
      uri: 'at://did:plc:author/social.coves.community.post/$rkey',
      cid: 'cid-$rkey',
      rkey: rkey,
      author: AuthorView(did: 'did:plc:author', handle: 'test.user'),
      community: CommunityRef(did: communityDid, name: communityHandle),
      createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
      indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
      record: PostRecord(title: title, content: 'Body'),
      stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
    ),
  );
}

/// A surface tall enough that both feed posts are built and laid out at
/// once, so `findsNothing` on a title means the post is gone rather than
/// merely scrolled out of the sliver's build range.
void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  late MockCovesApiService mockApiService;

  setUp(() {
    mockApiService = MockCovesApiService();
  });

  Future<void> pumpFeedScreen(WidgetTester tester) async {
    final auth = FakeAuthProvider();
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

    await pumpUnderAppTheme(
      tester,
      MultiProvider(
        providers: [
          Provider<CovesApiService>.value(value: mockApiService),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<VoteProvider>.value(value: votes),
          ChangeNotifierProvider<CommunitySubscriptionProvider>.value(
            value: subscriptions,
          ),
          ChangeNotifierProvider<BlockProvider>.value(value: blocks),
          Provider<StreamableService>(create: (_) => StreamableService()),
        ],
        child: const CommunityFeedScreen(identifier: communityDid),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The community and its two-post feed. The feed page carries no cursor,
  /// so the screen never pages past it on its own.
  void stubCommunityAndFeed() {
    when(mockApiService.getCommunity(community: anyNamed('community')))
        .thenAnswer((_) async => buildCommunity());

    when(
      mockApiService.getCommunityFeed(
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer(
      (_) async => TimelineResponse(
        feed: [
          buildFeedPost(rkey: 'p1', title: 'First community post'),
          buildFeedPost(rkey: 'p2', title: 'Second community post'),
        ],
      ),
    );
  }

  testWidgets('searching within a community replaces the feed with the '
      'matching posts, and closing search restores the feed at the sort '
      'that was active', (tester) async {
    useTallSurface(tester);

    stubCommunityAndFeed();

    when(
      mockApiService.searchPosts(
        q: 'linux',
        community: communityDid,
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        // `cursor` is left off: the mock passes its own null default
        // through, so this still matches only a first-page search.
      ),
    ).thenAnswer(
      (_) async => TimelineResponse(
        feed: [buildFeedPost(rkey: 's1', title: 'Linux kernel flaw')],
        cursor: 'c1',
      ),
    );

    // The second page of results: the screen keeps paging while the loaded
    // posts do not fill the viewport, and a strict mock has to answer.
    when(
      mockApiService.searchPosts(
        q: anyNamed('q'),
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: 'c1',
      ),
    ).thenAnswer((_) async => TimelineResponse(feed: const []));

    await pumpFeedScreen(tester);

    expect(find.text('First community post'), findsOneWidget);
    expect(find.text('Second community post'), findsOneWidget);

    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();

    // Everything fetched before the search is accounted for here, so the
    // verifyNever below can only see calls the search itself caused.
    verify(
      mockApiService.getCommunityFeed(
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).called(greaterThan(0));

    await tester.tap(find.byKey(searchButtonKey));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(searchFieldKey), 'linux');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('Linux kernel flaw'), findsOneWidget);
    expect(find.text('First community post'), findsNothing);
    expect(find.text('Second community post'), findsNothing);

    verifyNever(
      mockApiService.getCommunityFeed(
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    );

    await tester.tap(find.byKey(searchCloseKey));
    await tester.pumpAndSettle();

    expect(find.text('First community post'), findsOneWidget);
    expect(find.text('Second community post'), findsOneWidget);
    expect(find.text('Linux kernel flaw'), findsNothing);

    verify(
      mockApiService.getCommunityFeed(
        community: communityDid,
        sort: 'new',
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        // Omitted for the same reason: null is the only cursor that
        // matches a reload from the top.
      ),
    ).called(1);
  });

  testWidgets('the sort header carries a search button to the right of the '
      'Top chip, with the chips still shown and no field open', (tester) async {
    stubCommunityAndFeed();

    await pumpFeedScreen(tester);

    expect(find.byKey(searchButtonKey), findsOneWidget);
    expect(find.text('Hot'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    expect(find.text('Top'), findsOneWidget);
    expect(find.byKey(searchFieldKey), findsNothing);

    // To the right of the last chip, not somewhere else in the header.
    expect(
      tester.getTopLeft(find.byKey(searchButtonKey)).dx,
      greaterThan(tester.getTopRight(find.text('Top')).dx),
    );

    // The Lucide glyph, not a Material icon.
    expect(
      find.descendant(
        of: find.byKey(searchButtonKey),
        matching: find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.iconName == 'search',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('tapping the search button swaps the chips for a focused '
      'field and a close button, and calls nothing', (tester) async {
    stubCommunityAndFeed();

    await pumpFeedScreen(tester);

    // Account for the initial load so the check below only sees what the
    // tap caused.
    verify(
      mockApiService.getCommunityFeed(
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).called(greaterThan(0));

    await tester.tap(find.byKey(searchButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('Hot'), findsNothing);
    expect(find.text('New'), findsNothing);
    expect(find.text('Top'), findsNothing);
    expect(find.byKey(searchButtonKey), findsNothing);

    expect(find.byKey(searchFieldKey), findsOneWidget);
    expect(find.byKey(searchCloseKey), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(searchFieldKey),
        matching: find.text('Search posts in this community'),
      ),
      findsOneWidget,
    );

    final editable = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(searchFieldKey),
        matching: find.byType(EditableText),
      ),
    );
    expect(editable.focusNode.hasFocus, isTrue);

    // Opening search is not itself a query.
    verifyNever(
      mockApiService.searchPosts(
        q: anyNamed('q'),
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    );
    verifyNever(
      mockApiService.getCommunityFeed(
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    );
  });

  /// The field's live text, for asserting what the user still sees.
  EditableText searchField(WidgetTester tester) {
    return tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(searchFieldKey),
        matching: find.byType(EditableText),
      ),
    );
  }

  Future<void> openSearchAndSubmit(WidgetTester tester, String text) async {
    await tester.tap(find.byKey(searchButtonKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(searchFieldKey), text);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
  }

  testWidgets('submitting a query searches this community with the trimmed '
      'text and shows the results in place of the feed', (tester) async {
    useTallSurface(tester);
    stubCommunityAndFeed();

    when(
      mockApiService.searchPosts(
        q: 'linux',
        community: communityDid,
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
      ),
    ).thenAnswer(
      (_) async => TimelineResponse(
        feed: [buildFeedPost(rkey: 's1', title: 'Linux kernel flaw')],
      ),
    );

    await pumpFeedScreen(tester);
    await openSearchAndSubmit(tester, '  linux  ');

    verify(
      mockApiService.searchPosts(
        q: 'linux',
        community: communityDid,
        // A plain search sorts by relevance. Redundant against the API's
        // default, and pinned here so that default cannot drift unnoticed.
        // ignore: avoid_redundant_argument_values
        sort: 'relevance',
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
      ),
    ).called(1);

    expect(find.text('Linux kernel flaw'), findsOneWidget);
    expect(find.text('First community post'), findsNothing);
    expect(find.text('Second community post'), findsNothing);

    // Search stays open on its results, with what the user typed untouched.
    expect(find.byKey(searchFieldKey), findsOneWidget);
    expect(searchField(tester).controller.text, '  linux  ');
  });

  testWidgets('submitting a blank query searches nothing and leaves the '
      'feed and the open field alone', (tester) async {
    useTallSurface(tester);
    stubCommunityAndFeed();

    await pumpFeedScreen(tester);

    // Account for the initial load so the check below only sees what the
    // submit caused.
    verify(
      mockApiService.getCommunityFeed(
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).called(greaterThan(0));

    await openSearchAndSubmit(tester, '   ');

    verifyNever(
      mockApiService.searchPosts(
        q: anyNamed('q'),
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    );
    verifyNever(
      mockApiService.getCommunityFeed(
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    );

    expect(find.text('First community post'), findsOneWidget);
    expect(find.text('Second community post'), findsOneWidget);
    expect(find.byKey(searchFieldKey), findsOneWidget);
    expect(searchField(tester).controller.text, '   ');
  });

  /// Drags the feed to its bottom, where [PaginationScrollListener] asks
  /// for the next page.
  Future<void> dragToBottom(WidgetTester tester) async {
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
    await tester.pumpAndSettle();
  }

  /// Page one of a search for 'linux', then page two, then nothing.
  void stubTwoSearchPages({required List<FeedViewPost> firstPage}) {
    when(
      mockApiService.searchPosts(
        q: 'linux',
        community: communityDid,
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
      ),
    ).thenAnswer((_) async => TimelineResponse(feed: firstPage, cursor: 'c1'));

    when(
      mockApiService.searchPosts(
        q: 'linux',
        community: communityDid,
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: 'c1',
      ),
    ).thenAnswer(
      (_) async => TimelineResponse(
        feed: [buildFeedPost(rkey: 's2', title: 'Second linux match')],
      ),
    );
  }

  testWidgets('paging an active search asks for the next page of results, '
      'not the community feed', (tester) async {
    useTallSurface(tester);
    stubCommunityAndFeed();
    stubTwoSearchPages(
      firstPage: [buildFeedPost(rkey: 's1', title: 'Linux kernel flaw')],
    );

    await pumpFeedScreen(tester);

    // Account for the initial load so the check below only sees calls made
    // once the search was running.
    verify(
      mockApiService.getCommunityFeed(
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).called(greaterThan(0));

    await openSearchAndSubmit(tester, 'linux');
    await dragToBottom(tester);

    expect(find.text('Linux kernel flaw'), findsOneWidget);
    expect(find.text('Second linux match'), findsOneWidget);

    verify(
      mockApiService.searchPosts(
        q: 'linux',
        community: communityDid,
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: 'c1',
      ),
    ).called(1);

    verifyNever(
      mockApiService.getCommunityFeed(
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    );
  });

  testWidgets('the next page uses the submitted query, not whatever the '
      'field has been edited to since', (tester) async {
    // Deliberately the default surface with a full first page: the results
    // overflow it, so page two can only be asked for after the drag - the
    // viewport-fill check must not fetch it before the edit below.
    stubCommunityAndFeed();
    stubTwoSearchPages(
      firstPage: [
        for (var i = 1; i <= 6; i++)
          buildFeedPost(rkey: 'r$i', title: 'Linux result $i'),
      ],
    );

    await pumpFeedScreen(tester);
    await openSearchAndSubmit(tester, 'linux');

    // The premise of this test: page two is still unfetched.
    verifyNever(
      mockApiService.searchPosts(
        q: anyNamed('q'),
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: 'c1',
      ),
    );

    // The user retypes but never submits.
    await tester.enterText(find.byKey(searchFieldKey), 'kernel');
    await tester.pumpAndSettle();
    expect(searchField(tester).controller.text, 'kernel');

    await dragToBottom(tester);

    verify(
      mockApiService.searchPosts(
        q: 'linux',
        community: communityDid,
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: 'c1',
      ),
    ).called(1);

    verifyNever(
      mockApiService.searchPosts(
        q: 'kernel',
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    );

    expect(find.text('Second linux match'), findsOneWidget);
  });

  testWidgets('a search that matches nothing says so in its own words', (
    tester,
  ) async {
    useTallSurface(tester);
    stubCommunityAndFeed();

    when(
      mockApiService.searchPosts(
        q: 'zzz',
        community: communityDid,
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
      ),
    ).thenAnswer((_) async => TimelineResponse(feed: const []));

    await pumpFeedScreen(tester);
    await openSearchAndSubmit(tester, 'zzz');

    expect(find.text('No posts match'), findsOneWidget);
    // The community's own empty state would be a lie here: the community
    // has posts, this query has no matches.
    expect(find.text('No posts yet'), findsNothing);
    expect(find.text('First community post'), findsNothing);
    expect(find.text('Second community post'), findsNothing);
  });

  testWidgets('a failed search shows the mapped error, and its retry '
      'searches again rather than reloading the feed', (tester) async {
    useTallSurface(tester);
    stubCommunityAndFeed();

    var searchCalls = 0;
    when(
      mockApiService.searchPosts(
        q: 'linux',
        community: communityDid,
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
      ),
    ).thenAnswer((_) async {
      searchCalls++;
      if (searchCalls == 1) {
        throw NotFoundException('community not found');
      }
      return TimelineResponse(
        feed: [buildFeedPost(rkey: 's1', title: 'Linux kernel flaw')],
      );
    });

    await pumpFeedScreen(tester);

    // Account for the initial load so the check below only sees calls made
    // once the search was running.
    verify(
      mockApiService.getCommunityFeed(
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).called(greaterThan(0));

    await openSearchAndSubmit(tester, 'linux');

    expect(
      find.text('Content not found. It may have been removed.'),
      findsOneWidget,
    );
    expect(find.text('First community post'), findsNothing);
    expect(find.text('Second community post'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(searchCalls, 2);
    verify(
      mockApiService.searchPosts(
        q: 'linux',
        community: communityDid,
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
      ),
    ).called(2);
    verifyNever(
      mockApiService.getCommunityFeed(
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    );

    expect(find.text('Linux kernel flaw'), findsOneWidget);
  });

  /// The pinned sort header that [finder] sits inside, as a sliver.
  RenderSliver pinnedHeaderAround(WidgetTester tester, Finder finder) {
    final header = find.ancestor(
      of: finder,
      matching: find.byType(SliverPersistentHeader),
    );
    expect(header, findsOneWidget);
    return tester.renderObject<RenderSliver>(header);
  }

  testWidgets('closing search restores the chips, the previous sort and a '
      'clean field', (tester) async {
    useTallSurface(tester);
    stubCommunityAndFeed();

    when(
      mockApiService.searchPosts(
        q: 'linux',
        community: communityDid,
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
      ),
    ).thenAnswer(
      (_) async => TimelineResponse(
        feed: [buildFeedPost(rkey: 's1', title: 'Linux kernel flaw')],
      ),
    );

    await pumpFeedScreen(tester);

    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();

    await openSearchAndSubmit(tester, 'linux');
    expect(find.text('Linux kernel flaw'), findsOneWidget);

    // Everything fetched before the close is accounted for here, so the
    // count below is the reload the close itself caused.
    verify(
      mockApiService.getCommunityFeed(
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).called(greaterThan(0));

    await tester.tap(find.byKey(searchCloseKey));
    await tester.pumpAndSettle();

    // The header is back to browsing the community.
    expect(find.byKey(searchFieldKey), findsNothing);
    expect(find.byKey(searchButtonKey), findsOneWidget);
    expect(find.text('Hot'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    expect(find.text('Top'), findsOneWidget);

    // Reloaded at the sort that was chosen before search opened.
    verify(
      mockApiService.getCommunityFeed(
        community: communityDid,
        sort: 'new',
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
      ),
    ).called(1);

    expect(find.text('First community post'), findsOneWidget);
    expect(find.text('Second community post'), findsOneWidget);
    expect(find.text('Linux kernel flaw'), findsNothing);

    // ...and New is still the chip that looks chosen.
    expect(
      tester.widget<Text>(find.text('New')).style?.fontWeight,
      FontWeight.w600,
    );
    expect(
      tester.widget<Text>(find.text('Hot')).style?.fontWeight,
      FontWeight.normal,
    );

    // Nothing is left holding the keyboard.
    expect(
      FocusManager.instance.primaryFocus?.context?.widget,
      isNot(isA<EditableText>()),
    );

    // Reopening starts from empty, not from the closed query.
    await tester.tap(find.byKey(searchButtonKey));
    await tester.pumpAndSettle();
    expect(searchField(tester).controller.text, '');
  });

  testWidgets('an active search survives a trip through the About tab', (
    tester,
  ) async {
    useTallSurface(tester);
    stubCommunityAndFeed();

    when(
      mockApiService.searchPosts(
        q: 'linux',
        community: communityDid,
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
      ),
    ).thenAnswer(
      (_) async => TimelineResponse(
        feed: [buildFeedPost(rkey: 's1', title: 'Linux kernel flaw')],
      ),
    );

    await pumpFeedScreen(tester);
    await openSearchAndSubmit(tester, 'linux');
    expect(find.text('Linux kernel flaw'), findsOneWidget);

    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Feed'));
    await tester.pumpAndSettle();

    expect(find.byKey(searchFieldKey), findsOneWidget);
    expect(searchField(tester).controller.text, 'linux');
    expect(find.text('Linux kernel flaw'), findsOneWidget);

    // Coming back is not a reason to ask the server again.
    verify(
      mockApiService.searchPosts(
        q: 'linux',
        community: communityDid,
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
      ),
    ).called(1);
  });

  testWidgets('the pinned header stays 56px and does not overflow at 320dp, '
      'open or closed', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    stubCommunityAndFeed();

    await pumpFeedScreen(tester);

    // Closed: the chips row plus the search button.
    expect(
      pinnedHeaderAround(
        tester,
        find.byKey(searchButtonKey),
      ).geometry!.maxPaintExtent,
      56.0,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(searchButtonKey));
    await tester.pumpAndSettle();

    // Open: the field plus the close button, in the same 56px.
    expect(
      pinnedHeaderAround(
        tester,
        find.byKey(searchFieldKey),
      ).geometry!.maxPaintExtent,
      56.0,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing search without submitting one leaves the feed, its '
      'sort and its posts untouched', (tester) async {
    useTallSurface(tester);
    stubCommunityAndFeed();

    await pumpFeedScreen(tester);

    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();

    // Everything fetched before the close is accounted for here, so the
    // checks below can only see calls the close itself caused.
    verify(
      mockApiService.getCommunityFeed(
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).called(greaterThan(0));

    // Opened, typed into, and abandoned without ever submitting.
    await tester.tap(find.byKey(searchButtonKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(searchFieldKey), 'linux');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(searchCloseKey));
    await tester.pumpAndSettle();

    // Nothing was ever replaced, so there is nothing to restore: refetching
    // the feed here would throw away the user's place in a list already on
    // screen and burn a request to redraw it.
    verifyNever(
      mockApiService.getCommunityFeed(
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    );
    verifyNever(
      mockApiService.searchPosts(
        q: anyNamed('q'),
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    );

    expect(find.text('First community post'), findsOneWidget);
    expect(find.text('Second community post'), findsOneWidget);

    // The header is back to browsing, still on the sort picked earlier.
    expect(find.byKey(searchFieldKey), findsNothing);
    expect(find.byKey(searchButtonKey), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('New')).style?.fontWeight,
      FontWeight.w600,
    );
    expect(
      tester.widget<Text>(find.text('Hot')).style?.fontWeight,
      FontWeight.normal,
    );
  });

  testWidgets('a query past the 500-byte limit is refused without a request, '
      'while one exactly at the limit is sent', (tester) async {
    useTallSurface(tester);
    stubCommunityAndFeed();

    // The backend caps `q` at 500 *bytes* of UTF-8, so the limit has to be
    // measured after encoding: 300 accented characters are only 300 code
    // units but 600 bytes, and 250 of them land exactly on the cap.
    final tooLong = 'é' * 300;
    final atLimit = 'é' * 250;
    expect(tooLong.length, 300);
    expect(utf8.encode(tooLong).length, 600);
    expect(atLimit.length, 250);
    expect(utf8.encode(atLimit).length, 500);

    // Registered first so the specific stub below wins for `atLimit`. This
    // one exists only so that an over-long query which *is* sent comes back
    // with a real response rather than a missing-stub error, leaving the
    // verifyNever below as the assertion that speaks.
    when(
      mockApiService.searchPosts(
        q: anyNamed('q'),
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((_) async => TimelineResponse(feed: const []));

    when(
      mockApiService.searchPosts(
        q: atLimit,
        community: communityDid,
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
      ),
    ).thenAnswer(
      (_) async => TimelineResponse(
        feed: [buildFeedPost(rkey: 's1', title: 'Accented match')],
      ),
    );

    await pumpFeedScreen(tester);
    await openSearchAndSubmit(tester, tooLong);

    verifyNever(
      mockApiService.searchPosts(
        q: anyNamed('q'),
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    );

    expect(
      find.widgetWithText(SnackBar, 'Search is too long.'),
      findsOneWidget,
    );

    // Refusing is not closing: the user keeps the field and every character
    // they typed, so shortening it is one edit away.
    expect(find.byKey(searchFieldKey), findsOneWidget);
    expect(searchField(tester).controller.text, tooLong);
    expect(find.text('First community post'), findsOneWidget);
    expect(find.text('Second community post'), findsOneWidget);

    // The boundary itself is a legal query, not an off-by-one casualty.
    await tester.enterText(find.byKey(searchFieldKey), atLimit);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    verify(
      mockApiService.searchPosts(
        q: atLimit,
        community: communityDid,
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
      ),
    ).called(1);
    expect(find.text('Accented match'), findsOneWidget);
  });

  testWidgets('a failed search is described as a failed search, not as a '
      'failed feed load', (tester) async {
    useTallSurface(tester);
    stubCommunityAndFeed();

    // A plain ApiException carries no user-facing copy of its own, so the
    // fallback the screen supplies is the whole message.
    when(
      mockApiService.searchPosts(
        q: 'linux',
        community: communityDid,
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
      ),
    ).thenAnswer((_) async => throw ApiException('search backend blew up'));

    await pumpFeedScreen(tester);
    await openSearchAndSubmit(tester, 'linux');

    expect(
      find.text('Could not search posts. Pull to refresh.'),
      findsOneWidget,
    );
    expect(find.text('Could not load feed. Pull to refresh.'), findsNothing);

    // The counter-case: with no search running, the same kind of exception
    // still reads as a feed failure, so the copy tracks what was asked for.
    when(
      mockApiService.getCommunityFeed(
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((_) async => throw ApiException('feed backend blew up'));

    await tester.tap(find.byKey(searchCloseKey));
    await tester.pumpAndSettle();

    expect(find.text('Could not load feed. Pull to refresh.'), findsOneWidget);
    expect(find.text('Could not search posts. Pull to refresh.'), findsNothing);
  });

  testWidgets('the icon-only search and close controls announce themselves to '
      'a screen reader', (tester) async {
    final handle = tester.ensureSemantics();

    stubCommunityAndFeed();

    await pumpFeedScreen(tester);

    final searchNode = find.bySemanticsLabel('Search posts');
    expect(searchNode, findsOneWidget);
    expect(tester.getSemantics(searchNode).flagsCollection.isButton, isTrue);

    await tester.tap(find.byKey(searchButtonKey));
    await tester.pumpAndSettle();

    final closeNode = find.bySemanticsLabel('Close search');
    expect(closeNode, findsOneWidget);
    expect(tester.getSemantics(closeNode).flagsCollection.isButton, isTrue);

    handle.dispose();
  });

  testWidgets('clearing an active search and submitting returns to the feed '
      'with the field still open', (tester) async {
    useTallSurface(tester);
    stubCommunityAndFeed();

    when(
      mockApiService.searchPosts(
        q: 'linux',
        community: communityDid,
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
      ),
    ).thenAnswer(
      (_) async => TimelineResponse(
        feed: [buildFeedPost(rkey: 's1', title: 'Linux kernel flaw')],
      ),
    );

    await pumpFeedScreen(tester);

    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();

    await openSearchAndSubmit(tester, 'linux');
    expect(find.text('Linux kernel flaw'), findsOneWidget);

    // Everything fetched before the blank submit is accounted for here.
    verify(
      mockApiService.getCommunityFeed(
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).called(greaterThan(0));
    verify(
      mockApiService.searchPosts(
        q: anyNamed('q'),
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).called(greaterThan(0));

    await tester.enterText(find.byKey(searchFieldKey), '');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    // Emptying the box is how a user says "never mind" without giving up
    // the box, so the feed comes back at the sort search opened over.
    verify(
      mockApiService.getCommunityFeed(
        community: communityDid,
        sort: 'new',
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
      ),
    ).called(1);
    verifyNever(
      mockApiService.searchPosts(
        q: anyNamed('q'),
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    );

    expect(find.text('First community post'), findsOneWidget);
    expect(find.text('Second community post'), findsOneWidget);
    expect(find.text('Linux kernel flaw'), findsNothing);
    expect(find.byKey(searchFieldKey), findsOneWidget);
    expect(searchField(tester).controller.text, '');
  });

  testWidgets('closing search onto a feed that fails shows the feed error '
      'and retries the feed, not the search', (tester) async {
    useTallSurface(tester);
    stubCommunityAndFeed();

    when(
      mockApiService.searchPosts(
        q: 'linux',
        community: communityDid,
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
      ),
    ).thenAnswer(
      (_) async => TimelineResponse(
        feed: [buildFeedPost(rkey: 's1', title: 'Linux kernel flaw')],
      ),
    );

    await pumpFeedScreen(tester);

    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();

    await openSearchAndSubmit(tester, 'linux');
    expect(find.text('Linux kernel flaw'), findsOneWidget);

    // The feed that closing search falls back to is unreachable.
    when(
      mockApiService.getCommunityFeed(
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((_) async => throw NotFoundException('community not found'));

    await tester.tap(find.byKey(searchCloseKey));
    await tester.pumpAndSettle();

    // Closing clears the results even though nothing replaced them, so the
    // user is never left reading search hits under a feed error.
    expect(find.text('Linux kernel flaw'), findsNothing);
    expect(
      find.text('Content not found. It may have been removed.'),
      findsOneWidget,
    );
    final retry = find.text('Retry');
    expect(retry, findsOneWidget);
    expect(
      find.ancestor(
        of: retry,
        matching: find.byWidgetPredicate(
          (widget) => widget is ButtonStyleButton,
        ),
      ),
      findsOneWidget,
    );

    when(
      mockApiService.getCommunityFeed(
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer(
      (_) async => TimelineResponse(
        feed: [
          buildFeedPost(rkey: 'p1', title: 'First community post'),
          buildFeedPost(rkey: 'p2', title: 'Second community post'),
        ],
      ),
    );

    // Everything fetched up to here is accounted for, so the calls checked
    // below are the ones the Retry itself caused.
    verify(
      mockApiService.getCommunityFeed(
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).called(greaterThan(0));
    verify(
      mockApiService.searchPosts(
        q: anyNamed('q'),
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).called(greaterThan(0));

    await tester.tap(retry);
    await tester.pumpAndSettle();

    // The retry belongs to the feed the close reset to, at the sort that
    // was chosen before search opened.
    verify(
      mockApiService.getCommunityFeed(
        community: communityDid,
        sort: 'new',
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
      ),
    ).called(1);
    verifyNever(
      mockApiService.searchPosts(
        q: anyNamed('q'),
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    );

    expect(find.text('First community post'), findsOneWidget);
    expect(find.text('Second community post'), findsOneWidget);
  });
}
