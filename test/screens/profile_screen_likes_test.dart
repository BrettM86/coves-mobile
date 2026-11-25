// The Likes tab on a profile: only the signed-in viewer's own profile has
// one, and opening it loads that viewer's liked posts and comments once.
//
// Filter control contract: while the Likes tab is selected, a glyph button
// with tooltip 'Filter likes' sits inside the Likes tab item, right of its
// label, in the tab bar (key 'profile_tab_bar'). It opens a menu whose
// entries are the texts 'All', 'Posts' and 'Comments'; tapping an entry
// selects that filter, and scrolling closes the menu. Tests find it with
// find.byTooltip('Filter likes') and then find.text('<entry>').last (the
// profile's own 'Posts' and 'Comments' tabs share those texts).

import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/liked_item.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/screens/home/profile_screen.dart';
import 'package:coves_flutter/widgets/comment_card.dart';
import 'package:coves_flutter/widgets/post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/pump_helpers.dart';
import '../test_helpers/test_mocks.dart';

const String myDid = 'did:plc:me';
const String myHandle = 'me.coves.test';
const String otherDid = 'did:plc:other';
const String otherHandle = 'other.coves.test';
const String likedPostTitle = 'A post I liked';
const String secondLikedPostTitle = 'Another post I liked';
const String ownPostTitle = 'A post I wrote';
const String anotherDid = 'did:plc:another-account';
const String likedCommentText = 'A comment I liked';
const String rootPostUri =
    'at://did:plc:community/social.coves.community.post/root';
const String likedCommentUri =
    'at://did:plc:commenter/social.coves.community.comment/liked-comment';

FeedViewPost _post(String rkey, String title) {
  return FeedViewPost(
    post: PostView(
      uri: 'at://did:plc:community/social.coves.community.post/$rkey',
      cid: 'cid-$rkey',
      rkey: rkey,
      author: AuthorView(did: 'did:plc:author', handle: 'author.coves.test'),
      community: CommunityRef(did: 'did:plc:community', name: 'test-community'),
      createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
      indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
      record: PostRecord(title: title, content: 'body'),
      stats: PostStats(upvotes: 1, downvotes: 0, score: 1, commentCount: 0),
    ),
  );
}

FeedViewPost _likedPost() => _post('liked', likedPostTitle);

LikedPost _liked(FeedViewPost feedViewPost) => LikedPost(feedViewPost);

/// A liked comment by someone else on the post at [rootPostUri]; the item
/// carries that root post's view.
LikedComment _commentLike(String rkey, String content) {
  return LikedComment(
    comment: CommentView(
      uri: 'at://did:plc:commenter/social.coves.community.comment/$rkey',
      cid: 'cid-$rkey',
      record: CommentRecord(content: content),
      createdAt: DateTime.parse('2025-01-02T12:00:00Z'),
      indexedAt: DateTime.parse('2025-01-02T12:00:00Z'),
      author: AuthorView(
        did: 'did:plc:commenter',
        handle: 'commenter.coves.test',
      ),
      post: CommentRef(uri: rootPostUri, cid: 'cid-root'),
      stats: const CommentStats(score: 1, upvotes: 1),
    ),
    post: _post('root', 'The post that comment replies to').post,
  );
}

LikedComment _likedComment() => _commentLike('liked-comment', likedCommentText);

