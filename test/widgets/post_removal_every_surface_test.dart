// Cross-screen contract: one app-lifetime broadcast reaches every loaded
// owner, even while another route or shell tab covers its cards.
import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/community.dart';
import 'package:coves_flutter/models/moderation.dart';
import 'package:coves_flutter/models/moderation_subject_state.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/post_get_result.dart';
import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/providers/multi_feed_provider.dart';
import 'package:coves_flutter/providers/viewer_authority_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/community/community_feed_screen.dart';
import 'package:coves_flutter/screens/home/main_shell_screen.dart';
import 'package:coves_flutter/screens/home/profile_screen.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/post_change_broadcast.dart';
import 'package:coves_flutter/widgets/feed_page.dart';
import 'package:coves_flutter/widgets/post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/test_mocks.dart';

const _authorDid = 'did:plc:me';
const _communityDid = 'did:plc:community';
const _removedUri =
    'at://did:plc:community/social.coves.community.post/removed';
const _survivorUri =
    'at://did:plc:community/social.coves.community.post/survivor';
const _beforeUri = 'at://did:plc:community/social.coves.community.post/before';
const _afterUri = 'at://did:plc:community/social.coves.community.post/after';
const _adminPostUri = 'at://did:plc:author/social.coves.community.post/p1';
const _nonAdminDid = 'did:plc:nonadmin';
const _otherAdminDid = 'did:plc:otheradmin';

FeedViewPost _post(String uri, String title, {ViewerState? viewer}) =>
    FeedViewPost(
      post: PostView(
        uri: uri,
        cid: 'cid-${uri.split('/').last}',
        rkey: uri.split('/').last,
        author: uri == _adminPostUri
            ? AuthorView(did: 'did:plc:author', handle: 'author.coves.test')
            : AuthorView(did: _authorDid, handle: 'me.coves.test'),
        community: CommunityRef(did: _communityDid, name: 'testcove'),
        createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
        indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
        record: PostRecord(title: title, content: 'Body of $title'),
        stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
        viewer: viewer,
      ),
    );

Finder _card(String uri, {Finder? within}) {
  final cards = find.byWidgetPredicate(
    (widget) => widget is PostCard && widget.post.post.uri == uri,
    skipOffstage: false,
  );
  return within == null
      ? cards
      : find.descendant(of: within, matching: cards, skipOffstage: false);
}

Finder _home(FeedType type) => find.byWidgetPredicate(
  (widget) => widget is FeedPage && widget.feedType == type,
  skipOffstage: false,
);

