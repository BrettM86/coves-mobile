import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/home/profile_screen.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/comment_service.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/link_sharer.dart';
import 'package:coves_flutter/services/profile_cache.dart';
import 'package:coves_flutter/services/viewer_state_hydrator.dart';
import 'package:coves_flutter/widgets/share_button.dart';
import 'package:flutter/material.dart';
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

/// A profile is shareable by anyone who can see it: the viewer's own profile,
/// somebody else's, and a signed-out viewer's. Only the controls that act on
/// the profile — edit and the menu — stay own-only.
void main() {
  // Literals, never produced by the code under test.
  const otherProfileUrl = 'https://coves.social/profile/alice.coves.social';
  const didProfileUrl =
      'https://coves.social/profile/did%3Aplc%3Aauthor123';
  const ownProfileUrl = 'https://coves.social/profile/viewer.coves.social';

  const otherDid = 'did:plc:author123';
  const viewerDid = 'did:plc:viewer999';

  late MockAuthProvider mockAuthProvider;
  late MockVoteProvider mockVoteProvider;
  late MockCovesApiService mockApiService;
  late MockCommentService mockCommentService;
  late BlockProvider blockProvider;
  late RecordingLinkSharer linkSharer;

  setUp(() {
    mockAuthProvider = MockAuthProvider();
    mockVoteProvider = MockVoteProvider();
    mockApiService = MockCovesApiService();
    mockCommentService = MockCommentService();
    linkSharer = RecordingLinkSharer();

    // Signed in as a third party by default; the signed-out group overrides.
    when(mockAuthProvider.isAuthenticated).thenReturn(true);
    when(mockAuthProvider.did).thenReturn(viewerDid);

    blockProvider = BlockProvider(
      apiService: mockApiService,
      authProvider: mockAuthProvider,
    );

    // The posts tab is the initial tab; an empty page keeps the screen quiet.
    when(
      mockApiService.getAuthorPosts(
        actor: anyNamed('actor'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((_) async => TimelineResponse(feed: const []));
  });

  tearDown(() {
    blockProvider.dispose();
  });

  /// Answers `getProfile` with [profile].
  void stubProfile(UserProfile profile) {
    when(
      mockApiService.getProfile(actor: anyNamed('actor')),
    ).thenAnswer((_) async => profile);
  }

  Widget profileApp(String? actor) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: mockAuthProvider),
        ChangeNotifierProvider<VoteProvider>.value(value: mockVoteProvider),
        ChangeNotifierProvider<BlockProvider>.value(value: blockProvider),
        Provider<CovesApiService>.value(value: mockApiService),
        Provider<CommentService>.value(value: mockCommentService),
        Provider<ViewerStateHydrator>(
          create: (_) => ViewerStateHydrator(
            authProvider: mockAuthProvider,
            voteProvider: mockVoteProvider,
          ),
        ),
        Provider<ProfileCache>(
          create: (_) => ProfileCache(mockAuthProvider),
          dispose: (_, cache) => cache.dispose(),
        ),
        Provider<LinkSharer>.value(value: linkSharer),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: ProfileScreen(actor: actor),
      ),
    );
  }

  /// Pumps the screen until the profile has loaded.
  ///
  /// [actor] is null for the own-profile route, which resolves the actor from
  /// the signed-in DID.
  Future<void> pumpProfile(WidgetTester tester, {String? actor}) async {
    addTearDown(() async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark, home: const SizedBox.shrink()),
      );
    });

    await tester.pumpWidget(profileApp(actor));
    await tester.pumpAndSettle();
  }

  Future<void> tapShareButton(WidgetTester tester) async {
    final shareButton = find.byType(ShareButton);
    expect(shareButton, findsOneWidget);

    await tester.tap(shareButton);
    await tester.pumpAndSettle();
  }

  group("another user's profile", () {
    testWidgets('shares the profile web link', (tester) async {
      stubProfile(UserProfile(did: otherDid, handle: 'alice.coves.social'));

      await pumpProfile(tester, actor: otherDid);

      await tapShareButton(tester);

      expect(linkSharer.sharedUrls, [otherProfileUrl]);
      expect(find.text("Couldn't create link"), findsNothing);
    });

    testWidgets('offers no edit or menu control', (tester) async {
      stubProfile(UserProfile(did: otherDid, handle: 'alice.coves.social'));

      await pumpProfile(tester, actor: otherDid);

      // Editing and the sign-out menu act on the viewer's own account.
      expect(find.byTooltip('Edit Profile'), findsNothing);
      expect(find.byTooltip('Menu'), findsNothing);
      expect(find.byIcon(Icons.menu), findsNothing);
    });

    testWidgets('a signed-out viewer can still share it', (tester) async {
      when(mockAuthProvider.isAuthenticated).thenReturn(false);
      when(mockAuthProvider.did).thenReturn(null);
      stubProfile(UserProfile(did: otherDid, handle: 'alice.coves.social'));

      await pumpProfile(tester, actor: otherDid);

      await tapShareButton(tester);

      expect(linkSharer.sharedUrls, [otherProfileUrl]);
      expect(find.text("Couldn't create link"), findsNothing);
    });

    testWidgets('falls back to the DID when the handle is missing', (
      tester,
    ) async {
      stubProfile(UserProfile(did: otherDid));

      await pumpProfile(tester, actor: otherDid);

      await tapShareButton(tester);

      expect(linkSharer.sharedUrls, [didProfileUrl]);
    });

    testWidgets('falls back to the DID for an unresolved handle', (
      tester,
    ) async {
      // `handle.invalid` is ATProto's sentinel for a handle that would 404.
      stubProfile(UserProfile(did: otherDid, handle: 'handle.invalid'));

      await pumpProfile(tester, actor: otherDid);

      await tapShareButton(tester);

      expect(linkSharer.sharedUrls, [didProfileUrl]);
    });
  });

  group('own profile', () {
    testWidgets('shares the profile web link', (tester) async {
      stubProfile(UserProfile(did: viewerDid, handle: 'viewer.coves.social'));

      await pumpProfile(tester);

      await tapShareButton(tester);

      expect(linkSharer.sharedUrls, [ownProfileUrl]);
      expect(find.text("Couldn't create link"), findsNothing);
    });

    testWidgets('keeps the edit and menu controls', (tester) async {
      stubProfile(UserProfile(did: viewerDid, handle: 'viewer.coves.social'));

      await pumpProfile(tester);

      expect(find.byTooltip('Edit Profile'), findsOneWidget);
      expect(find.byTooltip('Menu'), findsOneWidget);
    });
  });

  group('profile that is not loaded', () {
    testWidgets('offers no share button while the profile is loading', (
      tester,
    ) async {
      // Never completes: the screen stays in its loading state.
      final pending = Completer<UserProfile>();
      when(
        mockApiService.getProfile(actor: anyNamed('actor')),
      ).thenAnswer((_) => pending.future);

      addTearDown(() async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark, home: const SizedBox.shrink()),
        );
      });

      await tester.pumpWidget(profileApp(otherDid));
      // The load starts in a post-frame callback; the second frame renders
      // the loading state it produced.
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Nothing identifies the profile yet, so there is no link to offer.
      expect(find.byType(ShareButton), findsNothing);
      expect(linkSharer.sharedUrls, isEmpty);
    });

    testWidgets('offers no share button when the profile failed to load', (
      tester,
    ) async {
      when(
        mockApiService.getProfile(actor: anyNamed('actor')),
      ).thenThrow(NotFoundException('User not found'));

      await pumpProfile(tester, actor: otherDid);

      expect(find.text('Failed to load profile'), findsOneWidget);

      expect(find.byType(ShareButton), findsNothing);
      expect(linkSharer.sharedUrls, isEmpty);
    });
  });
}
