// Admin tools in the post detail header menu: the same capability-gated
// items the feed card offers, run through the real router from the home
// feed or a cold load, with outcomes landing in place on detail.
import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/main.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/community.dart';
import 'package:coves_flutter/models/moderation.dart';
import 'package:coves_flutter/models/moderation_action.dart';
import 'package:coves_flutter/models/moderation_subject_state.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/post_get_result.dart';
import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/providers/community_guidelines_provider.dart';
import 'package:coves_flutter/providers/eula_provider.dart';
import 'package:coves_flutter/providers/multi_feed_provider.dart';
import 'package:coves_flutter/providers/viewer_authority_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/home/main_shell_screen.dart';
import 'package:coves_flutter/screens/home/post_detail_loader.dart';
import 'package:coves_flutter/screens/home/post_detail_screen.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/comments_provider_cache.dart';
import 'package:coves_flutter/services/post_change_broadcast.dart';
import 'package:coves_flutter/utils/post_detail_route.dart';
import 'package:coves_flutter/widgets/feed_page.dart';
import 'package:coves_flutter/widgets/icons/reply_icon.dart';
import 'package:coves_flutter/widgets/moderation/moderation_action_sheet.dart';
import 'package:coves_flutter/widgets/post_card.dart';
import 'package:coves_flutter/widgets/sensitive_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/pump_helpers.dart';
import '../test_helpers/test_mocks.dart';

const _adminDid = 'did:plc:admin';
const _otherAccountDid = 'did:plc:other';
const _communityDid = 'did:plc:community';
const _postUri = 'at://did:plc:author/social.coves.community.post/p1';
const _survivorUri =
    'at://did:plc:community/social.coves.community.post/survivor';
const _postTitle = 'Post to moderate';
const _postBody = 'Body of P';
const _survivorTitle = 'Post that stays';

/// The CID of P as the home feed shows it.
const _shownCid = 'cid-p1';

/// The CID the removal preflight reports as current: never the subject.
const _preflightCid = 'cid-newer';

const _removeAndLabel = {
  ModerationCapability.remove,
  ModerationCapability.label,
};
const _removeAndRetractLabel = {
  ModerationCapability.remove,
  ModerationCapability.retractLabel,
};

/// Every admin item either menu can offer for a post.
const _adminItems = ['Mark NSFW', 'Remove NSFW label', 'Remove post'];

/// Every item the detail header menu can list for the admin viewing P,
/// admin or not.
const _menuItems = [
  'Subscribe to !testcove',
  'Block @author.coves.test',
  'Block !testcove',
  'Report post',
  'Mark NSFW',
  'Remove NSFW label',
  'Remove post',
];

/// The entries every signed-in viewer of P sees above the admin tools.
const _viewerItems = [
  'Subscribe to !testcove',
  'Block @author.coves.test',
  'Block !testcove',
  'Report post',
];

final _encodedPostPath = '/post/${Uri.encodeComponent(_postUri)}';

class _AcceptedEulaProvider extends EulaProvider {
  @override
  bool get hasAccepted => true;

  @override
  bool get isLoading => false;
}

class _AcceptedGuidelinesProvider extends CommunityGuidelinesProvider {
  @override
  bool get hasAccepted => true;

  @override
  bool get isLoading => false;
}

const _nsfwModeration = ModerationView(
  state: ModerationState.clear,
  contentLabels: [ContentLabelView(value: 'nsfw')],
);

/// The instance's own nsfw label on P, as the removal preflight lists it.
const _nsfwLocalLabel = LocalLabel(
  value: 'nsfw',
  action: ModerationActionRef(
    serviceDid: 'did:web:s1.coves.social',
    actionId: 'A1',
  ),
);

/// Post P by someone other than the signed-in admin (so Report shows),
/// served with [capabilities] in `viewer.moderation` at [cid].
PostView _adminPostView({
  Set<ModerationCapability> capabilities = _removeAndLabel,
  String cid = _shownCid,
  ModerationView? moderation,
  String title = _postTitle,
  String body = _postBody,
}) => PostView(
  uri: _postUri,
  cid: cid,
  rkey: 'p1',
  author: AuthorView(did: 'did:plc:author', handle: 'author.coves.test'),
  community: CommunityRef(did: _communityDid, name: 'testcove'),
  createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
  indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
  record: PostRecord(title: title, content: body),
  stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
  viewer: ViewerState(moderation: capabilities),
  moderation: moderation,
);

FeedViewPost _survivor() => FeedViewPost(
  post: PostView(
    uri: _survivorUri,
    cid: 'cid-survivor',
    rkey: 'survivor',
    author: AuthorView(did: 'did:plc:author', handle: 'author.coves.test'),
    community: CommunityRef(did: _communityDid, name: 'testcove'),
    createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
    indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
    record: const PostRecord(title: _survivorTitle, content: 'Body'),
    stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
  ),
);

