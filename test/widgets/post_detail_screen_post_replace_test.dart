// An open post detail follows published replacements of its own post (so a
// server NSFW label blurs it in place) and stops listening once popped.
import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/moderation.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/post_get_result.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/home/post_detail_loader.dart';
import 'package:coves_flutter/screens/home/post_detail_screen.dart';
import 'package:coves_flutter/services/comments_provider_cache.dart';
import 'package:coves_flutter/services/post_change_broadcast.dart';
import 'package:coves_flutter/widgets/sensitive_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/pump_helpers.dart';
import '../test_helpers/test_mocks.dart';

const _signedInDid = 'did:plc:me';
const _postUri = 'at://did:plc:author/social.coves.community.post/p1';
const _otherUri = 'at://did:plc:author/social.coves.community.post/q1';
const _postBody = 'Body of the post in detail';
const _otherTitle = 'A different post';

const _nsfwModeration = ModerationView(
  state: ModerationState.clear,
  contentLabels: [ContentLabelView(value: 'nsfw')],
);

PostView _postView(
  String uri, {
  required String title,
  required String body,
  ModerationView? moderation,
}) => PostView(
  uri: uri,
  cid: 'cid-${uri.split('/').last}',
  rkey: uri.split('/').last,
  author: AuthorView(did: 'did:plc:author', handle: 'author.coves.test'),
  community: CommunityRef(did: 'did:plc:community', name: 'testcove'),
  createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
  indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
  record: PostRecord(title: title, content: body),
  stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
  moderation: moderation,
);

PostView _post({ModerationView? moderation}) => _postView(
  _postUri,
  title: 'Post in detail',
  body: _postBody,
  moderation: moderation,
);

void main() {
  late FakeAuthProvider auth;
  late MockCovesApiService api;

  setUp(() {
    auth = FakeAuthProvider(
      signedInDid: _signedInDid,
      signedInHandle: 'me.coves.test',
    );
    api = MockCovesApiService();
    when(api.getViewerAuthority()).thenAnswer((_) async => true);
    when(
      api.getComments(
        postUri: anyNamed('postUri'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        depth: anyNamed('depth'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
        parentRkey: anyNamed('parentRkey'),
      ),
    ).thenAnswer((_) async => CommentsResponse(post: null, comments: const []));
  });
  tearDown(() => auth.dispose());

  testWidgets('B9 an open post detail blurs on its own post replacement only '
      'and ignores replacements once popped', (tester) async {
    final broadcast = PostChangeBroadcast();
    final navigatorKey = GlobalKey<NavigatorState>();
    final commentService = MockCommentService();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ...profileScreenProviders(
            auth: auth,
            apiService: api,
            commentService: commentService,
            postChangeBroadcast: broadcast,
          ),
          Provider<CommentsProviderCache>(
            create: (context) => CommentsProviderCache(
              authProvider: auth,
              voteProvider: context.read<VoteProvider>(),
              commentService: commentService,
              apiService: api,
            ),
            dispose: (_, cache) => cache.dispose(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Text('Home')),
        ),
      ),
    );
    unawaited(
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => PostDetailScreen(
            sessionStamp: null,
            post: FeedViewPost(post: _post()),
          ),
        ),
      ),
    );
    await pumpFrames(tester);
    final detail = find.byType(PostDetailScreen);
    expect(detail, findsOneWidget);
    expect(
      find.descendant(of: detail, matching: find.text(_postBody)),
      findsOneWidget,
    );

    // Another post's replacement leaves this post's header as it was.
    broadcast.replacePost(
      _postView(
        _otherUri,
        title: _otherTitle,
        body: 'Body of a different post',
        moderation: _nsfwModeration,
      ),
    );
    await pumpFrames(tester);
    expect(
      find.descendant(
        of: detail,
        matching: find.byType(SensitiveContentBanner),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: detail, matching: find.text(_postBody)),
      findsOneWidget,
    );
    expect(find.text(_otherTitle), findsNothing);

    // This post's replacement carrying a server NSFW label conceals it.
    broadcast.replacePost(_post(moderation: _nsfwModeration));
    await pumpFrames(tester);
    expect(
      find.descendant(
        of: detail,
        matching: find.byWidgetPredicate(
          (widget) => widget is SensitiveContentBanner && widget.concealed,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: detail, matching: find.text(_postBody)),
      findsNothing,
    );

    // Once popped, the screen no longer reacts to replacements.
    navigatorKey.currentState!.pop();
    await pumpFrames(tester);
    expect(detail, findsNothing);
    broadcast.replacePost(_post(moderation: _nsfwModeration));
    await pumpFrames(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('B9 a cold-loaded post detail keeps a replacement of its post '
      'when its parent rebuilds with the same post', (tester) async {
    final broadcast = PostChangeBroadcast();
    final commentService = MockCommentService();
    final parentRebuild = ValueNotifier<int>(0);
    addTearDown(parentRebuild.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ...profileScreenProviders(
            auth: auth,
            apiService: api,
            commentService: commentService,
            postChangeBroadcast: broadcast,
          ),
          Provider<CommentsProviderCache>(
            create: (context) => CommentsProviderCache(
              authProvider: auth,
              voteProvider: context.read<VoteProvider>(),
              commentService: commentService,
              apiService: api,
            ),
            dispose: (_, cache) => cache.dispose(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: ValueListenableBuilder<int>(
            valueListenable: parentRebuild,
            builder: (context, _, _) => PostDetailLoader(
              postUri: _postUri,
              fetchPost: (_) async => PostGetSuccess(_post()),
            ),
          ),
        ),
      ),
    );
    await pumpFrames(tester);
    final detail = find.byType(PostDetailScreen);
    expect(detail, findsOneWidget);
    expect(
      find.descendant(of: detail, matching: find.text(_postBody)),
      findsOneWidget,
    );

    final concealedBanner = find.descendant(
      of: detail,
      matching: find.byWidgetPredicate(
        (widget) => widget is SensitiveContentBanner && widget.concealed,
      ),
    );
    broadcast.replacePost(_post(moderation: _nsfwModeration));
    await pumpFrames(tester);
    expect(concealedBanner, findsOneWidget);

    // The loader rebuilds PostDetailScreen from its first-loaded result,
    // as a router rebuilding its pages does; the replacement must survive.
    parentRebuild.value++;
    await pumpFrames(tester);
    expect(
      concealedBanner,
      findsOneWidget,
      reason: 'a same-post rebuild must not revert the NSFW replacement',
    );
    expect(
      find.descendant(of: detail, matching: find.text(_postBody)),
      findsNothing,
    );
  });
}