Finder _nav(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

void _usePhoneLayout(WidgetTester tester) {
  tester.view.physicalSize = const Size(540, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _answerPlatformChannel(WidgetTester tester) {
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
}

Future<void> _deleteFromCard(WidgetTester tester, Finder card) async {
  await tester.tap(
    find.descendant(of: card, matching: find.byTooltip('Post options')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Delete post'));
  await tester.pumpAndSettle();
  expect(find.text('Delete Post'), findsOneWidget);
  await tester.tap(find.text('Delete'));
  await tester.pumpAndSettle();
}

class _LoadedSurfaces {
  _LoadedSurfaces(
    this.api, {
    this.moderatedUri = _removedUri,
    this.carriesRemoveToken,
  });

  final MockCovesApiService api;
  final String moderatedUri;

  /// Whether the signed-in account's feeds carry the remove token, read when
  /// each page is fetched. Null means every account's feeds carry it.
  final bool Function()? carriesRemoveToken;
  int discoverFetches = 0;
  int timelineFetches = 0;
  int profileFetches = 0;
  int communityFetches = 0;

  void stub() {
    when(api.deletePost(uri: _removedUri)).thenAnswer((_) async {});
    when(api.getViewerAuthority()).thenAnswer((_) async => true);
    when(api.getProfile(actor: _authorDid)).thenAnswer(
      (_) async => UserProfile(did: _authorDid, handle: 'me.coves.test'),
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
      return TimelineResponse(
        feed: [
          _post(moderatedUri, 'Post to remove', viewer: _moderationViewer),
          _post(_survivorUri, 'Post that stays'),
        ],
      );
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
      return TimelineResponse(
        feed: [
          _post(moderatedUri, 'Post to remove', viewer: _moderationViewer),
          _post(_survivorUri, 'Post that stays'),
        ],
      );
    });
    when(
      api.getAuthorPosts(
        actor: _authorDid,
        filter: anyNamed('filter'),
        community: anyNamed('community'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((_) async {
      profileFetches++;
      return TimelineResponse(
        feed: [
          _post(moderatedUri, 'Post to remove', viewer: _moderationViewer),
          _post(_survivorUri, 'Post that stays'),
        ],
      );
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
      return TimelineResponse(
        feed: [
          _post(moderatedUri, 'Post to remove', viewer: _moderationViewer),
          _post(_survivorUri, 'Post that stays'),
        ],
      );
    });
  }

  List<int> get fetchCounts => [
    discoverFetches,
    timelineFetches,
    profileFetches,
    communityFetches,
  ];

  ViewerState? get _moderationViewer =>
      moderatedUri == _adminPostUri && (carriesRemoveToken?.call() ?? true)
      ? ViewerState(moderation: {ModerationCapability.remove})
      : null;
}

class _RecordingBroadcast extends PostChangeBroadcast {
  int additions = 0;
  int removals = 0;

  @override
  void addPostChangeListener(PostChangeListener listener) {
    additions++;
    super.addPostChangeListener(listener);
  }

  @override
  void removePostChangeListener(PostChangeListener listener) {
    removals++;
    super.removePostChangeListener(listener);
  }
}

void main() {
  late FakeAuthProvider auth;
  late MockCovesApiService api;
  late _LoadedSurfaces feeds;

  setUp(() {
    provideDummy<PostGetResult>(const PostGetNotFound(_adminPostUri));
    auth = FakeAuthProvider(
      signedInDid: _authorDid,
      signedInHandle: 'me.coves.test',
    );
    api = MockCovesApiService();
    feeds = _LoadedSurfaces(api)..stub();
  });
  tearDown(() => auth.dispose());

  Future<GlobalKey<NavigatorState>> pumpShell(
    WidgetTester tester,
    PostChangeBroadcast broadcast,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    // Built up front, as main.dart does, so the home feeds can stamp their
    // cards with its session key.
    final viewerAuthority = ViewerAuthorityProvider(
      apiService: api,
      authProvider: auth,
    );
    addTearDown(viewerAuthority.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ...profileScreenProviders(
            auth: auth,
            apiService: api,
            commentService: MockCommentService(),
            postChangeBroadcast: broadcast,
            viewerAuthority: viewerAuthority,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          navigatorKey: navigatorKey,
          home: const MainShellScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return navigatorKey;
  }

  Future<void> visitLoadedProfileThenHome(
    WidgetTester tester, {
    String uri = _removedUri,
  }) async {
    expect(_card(uri, within: _home(FeedType.discover)), findsOneWidget);
    expect(
      _card(_survivorUri, within: _home(FeedType.discover)),
      findsOneWidget,
    );
    await tester.tap(find.text('For You'));
    await tester.pumpAndSettle();
    expect(_card(uri, within: _home(FeedType.forYou)), findsOneWidget);
    expect(_card(_survivorUri, within: _home(FeedType.forYou)), findsOneWidget);
    await tester.tap(_nav('Me'));
    await tester.pumpAndSettle();
    expect(_card(uri, within: find.byType(ProfileScreen)), findsOneWidget);
    expect(
      _card(_survivorUri, within: find.byType(ProfileScreen)),
      findsOneWidget,
    );
    await tester.tap(_nav('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discover'));
    await tester.pumpAndSettle();
  }

  Future<void> expectHomeWithoutPost(
    WidgetTester tester, {
    String uri = _removedUri,
  }) async {
    expect(_card(uri, within: _home(FeedType.discover)), findsNothing);
    expect(
      _card(_survivorUri, within: _home(FeedType.discover)),
      findsOneWidget,
    );
    await tester.tap(find.text('For You'));
    await tester.pumpAndSettle();
    expect(_card(uri, within: _home(FeedType.forYou)), findsNothing);
    expect(_card(_survivorUri, within: _home(FeedType.forYou)), findsOneWidget);
  }

  Future<void> pushCommunity(
    WidgetTester tester,
    GlobalKey<NavigatorState> navigatorKey, {
    String uri = _removedUri,
  }) async {
    unawaited(
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const CommunityFeedScreen(identifier: _communityDid),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      _card(uri, within: find.byType(CommunityFeedScreen)),
      findsOneWidget,
    );
    expect(
      _card(_survivorUri, within: find.byType(CommunityFeedScreen)),
      findsOneWidget,
    );
  }

  void stubAdminState() {
    when(api.getModerationSubjectState(_adminPostUri)).thenAnswer(
      (_) async => const ModerationSubjectState(
        subject: _adminPostUri,
        version: 'v7',
        moderation: ModerationView(state: ModerationState.clear),
        recordState: ModerationRecordState.present,
        currentSubject: StrongRef(uri: _adminPostUri, cid: 'cid-p1'),
      ),
    );
  }

  Future<void> openAdminRemoval(
    WidgetTester tester,
    Finder card, {
    bool settle = true,
  }) async {
    await tester.tap(
      find.descendant(of: card, matching: find.byTooltip('Post options')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove post'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spam'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.ancestor(
        of: find.text('Remove'),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      // The in-flight spinner never settles.
      await tester.pump();
    }
  }

  String titleOn(Finder card) =>
      (card.evaluate().single.widget as PostCard).post.post.record!.title!;

  /// Admin A (the initial account) and admin C get the remove token and an
  /// instance-admin answer; non-admin B gets neither.
  void stubAccounts() {
    feeds = _LoadedSurfaces(
      api,
      moderatedUri: _adminPostUri,
      carriesRemoveToken: () => auth.did != _nonAdminDid,
    )..stub();
    when(api.getViewerAuthority())
        .thenAnswer((_) async => auth.did != _nonAdminDid);
  }

  Future<void> expectRemoveOffered(
    WidgetTester tester,
    Finder card, {
    required bool offered,
  }) async {
    final options = find.descendant(
      of: card,
      matching: find.byTooltip('Post options'),
    );
    await tester.tap(options);
    await tester.pumpAndSettle();
    expect(find.text('Remove post'), offered ? findsOneWidget : findsNothing);
    await tester.tap(options);
    await tester.pumpAndSettle();
  }

  Future<void> refreshCommunity(WidgetTester tester) async {
    unawaited(
      tester
          .state<RefreshIndicatorState>(
            find.descendant(
              of: find.byType(CommunityFeedScreen),
              matching: find.byType(RefreshIndicator),
            ),
          )
          .show(),
    );
    await tester.pumpAndSettle();
  }

  /// Bounded pumps that finish a sheet dismissal while a request is pending.
  Future<void> pumpPastSheetDismissal(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  }

  testWidgets(
    'S6 Remove post follows the account on mounted home and community feeds',
    (tester) async {
      _usePhoneLayout(tester);
      _answerPlatformChannel(tester);
      stubAccounts();
      final navigatorKey = await pumpShell(tester, PostChangeBroadcast());
      final community = find.byType(CommunityFeedScreen);
      await expectRemoveOffered(
        tester,
        _card(_adminPostUri, within: _home(FeedType.discover)),
        offered: true,
      );
      await pushCommunity(tester, navigatorKey, uri: _adminPostUri);
      await expectRemoveOffered(
        tester,
        _card(_adminPostUri, within: community),
        offered: true,
      );

      auth.setSignedInDid(_nonAdminDid);
      await tester.pump();
      // The community feed keeps the cards admin A loaded.
      expect(_card(_adminPostUri, within: community), findsOneWidget);
      await expectRemoveOffered(
        tester,
        _card(_adminPostUri, within: community),
        offered: false,
      );

      final fetchesBeforeRefresh = feeds.communityFetches;
      await refreshCommunity(tester);
      expect(feeds.communityFetches, fetchesBeforeRefresh + 1);
      await expectRemoveOffered(
        tester,
        _card(_adminPostUri, within: community),
        offered: false,
      );

      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      await expectRemoveOffered(
        tester,
        _card(_adminPostUri, within: _home(FeedType.discover)),
        offered: false,
      );

      await pushCommunity(tester, navigatorKey, uri: _adminPostUri);
      auth.setSignedInDid(_otherAdminDid);
      await tester.pumpAndSettle();
      await refreshCommunity(tester);
      await expectRemoveOffered(
        tester,
        _card(_adminPostUri, within: community),
        offered: true,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Remove post is offered to the signed-in admin on the home feed and the '
    'profile',
    (tester) async {
      _usePhoneLayout(tester);
      _answerPlatformChannel(tester);
      stubAccounts();
      await pumpShell(tester, PostChangeBroadcast());
      await visitLoadedProfileThenHome(tester, uri: _adminPostUri);

      await expectRemoveOffered(
        tester,
        _card(_adminPostUri, within: _home(FeedType.discover)),
        offered: true,
      );

      await tester.tap(_nav('Me'));
      await tester.pumpAndSettle();
      await expectRemoveOffered(
        tester,
        _card(_adminPostUri, within: find.byType(ProfileScreen)),
        offered: true,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final answer in ['applied', 'Forbidden']) {
    testWidgets(
      'S8 (${answer == 'applied' ? 'a' : 'b'}) switching accounts closes the '
      'sheet and ignores a late $answer answer',
      (tester) async {
        _usePhoneLayout(tester);
        _answerPlatformChannel(tester);
        stubAccounts();
        stubAdminState();
        final removal = Completer<ModerationMutationResult>();
        when(
          api.removeContent(
            subject: anyNamed('subject'),
            expectedVersion: anyNamed('expectedVersion'),
            idempotencyKey: anyNamed('idempotencyKey'),
            reason: anyNamed('reason'),
            privateNote: anyNamed('privateNote'),
          ),
        ).thenAnswer((_) => removal.future);
        try {
          await pumpShell(tester, PostChangeBroadcast());
          final authority = tester
              .element(_home(FeedType.discover))
              .read<ViewerAuthorityProvider>();
          await openAdminRemoval(
            tester,
            _card(_adminPostUri, within: _home(FeedType.discover)),
            settle: false,
          );
          await tester.pump();
          expect(find.byType(BottomSheet), findsOneWidget);
          verify(
            api.removeContent(
              subject: anyNamed('subject'),
              expectedVersion: anyNamed('expectedVersion'),
              idempotencyKey: anyNamed('idempotencyKey'),
              reason: anyNamed('reason'),
              privateNote: anyNamed('privateNote'),
            ),
          ).called(1);

          auth.setSignedInDid(_nonAdminDid);
          await pumpPastSheetDismissal(tester);
          expect(find.byType(BottomSheet), findsNothing);
          expect(
            _card(_adminPostUri, within: _home(FeedType.discover)),
            findsOneWidget,
          );

          if (answer == 'applied') {
            removal.complete(
              const ModerationMutationResult(
                outcome: ModerationMutationOutcome.applied,
                state: ModerationSubjectState(
                  subject: _adminPostUri,
                  version: 'v8',
                  moderation: ModerationView(state: ModerationState.removed),
                  recordState: ModerationRecordState.present,
                  currentSubject: StrongRef(uri: _adminPostUri, cid: 'cid-p1'),
                ),
              ),
            );
          } else {
            removal.completeError(
              ApiException(
                'Forbidden',
                statusCode: 403,
                errorCode: 'Forbidden',
              ),
            );
          }
          await tester.pumpAndSettle();
          expect(
            _card(_adminPostUri, within: _home(FeedType.discover)),
            findsOneWidget,
          );
          expect(find.byType(SnackBar), findsNothing);
          expect(authority.isRevoked, isFalse);
        } finally {
          if (!removal.isCompleted) {
            removal.complete(
              const ModerationMutationResult(
                outcome: ModerationMutationOutcome.applied,
                state: ModerationSubjectState(
                  subject: _adminPostUri,
                  version: 'v8',
                  moderation: ModerationView(state: ModerationState.clear),
                  recordState: ModerationRecordState.present,
                ),
              ),
            );
            await tester.pump();
          }
        }
      },
    );
  }

  testWidgets(
    'S8 (a) an applied answer that lands while the sheet is still closing '
    'leaves the pushed community feed open',
    (tester) async {
      _usePhoneLayout(tester);
      _answerPlatformChannel(tester);
      stubAccounts();
      stubAdminState();
      final removal = Completer<ModerationMutationResult>();
      when(
        api.removeContent(
          subject: anyNamed('subject'),
          expectedVersion: anyNamed('expectedVersion'),
          idempotencyKey: anyNamed('idempotencyKey'),
          reason: anyNamed('reason'),
          privateNote: anyNamed('privateNote'),
        ),
      ).thenAnswer((_) => removal.future);
      try {
        final navigatorKey = await pumpShell(tester, PostChangeBroadcast());
        await pushCommunity(tester, navigatorKey, uri: _adminPostUri);
        final community = find.byType(CommunityFeedScreen);
        await openAdminRemoval(
          tester,
          _card(_adminPostUri, within: community),
          settle: false,
        );
        await tester.pump();
        expect(find.byType(BottomSheet), findsOneWidget);

        auth.setSignedInDid(_nonAdminDid);
        await tester.pump();
        // The sheet is still mounted, running its exit animation.
        expect(find.byType(BottomSheet), findsOneWidget);

        removal.complete(
          const ModerationMutationResult(
            outcome: ModerationMutationOutcome.applied,
            state: ModerationSubjectState(
              subject: _adminPostUri,
              version: 'v8',
              moderation: ModerationView(state: ModerationState.removed),
              recordState: ModerationRecordState.present,
              currentSubject: StrongRef(uri: _adminPostUri, cid: 'cid-p1'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        expect(community, findsOneWidget);
        expect(_card(_adminPostUri, within: community), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        if (!removal.isCompleted) {
          removal.complete(
            const ModerationMutationResult(
              outcome: ModerationMutationOutcome.applied,
              state: ModerationSubjectState(
                subject: _adminPostUri,
                version: 'v8',
                moderation: ModerationView(state: ModerationState.clear),
                recordState: ModerationRecordState.present,
              ),
            ),
          );
          await tester.pump();
        }
      }
    },
  );

  testWidgets(
    'S8 (c) a ContentChanged reload that lands after the switch is ignored',
    (tester) async {
      _usePhoneLayout(tester);
      _answerPlatformChannel(tester);
      stubAccounts();
      stubAdminState();
      when(
        api.removeContent(
          subject: anyNamed('subject'),
          expectedVersion: anyNamed('expectedVersion'),
          idempotencyKey: anyNamed('idempotencyKey'),
          reason: anyNamed('reason'),
          privateNote: anyNamed('privateNote'),
        ),
      ).thenThrow(
        ApiException('Edited', statusCode: 400, errorCode: 'ContentChanged'),
      );
      final reload = Completer<PostGetResult>();
      when(api.getPost(_adminPostUri)).thenAnswer((_) => reload.future);
      try {
        await pumpShell(tester, PostChangeBroadcast());
        await openAdminRemoval(
          tester,
          _card(_adminPostUri, within: _home(FeedType.discover)),
          settle: false,
        );
        await tester.pump();
        verify(api.getPost(_adminPostUri)).called(1);

        auth.setSignedInDid(_nonAdminDid);
        await pumpPastSheetDismissal(tester);
        expect(find.byType(BottomSheet), findsNothing);

        reload.complete(
          PostGetSuccess(
            _post(
              _adminPostUri,
              'Edited after review',
              viewer: ViewerState(moderation: {ModerationCapability.remove}),
            ).post.copyWith(cid: 'cid-p1-edited'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsNothing);
        await expectRemoveOffered(
          tester,
          _card(_adminPostUri, within: _home(FeedType.discover)),
          offered: false,
        );
      } finally {
        if (!reload.isCompleted) {
          reload.complete(const PostGetNotFound(_adminPostUri));
          await tester.pump();
        }
      }
    },
  );

  testWidgets('W4 ContentChanged replaces loaded cards and reconciles vote', (
    tester,
  ) async {
    _usePhoneLayout(tester);
    _answerPlatformChannel(tester);
    feeds = _LoadedSurfaces(api, moderatedUri: _adminPostUri)..stub();
    stubAdminState();
    when(
      api.removeContent(
        subject: anyNamed('subject'),
        expectedVersion: anyNamed('expectedVersion'),
        idempotencyKey: anyNamed('idempotencyKey'),
        reason: anyNamed('reason'),
        privateNote: anyNamed('privateNote'),
      ),
    ).thenThrow(
      ApiException('Edited', statusCode: 400, errorCode: 'ContentChanged'),
    );
    final edited = _post(
      _adminPostUri,
      'Edited after review',
      viewer: ViewerState(
        vote: 'up',
        moderation: {ModerationCapability.remove},
      ),
    ).post.copyWith(cid: 'cid-p1-edited');
    when(api.getPost(_adminPostUri))
        .thenAnswer((_) async => PostGetSuccess(edited));
    await pumpShell(tester, PostChangeBroadcast());
    await visitLoadedProfileThenHome(tester, uri: _adminPostUri);
    final votes = tester.element(_home(FeedType.discover)).read<VoteProvider>();
    await openAdminRemoval(
      tester,
      _card(_adminPostUri, within: _home(FeedType.discover)),
    );
    verify(api.getPost(_adminPostUri)).called(1);
    expect(find.byType(BottomSheet), findsNothing);
    expect(
      find.text(
        'The author edited this post. Review the new version before acting.',
      ),
      findsOneWidget,
    );
    expect(
      titleOn(_card(_adminPostUri, within: _home(FeedType.discover))),
      'Edited after review',
    );
    expect(
      titleOn(
        _card(
          _adminPostUri,
          within: find.byType(ProfileScreen, skipOffstage: false),
        ),
      ),
      'Edited after review',
    );
    expect(votes.getVoteState(_adminPostUri)?.direction, 'up');
    expect(votes.isLiked(_adminPostUri), isTrue);
    // A subsequent action must carry the newly fetched content reference.
    await tester.tap(
      find.descendant(
        of: _card(_adminPostUri, within: _home(FeedType.discover)),
        matching: find.byTooltip('Post options'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove post'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spam'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.ancestor(
        of: find.text('Remove'),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );
    await tester.pumpAndSettle();
    final subjects = verify(
      api.removeContent(
        subject: captureAnyNamed('subject'),
        expectedVersion: anyNamed('expectedVersion'),
        idempotencyKey: anyNamed('idempotencyKey'),
        reason: anyNamed('reason'),
        privateNote: anyNamed('privateNote'),
      ),
    ).captured.cast<StrongRef>();
    expect(subjects, hasLength(2));
    expect(subjects.last.cid, 'cid-p1-edited');
  });

  testWidgets('W5a SubjectNotFound tombstone removes every loaded card', (
    tester,
  ) async {
    _usePhoneLayout(tester);
    _answerPlatformChannel(tester);
    feeds = _LoadedSurfaces(api, moderatedUri: _adminPostUri)..stub();
    stubAdminState();
    when(
      api.removeContent(
        subject: anyNamed('subject'),
        expectedVersion: anyNamed('expectedVersion'),
        idempotencyKey: anyNamed('idempotencyKey'),
        reason: anyNamed('reason'),
        privateNote: anyNamed('privateNote'),
      ),
    ).thenThrow(
      ApiException('Gone', statusCode: 400, errorCode: 'SubjectNotFound'),
    );
    when(api.getPost(_adminPostUri))
        .thenAnswer((_) async => const PostGetNotFound(_adminPostUri));
    final navigatorKey = await pumpShell(tester, PostChangeBroadcast());
    await visitLoadedProfileThenHome(tester, uri: _adminPostUri);
    await pushCommunity(tester, navigatorKey, uri: _adminPostUri);
    await openAdminRemoval(
      tester,
      _card(_adminPostUri, within: find.byType(CommunityFeedScreen)),
    );
    verify(api.getPost(_adminPostUri)).called(1);
    expect(find.byType(BottomSheet), findsNothing);
    expect(
      find.text('This item changed. Showing the latest version.'),
      findsOneWidget,
    );
    expect(
      _card(_adminPostUri, within: find.byType(CommunityFeedScreen)),
      findsNothing,
    );
    expect(
      _card(
        _adminPostUri,
        within: find.byType(ProfileScreen, skipOffstage: false),
      ),
      findsNothing,
    );
    expect(
      _card(_adminPostUri, within: _home(FeedType.discover)),
      findsNothing,
    );
    expect(
      _card(_survivorUri, within: find.byType(CommunityFeedScreen)),
      findsOneWidget,
    );
  });

  testWidgets(
    'W5b preflight SubjectNotFound replaces live post without mutation',
    (tester) async {
      _usePhoneLayout(tester);
      _answerPlatformChannel(tester);
      feeds = _LoadedSurfaces(api, moderatedUri: _adminPostUri)..stub();
      when(api.getModerationSubjectState(_adminPostUri)).thenThrow(
        ApiException('Gone', statusCode: 400, errorCode: 'SubjectNotFound'),
      );
      when(api.getPost(_adminPostUri)).thenAnswer(
        (_) async => PostGetSuccess(
          _post(
            _adminPostUri,
            'Current live title',
            viewer: ViewerState(moderation: {ModerationCapability.remove}),
          ).post.copyWith(cid: 'cid-p1-edited'),
        ),
      );
      await pumpShell(tester, PostChangeBroadcast());
      await openAdminRemoval(
        tester,
        _card(_adminPostUri, within: _home(FeedType.discover)),
      );
      verify(api.getPost(_adminPostUri)).called(1);
      verifyNever(
        api.removeContent(
          subject: anyNamed('subject'),
          expectedVersion: anyNamed('expectedVersion'),
          idempotencyKey: anyNamed('idempotencyKey'),
          reason: anyNamed('reason'),
          privateNote: anyNamed('privateNote'),
        ),
      );
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        find.text('This item changed. Showing the latest version.'),
        findsOneWidget,
      );
      expect(
        titleOn(_card(_adminPostUri, within: _home(FeedType.discover))),
        'Current live title',
      );
    },
  );

  for (final failurePoint in ['mutation', 'preflight']) {
    testWidgets('W6 Forbidden $failurePoint revokes menus across surfaces', (
      tester,
    ) async {
      _usePhoneLayout(tester);
      _answerPlatformChannel(tester);
      feeds = _LoadedSurfaces(api, moderatedUri: _adminPostUri)..stub();
      stubAdminState();
      if (failurePoint == 'preflight') {
        when(api.getModerationSubjectState(_adminPostUri)).thenThrow(
          ApiException('Forbidden', statusCode: 403, errorCode: 'Forbidden'),
        );
      } else {
        when(
          api.removeContent(
            subject: anyNamed('subject'),
            expectedVersion: anyNamed('expectedVersion'),
            idempotencyKey: anyNamed('idempotencyKey'),
            reason: anyNamed('reason'),
            privateNote: anyNamed('privateNote'),
          ),
        ).thenThrow(
          ApiException('Forbidden', statusCode: 403, errorCode: 'Forbidden'),
        );
      }
      final navigatorKey = await pumpShell(tester, PostChangeBroadcast());
      await pushCommunity(tester, navigatorKey, uri: _adminPostUri);
      final authority = tester
          .element(find.byType(CommunityFeedScreen))
          .read<ViewerAuthorityProvider>();
      await openAdminRemoval(
        tester,
        _card(_adminPostUri, within: find.byType(CommunityFeedScreen)),
      );
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('You no longer have admin access.'), findsOneWidget);
      expect(authority.status, ViewerAuthorityStatus.revoked);
      await tester.tap(
        find.descendant(
          of: _card(_adminPostUri, within: find.byType(CommunityFeedScreen)),
          matching: find.byTooltip('Post options'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Remove post'), findsNothing);
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: _card(_adminPostUri, within: _home(FeedType.discover)),
          matching: find.byTooltip('Post options'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Remove post'), findsNothing);
    });
  }

  testWidgets('B1 home delete removes the post from the already-open profile', (
    tester,
  ) async {
    _usePhoneLayout(tester);
    _answerPlatformChannel(tester);
    final broadcast = PostChangeBroadcast();
    await pumpShell(tester, broadcast);
    await visitLoadedProfileThenHome(tester);
    final fetchesBeforeDelete = feeds.fetchCounts;

    await _deleteFromCard(
      tester,
      _card(_removedUri, within: _home(FeedType.discover)),
    );
    verify(api.deletePost(uri: _removedUri)).called(1);
    await expectHomeWithoutPost(tester);
    await tester.tap(_nav('Me'));
    await tester.pumpAndSettle();
    final profile = find.byType(ProfileScreen);
    expect(_card(_removedUri, within: profile), findsNothing);
    expect(_card(_survivorUri, within: profile), findsOneWidget);
    expect(feeds.fetchCounts, fetchesBeforeDelete);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'B2 community delete removes the post from home and open profile',
    (tester) async {
      _usePhoneLayout(tester);
      _answerPlatformChannel(tester);
      final broadcast = PostChangeBroadcast();
      final navigatorKey = await pumpShell(tester, broadcast);
      await visitLoadedProfileThenHome(tester);
      await pushCommunity(tester, navigatorKey);
      final fetchesBeforeDelete = feeds.fetchCounts;

      final community = find.byType(CommunityFeedScreen);
      await _deleteFromCard(tester, _card(_removedUri, within: community));
      verify(api.deletePost(uri: _removedUri)).called(1);
      expect(_card(_removedUri, within: community), findsNothing);
      expect(_card(_survivorUri, within: community), findsOneWidget);
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      await expectHomeWithoutPost(tester);
      await tester.tap(_nav('Me'));
      await tester.pumpAndSettle();
      final profile = find.byType(ProfileScreen);
      expect(_card(_removedUri, within: profile), findsNothing);
      expect(_card(_survivorUri, within: profile), findsOneWidget);
      expect(feeds.fetchCounts, fetchesBeforeDelete);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'B3 profile delete removes the post from open community and home',
    (tester) async {
      _usePhoneLayout(tester);
      _answerPlatformChannel(tester);
      final broadcast = PostChangeBroadcast();
      final navigatorKey = await pumpShell(tester, broadcast);
      await visitLoadedProfileThenHome(tester);
      await pushCommunity(tester, navigatorKey);
      unawaited(
        navigatorKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const ProfileScreen(actor: _authorDid),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final pushedProfile = find.byType(ProfileScreen).last;
      expect(_card(_removedUri, within: pushedProfile), findsOneWidget);
      expect(_card(_survivorUri, within: pushedProfile), findsOneWidget);
      final fetchesBeforeDelete = feeds.fetchCounts;

      await _deleteFromCard(tester, _card(_removedUri, within: pushedProfile));
      verify(api.deletePost(uri: _removedUri)).called(1);
      expect(_card(_removedUri, within: pushedProfile), findsNothing);
      expect(_card(_survivorUri, within: pushedProfile), findsOneWidget);
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      final community = find.byType(CommunityFeedScreen);
      expect(_card(_removedUri, within: community), findsNothing);
      expect(_card(_survivorUri, within: community), findsOneWidget);
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      await expectHomeWithoutPost(tester);
      expect(feeds.fetchCounts, fetchesBeforeDelete);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('B3r community replacement stays in place and pop unsubscribes', (
    tester,
  ) async {
    _usePhoneLayout(tester);
    final broadcast = _RecordingBroadcast();
    when(
      api.getCommunityFeed(
        community: anyNamed('community'),
        sort: anyNamed('sort'),
        timeframe: anyNamed('timeframe'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((_) async {
      feeds.communityFetches++;
      return TimelineResponse(
        feed: [
          _post(_beforeUri, 'Before neighbour'),
          _post(_removedUri, 'Old middle title'),
          _post(_afterUri, 'After neighbour'),
        ],
      );
    });
    final navigatorKey = await pumpShell(tester, broadcast);
    final additionsBeforeCommunity = broadcast.additions;
    await pushCommunityForReplacement(tester, navigatorKey);
    final community = find.byType(CommunityFeedScreen);
    List<String> titles() => find
        .descendant(
          of: community,
          matching: find.byType(PostCard, skipOffstage: false),
          skipOffstage: false,
        )
        .evaluate()
        .map((element) => (element.widget as PostCard).post.post.record!.title!)
        .toList();
    expect(titles(), [
      'Before neighbour',
      'Old middle title',
      'After neighbour',
    ]);
    final fetchesBeforeReplace = feeds.fetchCounts;
    final additionsWithCommunity = broadcast.additions;
    final removalsWithCommunity = broadcast.removals;

    broadcast.replacePost(_post(_removedUri, 'New middle title').post);
    await tester.pump();
    expect(titles(), [
      'Before neighbour',
      'New middle title',
      'After neighbour',
    ]);
    expect(find.text('New middle title'), findsOneWidget);
    expect(find.text('Old middle title', skipOffstage: false), findsNothing);
    expect(feeds.fetchCounts, fetchesBeforeReplace);
    expect(additionsWithCommunity - additionsBeforeCommunity, 1);

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(broadcast.removals - removalsWithCommunity, 1);
    expect(broadcast.additions, additionsWithCommunity);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'B8 admin removal reaches home, loaded profile and open community',
    (tester) async {
      _usePhoneLayout(tester);
      _answerPlatformChannel(tester);
      feeds = _LoadedSurfaces(api, moderatedUri: _adminPostUri)..stub();
      when(api.getModerationSubjectState(_adminPostUri)).thenAnswer(
        (_) async => const ModerationSubjectState(
          subject: _adminPostUri,
          version: 'v7',
          moderation: ModerationView(state: ModerationState.clear),
          recordState: ModerationRecordState.present,
          currentSubject: StrongRef(uri: _adminPostUri, cid: 'cid-p1'),
        ),
      );
      final removal = Completer<ModerationMutationResult>();
      when(
        api.removeContent(
          subject: anyNamed('subject'),
          expectedVersion: anyNamed('expectedVersion'),
          idempotencyKey: anyNamed('idempotencyKey'),
          reason: anyNamed('reason'),
          privateNote: anyNamed('privateNote'),
        ),
      ).thenAnswer((_) => removal.future);
      final broadcast = PostChangeBroadcast();
      final changes = <PostChange>[];
      broadcast.addPostChangeListener(changes.add);
      try {
        final navigatorKey = await pumpShell(tester, broadcast);
        await visitLoadedProfileThenHome(tester, uri: _adminPostUri);
        await pushCommunity(tester, navigatorKey, uri: _adminPostUri);
        final community = find.byType(CommunityFeedScreen, skipOffstage: false);
        final profile = find.byType(ProfileScreen, skipOffstage: false);
        final fetchesBeforeRemove = feeds.fetchCounts;

        await tester.tap(
          find.descendant(
            of: _card(_adminPostUri, within: community),
            matching: find.byTooltip('Post options'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Remove post'), findsOneWidget);
        await tester.tap(find.text('Remove post'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Spam'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.ancestor(
            of: find.text('Remove'),
            matching: find.bySubtype<ButtonStyleButton>(),
          ),
        );
        await tester.pump();
        expect(_card(_adminPostUri, within: community), findsOneWidget);
        expect(_card(_adminPostUri, within: profile), findsOneWidget);
        expect(
          _card(_adminPostUri, within: _home(FeedType.discover)),
          findsOneWidget,
        );
        expect(changes.whereType<PostRemoved>(), isEmpty);

        removal.complete(
          const ModerationMutationResult(
            outcome: ModerationMutationOutcome.applied,
            state: ModerationSubjectState(
              subject: _adminPostUri,
              version: 'v8',
              moderation: ModerationView(state: ModerationState.removed),
              recordState: ModerationRecordState.present,
              currentSubject: StrongRef(uri: _adminPostUri, cid: 'cid-p1'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(changes.whereType<PostRemoved>().map((change) => change.uri), [
          _adminPostUri,
        ]);
        expect(_card(_adminPostUri, within: community), findsNothing);
        expect(_card(_survivorUri, within: community), findsOneWidget);
        expect(_card(_adminPostUri, within: profile), findsNothing);
        expect(
          _card(_adminPostUri, within: _home(FeedType.discover)),
          findsNothing,
        );
        expect(find.text('Post removed'), findsOneWidget);
        navigatorKey.currentState!.pop();
        await tester.pumpAndSettle();
        await expectHomeWithoutPost(tester, uri: _adminPostUri);
        await tester.tap(_nav('Me'));
        await tester.pumpAndSettle();
        expect(
          _card(_adminPostUri, within: find.byType(ProfileScreen)),
          findsNothing,
        );
        expect(
          _card(_survivorUri, within: find.byType(ProfileScreen)),
          findsOneWidget,
        );
        expect(feeds.fetchCounts, fetchesBeforeRemove);
        expect(tester.takeException(), isNull);
      } finally {
        if (!removal.isCompleted) {
          removal.complete(
            const ModerationMutationResult(
              outcome: ModerationMutationOutcome.applied,
              state: ModerationSubjectState(
                subject: _adminPostUri,
                version: 'v8',
                moderation: ModerationView(state: ModerationState.clear),
                recordState: ModerationRecordState.present,
              ),
            ),
          );
          await tester.pump();
        }
      }
    },
  );
}

Future<void> pushCommunityForReplacement(
  WidgetTester tester,
  GlobalKey<NavigatorState> navigatorKey,
) async {
  unawaited(
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const CommunityFeedScreen(identifier: _communityDid),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final community = find.byType(CommunityFeedScreen);
  expect(_card(_beforeUri, within: community), findsOneWidget);
  expect(_card(_removedUri, within: community), findsOneWidget);
  expect(_card(_afterUri, within: community), findsOneWidget);
}