void main() {
  late FakeAuthProvider authProvider;
  late MockCovesApiService apiService;

  setUp(() {
    authProvider = FakeAuthProvider(
      signedInDid: myDid,
      signedInHandle: myHandle,
    );
    apiService = MockCovesApiService();
    when(apiService.getViewerAuthority()).thenAnswer((_) async => false);
    for (final (did, handle) in [(myDid, myHandle), (otherDid, otherHandle)]) {
      when(apiService.getProfile(actor: did))
          .thenAnswer((_) async => UserProfile(did: did, handle: handle));
      when(
        apiService.getAuthorPosts(
          actor: did,
          filter: anyNamed('filter'),
          community: anyNamed('community'),
          limit: anyNamed('limit'),
          cursor: anyNamed('cursor'),
        ),
      ).thenAnswer((_) async => TimelineResponse(feed: []));
    }
  });

  tearDown(() {
    authProvider.dispose();
  });

  void stubLikes(List<LikedItem> feed) {
    when(
      apiService.getActorLikes(
        actor: anyNamed('actor'),
        filter: anyNamed('filter'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((_) async => LikesResponse(feed: feed));
  }

  /// Every getActorLikes request as (actor, cursor).
  late List<(String, String?)> likesRequests;

  /// Every getActorLikes request as (filter, cursor).
  late List<(LikesFilter, String?)> likesFilterRequests;

  /// Answers getActorLikes with [pages] in order (the last repeats); a page
  /// may be an exception to throw, or a Future (a Completer's) to answer
  /// later.
  void stubLikesPages(List<Object> pages) {
    likesRequests = <(String, String?)>[];
    likesFilterRequests = <(LikesFilter, String?)>[];
    var call = 0;
    when(
      apiService.getActorLikes(
        actor: anyNamed('actor'),
        filter: anyNamed('filter'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((invocation) async {
      likesRequests.add((
        invocation.namedArguments[#actor] as String,
        invocation.namedArguments[#cursor] as String?,
      ));
      likesFilterRequests.add((
        invocation.namedArguments[#filter] as LikesFilter,
        invocation.namedArguments[#cursor] as String?,
      ));
      final page = pages[call < pages.length ? call : pages.length - 1];
      call++;
      if (page is Exception) {
        throw page;
      }
      if (page is Future<LikesResponse>) {
        return page;
      }
      return page as LikesResponse;
    });
  }

  /// Whether the profile tab labeled [label] is the selected one (the
  /// selected tab's label is bold).
  bool isTabSelected(WidgetTester tester, String label) {
    final labelText = tester.widget<Text>(find.text(label));
    return labelText.style?.fontWeight == FontWeight.bold;
  }

  Finder postCardWithTitle(String title) =>
      find.ancestor(of: find.text(title), matching: find.byType(PostCard));

  Finder commentCardWithText(String text) =>
      find.ancestor(of: find.text(text), matching: find.byType(CommentCard));

  /// Every location the app routed to under /post/, as the full location.
  late List<String> openedPostLocations;

  Future<void> pumpProfile(
    WidgetTester tester, {
    String? actor,
    Size size = const Size(540, 960),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    openedPostLocations = <String>[];
    final router = GoRouter(
      initialLocation: '/profile',
      routes: [
        GoRoute(
          path: '/profile',
          builder: (context, state) => ProfileScreen(actor: actor),
        ),
        GoRoute(
          path: '/post/:uri',
          builder: (context, state) {
            openedPostLocations.add(state.uri.toString());
            return const Scaffold(body: Text('Post placeholder'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: profileScreenProviders(
          auth: authProvider,
          apiService: apiService,
          commentService: MockCommentService(),
        ),
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await pumpFrames(tester);
  }

  /// Chooses [entry] ('All', 'Posts' or 'Comments') in the Likes tab's
  /// filter control.
  Future<void> chooseLikesFilter(WidgetTester tester, String entry) async {
    await tester.tap(find.byTooltip('Filter likes'));
    await pumpFrames(tester);
    await tester.tap(find.text(entry).last);
    await pumpFrames(tester);
  }

  final tabRows = <({String name, String? actor, Matcher likesTab})>[
    (name: 'own profile', actor: null, likesTab: findsOneWidget),
    (name: 'another user\'s profile', actor: otherDid, likesTab: findsNothing),
  ];
  for (final row in tabRows) {
    testWidgets('the ${row.name} shows its tabs', (tester) async {
      stubLikes([]);
      await pumpProfile(tester, actor: row.actor);

      expect(find.text('Posts'), findsOneWidget);
      expect(find.text('Comments'), findsOneWidget);
      expect(find.text('Likes'), row.likesTab);
    });
  }

  testWidgets('the likes filter control is at least 48x48', (tester) async {
    stubLikes([_liked(_likedPost())]);
    await pumpProfile(tester);

    await tester.tap(find.text('Likes'));
    await pumpFrames(tester);

    final size = tester.getSize(
      find
          .descendant(
            of: find.byTooltip('Filter likes'),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });

  // The selected Likes tab carries a 48px filter target beside its label
  // inside a third of the tab bar; large accessibility text must not
  // overflow it.
  for (final textScale in <double>[1.5, 2]) {
    testWidgets('the selected Likes tab with its filter fits a 320-wide '
        'screen at text scale $textScale', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      stubLikes([_liked(_likedPost())]);
      await pumpProfile(tester, size: const Size(320, 960));

      await tester.tap(find.text('Likes'));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Filter likes'), findsOneWidget);
    });
  }

  testWidgets('opening Likes on the own profile loads the liked posts once', (
    tester,
  ) async {
    stubLikes([_liked(_likedPost())]);
    await pumpProfile(tester);

    await tester.tap(find.text('Likes'));
    await pumpFrames(tester);

    expect(
      find.ancestor(
        of: find.text(likedPostTitle),
        matching: find.byType(PostCard),
      ),
      findsOneWidget,
    );

    // Leaving and returning to the tab reuses the loaded page.
    await tester.tap(find.text('Posts'));
    await pumpFrames(tester);
    await tester.tap(find.text('Likes'));
    await pumpFrames(tester);

    verify(
      apiService.getActorLikes(
        actor: myDid,
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).called(1);
    expect(find.text(likedPostTitle), findsOneWidget);
  });

  testWidgets('pull-to-refresh on the own profile opened by handle keeps '
      'the Likes tab and refreshes the likes', (tester) async {
    // Enough likes to make the profile scrollable, so it can be pulled.
    stubLikesPages(<Object>[
      LikesResponse(
        feed: <LikedItem>[
          _liked(_likedPost()),
          for (var i = 1; i <= 5; i++)
            _liked(_post('filler-$i', 'Filler like $i')),
        ],
      ),
    ]);
    // The refresh's profile fetch is still in flight for at least a frame,
    // as over a real network.
    final refreshedProfile = Completer<UserProfile>();
    var handleLookups = 0;
    when(apiService.getProfile(actor: myHandle)).thenAnswer((_) {
      handleLookups++;
      if (handleLookups == 1) {
        return Future.value(UserProfile(did: myDid, handle: myHandle));
      }
      return refreshedProfile.future;
    });

    await pumpProfile(tester, actor: myHandle);
    await tester.tap(find.text('Likes'));
    await pumpFrames(tester);
    expect(postCardWithTitle(likedPostTitle), findsOneWidget);
    expect(likesRequests, <(String, String?)>[(myDid, null)]);

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 600),
      1000,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    refreshedProfile.complete(UserProfile(did: myDid, handle: myHandle));
    await pumpFrames(tester);
    await tester.pump(const Duration(seconds: 1));

    expect(handleLookups, 2);
    expect(find.text('Likes'), findsOneWidget);
    expect(isTabSelected(tester, 'Likes'), isTrue);
    expect(postCardWithTitle(likedPostTitle), findsOneWidget);
    expect(likesRequests, <(String, String?)>[(myDid, null), (myDid, null)]);
  });

  testWidgets('a short first page of likes loads the next page to fill the '
      'screen', (tester) async {
    stubLikesPages(<Object>[
      LikesResponse(feed: <LikedItem>[_liked(_likedPost())], cursor: 'c1'),
      LikesResponse(
        feed: <LikedItem>[_liked(_post('liked-2', secondLikedPostTitle))],
      ),
    ]);
    await pumpProfile(tester);

    await tester.tap(find.text('Likes'));
    await pumpFrames(tester);

    expect(likesRequests, <(String, String?)>[(myDid, null), (myDid, 'c1')]);
    await tester.scrollUntilVisible(
      find.text(secondLikedPostTitle),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(postCardWithTitle(likedPostTitle), findsOneWidget);
    expect(postCardWithTitle(secondLikedPostTitle), findsOneWidget);
  });

  testWidgets('an empty first page with a cursor whose next page fails '
      'shows the error with Retry, and Retry loads that page', (tester) async {
    stubLikesPages(<Object>[
      LikesResponse(feed: <LikedItem>[], cursor: 'c1'),
      Exception('page 2 exploded'),
      LikesResponse(feed: <LikedItem>[_likedComment()]),
    ]);
    await pumpProfile(tester);

    await tester.tap(find.text('Likes'));
    await pumpFrames(tester);

    expect(likesRequests, <(String, String?)>[(myDid, null), (myDid, 'c1')]);
    expect(
      find.text('Could not load likes. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('No likes yet'), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await pumpFrames(tester);

    expect(likesRequests, <(String, String?)>[
      (myDid, null),
      (myDid, 'c1'),
      (myDid, 'c1'),
    ]);
    expect(commentCardWithText(likedCommentText), findsOneWidget);
    expect(find.text('Could not load likes. Please try again.'), findsNothing);
  });

  testWidgets('an empty first page with a cursor shows a spinner, not the '
      'empty text, while the next page loads', (tester) async {
    final nextPage = Completer<LikesResponse>();
    stubLikesPages(<Object>[
      LikesResponse(feed: <LikedItem>[], cursor: 'c1'),
      nextPage.future,
    ]);
    await pumpProfile(tester);

    await tester.tap(find.text('Likes'));
    await pumpFrames(tester);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('No likes yet'), findsNothing);

    nextPage.complete(LikesResponse(feed: <LikedItem>[_likedComment()]));
    await pumpFrames(tester);

    expect(likesRequests, <(String, String?)>[(myDid, null), (myDid, 'c1')]);
    expect(commentCardWithText(likedCommentText), findsOneWidget);
  });

  testWidgets('a failed first page of likes shows the error, and Retry '
      'loads the likes', (tester) async {
    stubLikesPages(<Object>[
      Exception('likes exploded'),
      LikesResponse(feed: <LikedItem>[_liked(_likedPost())]),
    ]);
    await pumpProfile(tester);

    await tester.tap(find.text('Likes'));
    await pumpFrames(tester);

    expect(
      find.text('Could not load likes. Please try again.'),
      findsOneWidget,
    );
    expect(find.text(likedPostTitle), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await pumpFrames(tester);

    expect(find.text('Could not load likes. Please try again.'), findsNothing);
    expect(postCardWithTitle(likedPostTitle), findsOneWidget);
    expect(likesRequests, <(String, String?)>[(myDid, null), (myDid, null)]);
  });

  testWidgets('Retry after the signed-in account changes on the own profile '
      'drops the Likes tab and shows Posts', (tester) async {
    stubLikesPages(<Object>[
      LikesResponse(feed: <LikedItem>[_liked(_likedPost())]),
    ]);
    when(
      apiService.getAuthorPosts(
        actor: myDid,
        filter: anyNamed('filter'),
        community: anyNamed('community'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer(
      (_) async =>
          TimelineResponse(feed: <FeedViewPost>[_post('mine', ownPostTitle)]),
    );
    await pumpProfile(tester, actor: myDid);
    await tester.tap(find.text('Likes'));
    await pumpFrames(tester);
    expect(postCardWithTitle(likedPostTitle), findsOneWidget);
    expect(likesRequests, <(String, String?)>[(myDid, null)]);

    authProvider.setSignedInDid(anotherDid);
    await pumpFrames(tester);
    expect(
      find.text('Your session changed. Retry to reload this profile.'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'Retry'));
    await pumpFrames(tester);

    expect(find.text('Likes'), findsNothing);
    expect(isTabSelected(tester, 'Posts'), isTrue);
    expect(postCardWithTitle(ownPostTitle), findsOneWidget);
    expect(find.text(likedPostTitle), findsNothing);
    expect(likesRequests, <(String, String?)>[(myDid, null)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an own profile with no likes says so', (tester) async {
    stubLikes([]);
    await pumpProfile(tester);

    await tester.tap(find.text('Likes'));
    await pumpFrames(tester);

    expect(find.text('No likes yet'), findsOneWidget);
  });

  testWidgets('the own Likes tab lists liked posts and liked comments '
      'together, and Comments narrows it to the comments', (tester) async {
    stubLikesPages(<Object>[
      LikesResponse(feed: <LikedItem>[_liked(_likedPost()), _likedComment()]),
      LikesResponse(feed: <LikedItem>[_likedComment()]),
    ]);
    await pumpProfile(tester);

    await tester.tap(find.text('Likes'));
    await pumpFrames(tester);

    expect(postCardWithTitle(likedPostTitle), findsOneWidget);
    expect(commentCardWithText(likedCommentText), findsOneWidget);
    expect(likesFilterRequests, <(LikesFilter, String?)>[
      (LikesFilter.all, null),
    ]);

    await chooseLikesFilter(tester, 'Comments');

    expect(likesFilterRequests, <(LikesFilter, String?)>[
      (LikesFilter.all, null),
      (LikesFilter.comments, null),
    ]);
    expect(find.byType(PostCard), findsNothing);
    final commentCard = commentCardWithText(likedCommentText);
    expect(commentCard, findsOneWidget);
    expect(
      tester.widget<CommentCard>(commentCard).parentPost?.uri,
      'at://did:plc:community/social.coves.community.post/root',
    );
  });

  testWidgets('tapping a liked comment opens its root post scrolled to the '
      'comment', (tester) async {
    // The card awaits HapticFeedback before navigating; without a handler
    // the platform channel call never completes in tests.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (methodCall) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    stubLikes([_liked(_likedPost()), _likedComment()]);
    await pumpProfile(tester);

    await tester.tap(find.text('Likes'));
    await pumpFrames(tester);
    final commentCard = commentCardWithText(likedCommentText);
    expect(commentCard, findsOneWidget);
    expect(
      tester.widget<CommentCard>(commentCard).parentPost?.uri,
      'at://did:plc:community/social.coves.community.post/root',
    );

    await tester.ensureVisible(find.text(likedCommentText));
    await tester.pump();
    await tester.tap(find.text(likedCommentText));
    await pumpFrames(tester);

    const rootPostWithComment =
        '/post/at%3A%2F%2Fdid%3Aplc%3Acommunity%2Fsocial.coves.community.post'
        '%2Froot'
        '?comment=at%3A%2F%2Fdid%3Aplc%3Acommenter%2F'
        'social.coves.community.comment%2Fliked-comment';
    expect(openedPostLocations, <String>[rootPostWithComment]);
  });

  final emptyRows = <({String entry, String text})>[
    (entry: 'All', text: 'No likes yet'),
    (entry: 'Posts', text: 'No liked posts yet'),
    (entry: 'Comments', text: 'No liked comments yet'),
  ];
  for (final row in emptyRows) {
    testWidgets('an empty Likes tab with ${row.entry} selected says '
        '"${row.text}"', (tester) async {
      stubLikes([]);
      await pumpProfile(tester);
      await tester.tap(find.text('Likes'));
      await pumpFrames(tester);

      await chooseLikesFilter(tester, row.entry);

      expect(find.text(row.text), findsOneWidget);
    });
  }

  testWidgets('pull-to-refresh on Likes with Comments selected refreshes '
      'the liked comments', (tester) async {
    // Enough liked comments to make the profile scrollable, so it can be
    // pulled.
    final likedComments = LikesResponse(
      feed: <LikedItem>[
        _likedComment(),
        for (var i = 1; i <= 9; i++)
          _commentLike('filler-$i', 'Filler liked comment $i'),
      ],
    );
    stubLikesPages(<Object>[
      LikesResponse(feed: <LikedItem>[_liked(_likedPost())]),
      likedComments,
    ]);
    await pumpProfile(tester);
    await tester.tap(find.text('Likes'));
    await pumpFrames(tester);
    await chooseLikesFilter(tester, 'Comments');
    expect(commentCardWithText(likedCommentText), findsOneWidget);

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 600),
      1000,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await pumpFrames(tester);
    await tester.pump(const Duration(seconds: 1));

    expect(likesFilterRequests, <(LikesFilter, String?)>[
      (LikesFilter.all, null),
      (LikesFilter.comments, null),
      (LikesFilter.comments, null),
    ]);
    expect(isTabSelected(tester, 'Likes'), isTrue);
    expect(commentCardWithText(likedCommentText), findsOneWidget);
    expect(find.byType(PostCard), findsNothing);
  });

  testWidgets('with Comments selected, an empty first page that has a '
      'cursor loads the next page of liked comments', (tester) async {
    stubLikesPages(<Object>[
      LikesResponse(feed: <LikedItem>[_liked(_likedPost())]),
      LikesResponse(feed: <LikedItem>[], cursor: 'c1'),
      LikesResponse(feed: <LikedItem>[_likedComment()]),
    ]);
    await pumpProfile(tester);
    await tester.tap(find.text('Likes'));
    await pumpFrames(tester);

    await chooseLikesFilter(tester, 'Comments');

    expect(likesFilterRequests, <(LikesFilter, String?)>[
      (LikesFilter.all, null),
      (LikesFilter.comments, null),
      (LikesFilter.comments, 'c1'),
    ]);
    expect(commentCardWithText(likedCommentText), findsOneWidget);
    expect(find.text('No liked comments yet'), findsNothing);
  });

  /// The profile's tab bar (Posts / Comments / Likes).
  Finder profileTabBar() => find.byKey(const ValueKey('profile_tab_bar'));

  Finder tabBarFilterControl() => find.descendant(
    of: profileTabBar(),
    matching: find.byTooltip('Filter likes'),
  );

  testWidgets('the filter glyph sits in the tab bar right of the Likes label '
      'and shows only while Likes is selected', (tester) async {
    stubLikesPages(<Object>[
      LikesResponse(feed: <LikedItem>[_liked(_likedPost())]),
    ]);
    await pumpProfile(tester);

    expect(isTabSelected(tester, 'Posts'), isTrue);
    expect(find.byTooltip('Filter likes'), findsNothing);

    await tester.tap(find.text('Likes'));
    await pumpFrames(tester);

    expect(find.byTooltip('Filter likes'), findsOneWidget);
    expect(tabBarFilterControl(), findsOneWidget);
    expect(
      tester.getCenter(tabBarFilterControl()).dx,
      greaterThan(tester.getCenter(find.text('Likes')).dx),
    );

    await tester.tap(find.text('Posts'));
    await pumpFrames(tester);

    expect(isTabSelected(tester, 'Posts'), isTrue);
    expect(find.byTooltip('Filter likes'), findsNothing);
  });

  testWidgets('with Likes selected, tapping the Likes label keeps the filter '
      'menu closed, and tapping the glyph opens it', (tester) async {
    stubLikesPages(<Object>[
      LikesResponse(feed: <LikedItem>[_liked(_likedPost())]),
    ]);
    await pumpProfile(tester);
    await tester.tap(find.text('Likes'));
    await pumpFrames(tester);
    expect(find.text('All'), findsNothing);

    await tester.tap(find.text('Likes'));
    await pumpFrames(tester);

    // 'All' is only ever a menu entry; 'Posts' and 'Comments' are also tabs.
    expect(find.text('All'), findsNothing);
    expect(find.text('Posts'), findsOneWidget);
    expect(find.text('Comments'), findsOneWidget);
    expect(isTabSelected(tester, 'Likes'), isTrue);
    expect(likesFilterRequests, <(LikesFilter, String?)>[
      (LikesFilter.all, null),
    ]);

    await tester.tap(tabBarFilterControl());
    await pumpFrames(tester);

    expect(find.text('All'), findsOneWidget);
    expect(find.text('Posts'), findsNWidgets(2));
    expect(find.text('Comments'), findsNWidgets(2));
  });

  testWidgets('scrolling the likes list closes an open filter menu without '
      'changing the filter', (tester) async {
    // Enough likes to make the profile scrollable.
    stubLikesPages(<Object>[
      LikesResponse(
        feed: <LikedItem>[
          _liked(_likedPost()),
          for (var i = 1; i <= 5; i++)
            _liked(_post('filler-$i', 'Filler like $i')),
        ],
      ),
    ]);
    await pumpProfile(tester);
    await tester.tap(find.text('Likes'));
    await pumpFrames(tester);

    await tester.tap(find.byTooltip('Filter likes'));
    await pumpFrames(tester);
    expect(find.text('All'), findsOneWidget);
    final likedPostTopBefore = tester
        .getTopLeft(postCardWithTitle(likedPostTitle))
        .dy;

    // Drag the list from its lower-left corner, clear of the menu.
    final listBottom = tester.getBottomLeft(find.byType(CustomScrollView)).dy;
    await tester.dragFrom(Offset(40, listBottom - 100), const Offset(0, -300));
    await pumpFrames(tester);

    expect(find.text('All'), findsNothing);
    expect(find.text('Posts'), findsOneWidget);
    expect(find.text('Comments'), findsOneWidget);
    expect(
      tester.getTopLeft(postCardWithTitle(likedPostTitle)).dy,
      lessThan(likedPostTopBefore),
    );
    expect(isTabSelected(tester, 'Likes'), isTrue);
    expect(postCardWithTitle(likedPostTitle), findsOneWidget);
    expect(likesFilterRequests, <(LikesFilter, String?)>[
      (LikesFilter.all, null),
    ]);
  });

  testWidgets('a liked comment on the profile paints no thread line', (
    tester,
  ) async {
    stubLikes([_likedComment()]);
    await pumpProfile(tester);
    await tester.tap(find.text('Likes'));
    await pumpFrames(tester);

    final commentCard = commentCardWithText(likedCommentText);
    expect(commentCard, findsOneWidget);
    expect(tester.renderObject(commentCard), isNot(paints..line()));
  });
}