/// P removed by the instance admin, as post.get answers an admin who may
/// restore it.
const _tombstone = PostGetModerated(
  uri: _postUri,
  moderation: ModerationView(
    state: ModerationState.removed,
    sources: [
      ModerationSource(
        authorityDid: 'did:web:coves.social',
        scope: ModerationScope(kind: ModerationScopeKind.instance),
      ),
    ],
  ),
  viewerModeration: {ModerationCapability.restore},
);

const _appliedRemoval = ModerationMutationResult(
  outcome: ModerationMutationOutcome.applied,
  state: ModerationSubjectState(
    subject: _postUri,
    version: 'v8',
    moderation: ModerationView(state: ModerationState.removed),
    recordState: ModerationRecordState.present,
    currentSubject: StrongRef(uri: _postUri, cid: _shownCid),
  ),
);

/// An applied label change whose state carries [moderation].
ModerationMutationResult _appliedLabelChange(ModerationView moderation) =>
    ModerationMutationResult(
      outcome: ModerationMutationOutcome.applied,
      state: ModerationSubjectState(
        subject: _postUri,
        version: 'v8',
        moderation: moderation,
        recordState: ModerationRecordState.present,
        currentSubject: const StrongRef(uri: _postUri, cid: _shownCid),
      ),
    );

/// A captured StrongRef as a record, so a mismatch prints its uri and cid.
Object? _readableStrongRef(Object? ref) =>
    ref is StrongRef ? (uri: ref.uri, cid: ref.cid) : ref;

/// A signed-in instance admin's API: the home feeds list [feedPost] (P) and
/// the survivor, comments are empty, and the removal preflight answers a
/// clear v7 state whose current CID is [_preflightCid]. post.get and the
/// mutations are left to each test.
MockCovesApiService _adminApi({FeedViewPost? feedPost}) {
  final api = MockCovesApiService();
  final page = TimelineResponse(
    feed: [
      feedPost ?? FeedViewPost(post: _adminPostView()),
      _survivor(),
    ],
  );
  when(api.getViewerAuthority()).thenAnswer((_) async => true);
  when(api.getUnreadCount()).thenAnswer((_) async => 0);
  when(
    api.getProfile(actor: anyNamed('actor')),
  ).thenAnswer((_) async => UserProfile(did: _adminDid, handle: 'admin.test'));
  when(api.getCommunity(community: anyNamed('community'))).thenAnswer(
    (_) async =>
        CommunityView(did: _communityDid, name: 'testcove', displayName: 'TC'),
  );
  when(
    api.getDiscover(
      sort: anyNamed('sort'),
      timeframe: anyNamed('timeframe'),
      limit: anyNamed('limit'),
      cursor: anyNamed('cursor'),
    ),
  ).thenAnswer((_) async => page);
  when(
    api.getTimeline(
      sort: anyNamed('sort'),
      timeframe: anyNamed('timeframe'),
      limit: anyNamed('limit'),
      cursor: anyNamed('cursor'),
    ),
  ).thenAnswer((_) async => page);
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
  when(api.getModerationSubjectState(_postUri)).thenAnswer(
    (_) async => const ModerationSubjectState(
      subject: _postUri,
      version: 'v7',
      moderation: ModerationView(state: ModerationState.clear),
      recordState: ModerationRecordState.present,
      currentSubject: StrongRef(uri: _postUri, cid: _preflightCid),
    ),
  );
  return api;
}

/// Answers every removeContent with [answer].
void _answerRemoval(
  MockCovesApiService api,
  Future<ModerationMutationResult> Function() answer,
) {
  when(
    api.removeContent(
      subject: anyNamed('subject'),
      expectedVersion: anyNamed('expectedVersion'),
      idempotencyKey: anyNamed('idempotencyKey'),
      reason: anyNamed('reason'),
      privateNote: anyNamed('privateNote'),
    ),
  ).thenAnswer((_) => answer());
}

/// Answers every labelContent with [result].
void _answerLabel(MockCovesApiService api, ModerationMutationResult result) {
  when(
    api.labelContent(
      subject: anyNamed('subject'),
      expectedVersion: anyNamed('expectedVersion'),
      idempotencyKey: anyNamed('idempotencyKey'),
      reason: anyNamed('reason'),
      privateNote: anyNamed('privateNote'),
    ),
  ).thenAnswer((_) async => result);
}

