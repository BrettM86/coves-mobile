// Acceptance: a server NSFW label applied from one card blurs the post in
// place on every surface that shows it, with no feed reload.
import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/community.dart';
import 'package:coves_flutter/models/moderation.dart';
import 'package:coves_flutter/models/moderation_action.dart';
import 'package:coves_flutter/models/moderation_subject_state.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/post_get_result.dart';
import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/providers/multi_feed_provider.dart';
import 'package:coves_flutter/providers/viewer_authority_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/community/community_feed_screen.dart';
import 'package:coves_flutter/screens/home/main_shell_screen.dart';
import 'package:coves_flutter/screens/home/post_detail_screen.dart';
import 'package:coves_flutter/screens/home/profile_screen.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/comments_provider_cache.dart';
import 'package:coves_flutter/services/post_change_broadcast.dart';
import 'package:coves_flutter/widgets/feed_page.dart';
import 'package:coves_flutter/widgets/post_card.dart';
import 'package:coves_flutter/widgets/sensitive_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/pump_helpers.dart';
import '../test_helpers/test_mocks.dart';

const _signedInDid = 'did:plc:me';
const _communityDid = 'did:plc:community';
const _postUri = 'at://did:plc:author/social.coves.community.post/p1';
const _otherUri = 'at://did:plc:community/social.coves.community.post/other';
const _postBody = 'Body of Post to label';

FeedViewPost _post(
  String uri,
  String title, {
  ViewerState? viewer,
  String? cid,
  ModerationView? moderation,
}) => FeedViewPost(
  post: PostView(
    uri: uri,
    cid: cid ?? 'cid-${uri.split('/').last}',
    rkey: uri.split('/').last,
    author: AuthorView(did: 'did:plc:author', handle: 'author.coves.test'),
    community: CommunityRef(did: _communityDid, name: 'testcove'),
    createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
    indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
    record: PostRecord(title: title, content: 'Body of $title'),
    stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
    viewer: viewer,
    moderation: moderation,
  ),
);

/// Post P as the server serves it to an instance admin: no author
/// self-label, Remove post and Mark NSFW offered.
FeedViewPost _adminPost() => _post(
  _postUri,
  'Post to label',
  viewer: ViewerState(
    moderation: {ModerationCapability.remove, ModerationCapability.label},
  ),
);

/// Post P at [cid] carrying the server NSFW label, as the server serves it
/// to an instance admin: Remove post and Remove NSFW label offered.
FeedViewPost _labeledAdminPost({required String cid}) => _post(
  _postUri,
  'Post to label',
  cid: cid,
  viewer: ViewerState(
    moderation: {
      ModerationCapability.remove,
      ModerationCapability.retractLabel,
    },
  ),
  moderation: const ModerationView(
    state: ModerationState.clear,
    contentLabels: [ContentLabelView(value: 'nsfw')],
  ),
);

TimelineResponse _page(FeedViewPost post) =>
    TimelineResponse(feed: [post, _post(_otherUri, 'Post that stays')]);

/// A captured StrongRef as a record, so a mismatch prints its uri and cid.
Object? _readableStrongRef(Object? ref) =>
    ref is StrongRef ? (uri: ref.uri, cid: ref.cid) : ref;

Finder _card(String uri, {required Finder within}) => find.descendant(
  of: within,
  matching: find.byWidgetPredicate(
    (widget) => widget is PostCard && widget.post.post.uri == uri,
    skipOffstage: false,
  ),
  skipOffstage: false,
);

Finder _home(FeedType type) => find.byWidgetPredicate(
  (widget) => widget is FeedPage && widget.feedType == type,
  skipOffstage: false,
);

