import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/services/streamable_service.dart';
import 'package:coves_flutter/widgets/post_card.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:provider/provider.dart';

import '../test_helpers/mock_providers.dart';

void main() {
  late MockAuthProvider mockAuthProvider;
  late MockVoteProvider mockVoteProvider;

  setUp(() {
    mockAuthProvider = MockAuthProvider();
    mockVoteProvider = MockVoteProvider();
  });

  Widget createTestWidget(
    FeedViewPost post, {
    StreamableService? streamableService,
  }) {
    return MultiProvider(
      providers: [
        // ignore: argument_type_not_assignable
        ChangeNotifierProvider<MockAuthProvider>.value(value: mockAuthProvider),
        // ignore: argument_type_not_assignable
        ChangeNotifierProvider<MockVoteProvider>.value(value: mockVoteProvider),
        Provider<StreamableService>.value(
          value: streamableService ?? StreamableService(),
        ),
      ],
      child: MaterialApp(home: Scaffold(body: PostCard(post: post))),
    );
  }

  group(
    'PostCard',
    skip: 'Provider type compatibility issues - needs mock refactoring',
    () {
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
            text: 'Test post content',
            title: 'Test Post Title',
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

        // Verify community name is displayed
        expect(find.text('c/test-community'), findsOneWidget);

        // Verify author handle is displayed
        expect(find.text('@author.test'), findsOneWidget);

        // Verify text content is displayed
        expect(find.text('Test post content'), findsOneWidget);

        // Verify stats are displayed
        expect(find.text('8'), findsOneWidget); // score
        expect(find.text('5'), findsOneWidget); // comment count
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
            text: '',
            stats: PostStats(
              upvotes: 0,
              downvotes: 0,
              score: 0,
              commentCount: 0,
            ),
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
            text: '',
            stats: PostStats(
              upvotes: 0,
              downvotes: 0,
              score: 0,
              commentCount: 0,
            ),
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
            text: '',
            stats: PostStats(
              upvotes: 0,
              downvotes: 0,
              score: 0,
              commentCount: 0,
            ),
            embed: PostEmbed(
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
            text: '',
            stats: PostStats(
              upvotes: 0,
              downvotes: 0,
              score: 0,
              commentCount: 0,
            ),
            embed: PostEmbed(
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
            text: 'Just body text',
            stats: PostStats(
              upvotes: 0,
              downvotes: 0,
              score: 0,
              commentCount: 0,
            ),
          ),
        );

        await tester.pumpWidget(createTestWidget(post));

        // Should render without errors
        expect(find.text('Just body text'), findsOneWidget);
        expect(find.text('c/test-community'), findsOneWidget);
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
            text: '',
            stats: PostStats(
              upvotes: 0,
              downvotes: 0,
              score: 0,
              commentCount: 0,
            ),
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
            text: '',
            stats: PostStats(
              upvotes: 0,
              downvotes: 0,
              score: 0,
              commentCount: 0,
            ),
            embed: PostEmbed(
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

          // Delay the response to test loading state
          dioAdapter.onGet(
            '/videos/abc123',
            (server) => server.reply(200, {
              'files': {
                'mp4': {'url': '//cdn.streamable.com/video.mp4'},
              },
            }, delay: const Duration(milliseconds: 500)),
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
              text: '',
              stats: PostStats(
                upvotes: 0,
                downvotes: 0,
                score: 0,
                commentCount: 0,
              ),
              embed: PostEmbed(
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
            text: '',
            stats: PostStats(
              upvotes: 0,
              downvotes: 0,
              score: 0,
              commentCount: 0,
            ),
            embed: PostEmbed(
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
    },
  );
}