/// Answers every retractContentLabel with [result].
void _answerRetraction(
  MockCovesApiService api,
  ModerationMutationResult result,
) {
  when(
    api.retractContentLabel(
      actionId: anyNamed('actionId'),
      expectedVersion: anyNamed('expectedVersion'),
      idempotencyKey: anyNamed('idempotencyKey'),
      reason: anyNamed('reason'),
      reviewedSubject: anyNamed('reviewedSubject'),
      privateNote: anyNamed('privateNote'),
    ),
  ).thenAnswer((_) async => result);
}

/// The running app: the signed-in admin, the real authority and router.
class _AdminApp {
  _AdminApp(this.auth, this.api, this.authority, this.router);

  final FakeAuthProvider auth;
  final MockCovesApiService api;
  final ViewerAuthorityProvider authority;
  final GoRouter router;
}

/// Pumps the app as main.dart wires it, signed in as an instance admin, on
/// a phone-sized view, through the real router.
///
/// With no [initialLocation] the router lands on `/feed` and the home feed
/// loads. With one, the router starts there and the feed is never built.
Future<_AdminApp> _pumpApp(
  WidgetTester tester, {
  required MockCovesApiService api,
  String? initialLocation,
}) async {
  tester.view.physicalSize = const Size(540, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (_) async => null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );

  final auth = FakeAuthProvider(
    signedInDid: _adminDid,
    signedInHandle: 'admin.coves.test',
  );
  addTearDown(auth.dispose);
  final authority = ViewerAuthorityProvider(
    apiService: api,
    authProvider: auth,
  );
  addTearDown(authority.dispose);
  final router = createRouter(
    auth,
    _AcceptedEulaProvider(),
    _AcceptedGuidelinesProvider(),
  );
  addTearDown(router.dispose);
  if (initialLocation != null) {
    router.go(initialLocation);
  }
  final commentService = MockCommentService();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ...profileScreenProviders(
          auth: auth,
          apiService: api,
          commentService: commentService,
          postChangeBroadcast: PostChangeBroadcast(),
          viewerAuthority: authority,
        ),
        Provider<CommentsProviderCache>(
          create: (context) => CommentsProviderCache(
            authProvider: auth,
            voteProvider: context.read<VoteProvider>(),
            commentService: commentService,
            apiService: api,
            sessionKeyOf: () => authority.sessionKey,
          ),
          dispose: (_, cache) => cache.dispose(),
        ),
      ],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    ),
  );
  await pumpFrames(tester);
  return _AdminApp(auth, api, authority, router);
}

Finder _home(FeedType type) => find.byWidgetPredicate(
  (widget) => widget is FeedPage && widget.feedType == type,
  skipOffstage: false,
);

/// The card for [uri] on the Discover home feed, onstage or not.
Finder _homeCard(String uri) => find.descendant(
  of: _home(FeedType.discover),
  matching: find.byWidgetPredicate(
    (widget) => widget is PostCard && widget.post.post.uri == uri,
    skipOffstage: false,
  ),
  skipOffstage: false,
);

final Finder _detail = find.byType(PostDetailScreen, skipOffstage: false);

final Finder _sheet = find.byWidgetPredicate(
  (widget) => widget is ModerationActionSheet,
);

/// The sheet's confirm button, found by type because its label becomes a
/// spinner while the request is in flight.
final Finder _confirmButton = find.descendant(
  of: _sheet,
  matching: find.bySubtype<FilledButton>(),
);

/// Opens P's detail by tapping its title on the home feed card.
Future<void> _openDetailFromCard(WidgetTester tester) async {
  expect(_homeCard(_postUri), findsOneWidget);
  await tester.tap(
    find.descendant(of: _homeCard(_postUri), matching: find.text(_postTitle)),
  );
  await pumpFrames(tester);
  expect(_detail, findsOneWidget);
}

/// Opens P's detail through the home card's comment button.
Future<void> _openDetailFromCommentButton(WidgetTester tester) async {
  expect(_homeCard(_postUri), findsOneWidget);
  await tester.tap(
    find.descendant(of: _homeCard(_postUri), matching: find.byType(ReplyIcon)),
  );
  await pumpFrames(tester);
  expect(_detail, findsOneWidget);
}

/// Pushes [screen] over the home feed the way create_post_screen pushes its
/// optimistic detail: a plain MaterialPageRoute on the app navigator.
Future<void> _pushDetail(WidgetTester tester, PostDetailScreen screen) async {
  unawaited(
    Navigator.of(tester.element(find.byType(MainShellScreen)))
        .push(MaterialPageRoute<void>(builder: (_) => screen)),
  );
  await pumpFrames(tester);
  expect(_detail, findsOneWidget);
}

