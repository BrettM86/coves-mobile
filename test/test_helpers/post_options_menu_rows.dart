// The grouped post options menu shared by the feed card's ⋯ and the post
// detail app bar's ⋮: the fixtures, the provider set both surfaces build
// under, the literal rows each viewer should see, and a reader that lists
// what an open menu actually renders.
import 'package:coves_flutter/models/moderation.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/community_subscription_provider.dart';
import 'package:coves_flutter/providers/viewer_authority_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/services/comments_provider_cache.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/link_sharer.dart';
import 'package:coves_flutter/services/post_change_broadcast.dart';
import 'package:coves_flutter/services/streamable_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'fake_providers.dart';
import 'test_mocks.dart';

const menuAuthorDid = 'did:plc:alice';
const menuCommunityDid = 'did:plc:gaming';
const menuViewerDid = 'did:plc:viewer';
const menuAdminDid = 'did:plc:admin';

/// What the menu reader lists for a divider.
const menuDivider = '—';

/// Who is looking at the post, and with what state.
enum MenuViewer {
  signedOut,
  signedInNotSubscribed,
  signedInSubscribed,
  postAuthor,
  adminWithRemoveAndLabel,
}

/// One viewer and the menu they should see, top to bottom.
typedef PostOptionsMenuRow = ({
  String name,
  MenuViewer viewer,
  List<String> expected,
});

/// The rows both menus are held to. Written out, never derived from either
/// rendered menu.
const List<PostOptionsMenuRow> postOptionsMenuRows = [
  (
    name: "signed out, someone else's post",
    viewer: MenuViewer.signedOut,
    expected: [
      'Subscribe to !Gaming',
      menuDivider,
      'Block @alice.coves.social',
      'Block !Gaming',
      menuDivider,
      'Report post',
    ],
  ),
  (
    name: "signed in and subscribed, someone else's post",
    viewer: MenuViewer.signedInSubscribed,
    expected: [
      'Unsubscribe from !Gaming',
      menuDivider,
      'Block @alice.coves.social',
      'Block !Gaming',
      menuDivider,
      'Report post',
    ],
  ),
  (
    name: 'signed in, own post',
    viewer: MenuViewer.postAuthor,
    expected: [
      'Subscribe to !Gaming',
      menuDivider,
      'Block !Gaming',
      menuDivider,
      'Delete post',
    ],
  ),
  (
    name: "admin with remove and label, someone else's post",
    viewer: MenuViewer.adminWithRemoveAndLabel,
    expected: [
      'Subscribe to !Gaming',
      menuDivider,
      'Block @alice.coves.social',
      'Block !Gaming',
      menuDivider,
      'Report post',
      menuDivider,
      'Mark NSFW',
      'Remove post',
    ],
  ),
];

/// Alice's post in !Gaming, carrying remove and label capabilities when
/// [viewer] is the admin.
FeedViewPost menuPost(MenuViewer viewer) => FeedViewPost(
  post: PostView(
    uri: 'at://did:plc:alice/social.coves.community.post/p1',
    cid: 'cid-p1',
    rkey: 'p1',
    author: AuthorView(did: menuAuthorDid, handle: 'alice.coves.social'),
    community: CommunityRef(
      did: menuCommunityDid,
      name: 'Gaming',
      origin: 'coves.social',
    ),
    createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
    indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
    record: const PostRecord(title: 'Menu post', content: 'Body'),
    stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
    viewer: viewer == MenuViewer.adminWithRemoveAndLabel
        ? ViewerState(
            moderation: {
              ModerationCapability.remove,
              ModerationCapability.label,
            },
          )
        : null,
  ),
);

/// The providers both surfaces build under for one [MenuViewer]. The caller
/// pumps
/// its widget under [providers] with [sessionStamp] and disposes nothing:
/// teardowns are registered by [MenuHarness.create].
class MenuHarness {
  MenuHarness._(this.providers, this.sessionStamp, this.api);

  final List<SingleChildWidget> providers;
  final Object? sessionStamp;

  /// The mocked API every provider in [providers] talks to, for a test to
  /// answer the requests its flow sends.
  final MockCovesApiService api;

