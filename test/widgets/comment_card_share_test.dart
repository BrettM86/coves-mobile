import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/services/link_sharer.dart';
import 'package:coves_flutter/widgets/comment_card.dart';
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
  final List<({String url, Rect origin})> shares = [];

  @override
  Future<void> shareLink(
    String url, {
    required Rect sharePositionOrigin,
  }) async {
    shares.add((url: url, origin: sharePositionOrigin));
  }
}

/// A `LinkSharer` whose dispatch fails the way a platform channel can.
class FailingLinkSharer implements LinkSharer {
  int callCount = 0;

  @override
  Future<void> shareLink(
    String url, {
    required Rect sharePositionOrigin,
  }) async {
    callCount++;
    throw PlatformException(code: 'share_failed');
  }
}

void main() {
  // Literal, never produced by the code under test.
  const expectedPermalink =
      'https://coves.social/c/gaming/post/alice.coves.social/3kabcxyz'
      '/comment/bob.coves.social/3kcmt001';
  const parentPostUri =
      'at://did:plc:author123/social.coves.community.postv2/3kabcxyz';
  const commentUri =
      'at://did:plc:commenter789/social.coves.community.comment/3kcmt001';

  late MockAuthProvider mockAuthProvider;
  late MockVoteProvider mockVoteProvider;
  late BlockProvider blockProvider;
  late RecordingLinkSharer linkSharer;
  late List<Object?> clipboardTexts;

  /// The post the comment belongs to: author-owned repo, valid handle, and a
  /// community served by this instance.
  PostView parentPost() {
    return PostView(
      uri: parentPostUri,
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
      stats: PostStats(upvotes: 1, downvotes: 0, score: 1, commentCount: 1),
    );
  }

  /// The comment under test. [postRefUri] is the post the comment itself
  /// says it hangs under, which normally matches the parent post handed to
  /// the card.
  CommentView comment({String postRefUri = parentPostUri}) {
    return CommentView(
      uri: commentUri,
      cid: 'cid-comment',
      record: const CommentRecord(content: 'Shareable comment'),
      createdAt: DateTime(2025),
      indexedAt: DateTime(2025),
      author: AuthorView(
        did: 'did:plc:commenter789',
        handle: 'bob.coves.social',
      ),
      post: CommentRef(uri: postRefUri, cid: 'cid123'),
      stats: const CommentStats(upvotes: 5, downvotes: 1, score: 4),
    );
  }

  /// A deleted comment: the backend withholds both the record and the author
  /// so the deleted content and its author's identity never ship.
  CommentView deletedComment() {
    return CommentView(
      uri: commentUri,
      cid: 'cid-comment',
      isDeleted: true,
      createdAt: DateTime(2025),
      indexedAt: DateTime(2025),
      post: CommentRef(uri: parentPostUri, cid: 'cid123'),
      stats: const CommentStats(upvotes: 5, downvotes: 1, score: 4),
    );
  }

  setUp(() {
    mockAuthProvider = MockAuthProvider();
    mockVoteProvider = MockVoteProvider();
    linkSharer = RecordingLinkSharer();
    clipboardTexts = [];

    // Signed-in viewer who is not the comment author, so the menu carries the
    // moderation items a non-author sees.
    when(mockAuthProvider.isAuthenticated).thenReturn(true);
    when(mockAuthProvider.did).thenReturn('did:plc:viewer999');
    when(mockVoteProvider.isLiked(any)).thenReturn(false);
    when(mockVoteProvider.getVoteState(any)).thenReturn(null);
    when(mockVoteProvider.isPending(any)).thenReturn(false);
    when(mockVoteProvider.getAdjustedScore(any, any)).thenAnswer(
      (invocation) => invocation.positionalArguments[1] as int,
    );
    blockProvider = BlockProvider(
      apiService: MockCovesApiService(),
      authProvider: mockAuthProvider,
    );
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

  /// The providers and themed app the card lives under, around whatever
  /// [body] the test wants — the card, or a tree that no longer holds it.
  Widget wrap(Widget body, {LinkSharer? sharer}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: mockAuthProvider),
        ChangeNotifierProvider<VoteProvider>.value(value: mockVoteProvider),
        ChangeNotifierProvider<BlockProvider>.value(value: blockProvider),
        Provider<LinkSharer>.value(value: sharer ?? linkSharer),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: body),
      ),
    );
  }

  Future<void> pumpCard(
    WidgetTester tester, {
    required PostView? post,
    LinkSharer? sharer,
    CommentView? view,
  }) async {
    recordPlatformChannel(tester);

    await tester.pumpWidget(
      wrap(
        CommentCard(comment: view ?? comment(), parentPost: post),
        sharer: sharer,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openCommentMenu(WidgetTester tester) async {
    final trigger = find.byTooltip('Comment options');
    expect(trigger, findsOneWidget);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
  }

  group('CommentCard share actions', () {
    testWidgets('Share dispatches the comment permalink with an anchor rect', (
      tester,
    ) async {
      await pumpCard(tester, post: parentPost());
      await openCommentMenu(tester);

      // Sharing joins the moderation items rather than replacing them.
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Copy link'), findsOneWidget);
      expect(find.text('Block @bob.coves.social'), findsOneWidget);
      expect(find.text('Report comment'), findsOneWidget);

      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();

      expect(linkSharer.shares, hasLength(1));
      expect(linkSharer.shares.single.url, expectedPermalink);
      // iPad anchors the share popover to this rect, and the tapped menu item
      // is gone by the time the sheet opens, so it must be the trigger's.
      expect(linkSharer.shares.single.origin.width, greaterThan(0));
      expect(linkSharer.shares.single.origin.height, greaterThan(0));
      // Sharing is not copying.
      expect(clipboardTexts, isEmpty);
    });

    testWidgets('Copy link copies the comment permalink', (tester) async {
      await pumpCard(tester, post: parentPost());
      await openCommentMenu(tester);

      expect(find.text('Copy link'), findsOneWidget);

      await tester.tap(find.text('Copy link'));
      await tester.pumpAndSettle();

      expect(clipboardTexts, [expectedPermalink]);
      expect(find.text('Link copied to clipboard'), findsOneWidget);
      // Copying is not sharing: the share sheet must stay shut.
      expect(linkSharer.shares, isEmpty);
    });

    testWidgets('signed-out viewer gets share and copy only', (tester) async {
      when(mockAuthProvider.isAuthenticated).thenReturn(false);
      when(mockAuthProvider.did).thenReturn(null);

      await pumpCard(tester, post: parentPost());

      // Today the trigger itself is signed-in only; sharing is not.
      final trigger = find.byTooltip('Comment options');
      expect(trigger, findsOneWidget);
      await tester.tap(trigger);
      await tester.pumpAndSettle();

      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Copy link'), findsOneWidget);
      // The moderation items stay signed-in only, exactly as today.
      expect(find.text('Block @bob.coves.social'), findsNothing);
      expect(find.text('Unblock @bob.coves.social'), findsNothing);
      expect(find.text('Report comment'), findsNothing);
      expect(find.text('Delete comment'), findsNothing);
    });

    testWidgets('LinkSharer failure reports instead of throwing', (
      tester,
    ) async {
      final failingSharer = FailingLinkSharer();

      await pumpCard(tester, post: parentPost(), sharer: failingSharer);
      await openCommentMenu(tester);

      expect(find.text('Share'), findsOneWidget);

      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();

      expect(failingSharer.callCount, 1);
      expect(find.text("Couldn't share link"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no parent post leaves the menu exactly as it is', (
      tester,
    ) async {
      // Profile comment lists show comments without their post, and a
      // permalink cannot be built without the post's community.
      await pumpCard(tester, post: null);
      await openCommentMenu(tester);

      expect(find.text('Share'), findsNothing);
      expect(find.text('Copy link'), findsNothing);
      expect(find.text('Block @bob.coves.social'), findsOneWidget);
      expect(find.text('Report comment'), findsOneWidget);
    });

    testWidgets('a parent post the comment does not hang under builds no '
        'link', (tester) async {
      // The card is handed its post by the surface showing it. If the two
      // disagree, the permalink would address a comment under a post it is
      // not on, which is a working URL pointing at the wrong thing.
      await pumpCard(
        tester,
        post: parentPost(),
        view: comment(
          postRefUri:
              'at://did:plc:author123/social.coves.community.postv2/3kother0',
        ),
      );
      await openCommentMenu(tester);

      await tester.tap(find.text('Copy link'));
      await tester.pumpAndSettle();

      expect(clipboardTexts, isEmpty);
      expect(find.text("Couldn't create link"), findsOneWidget);
      expect(find.text('Link copied to clipboard'), findsNothing);
    });

    testWidgets('a deleted comment offers no menu even with a parent post', (
      tester,
    ) async {
      // A tombstone renders no action row at all, so there is no trigger to
      // share or copy from.
      await pumpCard(tester, post: parentPost(), view: deletedComment());

      expect(find.byTooltip('Comment options'), findsNothing);
      expect(find.text('Share'), findsNothing);
      expect(find.text('Copy link'), findsNothing);
    });

    testWidgets('no parent post signed-out still shows no menu at all', (
      tester,
    ) async {
      when(mockAuthProvider.isAuthenticated).thenReturn(false);
      when(mockAuthProvider.did).thenReturn(null);

      await pumpCard(tester, post: null);

      expect(find.byTooltip('Comment options'), findsNothing);
      expect(find.text('Share'), findsNothing);
      expect(find.text('Copy link'), findsNothing);
    });
  });
}