/// The blurred-post banner inside [within], onstage or not.
Finder _concealedBanner({required Finder within}) => find.descendant(
  of: within,
  matching: find.byWidgetPredicate(
    (widget) => widget is SensitiveContentBanner && widget.concealed,
    skipOffstage: false,
  ),
  skipOffstage: false,
);

/// Opens the detail header's ⋮ menu.
Future<void> _openDetailMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('More options'));
  await pumpFrames(tester);
}

/// The open menu's items, top to bottom.
List<String> _menuLabels(WidgetTester tester) {
  final positioned = <(double, String)>[];
  for (final label in _menuItems) {
    for (final element in find.text(label).evaluate()) {
      final box = element.renderObject! as RenderBox;
      positioned.add((box.localToGlobal(Offset.zero).dy, label));
    }
  }
  positioned.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final (_, label) in positioned) label];
}

/// Picks Remove post in the open menu, chooses Spam and presses Remove,
/// leaving the request to answer.
Future<void> _removeAsSpam(WidgetTester tester) async {
  expect(find.text('Remove post'), findsOneWidget);
  await tester.tap(find.text('Remove post'));
  await pumpFrames(tester);
  expect(_sheet, findsOneWidget);
  await tester.tap(find.descendant(of: _sheet, matching: find.text('Spam')));
  await pumpFrames(tester);
  await tester.tap(_confirmButton);
  await tester.pump();
  await tester.pump();
}

/// Picks the NSFW [item] in the open menu and confirms its sheet with the
/// preselected "No reason".
Future<void> _confirmNsfwItem(WidgetTester tester, String item) async {
  expect(find.text(item), findsOneWidget);
  await tester.tap(find.text(item));
  await pumpFrames(tester);
  expect(_sheet, findsOneWidget);
  await tester.tap(_confirmButton);
  await pumpFrames(tester);
  await pumpFrames(tester);
}

/// Unmounts the tree and runs out the snackbar timer.
Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 5));
}