  // A factory that registers teardowns, so not a plain constructor.
  // ignore: prefer_constructors_over_static_methods
  static MenuHarness create(MenuViewer viewer) {
    final signedInDid = switch (viewer) {
      MenuViewer.signedOut => null,
      MenuViewer.signedInNotSubscribed => menuViewerDid,
      MenuViewer.signedInSubscribed => menuViewerDid,
      MenuViewer.postAuthor => menuAuthorDid,
      MenuViewer.adminWithRemoveAndLabel => menuAdminDid,
    };
    final auth = FakeAuthProvider(signedInDid: signedInDid);
    addTearDown(auth.dispose);
    final api = MockCovesApiService();
    when(api.getViewerAuthority())
        .thenAnswer((_) async => viewer == MenuViewer.adminWithRemoveAndLabel);
    final authority = ViewerAuthorityProvider(
      apiService: api,
      authProvider: auth,
    );
    addTearDown(authority.dispose);
    final subscriptions = FakeSubscriptionProvider(
      authProvider: auth,
      apiService: api,
    );
    addTearDown(subscriptions.dispose);
    if (viewer == MenuViewer.signedInSubscribed) {
      subscriptions.setInitialSubscriptionState(
        communityDid: menuCommunityDid,
        isSubscribed: true,
      );
    }
    final blocks = BlockProvider(apiService: api, authProvider: auth);
    addTearDown(blocks.dispose);
    final votes = FakeVoteProvider(auth);
    addTearDown(votes.dispose);
    final commentsCache = CommentsProviderCache(
      authProvider: auth,
      voteProvider: votes,
      commentService: MockCommentService(),
      apiService: api,
    );
    addTearDown(commentsCache.dispose);
    return MenuHarness._(
      [
        Provider<CovesApiService>.value(value: api),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<ViewerAuthorityProvider>.value(value: authority),
        ChangeNotifierProvider<VoteProvider>.value(value: votes),
        ChangeNotifierProvider<CommunitySubscriptionProvider>.value(
          value: subscriptions,
        ),
        ChangeNotifierProvider<BlockProvider>.value(value: blocks),
        Provider<StreamableService>.value(value: StreamableService()),
        Provider<PostChangeBroadcast>.value(value: PostChangeBroadcast()),
        Provider<CommentsProviderCache>.value(value: commentsCache),
        Provider<LinkSharer>.value(value: const SharePlusLinkSharer()),
      ],
      authority.sessionKey,
      api,
    );
  }
}

/// The open menu as rendered, top to bottom: each tappable entry's text,
/// and [menuDivider] for each divider between entries.
///
/// Entries are whatever menu item widgets are on screen (a MenuAnchor's
/// MenuItemButtons or a popup menu's PopupMenuItems). Dividers count only
/// when they sit inside the band the entries span, so dividers elsewhere on
/// the page are ignored.
List<String> openMenuRows(WidgetTester tester) {
  final entries = find.byWidgetPredicate(
    (widget) => widget is MenuItemButton || widget is PopupMenuItem,
  );
  final rows = <(double, String)>[];
  Rect? band;
  for (final element in entries.evaluate()) {
    final box = element.renderObject! as RenderBox;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    band = band == null ? rect : band.expandToInclude(rect);
    final texts = find.descendant(
      of: find.byElementPredicate((candidate) => candidate == element),
      matching: find.byType(Text),
    );
    final label = [
      for (final text in tester.widgetList<Text>(texts))
        text.data ?? text.textSpan?.toPlainText() ?? '',
    ].where((part) => part.isNotEmpty).join(' ');
    rows.add((rect.center.dy, label));
  }
  if (band == null) {
    return const [];
  }
  final seenDividers = <Rect>{};
  for (final element in find.byType(Divider).evaluate()) {
    final box = element.renderObject! as RenderBox;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final inBand =
        rect.center.dy > band.top &&
        rect.center.dy < band.bottom &&
        rect.center.dx > band.left &&
        rect.center.dx < band.right;
    if (inBand && seenDividers.add(rect)) {
      rows.add((rect.center.dy, menuDivider));
    }
  }
  rows.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final (_, label) in rows) label];
}
