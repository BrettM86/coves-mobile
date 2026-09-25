import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/services/link_sharer.dart';
import 'package:coves_flutter/widgets/post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_providers.dart';

/// An `AuthProvider` reporting a signed-in viewer who is not the post author.
class SignedInAuthProvider extends AuthProvider {
  @override
  bool get isAuthenticated => true;

  @override
  bool get isLoading => false;

  @override
  String? get did => 'did:plc:viewer999';
}

/// A `LinkSharer` that records dispatches instead of opening a native sheet.
///
/// The card's share button reads one at tap time; copying must not dispatch
/// a share of its own.
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
  const expectedCopiedUrl =
      'https://coves.social/c/gaming/post/alice.coves.social/3kabcxyz';

  late RecordingLinkSharer linkSharer;
  late List<Object?> clipboardTexts;

  setUp(() {
    linkSharer = RecordingLinkSharer();
    clipboardTexts = [];
  });

  /// Records every `Clipboard.setData` payload while still answering the
  /// haptic calls the menu handler makes.
  ///
  /// A handler that only returns null for everything would let a clipboard
  /// assertion pass without any copy happening, so this one is the single
  /// handler on the channel for the whole test.
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

  /// Fails every `Clipboard.setData` the way a platform channel can, while
  /// still answering the haptic calls the menu handler makes.
  void failClipboardWrites(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (methodCall) async {
        if (methodCall.method == 'Clipboard.setData') {
          throw PlatformException(code: 'clipboard_unavailable');
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

  /// A post in the author's own repo, with a valid handle and a community
  /// served by this instance.
  FeedViewPost authorOwnedPost({
    String uri = 'at://did:plc:author123/social.coves.community.postv2/3kabcxyz',
  }) {
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
          content: 'Test post content',
          title: 'Test Post Title',
        ),
        stats: PostStats(upvotes: 1, downvotes: 0, score: 1, commentCount: 0),
      ),
    );
  }

  Widget createTestWidget(FeedViewPost post, {required AuthProvider auth}) {
    // PostCard's subtree navigates with go_router, so it needs a router
    // rather than a bare MaterialApp.
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(body: PostCard(post: post)),
        ),
      ],
    );
    addTearDown(router.dispose);

    return MultiProvider(
      providers: [
        ...postCardProviders(auth: auth),
        Provider<LinkSharer>.value(value: linkSharer),
      ],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    );
  }

  Future<void> openOverflowMenu(WidgetTester tester) async {
    final trigger = find.byTooltip('Post options');
    expect(trigger, findsOneWidget);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
  }

  testWidgets('Copy link copies the post web link for a signed-in viewer', (
    tester,
  ) async {
    recordPlatformChannel(tester);

    await tester.pumpWidget(
      createTestWidget(authorOwnedPost(), auth: SignedInAuthProvider()),
    );

    await openOverflowMenu(tester);

    final copyLink = find.text('Copy link');
    expect(copyLink, findsOneWidget);

    await tester.tap(copyLink);
    await tester.pumpAndSettle();

    expect(clipboardTexts, [expectedCopiedUrl]);
    expect(find.text('Link copied to clipboard'), findsOneWidget);
    // Copying is not sharing: the share sheet must stay shut.
    expect(linkSharer.sharedUrls, isEmpty);
  });

  testWidgets('Copy link is reachable for a signed-out viewer', (tester) async {
    recordPlatformChannel(tester);

    await tester.pumpWidget(
      createTestWidget(authorOwnedPost(), auth: FakeAuthProvider()),
    );

    await openOverflowMenu(tester);

    expect(find.text('Copy link'), findsOneWidget);

    // The moderation items keep the gating they have today: they are shown
    // signed-out and prompt for sign-in when tapped. Only the author-only
    // item stays out of the menu, because a signed-out viewer owns no post.
    expect(find.text('Report post'), findsOneWidget);
    expect(find.text('Block @alice.coves.social'), findsOneWidget);
    expect(find.text('Block !Gaming'), findsOneWidget);
    expect(find.text('Subscribe to !Gaming'), findsOneWidget);
    expect(find.text('Delete post'), findsNothing);

    // A link is public: the signed-out viewer gets the same URL, not a
    // sign-in prompt and not a different link.
    await tester.tap(find.text('Copy link'));
    await tester.pumpAndSettle();

    expect(clipboardTexts, [expectedCopiedUrl]);
    expect(find.text('Link copied to clipboard'), findsOneWidget);
    expect(linkSharer.sharedUrls, isEmpty);
  });

  testWidgets('Copy link reports a clipboard that refuses the write', (
    tester,
  ) async {
    failClipboardWrites(tester);

    await tester.pumpWidget(
      createTestWidget(authorOwnedPost(), auth: SignedInAuthProvider()),
    );

    await openOverflowMenu(tester);

    await tester.tap(find.text('Copy link'));
    await tester.pumpAndSettle();

    expect(clipboardTexts, isEmpty);
    expect(find.text('Failed to copy link to clipboard'), findsOneWidget);
    expect(find.text('Link copied to clipboard'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Copy link reports failure when no link can be built', (
    tester,
  ) async {
    recordPlatformChannel(tester);

    await tester.pumpWidget(
      createTestWidget(
        authorOwnedPost(uri: 'not-an-at-uri'),
        auth: SignedInAuthProvider(),
      ),
    );

    await openOverflowMenu(tester);

    final copyLink = find.text('Copy link');
    expect(copyLink, findsOneWidget);

    await tester.tap(copyLink);
    await tester.pumpAndSettle();

    expect(clipboardTexts, isEmpty);
    expect(find.text("Couldn't create link"), findsOneWidget);
    expect(find.text('Link copied to clipboard'), findsNothing);
  });
}