void main() {
  setUp(() {
    provideDummy<PostGetResult>(const PostGetNotFound(_postUri));
  });

  group('B1 detail menu lists the allowed admin items', () {
    for (final row
        in <
          ({
            String name,
            Set<ModerationCapability> capabilities,
            bool viaCommentButton,
            List<String> expected,
          })
        >[
          (
            name: 'remove and label from the card',
            capabilities: _removeAndLabel,
            viaCommentButton: false,
            expected: [..._viewerItems, 'Mark NSFW', 'Remove post'],
          ),
          (
            name: 'remove and retract-label from the card',
            capabilities: _removeAndRetractLabel,
            viaCommentButton: false,
            expected: [..._viewerItems, 'Remove NSFW label', 'Remove post'],
          ),
          (
            name: 'remove and label from the comment button',
            capabilities: _removeAndLabel,
            viaCommentButton: true,
            expected: [..._viewerItems, 'Mark NSFW', 'Remove post'],
          ),
          (
            name: 'label only',
            capabilities: {ModerationCapability.label},
            viaCommentButton: false,
            expected: [..._viewerItems, 'Mark NSFW'],
          ),
          (
            name: 'retract-label only',
            capabilities: {ModerationCapability.retractLabel},
            viaCommentButton: false,
            expected: [..._viewerItems, 'Remove NSFW label'],
          ),
          (
            name: 'remove only',
            capabilities: {ModerationCapability.remove},
            viaCommentButton: false,
            expected: [..._viewerItems, 'Remove post'],
          ),
        ]) {
      testWidgets('B1 ${row.name}', (tester) async {
        await _pumpApp(
          tester,
          api: _adminApi(
            feedPost: FeedViewPost(
              post: _adminPostView(capabilities: row.capabilities),
            ),
          ),
        );
        if (row.viaCommentButton) {
          await _openDetailFromCommentButton(tester);
        } else {
          await _openDetailFromCard(tester);
        }

        await _openDetailMenu(tester);

        expect(_menuLabels(tester), row.expected);
      });
    }
  });

  group('B2 detail menu shows no admin item', () {
    for (final row
        in <
          ({
            String name,
            Set<ModerationCapability> capabilities,
            bool allowed,
            Future<void> Function(WidgetTester tester, _AdminApp app) open,
          })
        >[
          (
            name: 'without moderation tokens',
            capabilities: const {},
            allowed: false,
            open: (tester, _) => _openDetailFromCard(tester),
          ),
          (
            name: 'with authority revoked',
            capabilities: _removeAndLabel,
            allowed: false,
            open: (tester, app) async {
              await _openDetailFromCard(tester);
              app.authority.markRevoked();
              await tester.pump();
            },
          ),
          (
            name: 'with a stamp that differs from the current session key',
            capabilities: _removeAndLabel,
            allowed: false,
            open: (tester, app) async {
              // The router drops a card-pushed detail when the account
              // changes (its refresh re-parses the location to /feed), so
              // the detail is pushed directly, stamped with the session it
              // was opened under.
              final openedUnder = app.authority.sessionKey;
              await _pushDetail(
                tester,
                PostDetailScreen(
                  post: FeedViewPost(post: _adminPostView()),
                  sessionStamp: openedUnder,
                ),
              );
              // The detail refetches the post's vote for the new account.
              when(app.api.getPost(_postUri))
                  .thenAnswer((_) async => PostGetSuccess(_adminPostView()));
              // Another account signs in directly, with no sign-out between.
              app.auth.setSignedInDid(_otherAccountDid);
              await pumpFrames(tester);
              expect(app.authority.sessionKey, isNot(openedUnder));
              expect(app.authority.isInstanceAdmin, isTrue);
              expect(_detail, findsOneWidget);
            },
          ),
          (
            name:
                'handed over through the router with a stamp from an '
                'earlier session key',
            capabilities: _removeAndLabel,
            allowed: false,
            open: (tester, app) async {
              final loadedUnder = app.authority.sessionKey;
              app.auth.setSignedInDid(_otherAccountDid);
              await pumpFrames(tester);
              expect(app.authority.sessionKey, isNot(loadedUnder));
              expect(app.authority.isInstanceAdmin, isTrue);
              // The route hands the card's post and its stamp to the loader,
              // which shows the post without a fetch.
              unawaited(
                app.router.push(
                  _encodedPostPath,
                  extra: PostDetailRouteExtra(
                    post: FeedViewPost(post: _adminPostView()),
                    sessionStamp: loadedUnder,
                  ),
                ),
              );
              await pumpFrames(tester);
              expect(find.byType(PostDetailLoader), findsOneWidget);
              expect(_detail, findsOneWidget);
            },
          ),
          (
            name: 'on the optimistic detail (null stamp)',
            capabilities: _removeAndLabel,
            allowed: false,
            open: (tester, _) => _pushDetail(
              tester,
              PostDetailScreen(
                post: FeedViewPost(post: _adminPostView()),
                isOptimistic: true,
                sessionStamp: null,
              ),
            ),
          ),
          (
            name: 'control: stamped with the current session key',
            capabilities: _removeAndLabel,
            allowed: true,
            open: (tester, app) => _pushDetail(
              tester,
              PostDetailScreen(
                post: FeedViewPost(post: _adminPostView()),
                sessionStamp: app.authority.sessionKey,
              ),
            ),
          ),
        ]) {
      testWidgets('B2 ${row.name}', (tester) async {
        final app = await _pumpApp(
          tester,
          api: _adminApi(
            feedPost: FeedViewPost(
              post: _adminPostView(capabilities: row.capabilities),
            ),
          ),
        );
        await row.open(tester, app);

        await _openDetailMenu(tester);

        // The menu is open.
        expect(find.text('Report post'), findsOneWidget);
        if (row.allowed) {
          expect(find.text('Mark NSFW'), findsOneWidget);
          expect(find.text('Remove post'), findsOneWidget);
        } else {
          for (final item in _adminItems) {
            expect(find.text(item), findsNothing, reason: item);
          }
        }
      });
    }
  });

  testWidgets('B2 an admin item revoked while the menu was open cannot '
      'run', (tester) async {
    final api = _adminApi();
    _answerRemoval(
      api,
      () async => throw StateError('removeContent must not be sent'),
    );
    final app = await _pumpApp(tester, api: api);
    await _openDetailFromCard(tester);
    await _openDetailMenu(tester);
    expect(find.text('Remove post'), findsOneWidget);

    app.authority.markRevoked();
    await pumpFrames(tester);
    // The open menu may drop the item as authority changes or keep the one
    // it was built with; either way, picking it must run nothing.
    final removeItem = find.text('Remove post');
    if (removeItem.evaluate().isNotEmpty) {
      await tester.tap(removeItem);
      await pumpFrames(tester);
    }

    expect(_sheet, findsNothing);
    verifyNever(api.getModerationSubjectState(any));
    verifyNever(
      api.removeContent(
        subject: anyNamed('subject'),
        expectedVersion: anyNamed('expectedVersion'),
        idempotencyKey: anyNamed('idempotencyKey'),
        reason: anyNamed('reason'),
        privateNote: anyNamed('privateNote'),
      ),
    );
    await _finish(tester);
  });

  group('B3 cold-loaded detail', () {
    testWidgets('B3 offers Mark NSFW and Remove post from a post.get loaded '
        'under the current session', (tester) async {
      final api = _adminApi();
      when(api.getPost(_postUri))
          .thenAnswer((_) async => PostGetSuccess(_adminPostView()));
      await _pumpApp(tester, api: api, initialLocation: _encodedPostPath);
      expect(find.byType(PostDetailLoader), findsOneWidget);
      expect(_detail, findsOneWidget);

      await _openDetailMenu(tester);

      expect(find.text('Report post'), findsOneWidget);
      expect(find.text('Mark NSFW'), findsOneWidget);
      expect(find.text('Remove post'), findsOneWidget);
    });

    testWidgets('B3 offers neither when the session key changed after the '
        'post.get was requested', (tester) async {
      final api = _adminApi();
      final answer = Completer<PostGetResult>();
      addTearDown(() {
        if (!answer.isCompleted) {
          answer.complete(const PostGetNotFound(_postUri));
        }
      });
      when(api.getPost(_postUri)).thenAnswer((_) => answer.future);
      final app = await _pumpApp(
        tester,
        api: api,
        initialLocation: _encodedPostPath,
      );
      verify(api.getPost(_postUri)).called(1);
      final requestedUnder = app.authority.sessionKey;

      app.auth.setSignedInDid(_otherAccountDid);
      await pumpFrames(tester);
      expect(app.authority.sessionKey, isNot(requestedUnder));
      expect(app.authority.isInstanceAdmin, isTrue);
      // Premise: the answer below is to the request sent under the old key.
      verifyNever(api.getPost(_postUri));

      answer.complete(PostGetSuccess(_adminPostView()));
      await pumpFrames(tester);
      expect(_detail, findsOneWidget);

      await _openDetailMenu(tester);

      expect(find.text('Report post'), findsOneWidget);
      for (final item in _adminItems) {
        expect(find.text(item), findsNothing, reason: item);
      }
    });
  });

  testWidgets('B4 Remove post from detail opened on a home card removes the '
      'shown post and shows its tombstone in place', (tester) async {
    final api = _adminApi();
    final removal = Completer<ModerationMutationResult>();
    _answerRemoval(api, () => removal.future);
    when(api.getPost(_postUri)).thenAnswer((_) async => _tombstone);
    try {
      await _pumpApp(tester, api: api);
      expect(_homeCard(_survivorUri), findsOneWidget);
      await _openDetailFromCard(tester);
      await _openDetailMenu(tester);

      await _removeAsSpam(tester);

      final subjects = verify(
        api.removeContent(
          subject: captureAnyNamed('subject'),
          expectedVersion: anyNamed('expectedVersion'),
          idempotencyKey: anyNamed('idempotencyKey'),
          reason: anyNamed('reason'),
          privateNote: anyNamed('privateNote'),
        ),
      ).captured;
      expect(subjects.map(_readableStrongRef), [
        (uri: _postUri, cid: _shownCid),
      ]);
      // Before the server answers, the post stays and Remove is disabled.
      expect(
        find.descendant(of: _detail, matching: find.text(_postTitle)),
        findsOneWidget,
      );
      expect(find.text('Post Removed'), findsNothing);
      expect(
        tester.widget<ButtonStyleButton>(_confirmButton).onPressed,
        isNull,
      );

      removal.complete(_appliedRemoval);
      await pumpFrames(tester);
      await pumpFrames(tester);

      expect(_sheet, findsNothing);
      expect(find.text('Post removed'), findsOneWidget);
      expect(find.text('Post Removed'), findsWidgets);
      expect(find.textContaining('[Removed by server admin]'), findsWidgets);
      expect(find.text('View moderation log'), findsOneWidget);
      expect(find.text('Restore post'), findsOneWidget);
      expect(_homeCard(_postUri), findsNothing);
      expect(_homeCard(_survivorUri), findsOneWidget);
    } finally {
      if (!removal.isCompleted) {
        removal.complete(_appliedRemoval);
        await tester.pump();
      }
    }
    await _finish(tester);
  });

  testWidgets('B5 Remove post on a cold-loaded root detail sends a second '
      'post.get and shows the tombstone from its answer', (tester) async {
    final api = _adminApi();
    _answerRemoval(api, () async => _appliedRemoval);
    var postGets = 0;
    when(api.getPost(_postUri)).thenAnswer((_) async {
      postGets++;
      return postGets == 1 ? PostGetSuccess(_adminPostView()) : _tombstone;
    });
    await _pumpApp(tester, api: api, initialLocation: _encodedPostPath);
    expect(find.byType(MainShellScreen, skipOffstage: false), findsNothing);
    expect(_detail, findsOneWidget);
    expect(postGets, 1);

    await _openDetailMenu(tester);
    await _removeAsSpam(tester);
    await pumpFrames(tester);
    await pumpFrames(tester);

    expect(postGets, 2);
    expect(find.text('Post Removed'), findsWidgets);
    expect(find.text('Restore post'), findsOneWidget);
    expect(_detail, findsNothing);
    await _finish(tester);
  });

  group('B6 removal from detail that finds P already removed', () {
    for (final row
        in <
          ({
            String name,
            void Function(MockCovesApiService api) answer,
            String message,
          })
        >[
          (
            name: 'answers unchanged',
            answer: (api) => _answerRemoval(
              api,
              () async => const ModerationMutationResult(
                outcome: ModerationMutationOutcome.unchanged,
                state: ModerationSubjectState(
                  subject: _postUri,
                  version: 'v7',
                  moderation: ModerationView(state: ModerationState.removed),
                  recordState: ModerationRecordState.present,
                  currentSubject: StrongRef(uri: _postUri, cid: _shownCid),
                ),
              ),
            ),
            message: 'Post was already removed',
          ),
          (
            name: 'fails with StateConflict whose current state is removed',
            answer: (api) {
              var reads = 0;
              when(api.getModerationSubjectState(_postUri)).thenAnswer((
                _,
              ) async {
                if (++reads == 1) {
                  return const ModerationSubjectState(
                    subject: _postUri,
                    version: 'v7',
                    moderation: ModerationView(state: ModerationState.clear),
                    recordState: ModerationRecordState.present,
                    currentSubject: StrongRef(
                      uri: _postUri,
                      cid: _preflightCid,
                    ),
                  );
                }
                return const ModerationSubjectState(
                  subject: _postUri,
                  version: 'v8',
                  moderation: ModerationView(state: ModerationState.removed),
                  recordState: ModerationRecordState.present,
                );
              });
              _answerRemoval(
                api,
                () => Future.error(
                  ApiException(
                    'Conflict',
                    statusCode: 400,
                    errorCode: 'StateConflict',
                  ),
                ),
              );
            },
            message: 'Someone else already removed this post.',
          ),
        ]) {
      testWidgets('B6 removal that ${row.name} shows the tombstone and says '
          'so', (tester) async {
        final api = _adminApi();
        row.answer(api);
        when(api.getPost(_postUri)).thenAnswer((_) async => _tombstone);
        await _pumpApp(tester, api: api);
        await _openDetailFromCard(tester);
        await _openDetailMenu(tester);

        await _removeAsSpam(tester);
        await pumpFrames(tester);
        await pumpFrames(tester);

        expect(_sheet, findsNothing);
        expect(find.text(row.message), findsOneWidget);
        expect(find.text('Post Removed'), findsWidgets);
        expect(find.text('View moderation log'), findsOneWidget);
        expect(find.text('Restore post'), findsOneWidget);
        await _finish(tester);
      });
    }
  });

  testWidgets('B7 removal from detail failing with ContentChanged shows the '
      "author's edited post in place", (tester) async {
    final api = _adminApi();
    _answerRemoval(
      api,
      () => Future.error(
        ApiException('Edited', statusCode: 400, errorCode: 'ContentChanged'),
      ),
    );
    when(api.getPost(_postUri)).thenAnswer(
      (_) async => PostGetSuccess(
        _adminPostView(
          cid: 'cid-p1-edited',
          title: 'Edited after review',
          body: 'Body the author rewrote',
        ),
      ),
    );
    await _pumpApp(tester, api: api);
    await _openDetailFromCard(tester);
    final detailState = tester.state(find.byType(PostDetailScreen));
    await _openDetailMenu(tester);

    await _removeAsSpam(tester);
    await pumpFrames(tester);
    await pumpFrames(tester);

    expect(_sheet, findsNothing);
    expect(
      find.text(
        'The author edited this post. Review the new version before acting.',
      ),
      findsOneWidget,
    );
    expect(tester.state(find.byType(PostDetailScreen)), same(detailState));
    expect(
      find.descendant(
        of: find.byType(PostDetailScreen),
        matching: find.text('Edited after review'),
      ),
      findsOneWidget,
    );
    expect(find.text(_postTitle), findsNothing);
    expect(find.text('Post Removed'), findsNothing);
    await _finish(tester);
  });

  testWidgets('B7 removal from detail failing with ModerationUnavailable '
      'keeps the post and offers Try again', (tester) async {
    final api = _adminApi();
    _answerRemoval(
      api,
      () => Future.error(
        ServerException(
          'Unavailable',
          statusCode: 503,
          errorCode: 'ModerationUnavailable',
        ),
      ),
    );
    when(api.getPost(_postUri)).thenAnswer((_) async => _tombstone);
    await _pumpApp(tester, api: api);
    await _openDetailFromCard(tester);
    await _openDetailMenu(tester);

    await _removeAsSpam(tester);
    await pumpFrames(tester);

    expect(_sheet, findsOneWidget);
    expect(
      find.descendant(of: _sheet, matching: find.text('Try again')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _detail, matching: find.text(_postTitle)),
      findsOneWidget,
    );
    expect(find.text('Post Removed'), findsNothing);
    expect(_homeCard(_postUri), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('B8 Mark NSFW from detail blurs P in place, on the home card '
      'underneath, and offers Remove NSFW label next', (tester) async {
    final api = _adminApi();
    _answerLabel(api, _appliedLabelChange(_nsfwModeration));
    when(api.getPost(_postUri)).thenAnswer(
      (_) async => PostGetSuccess(
        _adminPostView(
          capabilities: _removeAndRetractLabel,
          moderation: _nsfwModeration,
        ),
      ),
    );
    await _pumpApp(tester, api: api);
    await _openDetailFromCard(tester);
    final detailState = tester.state(find.byType(PostDetailScreen));
    expect(
      find.descendant(of: _detail, matching: find.text(_postBody)),
      findsOneWidget,
    );
    expect(_concealedBanner(within: _detail), findsNothing);
    await _openDetailMenu(tester);

    await _confirmNsfwItem(tester, 'Mark NSFW');

    expect(_sheet, findsNothing);
    expect(tester.state(find.byType(PostDetailScreen)), same(detailState));
    expect(_concealedBanner(within: _detail), findsOneWidget);
    expect(
      find.descendant(of: _detail, matching: find.text(_postBody)),
      findsNothing,
    );
    expect(_concealedBanner(within: _homeCard(_postUri)), findsOneWidget);

    await _openDetailMenu(tester);
    expect(find.text('Report post'), findsOneWidget);
    expect(find.text('Remove NSFW label'), findsOneWidget);
    expect(find.text('Mark NSFW'), findsNothing);
    await _finish(tester);
  });

  testWidgets('B9 Remove NSFW label from detail reviews the version detail '
      'shows and unblurs P in place', (tester) async {
    final api = _adminApi(
      feedPost: FeedViewPost(
        post: _adminPostView(
          capabilities: _removeAndRetractLabel,
          moderation: _nsfwModeration,
          cid: 'cid-p0',
        ),
      ),
    );
    when(api.getModerationSubjectState(_postUri)).thenAnswer(
      (_) async => const ModerationSubjectState(
        subject: _postUri,
        version: 'v7',
        moderation: _nsfwModeration,
        recordState: ModerationRecordState.present,
        currentSubject: StrongRef(uri: _postUri, cid: 'cid-p2'),
        localLabels: [_nsfwLocalLabel],
      ),
    );
    _answerRetraction(
      api,
      _appliedLabelChange(const ModerationView(state: ModerationState.clear)),
    );
    // The server's read: P at cid-p1 (the default CID), unlabelled.
    when(api.getPost(_postUri))
        .thenAnswer((_) async => PostGetSuccess(_adminPostView()));
    await _pumpApp(tester, api: api);
    await _openDetailFromCard(tester);
    final detailState = tester.state(find.byType(PostDetailScreen));

    // Before acting, detail is handed a newer version of P in place: still
    // labelled, at cid-p1 (the default CID).
    Provider.of<PostChangeBroadcast>(
      tester.element(_detail),
      listen: false,
    ).replacePost(
      _adminPostView(
        capabilities: _removeAndRetractLabel,
        moderation: _nsfwModeration,
      ),
    );
    await pumpFrames(tester);
    expect(_concealedBanner(within: _detail), findsOneWidget);
    await _openDetailMenu(tester);

    await _confirmNsfwItem(tester, 'Remove NSFW label');

    expect(
      verify(
        api.retractContentLabel(
          actionId: anyNamed('actionId'),
          expectedVersion: anyNamed('expectedVersion'),
          idempotencyKey: anyNamed('idempotencyKey'),
          reason: anyNamed('reason'),
          reviewedSubject: captureAnyNamed('reviewedSubject'),
          privateNote: anyNamed('privateNote'),
        ),
      ).captured.map(_readableStrongRef),
      [(uri: _postUri, cid: 'cid-p1')],
      reason: 'reviewedSubject',
    );
    expect(_sheet, findsNothing);
    expect(tester.state(find.byType(PostDetailScreen)), same(detailState));
    expect(
      find.descendant(
        of: _detail,
        matching: find.byType(SensitiveContentBanner),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: _detail, matching: find.text(_postBody)),
      findsOneWidget,
    );
    await _finish(tester);
  });
}
