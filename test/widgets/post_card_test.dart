import 'dart:async';

import 'package:coves_flutter/constants/app_colors.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/services/streamable_service.dart';
import 'package:coves_flutter/widgets/icons/animated_heart_icon.dart';
import 'package:coves_flutter/widgets/icons/lucide_icon_painter.dart';
import 'package:coves_flutter/widgets/post_card.dart';
import 'package:coves_flutter/widgets/post_card_actions.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/test_mocks.dart';

void main() {
  late FakeAuthProvider auth;

  setUp(() {
    auth = FakeAuthProvider();
  });

  Widget createTestWidget(
    FeedViewPost post, {
    StreamableService? streamableService,
    AuthProvider? authProvider,
    VoteProvider? voteProvider,
  }) {
    // PostCard's subtree navigates with go_router (TappableAuthor,
    // TappableCommunity, _navigateToDetail), so it needs a router rather
    // than a bare MaterialApp.
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(body: PostCard(post: post)),
        ),
        GoRoute(
          path: '/post/:uri',
          builder: (context, state) =>
              const Scaffold(body: Text('DETAIL SCREEN')),
        ),
      ],
    );
    addTearDown(router.dispose);

    Widget child = MaterialApp.router(routerConfig: router);
    if (authProvider != null || voteProvider != null) {
      child = MultiProvider(
        providers: [
          if (authProvider != null)
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          if (voteProvider != null)
            ChangeNotifierProvider<VoteProvider>.value(value: voteProvider),
        ],
        child: child,
      );
    }

    return MultiProvider(
      providers: postCardProviders(
        auth: auth,
        streamableService: streamableService,
      ),
      child: child,
    );
  }

  group('PostCard', () {
    testWidgets('renders all basic components', (tester) async {
      final post = FeedViewPost(
        post: PostView(
          uri: 'at://did:example/post/123',
          cid: 'cid123',
          rkey: '123',
          author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
          community: CommunityRef(
            did: 'did:plc:community',
            name: 'test-community',
          ),
          createdAt: DateTime(2024),
          indexedAt: DateTime(2024),
          record: const PostRecord(
            content: 'Test post content',
            title: 'Test Post Title',
          ),
          stats: PostStats(
            upvotes: 10,
            downvotes: 2,
            score: 8,
            commentCount: 5,
          ),
        ),
      );

      await tester.pumpWidget(createTestWidget(post));

      // Verify title is displayed
      expect(find.text('Test Post Title'), findsOneWidget);

      // Verify community name is displayed. With no atProto handle set,
      // the card falls back to the bare community name; a handle would
      // render as `!name@instance` via Text.rich instead.
      expect(find.text('test-community'), findsOneWidget);

      // Verify author handle is displayed
      expect(find.text('@author.test'), findsOneWidget);

      // Verify text content is displayed
      expect(find.text('Test post content'), findsOneWidget);

      // Verify stats are displayed
      expect(find.text('8'), findsOneWidget); // score
      expect(find.text('5'), findsOneWidget); // comment count
    });

    testWidgets('renders !name@origin two-tone when origin is served', (
      tester,
    ) async {
      final post = FeedViewPost(
        post: PostView(
          uri: 'at://did:example/post/123',
          cid: 'cid123',
          rkey: '123',
          author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
          community: CommunityRef(
            did: 'did:plc:community',
            name: 'comicstrips',
            origin: 'lemmy.world',
            handle: 'comicstrips.lemmy-world.tdpl.io',
          ),
          createdAt: DateTime(2024),
          indexedAt: DateTime(2024),
          record: const PostRecord(content: 'Body', title: 'Title'),
          stats: PostStats(upvotes: 1, downvotes: 0, score: 1, commentCount: 0),
        ),
      );

      await tester.pumpWidget(createTestWidget(post));

      // Origin wins over the bridged handle; rendered as one Text.rich so
      // the two halves can be styled differently.
      expect(
        find.text('!comicstrips@lemmy.world', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('comicstrips'), findsNothing);
      expect(find.text('comicstrips.lemmy-world.tdpl.io'), findsNothing);
    });

    testWidgets('falls back to the raw handle when it is unrecognised', (
      tester,
    ) async {
      final post = FeedViewPost(
        post: PostView(
          uri: 'at://did:example/post/123',
          cid: 'cid123',
          rkey: '123',
          author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
          community: CommunityRef(
            did: 'did:plc:community',
            name: 'weird',
            handle: 'weird.example.org',
          ),
          createdAt: DateTime(2024),
          indexedAt: DateTime(2024),
          record: const PostRecord(content: 'Body', title: 'Title'),
          stats: PostStats(upvotes: 1, downvotes: 0, score: 1, commentCount: 0),
        ),
      );

      await tester.pumpWidget(createTestWidget(post));

      expect(find.text('weird.example.org'), findsOneWidget);
    });

    testWidgets('formats large stats through the canonical formatter', (
      tester,
    ) async {
      // PostCardActions must render counts the same way every other surface
      // does: uppercase K/M via DisplayUtils.formatCount.
      final post = FeedViewPost(
        post: PostView(
          uri: 'at://did:example/post/123',
          cid: 'cid123',
          rkey: '123',
          author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
          community: CommunityRef(
            did: 'did:plc:community',
            name: 'test-community',
          ),
          createdAt: DateTime(2024),
          indexedAt: DateTime(2024),
          record: const PostRecord(content: 'Test post content'),
          stats: PostStats(
            upvotes: 5234,
            downvotes: 0,
            score: 5234,
            commentCount: 1500000,
          ),
        ),
      );

      await tester.pumpWidget(createTestWidget(post));

      expect(find.text('5.2K'), findsOneWidget); // score
      expect(find.text('1.5M'), findsOneWidget); // comment count
      expect(find.text('5.2k'), findsNothing);
      expect(find.text('1500.0k'), findsNothing);
    });

    testWidgets('displays community avatar when available', (tester) async {
      final post = FeedViewPost(
        post: PostView(
          uri: 'at://did:example/post/123',
          cid: 'cid123',
          rkey: '123',
          author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
          community: CommunityRef(
            did: 'did:plc:community',
            name: 'test-community',
            avatar: 'https://example.com/avatar.jpg',
          ),
          createdAt: DateTime(2024),
          indexedAt: DateTime(2024),
          stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
        ),
      );

      await tester.pumpWidget(createTestWidget(post));
      await tester.pumpAndSettle();

      // Avatar image should be present
      expect(find.byType(Image), findsWidgets);
    });

    testWidgets('shows fallback avatar when no avatar URL', (tester) async {
      final post = FeedViewPost(
        post: PostView(
          uri: 'at://did:example/post/123',
          cid: 'cid123',
          rkey: '123',
          author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
          community: CommunityRef(
            did: 'did:plc:community',
            name: 'TestCommunity',
          ),
          createdAt: DateTime(2024),
          indexedAt: DateTime(2024),
          stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
        ),
      );

      await tester.pumpWidget(createTestWidget(post));

      // Verify fallback shows first letter
      expect(find.text('T'), findsOneWidget);
    });

    testWidgets('displays external link bar when embed present', (
      tester,
    ) async {
      final post = FeedViewPost(
        post: PostView(
          uri: 'at://did:example/post/123',
          cid: 'cid123',
          rkey: '123',
          author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
          community: CommunityRef(
            did: 'did:plc:community',
            name: 'test-community',
          ),
          createdAt: DateTime(2024),
          indexedAt: DateTime(2024),
          stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
          embed: ExternalPostEmbed(
            type: 'social.coves.embed.external',
            external: ExternalEmbed(
              uri: 'https://example.com/article',
              domain: 'example.com',
              title: 'Example Article',
            ),
            data: const {},
          ),
        ),
      );

      await tester.pumpWidget(createTestWidget(post));

      // Verify external link bar is present
      expect(find.text('example.com'), findsOneWidget);
      expect(find.byIcon(Icons.open_in_new), findsOneWidget);
    });

    testWidgets('displays embed image when available', (tester) async {
      final post = FeedViewPost(
        post: PostView(
          uri: 'at://did:example/post/123',
          cid: 'cid123',
          rkey: '123',
          author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
          community: CommunityRef(
            did: 'did:plc:community',
            name: 'test-community',
          ),
          createdAt: DateTime(2024),
          indexedAt: DateTime(2024),
          stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
          embed: ExternalPostEmbed(
            type: 'social.coves.embed.external',
            external: ExternalEmbed(
              uri: 'https://example.com/article',
              thumb: 'https://example.com/thumb.jpg',
            ),
            data: const {},
          ),
        ),
      );

      await tester.pumpWidget(createTestWidget(post));
      await tester.pump();

      // Embed image should be loading/present
      expect(find.byType(Image), findsWidgets);
    });

    testWidgets('renders without title', (tester) async {
      final post = FeedViewPost(
        post: PostView(
          uri: 'at://did:example/post/123',
          cid: 'cid123',
          rkey: '123',
          author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
          community: CommunityRef(
            did: 'did:plc:community',
            name: 'test-community',
          ),
          createdAt: DateTime(2024),
          indexedAt: DateTime(2024),
          record: const PostRecord(content: 'Just body text'),
          stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
        ),
      );

      await tester.pumpWidget(createTestWidget(post));

      // Should render without errors
      expect(find.text('Just body text'), findsOneWidget);
      expect(find.text('test-community'), findsOneWidget);
    });

    testWidgets('has action buttons', (tester) async {
      final post = FeedViewPost(
        post: PostView(
          uri: 'at://did:example/post/123',
          cid: 'cid123',
          rkey: '123',
          author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
          community: CommunityRef(
            did: 'did:plc:community',
            name: 'test-community',
          ),
          createdAt: DateTime(2024),
          indexedAt: DateTime(2024),
          stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
        ),
      );

      await tester.pumpWidget(createTestWidget(post));

      // Verify action buttons are present
      expect(find.byIcon(Icons.more_horiz), findsOneWidget); // menu
      // Share, comment, and heart icons are custom widgets, verify by count
      expect(find.byType(InkWell), findsWidgets);
    });

    testWidgets('displays play button overlay for Streamable videos', (
      tester,
    ) async {
      final post = FeedViewPost(
        post: PostView(
          uri: 'at://did:example/post/123',
          cid: 'cid123',
          rkey: '123',
          author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
          community: CommunityRef(
            did: 'did:plc:community',
            name: 'test-community',
          ),
          createdAt: DateTime(2024),
          indexedAt: DateTime(2024),
          stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
          embed: ExternalPostEmbed(
            type: 'social.coves.embed.external',
            external: ExternalEmbed(
              uri: 'https://streamable.com/abc123',
              thumb: 'https://example.com/thumb.jpg',
              embedType: 'video',
              provider: 'streamable',
            ),
            data: const {},
          ),
        ),
      );

      await tester.pumpWidget(createTestWidget(post));
      await tester.pump();

      // Verify play button is displayed
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets(
      'shows loading indicator when fetching video URL for Streamable',
      (tester) async {
        final dio = Dio(BaseOptions(baseUrl: 'https://api.streamable.com'));
        final dioAdapter = DioAdapter(dio: dio);
        final streamableService = StreamableService(dio: dio);

        // The service requests the absolute URL, so the mock must be
        // registered against the full path, not a baseUrl-relative one.
        //
        // The reply carries no `files` entry, so getVideoUrl resolves to
        // null and the widget shows a snackbar instead of pushing
        // FullscreenVideoPlayer — mounting that player would hit the
        // video_player platform channel, which throws UnimplementedError
        // under flutter_test. The delay is what makes the loading state
        // observable before the request settles.
        dioAdapter.onGet(
          'https://api.streamable.com/videos/abc123',
          (server) => server.reply(
            200,
            <String, dynamic>{},
            delay: const Duration(milliseconds: 500),
          ),
        );

        final post = FeedViewPost(
          post: PostView(
            uri: 'at://did:example/post/123',
            cid: 'cid123',
            rkey: '123',
            author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
            community: CommunityRef(
              did: 'did:plc:community',
              name: 'test-community',
            ),
            createdAt: DateTime(2024),
            indexedAt: DateTime(2024),
            stats: PostStats(
              upvotes: 0,
              downvotes: 0,
              score: 0,
              commentCount: 0,
            ),
            embed: ExternalPostEmbed(
              type: 'social.coves.embed.external',
              external: ExternalEmbed(
                uri: 'https://streamable.com/abc123',
                thumb: 'https://example.com/thumb.jpg',
                embedType: 'video',
                provider: 'streamable',
              ),
              data: const {},
            ),
          ),
        );

        await tester.pumpWidget(
          createTestWidget(post, streamableService: streamableService),
        );
        await tester.pump();

        // Tap the play button
        await tester.tap(find.byIcon(Icons.play_arrow));
        await tester.pump();

        // Verify loading indicator is displayed
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        // Drain the request delay and the resulting snackbar so no timer
        // is left pending when the test tears down.
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();

        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );

    testWidgets('does not show play button for non-video embeds', (
      tester,
    ) async {
      final post = FeedViewPost(
        post: PostView(
          uri: 'at://did:example/post/123',
          cid: 'cid123',
          rkey: '123',
          author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
          community: CommunityRef(
            did: 'did:plc:community',
            name: 'test-community',
          ),
          createdAt: DateTime(2024),
          indexedAt: DateTime(2024),
          stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
          embed: ExternalPostEmbed(
            type: 'social.coves.embed.external',
            external: ExternalEmbed(
              uri: 'https://example.com/article',
              thumb: 'https://example.com/thumb.jpg',
            ),
            data: const {},
          ),
        ),
      );

      await tester.pumpWidget(createTestWidget(post));
      await tester.pump();

      // Verify play button is NOT displayed
      expect(find.byIcon(Icons.play_arrow), findsNothing);
    });

    group('post card vote group', () {
      const postUri = 'at://did:plc:author/social.coves.community.post/123';
      const postCid = 'bafy-post-cid';
      final thumbsDownPaths = <String>[
        <String>[
          'M9 18.12 10 14H4.17a2 2 0 0 1-1.92-2.56',
          'l2.33-8A2 2 0 0 1 6.5 2H20a2 2 0 0 1 2 2v8',
          'a2 2 0 0 1-2 2h-2.76a2 2 0 0 0-1.79 1.11',
          'L12 22a3.13 3.13 0 0 1-3-3.88Z',
        ].join(),
        'M17 14V2',
      ];

      late MockAuthProvider mockAuthProvider;
      late MockVoteProvider mockVoteProvider;

      FeedViewPost votePost({int commentCount = 0}) {
        return FeedViewPost(
          post: PostView(
            uri: postUri,
            cid: postCid,
            rkey: '123',
            author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
            community: CommunityRef(
              did: 'did:plc:community',
              name: 'test-community',
            ),
            createdAt: DateTime(2024),
            indexedAt: DateTime(2024),
            record: const PostRecord(content: 'Vote controls'),
            stats: PostStats(
              upvotes: 6,
              downvotes: 1,
              score: 5,
              commentCount: commentCount,
            ),
          ),
        );
      }

      Finder actionRow() => find.byType(PostCardActions);

      Finder heartControl() => find.descendant(
        of: actionRow(),
        matching: find.byType(AnimatedHeartIcon),
      );

      Finder upvoteControl(String actionLabel) => find.descendant(
        of: actionRow(),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.label == actionLabel,
          description: 'Semantics labelled "$actionLabel"',
        ),
      );

      Finder scoreText(String score) =>
          find.descendant(of: actionRow(), matching: find.text(score));

      Finder downvoteControl(String actionLabel) {
        final semanticDownvote = find.descendant(
          of: actionRow(),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.label == actionLabel,
            description: 'Semantics labelled "$actionLabel"',
          ),
        );
        final tooltipDownvote = find.descendant(
          of: actionRow(),
          matching: find.byWidgetPredicate(
            (widget) => widget is Tooltip && widget.message == actionLabel,
            description: 'Tooltip labelled "$actionLabel"',
          ),
        );
        return semanticDownvote.evaluate().isNotEmpty
            ? semanticDownvote
            : tooltipDownvote;
      }

      LucideIconPainter? downvotePainter(
        WidgetTester tester,
        String actionLabel,
      ) {
        final downvote = downvoteControl(actionLabel);
        if (downvote.evaluate().length != 1) {
          return null;
        }
        final paints = find.descendant(
          of: downvote,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is CustomPaint && widget.painter is LucideIconPainter,
            description: 'CustomPaint with a LucideIconPainter',
          ),
        );
        if (paints.evaluate().length != 1) {
          return null;
        }
        final painter = tester.widget<CustomPaint>(paints.first).painter;
        return painter is LucideIconPainter ? painter : null;
      }

      bool usesCanonicalThumbsDownPaths(LucideIconPainter? painter) {
        final paths = painter?.paths;
        if (paths == null || paths.length != thumbsDownPaths.length) {
          return false;
        }
        for (var index = 0; index < paths.length; index++) {
          if (paths[index] != thumbsDownPaths[index]) {
            return false;
          }
        }
        return true;
      }

      Color? effectiveScoreColor(WidgetTester tester, Finder score) {
        final text = tester.widget<Text>(score);
        return text.style?.color ??
            DefaultTextStyle.of(tester.element(score)).style.color;
      }

      void expectMinimumTapTargets(
        WidgetTester tester,
        Map<String, Finder> controls,
      ) {
        final undersized = <String, Size>{};
        for (final entry in controls.entries) {
          final size = tester.getSize(entry.value);
          if (size.width < 48 || size.height < 48) {
            undersized[entry.key] = size;
          }
        }
        expect(
          undersized,
          isEmpty,
          reason: 'interactive vote render boxes must be at least 48x48',
        );
      }

      Future<void> pumpVotePost(
        WidgetTester tester, {
        Future<Object?>? hapticFuture,
      }) {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (methodCall) {
            if (hapticFuture != null &&
                methodCall.method == 'HapticFeedback.vibrate') {
              return hapticFuture;
            }
            return Future<Object?>.value();
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        return tester.pumpWidget(
          createTestWidget(
            votePost(),
            authProvider: mockAuthProvider,
            voteProvider: mockVoteProvider,
          ),
        );
      }

      setUp(() {
        mockAuthProvider = MockAuthProvider();
        mockVoteProvider = MockVoteProvider();

        when(mockAuthProvider.isAuthenticated).thenReturn(true);
        when(mockAuthProvider.did).thenReturn('did:plc:viewer');
        when(mockVoteProvider.isLiked(postUri)).thenReturn(false);
        when(mockVoteProvider.getVoteState(postUri)).thenReturn(null);
        when(mockVoteProvider.isPending(postUri)).thenReturn(false);
        when(mockVoteProvider.getAdjustedScore(postUri, 5)).thenReturn(4);
        when(
          mockVoteProvider.toggleVote(
            postUri: anyNamed('postUri'),
            postCid: anyNamed('postCid'),
            direction: anyNamed('direction'),
          ),
        ).thenAnswer((_) async => true);
      });

      testWidgets('orders heart, one adjusted score, then downvote', (
        tester,
      ) async {
        await pumpVotePost(tester);

        final heart = heartControl();
        final upvote = upvoteControl('Upvote post');
        final score = scoreText('4');
        final downvote = downvoteControl('Downvote post');
        expect(heart, findsOneWidget);
        expect(upvote, findsOneWidget);
        expect(score, findsOneWidget);
        expect(tester.getTopLeft(score).dx - tester.getTopRight(heart).dx, 5);
        expect(find.descendant(of: upvote, matching: score), findsOneWidget);
        expect(
          downvote,
          findsOneWidget,
          reason: 'the post-card action row needs a separate downvote control',
        );
        expect(
          tester.getCenter(heart).dx,
          lessThan(tester.getCenter(score).dx),
        );
        expect(
          tester.getCenter(score).dx,
          lessThan(tester.getCenter(downvote).dx),
        );
        expectMinimumTapTargets(tester, {
          'post card upvote': upvote,
          'post card downvote': downvote,
        });
      });

      testWidgets('liked score is red beside the heart', (tester) async {
        when(mockVoteProvider.isLiked(postUri)).thenReturn(true);
        await pumpVotePost(tester);
        expect(
          effectiveScoreColor(tester, scoreText('4')),
          AppColors.voteLiked,
        );
      });

      testWidgets('authenticated downvote requests the down direction', (
        tester,
      ) async {
        await pumpVotePost(tester);

        final downvote = downvoteControl('Downvote post');
        expect(
          downvote,
          findsOneWidget,
          reason: 'the authenticated downvote action must be rendered',
        );
        await tester.tap(downvote);
        await tester.pumpAndSettle();

        verify(
          mockVoteProvider.toggleVote(
            postUri: postUri,
            postCid: postCid,
            direction: 'down',
          ),
        ).called(1);
      });

      testWidgets('compact card keeps the comment action without its count', (
        tester,
      ) async {
        addTearDown(tester.view.reset);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(340, 800);

        await tester.pumpWidget(
          createTestWidget(
            votePost(commentCount: 123),
            authProvider: mockAuthProvider,
            voteProvider: mockVoteProvider,
          ),
        );

        expect(tester.takeException(), isNull);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label == 'View 123 comments',
          ),
          findsOneWidget,
        );
        expect(find.text('123'), findsNothing);
        expect(scoreText('4'), findsOneWidget);
      });

      testWidgets(
        'starts post-card downvote mutation before haptic feedback completes',
        (tester) async {
          final hapticGate = Completer<Object?>();
          addTearDown(() {
            if (!hapticGate.isCompleted) {
              hapticGate.complete(null);
            }
          });
          await pumpVotePost(tester, hapticFuture: hapticGate.future);

          final downvote = downvoteControl('Downvote post');
          expect(downvote, findsOneWidget);
          await tester.tap(downvote);
          await tester.pump();

          try {
            expect(hapticGate.isCompleted, isFalse);
            verify(
              mockVoteProvider.toggleVote(
                postUri: postUri,
                postCid: postCid,
                direction: 'down',
              ),
            ).called(1);
          } finally {
            if (!hapticGate.isCompleted) {
              hapticGate.complete(null);
            }
            await tester.pump();
          }
        },
      );

      testWidgets('existing downvote is teal and keeps score neutral', (
        tester,
      ) async {
        when(mockVoteProvider.getVoteState(postUri))
            .thenReturn(const VoteState(direction: 'down', deleted: false));
        await pumpVotePost(tester);

        final downvote = downvoteControl('Remove downvote');
        expect(
          find.descendant(
            of: actionRow(),
            matching: find.byTooltip('Remove downvote'),
          ),
          findsOneWidget,
        );
        final painter = downvotePainter(tester, 'Remove downvote');
        final score = scoreText('4');
        final scoreColor = effectiveScoreColor(tester, score);
        expect(score, findsOneWidget);
        expect(
          (
            downvoteVisible: downvote.evaluate().length == 1,
            usesLucidePainter: painter != null,
            usesCanonicalPaths: usesCanonicalThumbsDownPaths(painter),
            selectedIsFilled: painter?.filled ?? false,
            selectedIsTeal: painter?.color == AppColors.teal,
            scoreIsNeutral:
                scoreColor != AppColors.teal &&
                scoreColor != AppColors.voteLiked,
          ),
          (
            downvoteVisible: true,
            usesLucidePainter: true,
            usesCanonicalPaths: true,
            selectedIsFilled: false,
            selectedIsTeal: true,
            scoreIsNeutral: true,
          ),
        );
        verify(mockVoteProvider.getVoteState(postUri)).called(1);
      });

      testWidgets('pending vote keeps both controls visible and inert', (
        tester,
      ) async {
        final requestedDirections = <String?>[];
        when(mockVoteProvider.isPending(postUri)).thenReturn(true);
        when(mockVoteProvider.getVoteState(postUri))
            .thenReturn(const VoteState(direction: 'down', deleted: false));
        when(mockVoteProvider.getAdjustedScore(postUri, 5)).thenReturn(3);
        when(
          mockVoteProvider.toggleVote(
            postUri: anyNamed('postUri'),
            postCid: anyNamed('postCid'),
            direction: anyNamed('direction'),
          ),
        ).thenAnswer((invocation) async {
          requestedDirections.add(
            invocation.namedArguments[#direction] as String?,
          );
          return true;
        });
        await pumpVotePost(tester);

        final heart = heartControl();
        final downvote = downvoteControl('Remove downvote');
        final downvoteVisible = downvote.evaluate().length == 1;
        final painter = downvotePainter(tester, 'Remove downvote');
        await tester.tap(heart);
        if (downvoteVisible) {
          await tester.tap(downvote);
        }
        await tester.pumpAndSettle();

        expect(
          (
            heartVisible: heart.evaluate().length == 1,
            downvoteVisible: downvoteVisible,
            optimisticScoreVisible: scoreText('3').evaluate().length == 1,
            optimisticDownvoteSelected: painter?.color == AppColors.teal,
            mutationCalls: requestedDirections.length,
            spinnerVisible: find
                .byType(CircularProgressIndicator)
                .evaluate()
                .isNotEmpty,
          ),
          (
            heartVisible: true,
            downvoteVisible: true,
            optimisticScoreVisible: true,
            optimisticDownvoteSelected: true,
            mutationCalls: 0,
            spinnerVisible: false,
          ),
        );
        verify(mockVoteProvider.isPending(postUri)).called(1);
      });
    });
  });
}