Finder _nav(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

Finder _concealedBanner({required Finder within}) => find.descendant(
  of: within,
  matching: find.byWidgetPredicate(
    (widget) => widget is SensitiveContentBanner && widget.concealed,
    skipOffstage: false,
  ),
  skipOffstage: false,
);

Finder get _sheetPrimaryButton => find
    .descendant(
      of: find.byType(BottomSheet),
      matching: find.bySubtype<ButtonStyleButton>(),
    )
    .last;

void main() {
  late FakeAuthProvider auth;
  late MockCovesApiService api;
  late int discoverFetches;
  late int timelineFetches;
  late int profileFetches;
  late int communityFetches;
  // The post P every feed serves.
  late FeedViewPost servedPost;

  setUp(() {
    provideDummy<PostGetResult>(const PostGetNotFound(_postUri));
    auth = FakeAuthProvider(
      signedInDid: _signedInDid,
      signedInHandle: 'me.coves.test',
    );
    api = MockCovesApiService();
    discoverFetches = 0;
    timelineFetches = 0;
    profileFetches = 0;
    communityFetches = 0;
    servedPost = _adminPost();

    when(api.getViewerAuthority()).thenAnswer((_) async => true);
    when(api.getProfile(actor: _signedInDid)).thenAnswer(
      (_) async => UserProfile(did: _signedInDid, handle: 'me.coves.test'),
    );
    when(api.getCommunity(community: anyNamed('community'))).thenAnswer(
      (_) async => CommunityView(
        did: _communityDid,
        name: 'testcove',
        displayName: 'Test Cove',
      ),
    );
    when(
      api.getDiscover(
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((_) async {
      discoverFetches++;
      return _page(servedPost);
    });
    when(
      api.getTimeline(
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((_) async {
      timelineFetches++;
      return _page(servedPost);
    });
    when(
      api.getAuthorPosts(
        actor: _signedInDid,
        filter: anyNamed('filter'),
        community: anyNamed('community'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((_) async {
      profileFetches++;
      return _page(servedPost);
    });
    when(
      api.getCommunityFeed(
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((_) async {
      communityFetches++;
      return _page(servedPost);
    });
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
        currentSubject: StrongRef(uri: _postUri, cid: 'cid-p1'),
      ),
    );
    // The follow-up read fails, so the blur can only come from the
    // mutation's returned state.
    when(api.getPost(_postUri)).thenAnswer(
      (_) => Future.error(
        ApiException('Down', statusCode: 503, errorCode: 'Unavailable'),
      ),
    );
  });
  tearDown(() => auth.dispose());

  /// Pumps the signed-in app shell on a phone-sized view, with the home
  /// feed loaded.
  Future<GlobalKey<NavigatorState>> pumpShell(WidgetTester tester) async {
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

    final navigatorKey = GlobalKey<NavigatorState>();
    final viewerAuthority = ViewerAuthorityProvider(
      apiService: api,
      authProvider: auth,
    );
    addTearDown(viewerAuthority.dispose);
    final commentService = MockCommentService();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ...profileScreenProviders(
            auth: auth,
            apiService: api,
            commentService: commentService,
            postChangeBroadcast: PostChangeBroadcast(),
            viewerAuthority: viewerAuthority,
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
          home: const MainShellScreen(),
        ),
      ),
    );
    await pumpFrames(tester);
    return navigatorKey;
  }

  testWidgets('B6 Mark NSFW blurs the post in place on the home feed, the '
      'profile, the community feed and the open post detail', (tester) async {
    final labeling = Completer<ModerationMutationResult>();
    when(
      api.labelContent(
        subject: anyNamed('subject'),
        expectedVersion: anyNamed('expectedVersion'),
        idempotencyKey: anyNamed('idempotencyKey'),
        reason: anyNamed('reason'),
        privateNote: anyNamed('privateNote'),
      ),
    ).thenAnswer((_) => labeling.future);

    final navigatorKey = await pumpShell(tester);

    // Home feed and profile loaded, then back on the home feed.
    expect(_card(_postUri, within: _home(FeedType.discover)), findsOneWidget);
    await tester.tap(_nav('Me'));
    await pumpFrames(tester);
    expect(_card(_postUri, within: find.byType(ProfileScreen)), findsOneWidget);
    await tester.tap(_nav('Home'));
    await pumpFrames(tester);

    // The post detail is open, and a community feed showing the post is
    // pushed over it.
    unawaited(
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              PostDetailScreen(sessionStamp: null, post: _adminPost()),
        ),
      ),
    );
    await pumpFrames(tester);
    final detail = find.byType(PostDetailScreen, skipOffstage: false);
    expect(detail, findsOneWidget);
    unawaited(
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const CommunityFeedScreen(identifier: _communityDid),
        ),
      ),
    );
    await pumpFrames(tester);
    final communityCard = _card(
      _postUri,
      within: find.byType(CommunityFeedScreen),
    );
    expect(communityCard, findsOneWidget);
    final fetchesBeforeLabel = [
      discoverFetches,
      timelineFetches,
      profileFetches,
      communityFetches,
    ];

    await tester.tap(
      find.descendant(
        of: communityCard,
        matching: find.byTooltip('Post options'),
      ),
    );
    await pumpFrames(tester);
    // The admin menu is open; the label item is offered beside removal.
    expect(find.text('Remove post'), findsOneWidget);
    expect(find.text('Mark NSFW'), findsOneWidget);
    await tester.tap(find.text('Mark NSFW'));
    await pumpFrames(tester);
    await tester.tap(
      find.ancestor(
        of: find.text('Mark NSFW'),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Before the server answers: unblurred, confirm disabled.
    expect(
      tester.widget<ButtonStyleButton>(_sheetPrimaryButton).onPressed,
      isNull,
    );
    expect(
      find.descendant(
        of: communityCard,
        matching: find.byType(SensitiveContentBanner),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: communityCard, matching: find.text(_postBody)),
      findsOneWidget,
    );

    labeling.complete(
      const ModerationMutationResult(
        outcome: ModerationMutationOutcome.applied,
        state: ModerationSubjectState(
          subject: _postUri,
          version: 'v8',
          moderation: ModerationView(
            state: ModerationState.clear,
            contentLabels: [ContentLabelView(value: 'nsfw')],
          ),
          recordState: ModerationRecordState.present,
          currentSubject: StrongRef(uri: _postUri, cid: 'cid-p1'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await pumpFrames(tester);

    expect(_concealedBanner(within: communityCard), findsOneWidget);
    expect(
      find.descendant(of: communityCard, matching: find.text(_postBody)),
      findsNothing,
    );
    expect(_concealedBanner(within: detail), findsOneWidget);
    expect(
      _concealedBanner(
        within: _card(_postUri, within: _home(FeedType.discover)),
      ),
      findsOneWidget,
    );
    expect(
      _concealedBanner(
        within: _card(
          _postUri,
          within: find.byType(ProfileScreen, skipOffstage: false),
        ),
      ),
      findsOneWidget,
    );
    expect([
      discoverFetches,
      timelineFetches,
      profileFetches,
      communityFetches,
    ], fetchesBeforeLabel);
    expect(tester.takeException(), isNull);
  });

  /// Removes the NSFW label from [card] through its menu and sheet, with no
  /// reason chosen.
  Future<void> removeNsfwLabelFrom(WidgetTester tester, Finder card) async {
    await tester.tap(
      find.descendant(of: card, matching: find.byTooltip('Post options')),
    );
    await pumpFrames(tester);
    await tester.tap(find.text('Remove NSFW label'));
    await pumpFrames(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.ancestor(
          of: find.text('Remove NSFW label'),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      ),
    );
    await pumpFrames(tester);
    await tester.pump(const Duration(seconds: 1));
    await pumpFrames(tester);
  }

  for (final row
      in <
        ({
          String surface,
          Future<Finder> Function(
            WidgetTester tester,
            GlobalKey<NavigatorState> navigatorKey,
          )
          open,
        })
      >[
        (
          surface: 'home feed',
          open: (tester, navigatorKey) async =>
              _card(_postUri, within: _home(FeedType.discover)),
        ),
        (
          surface: 'profile',
          open: (tester, navigatorKey) async {
            await tester.tap(_nav('Me'));
            await pumpFrames(tester);
            return _card(_postUri, within: find.byType(ProfileScreen));
          },
        ),
        (
          surface: 'community feed',
          open: (tester, navigatorKey) async {
            unawaited(
              navigatorKey.currentState!.push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const CommunityFeedScreen(identifier: _communityDid),
                ),
              ),
            );
            await pumpFrames(tester);
            return _card(_postUri, within: find.byType(CommunityFeedScreen));
          },
        ),
      ]) {
    testWidgets('Remove NSFW label from the ${row.surface} reviews the '
        'version its card shows, before and after an edit reloads it', (
      tester,
    ) async {
      servedPost = _labeledAdminPost(cid: 'cid-p1');
      // The server already holds the author's edit (cid-p2).
      when(api.getModerationSubjectState(_postUri)).thenAnswer(
        (_) async => const ModerationSubjectState(
          subject: _postUri,
          version: 'v7',
          moderation: ModerationView(
            state: ModerationState.clear,
            contentLabels: [ContentLabelView(value: 'nsfw')],
          ),
          recordState: ModerationRecordState.present,
          currentSubject: StrongRef(uri: _postUri, cid: 'cid-p2'),
          localLabels: [
            LocalLabel(
              value: 'nsfw',
              action: ModerationActionRef(
                serviceDid: 'did:web:s1.coves.social',
                actionId: 'A1',
              ),
            ),
          ],
        ),
      );
      // The first retraction finds the edit; the next one is applied.
      final retractionAnswers = <Future<ModerationMutationResult> Function()>[
        () => Future.error(
          ApiException('Edited', statusCode: 400, errorCode: 'ContentChanged'),
        ),
        () async => const ModerationMutationResult(
          outcome: ModerationMutationOutcome.applied,
          state: ModerationSubjectState(
            subject: _postUri,
            version: 'v8',
            moderation: ModerationView(state: ModerationState.clear),
            recordState: ModerationRecordState.present,
            currentSubject: StrongRef(uri: _postUri, cid: 'cid-p2'),
          ),
        ),
      ];
      when(
        api.retractContentLabel(
          actionId: anyNamed('actionId'),
          expectedVersion: anyNamed('expectedVersion'),
          idempotencyKey: anyNamed('idempotencyKey'),
          reason: anyNamed('reason'),
          reviewedSubject: anyNamed('reviewedSubject'),
          privateNote: anyNamed('privateNote'),
        ),
      ).thenAnswer((_) => retractionAnswers.removeAt(0)());
      when(api.getPost(_postUri)).thenAnswer(
        (_) async => PostGetSuccess(_labeledAdminPost(cid: 'cid-p2').post),
      );

      final navigatorKey = await pumpShell(tester);
      final card = await row.open(tester, navigatorKey);
      expect(card, findsOneWidget);
      expect(tester.widget<PostCard>(card).post.post.cid, 'cid-p1');

      await removeNsfwLabelFrom(tester, card);
      expect(tester.widget<PostCard>(card).post.post.cid, 'cid-p2');
      await removeNsfwLabelFrom(tester, card);

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
        [(uri: _postUri, cid: 'cid-p1'), (uri: _postUri, cid: 'cid-p2')],
        reason: 'reviewedSubject',
      );
      expect(tester.takeException(), isNull);
    });
  }
}
