// Rebuilding a ProfileScreen with a different actor replaces what it shows.
//
// The same ProfileScreen element is rebuilt in place (same tree position,
// no key change) with `actor: B` after `actor: A`. From that moment the
// screen belongs to B: A's header and posts never show while B loads, after
// B loads, or after B fails, and a late answer for A neither loads A's posts
// nor seeds A's block state.
//
// The tree provides only app-level dependencies (the same set main.dart
// registers); no UserProfileProvider is provided here.

import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/screens/home/profile_screen.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/pump_helpers.dart';
import '../test_helpers/test_mocks.dart';

const String myDid = 'did:plc:me';

const String didA = 'did:plc:a';
const String handleA = 'a.coves.test';
const String postTitleA = 'Post by author A';

const String didB = 'did:plc:b';
const String handleB = 'b.coves.test';
const String postTitleB = 'Post by author B';

/// A's profile says I have blocked A, so seeding it would be observable on
/// [BlockProvider.isUserBlocked].
UserProfile _profileA() => UserProfile(
  did: didA,
  handle: handleA,
  viewer: ProfileViewerState(
    blocked: true,
    blockUri: 'at://$myDid/social.coves.actor.block/a',
  ),
);

UserProfile _profileB() => UserProfile(did: didB, handle: handleB);

FeedViewPost _post({
  required String authorDid,
  required String authorHandle,
  required String rkey,
  required String title,
}) {
  return FeedViewPost(
    post: PostView(
      uri: 'at://did:plc:community/social.coves.community.post/$rkey',
      cid: 'cid-$rkey',
      rkey: rkey,
      author: AuthorView(did: authorDid, handle: authorHandle),
      community: CommunityRef(did: 'did:plc:community', name: 'testcove'),
      createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
      indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
      record: PostRecord(title: title, content: 'Body of $title'),
      stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
    ),
  );
}

void main() {
  late FakeAuthProvider authProvider;
  late MockCovesApiService apiService;
  late ValueNotifier<String> actor;

  /// getProfile for a DID listed here answers with the completer's future
  /// instead of resolving immediately.
  late Map<String, Completer<UserProfile>> pendingProfiles;

  setUp(() {
    authProvider = FakeAuthProvider(
      signedInDid: myDid,
      signedInHandle: 'me.coves.test',
    );
    apiService = MockCovesApiService();
    actor = ValueNotifier<String>(didA);
    pendingProfiles = {};

    when(apiService.getProfile(actor: anyNamed('actor')))
        .thenAnswer((invocation) {
          final requested = invocation.namedArguments[#actor] as String;
          final pending = pendingProfiles[requested];
          if (pending != null) {
            return pending.future;
          }
          if (requested == didA) {
            return Future.value(_profileA());
          }
          if (requested == didB) {
            return Future.value(_profileB());
          }
          throw StateError('Unexpected getProfile actor: $requested');
        });

    when(
      apiService.getAuthorPosts(
        actor: anyNamed('actor'),
        filter: anyNamed('filter'),
        community: anyNamed('community'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((invocation) async {
      final requested = invocation.namedArguments[#actor] as String;
      if (requested == didA) {
        return TimelineResponse(
          feed: [
            _post(
              authorDid: didA,
              authorHandle: handleA,
              rkey: 'a',
              title: postTitleA,
            ),
          ],
        );
      }
      if (requested == didB) {
        return TimelineResponse(
          feed: [
            _post(
              authorDid: didB,
              authorHandle: handleB,
              rkey: 'b',
              title: postTitleB,
            ),
          ],
        );
      }
      throw StateError('Unexpected getAuthorPosts actor: $requested');
    });
  });

  tearDown(() {
    actor.dispose();
    authProvider.dispose();
  });

  /// Pumps one ProfileScreen whose actor follows [actor]; changing the
  /// notifier rebuilds the same element with the new actor.
  Future<void> pumpScreen(WidgetTester tester) async {
    // Phone layout
    tester.view.physicalSize = const Size(540, 960);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: profileScreenProviders(
          auth: authProvider,
          apiService: apiService,
          commentService: MockCommentService(),
        ),
        child: MaterialApp(
          theme: AppTheme.dark,
          home: ValueListenableBuilder<String>(
            valueListenable: actor,
            builder: (context, currentActor, _) =>
                ProfileScreen(actor: currentActor),
          ),
        ),
      ),
    );
  }

  void expectNothingOfA() {
    expect(find.text('@$handleA'), findsNothing);
    expect(find.text(didA), findsNothing);
    expect(find.text(postTitleA), findsNothing);
  }

  void expectShowsA() {
    expect(find.text('@$handleA'), findsWidgets);
    expect(find.text(postTitleA), findsOneWidget);
  }

  void expectShowsB() {
    expect(find.text('@$handleB'), findsWidgets);
    expect(find.text(postTitleB), findsOneWidget);
  }

  /// Swaps the screen to B, checking each frame that A never shows.
  Future<void> swapToBCheckingFrames(WidgetTester tester) async {
    final element = tester.element(find.byType(ProfileScreen));

    actor.value = didB;
    await tester.pump();
    // Same element, rebuilt with the new actor
    expect(tester.element(find.byType(ProfileScreen)), same(element));
    expect(
      tester.widget<ProfileScreen>(find.byType(ProfileScreen)).actor,
      didB,
    );
    expectNothingOfA();
    await tester.pump();
    expectNothingOfA();
    await tester.pump(const Duration(milliseconds: 600));
    expectNothingOfA();
  }

  BlockProvider blockProvider(WidgetTester tester) =>
      tester.element(find.byType(ProfileScreen)).read<BlockProvider>();

  testWidgets("switching from a loaded A to a pending B never shows A's "
      'header or posts, then shows only B', (tester) async {
    await pumpScreen(tester);
    await pumpFrames(tester);
    expectShowsA();

    final profileB = Completer<UserProfile>();
    pendingProfiles[didB] = profileB;

    await swapToBCheckingFrames(tester);
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    profileB.complete(_profileB());
    await pumpFrames(tester);

    expectShowsB();
    expectNothingOfA();
    expect(tester.takeException(), isNull);
  });

  testWidgets("A's late answer after switching to B neither shows A, loads "
      "A's posts, nor seeds A's block state", (tester) async {
    final profileA = Completer<UserProfile>();
    pendingProfiles[didA] = profileA;

    await pumpScreen(tester);
    await pumpFrames(tester);
    expectNothingOfA();

    await swapToBCheckingFrames(tester);
    await pumpFrames(tester);
    expectShowsB();
    expectNothingOfA();

    profileA.complete(_profileA());
    await pumpFrames(tester);

    expectShowsB();
    expectNothingOfA();
    verifyNever(
      apiService.getAuthorPosts(
        actor: argThat(equals(didA), named: 'actor'),
        filter: anyNamed('filter'),
        community: anyNamed('community'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    );
    expect(blockProvider(tester).isUserBlocked(didA), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching from a loaded A to B whose load fails shows the '
      "failure state, never A's header or posts", (tester) async {
    await pumpScreen(tester);
    await pumpFrames(tester);
    expectShowsA();

    final profileB = Completer<UserProfile>();
    pendingProfiles[didB] = profileB;

    await swapToBCheckingFrames(tester);

    profileB.completeError(NetworkException('Connection refused'));
    await pumpFrames(tester);

    expect(find.text('Failed to load profile'), findsOneWidget);
    expectNothingOfA();
    expect(tester.takeException(), isNull);
  });
}
