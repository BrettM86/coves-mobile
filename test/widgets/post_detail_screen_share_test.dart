import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/home/post_detail_screen.dart';
import 'package:coves_flutter/services/comments_provider_cache.dart';
import 'package:coves_flutter/services/link_sharer.dart';
import 'package:coves_flutter/widgets/share_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

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

void main() {
  // Literal, never produced by the code under test.
  const expectedWebUrl =
      'https://coves.social/c/gaming/post/alice.coves.social/3kabcxyz';
  const postUri =
      'at://did:plc:author123/social.coves.community.postv2/3kabcxyz';

  late MockAuthProvider mockAuthProvider;
  late MockVoteProvider mockVoteProvider;
  late CommentsProviderCache commentsCache;
  late RecordingLinkSharer linkSharer;
  late List<Object?> clipboardTexts;

  /// A post in the author's own repo, with a valid handle and a community
  /// served by this instance.
  FeedViewPost authorOwnedPost({String uri = postUri}) {
    return FeedViewPost(
      post: PostView(
        uri: uri,
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
        record: const PostRecord(
          content: 'Detail share post',
          title: 'Detail Share Post',
        ),
        stats: PostStats(upvotes: 1, downvotes: 0, score: 1, commentCount: 0),
      ),
    );
  }

  setUp(() {
    mockAuthProvider = MockAuthProvider();
    mockVoteProvider = MockVoteProvider();
    linkSharer = RecordingLinkSharer();
    clipboardTexts = [];

    when(mockAuthProvider.isAuthenticated).thenReturn(true);
    when(mockAuthProvider.did).thenReturn('did:plc:viewer999');
    when(mockVoteProvider.isLiked(any)).thenReturn(false);
    when(mockVoteProvider.getVoteState(any)).thenReturn(null);
    when(mockVoteProvider.isPending(any)).thenReturn(false);
    when(mockVoteProvider.getAdjustedScore(any, any)).thenAnswer(
      (invocation) => invocation.positionalArguments[1] as int,
    );

    commentsCache = CommentsProviderCache(
      authProvider: mockAuthProvider,
      voteProvider: mockVoteProvider,
      commentService: MockCommentService(),
      apiService: MockCovesApiService(),
    );
  });

  /// Pumps the detail screen with a recording `LinkSharer`.
  ///
  /// The post is marked optimistic so the screen skips its initial comment
  /// load: no API call, no pending timers.
  ///
  /// The single mock handler on `SystemChannels.platform` records every
  /// `Clipboard.setData` payload and answers the menu's haptic calls with
  /// null. A handler that only returned null would let a clipboard assertion
  /// pass with no copy happening, so this one is installed last and owns the
  /// channel for the whole test.
  Future<void> pumpScreen(WidgetTester tester, FeedViewPost post) async {
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
    addTearDown(() async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark, home: const SizedBox.shrink()),
      );
      commentsCache.dispose();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: mockAuthProvider),
          ChangeNotifierProvider<VoteProvider>.value(value: mockVoteProvider),
          Provider<CommentsProviderCache>.value(value: commentsCache),
          Provider<LinkSharer>.value(value: linkSharer),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: PostDetailScreen(post: post, isOptimistic: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openOverflowMenu(WidgetTester tester) async {
    final trigger = find.byTooltip('More options');
    expect(trigger, findsOneWidget);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
  }

  group('PostDetailScreen share actions', () {
    testWidgets('app bar share button shares the post web link', (
      tester,
    ) async {
      await pumpScreen(tester, authorOwnedPost());

      final shareButton = find.byType(ShareButton);
      expect(shareButton, findsOneWidget);

      await tester.tap(shareButton);
      await tester.pumpAndSettle();

      expect(linkSharer.sharedUrls, [expectedWebUrl]);
      expect(find.text("Couldn't create link"), findsNothing);
    });

    testWidgets('Copy link copies the web link, not the at-URI', (
      tester,
    ) async {
      await pumpScreen(tester, authorOwnedPost());

      await openOverflowMenu(tester);

      final copyLink = find.text('Copy link');
      expect(copyLink, findsOneWidget);

      await tester.tap(copyLink);
      await tester.pumpAndSettle();

      expect(clipboardTexts, hasLength(1));
      expect(clipboardTexts.single, isNot(startsWith('at://')));
      expect(clipboardTexts.single, expectedWebUrl);
      expect(find.text('Link copied to clipboard'), findsOneWidget);
      // Copying is not sharing: the share sheet must stay shut.
      expect(linkSharer.sharedUrls, isEmpty);
    });

    testWidgets('Copy link reports failure when no link can be built', (
      tester,
    ) async {
      await pumpScreen(tester, authorOwnedPost(uri: 'not-an-at-uri'));

      await openOverflowMenu(tester);

      final copyLink = find.text('Copy link');
      expect(copyLink, findsOneWidget);

      await tester.tap(copyLink);
      await tester.pumpAndSettle();

      expect(clipboardTexts, isEmpty);
      expect(find.text("Couldn't create link"), findsOneWidget);
      expect(find.text('Link copied to clipboard'), findsNothing);
    });
  });
}
