import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/comments_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/home/focused_thread_screen.dart';
import 'package:coves_flutter/screens/home/post_detail_screen.dart';
import 'package:coves_flutter/screens/home/profile_screen.dart';
import 'package:coves_flutter/services/comment_service.dart';
import 'package:coves_flutter/services/comments_provider_cache.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/link_sharer.dart';
import 'package:coves_flutter/services/profile_cache.dart';
import 'package:coves_flutter/services/viewer_state_hydrator.dart';
import 'package:coves_flutter/widgets/comment_card.dart';
import 'package:coves_flutter/widgets/comment_thread.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

// Shared generated mockito mocks (real provider types) so the
// Consumer<AuthProvider>/Consumer<VoteProvider> lookups inside CommentCard
// resolve correctly.
import '../test_helpers/test_mocks.dart';

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

/// Every surface that has the post loaded must hand it to the comments it
/// renders, or the card's share actions are unreachable in the app.
///
/// The viewer is signed out throughout: without a parent post the card
/// renders no 'Comment options' trigger at all, so the trigger's presence is
/// a direct read-out of whether the post reached the card.
void main() {
  // Literals, never produced by the code under test.
  const postUri =
      'at://did:plc:author123/social.coves.community.postv2/3kabcxyz';
  const topLevelCommentUri =
      'at://did:plc:commenter789/social.coves.community.comment/3kcmt001';
  const middleCommentUri =
      'at://did:plc:commenter222/social.coves.community.comment/3kcmt002';
  const nestedCommentUri =
      'at://did:plc:commenter555/social.coves.community.comment/3kcmt003';
  const topLevelPermalink =
      'https://coves.social/c/gaming/post/alice.coves.social/3kabcxyz'
      '/comment/bob.coves.social/3kcmt001';
  const nestedPermalink =
      'https://coves.social/c/gaming/post/alice.coves.social/3kabcxyz'
      '/comment/carol.coves.social/3kcmt003';

  late MockAuthProvider mockAuthProvider;
  late MockVoteProvider mockVoteProvider;
  late MockCovesApiService mockApiService;
  late MockCommentService mockCommentService;
  late BlockProvider blockProvider;
  late RecordingLinkSharer linkSharer;
  late List<Object?> clipboardTexts;

  /// The loaded post: author-owned repo, valid handle, and a community
  /// served by this instance.
  PostView parentPost() {
    return PostView(
      uri: postUri,
      cid: 'cid123',
      rkey: '3kabcxyz',
      author: AuthorView(
        did: 'did:plc:author123',
        handle: 'alice.coves.social',
      ),
      community: CommunityRef(
        did: 'did:plc:community456',
        name: 'Gaming',
        origin: 'coves.social',
      ),
      createdAt: DateTime(2024),
      indexedAt: DateTime(2024),
      record: const PostRecord(content: 'Parent post', title: 'Parent Post'),
      stats: PostStats(upvotes: 1, downvotes: 0, score: 1, commentCount: 3),
    );
  }

  CommentView comment({
    required String uri,
    required String commenterDid,
    required String handle,
    required String content,
    int replyCount = 0,
  }) {
    return CommentView(
      uri: uri,
      cid: 'cid-$uri',
      record: CommentRecord(content: content),
      createdAt: DateTime(2025),
      indexedAt: DateTime(2025),
      author: AuthorView(did: commenterDid, handle: handle),
      post: CommentRef(uri: postUri, cid: 'cid123'),
      stats: CommentStats(
        upvotes: 5,
        downvotes: 1,
        score: 4,
        replyCount: replyCount,
      ),
    );
  }

  /// The top-level comment every group renders.
  CommentView topLevelComment({int replyCount = 0}) {
    return comment(
      uri: topLevelCommentUri,
      commenterDid: 'did:plc:commenter789',
      handle: 'bob.coves.social',
      content: 'Top level comment',
      replyCount: replyCount,
    );
  }

  setUp(() {
    mockAuthProvider = MockAuthProvider();
    mockVoteProvider = MockVoteProvider();
    mockApiService = MockCovesApiService();
    mockCommentService = MockCommentService();
    linkSharer = RecordingLinkSharer();
    clipboardTexts = [];

    // Signed out: the moderation items are hidden, so the menu exists only
    // where the parent post reached the card.
    when(mockAuthProvider.isAuthenticated).thenReturn(false);
    when(mockAuthProvider.did).thenReturn(null);
    when(mockVoteProvider.isLiked(any)).thenReturn(false);
    when(mockVoteProvider.getVoteState(any)).thenReturn(null);
    when(mockVoteProvider.isPending(any)).thenReturn(false);
    when(mockVoteProvider.getAdjustedScore(any, any)).thenAnswer(
      (invocation) => invocation.positionalArguments[1] as int,
    );
    blockProvider = BlockProvider(
      apiService: mockApiService,
      authProvider: mockAuthProvider,
    );
  });

  tearDown(() {
    blockProvider.dispose();
  });

  /// Records every `Clipboard.setData` payload while still answering the
  /// haptic calls the menu handlers make.
  ///
  /// A handler that only returned null would let a clipboard assertion pass
  /// with no copy happening, so this one is the single handler on the channel
  /// for the whole test.
  void recordPlatformChannel(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (methodCall) async {
        if (methodCall.method == 'Clipboard.setData') {
          final arguments = Map<Object?, Object?>.from(
            methodCall.arguments as Map<Object?, Object?>,
          );
          clipboardTexts.add(arguments['text']);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
  }

  /// A surface tall enough that every comment builds without scrolling.
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// The options trigger on the card rendering [content].
  Finder triggerOn(String content) {
    return find.descendant(
      of: find.ancestor(
        of: find.text(content),
        matching: find.byType(CommentCard),
      ),
      matching: find.byTooltip('Comment options'),
    );
  }

  Future<void> openMenuOn(WidgetTester tester, String content) async {
    expect(find.text(content), findsOneWidget);
    final trigger = triggerOn(content);
    expect(
      trigger,
      findsOneWidget,
      reason: 'the parent post must reach the card rendering "$content"',
    );
    await tester.tap(trigger);
    await tester.pumpAndSettle();
  }

  group('CommentThread parent post propagation', () {
    ThreadViewComment nestedThread() {
      return ThreadViewComment(
        comment: topLevelComment(replyCount: 1),
        replies: [
          ThreadViewComment(
            comment: comment(
              uri: middleCommentUri,
              commenterDid: 'did:plc:commenter222',
              handle: 'dave.coves.social',
              content: 'Middle reply',
              replyCount: 1,
            ),
            replies: [
              ThreadViewComment(
                comment: comment(
                  uri: nestedCommentUri,
                  commenterDid: 'did:plc:commenter555',
                  handle: 'carol.coves.social',
                  content: 'Nested reply',
                ),
              ),
            ],
          ),
        ],
      );
    }

    Future<void> pumpThread(WidgetTester tester) async {
      useTallSurface(tester);
      recordPlatformChannel(tester);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: mockAuthProvider),
            ChangeNotifierProvider<VoteProvider>.value(value: mockVoteProvider),
            ChangeNotifierProvider<BlockProvider>.value(value: blockProvider),
            Provider<LinkSharer>.value(value: linkSharer),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(
              body: SingleChildScrollView(
                child: CommentThread(
                  thread: nestedThread(),
                  parentPost: parentPost(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('every comment in the tree offers Share and Copy link', (
      tester,
    ) async {
      await pumpThread(tester);

      // Top level, its reply, and the reply's reply: the post has to survive
      // the recursion, not just the first level.
      expect(find.byType(CommentCard), findsNWidgets(3));
      expect(find.byTooltip('Comment options'), findsNWidgets(3));

      await openMenuOn(tester, 'Top level comment');

      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Copy link'), findsOneWidget);
    });

    testWidgets('a nested reply copies its own permalink', (tester) async {
      await pumpThread(tester);

      await openMenuOn(tester, 'Nested reply');

      final copyLink = find.text('Copy link');
      expect(copyLink, findsOneWidget);

      await tester.tap(copyLink);
      await tester.pumpAndSettle();

      // The reply's own commenter and rkey, not its parent's.
      expect(clipboardTexts, [nestedPermalink]);
      expect(find.text('Link copied to clipboard'), findsOneWidget);
    });
  });

  group('PostDetailScreen comment share propagation', () {
    late CommentsProviderCache commentsCache;

    setUp(() {
      commentsCache = CommentsProviderCache(
        authProvider: mockAuthProvider,
        voteProvider: mockVoteProvider,
        commentService: mockCommentService,
        apiService: mockApiService,
      );

      when(
        mockApiService.getComments(
          postUri: anyNamed('postUri'),
          sort: anyNamed('sort'),
          timeframe: anyNamed('timeframe'),
          depth: anyNamed('depth'),
          limit: anyNamed('limit'),
          cursor: anyNamed('cursor'),
          parentRkey: anyNamed('parentRkey'),
        ),
      ).thenAnswer(
        (_) async => CommentsResponse(
          post: null,
          comments: [ThreadViewComment(comment: topLevelComment())],
        ),
      );
    });

    Future<void> pumpScreen(WidgetTester tester) async {
      useTallSurface(tester);
      recordPlatformChannel(tester);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: mockAuthProvider),
            ChangeNotifierProvider<VoteProvider>.value(value: mockVoteProvider),
            ChangeNotifierProvider<BlockProvider>.value(value: blockProvider),
            Provider<CommentsProviderCache>.value(value: commentsCache),
            Provider<LinkSharer>.value(value: linkSharer),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: PostDetailScreen(post: FeedViewPost(post: parentPost())),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a loaded comment copies the permalink under this post', (
      tester,
    ) async {
      await pumpScreen(tester);

      await openMenuOn(tester, 'Top level comment');

      expect(find.text('Share'), findsOneWidget);
      final copyLink = find.text('Copy link');
      expect(copyLink, findsOneWidget);

      await tester.tap(copyLink);
      await tester.pumpAndSettle();

      expect(clipboardTexts, [topLevelPermalink]);
      expect(find.text('Link copied to clipboard'), findsOneWidget);

      // Loading comments starts the provider's periodic time-update timer.
      // Stop it inside the body: addTearDown runs after the framework's
      // pending-timer check.
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark, home: const SizedBox.shrink()),
      );
      commentsCache.dispose();
    });
  });

  group('FocusedThreadScreen comment share propagation', () {
    late CommentsProvider commentsProvider;

    setUp(() {
      commentsProvider = CommentsProvider(
        mockAuthProvider,
        postUri: postUri,
        postCid: 'cid123',
        apiService: mockApiService,
        voteProvider: mockVoteProvider,
        commentService: mockCommentService,
      );

      // Entry hydration resolves to an empty subtree: the screen keeps
      // rendering the snapshot it was given.
      when(
        mockApiService.getComments(
          postUri: anyNamed('postUri'),
          sort: anyNamed('sort'),
          timeframe: anyNamed('timeframe'),
          depth: anyNamed('depth'),
          limit: anyNamed('limit'),
          cursor: anyNamed('cursor'),
          parentRkey: anyNamed('parentRkey'),
        ),
      ).thenAnswer(
        (_) async => CommentsResponse(post: null, comments: const []),
      );
    });

    tearDown(() {
      commentsProvider.dispose();
    });

    Future<void> pumpFocusedThread(WidgetTester tester) async {
      useTallSurface(tester);
      recordPlatformChannel(tester);

      final anchor = ThreadViewComment(
        comment: topLevelComment(replyCount: 1),
        replies: [
          ThreadViewComment(
            comment: comment(
              uri: nestedCommentUri,
              commenterDid: 'did:plc:commenter555',
              handle: 'carol.coves.social',
              content: 'Nested reply',
            ),
          ),
        ],
      );
      final ancestor = ThreadViewComment(
        comment: comment(
          uri: middleCommentUri,
          commenterDid: 'did:plc:commenter222',
          handle: 'dave.coves.social',
          content: 'Ancestor comment',
          replyCount: 1,
        ),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: mockAuthProvider),
            ChangeNotifierProvider<VoteProvider>.value(value: mockVoteProvider),
            ChangeNotifierProvider<BlockProvider>.value(value: blockProvider),
            Provider<LinkSharer>.value(value: linkSharer),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: FocusedThreadScreen(
              thread: anchor,
              ancestors: [ancestor],
              onReply: (content, facets, parent) async {},
              commentsProvider: commentsProvider,
              parentPost: parentPost(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Entry scrolls the anchor to the top, which pushes the ancestors out
      // of the sliver viewport; scroll back so they are built again.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 800));
      await tester.pumpAndSettle();
    }

    testWidgets('ancestor, anchor and reply all offer the share actions', (
      tester,
    ) async {
      await pumpFocusedThread(tester);

      // All three cards are on screen before their menus are asserted.
      expect(find.byType(CommentCard), findsNWidgets(3));
      expect(find.text('Ancestor comment'), findsOneWidget);
      expect(find.text('Top level comment'), findsOneWidget);
      expect(find.text('Nested reply'), findsOneWidget);

      expect(triggerOn('Ancestor comment'), findsOneWidget);
      expect(triggerOn('Top level comment'), findsOneWidget);
      expect(triggerOn('Nested reply'), findsOneWidget);
    });

    testWidgets('the anchor comment copies its permalink', (tester) async {
      await pumpFocusedThread(tester);

      await openMenuOn(tester, 'Top level comment');

      expect(find.text('Share'), findsOneWidget);
      final copyLink = find.text('Copy link');
      expect(copyLink, findsOneWidget);

      await tester.tap(copyLink);
      await tester.pumpAndSettle();

      expect(clipboardTexts, [topLevelPermalink]);
      expect(find.text('Link copied to clipboard'), findsOneWidget);
    });
  });

  group('profile comment list has no post to share under', () {
    setUp(() {
      when(
        mockApiService.getProfile(actor: anyNamed('actor')),
      ).thenAnswer(
        (_) async => UserProfile(
          did: 'did:plc:commenter789',
          handle: 'bob.coves.social',
        ),
      );
      when(
        mockApiService.getAuthorPosts(
          actor: anyNamed('actor'),
          limit: anyNamed('limit'),
          cursor: anyNamed('cursor'),
        ),
      ).thenAnswer((_) async => TimelineResponse(feed: const []));
      when(
        mockApiService.getActorComments(
          actor: anyNamed('actor'),
          limit: anyNamed('limit'),
          cursor: anyNamed('cursor'),
        ),
      ).thenAnswer(
        (_) async => ActorCommentsResponse(comments: [topLevelComment()]),
      );
    });

    testWidgets('a profile comment offers neither Share nor Copy link', (
      tester,
    ) async {
      useTallSurface(tester);
      recordPlatformChannel(tester);
      addTearDown(() async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark, home: const SizedBox.shrink()),
        );
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: mockAuthProvider),
            ChangeNotifierProvider<VoteProvider>.value(value: mockVoteProvider),
            ChangeNotifierProvider<BlockProvider>.value(value: blockProvider),
            Provider<CovesApiService>.value(value: mockApiService),
            Provider<CommentService>.value(value: mockCommentService),
            Provider<ViewerStateHydrator>(
              create: (_) => ViewerStateHydrator(
                authProvider: mockAuthProvider,
                voteProvider: mockVoteProvider,
              ),
            ),
            Provider<ProfileCache>(
              create: (_) => ProfileCache(mockAuthProvider),
              dispose: (_, cache) => cache.dispose(),
            ),
            Provider<LinkSharer>.value(value: linkSharer),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const ProfileScreen(actor: 'did:plc:commenter789'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Comments'));
      await tester.pumpAndSettle();

      // A profile comment arrives without its post, so no permalink can be
      // built: propagating the post elsewhere must not reach this list.
      expect(find.text('Top level comment'), findsOneWidget);
      expect(find.byTooltip('Comment options'), findsNothing);
      expect(find.text('Share'), findsNothing);
      expect(find.text('Copy link'), findsNothing);
    });
  });
}
