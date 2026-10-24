// A confirmed delete publishes once on the app-wide post change broadcast,
// including when the card has left the tree before the request completes.
// A failed delete shows the shared delete-post error copy.

import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/community_subscription_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/post_change_broadcast.dart';
import 'package:coves_flutter/services/streamable_service.dart';
import 'package:coves_flutter/widgets/post_card.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/error_copy_rows.dart';
import '../test_helpers/fake_providers.dart';
import '../test_helpers/test_mocks.dart';

const String myDid = 'did:plc:me';
const String myHandle = 'me.coves.test';
const String postUri = 'at://did:plc:community/social.coves.community.post/p1';

/// A post written by the signed-in user, so its menu offers "Delete post".
FeedViewPost _myPost() {
  return FeedViewPost(
    post: PostView(
      uri: postUri,
      cid: 'cid-p1',
      rkey: 'p1',
      author: AuthorView(did: myDid, handle: myHandle),
      community: CommunityRef(did: 'did:plc:community', name: 'testcove'),
      createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
      indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
      record: const PostRecord(title: 'My post', content: 'Body'),
      stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
    ),
  );
}

void main() {
  late FakeAuthProvider authProvider;
  late MockCovesApiService apiService;
  late PostChangeBroadcast broadcast;
  late List<PostChange> changes;

  setUp(() {
    authProvider = FakeAuthProvider(
      signedInDid: myDid,
      signedInHandle: myHandle,
    );
    apiService = MockCovesApiService();
    broadcast = PostChangeBroadcast();
    changes = [];
    broadcast.addPostChangeListener(changes.add);
  });

  tearDown(() {
    authProvider.dispose();
  });

  /// With [cardShown], the Scaffold body is a host that stays mounted and
  /// shows the card only while [cardShown] is true, the way a feed list
  /// disposes a card scrolled off screen.
  Future<void> pumpMyPostCard(
    WidgetTester tester, {
    ValueListenable<bool>? cardShown,
  }) async {
    // The delete flow awaits HapticFeedback; without a handler the platform
    // channel call never completes in tests.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (methodCall) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<CovesApiService>.value(value: apiService),
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<VoteProvider>(
            create: (_) => FakeVoteProvider(authProvider),
          ),
          ChangeNotifierProvider<CommunitySubscriptionProvider>(
            create: (_) => FakeSubscriptionProvider(
              authProvider: authProvider,
              apiService: apiService,
            ),
          ),
          ChangeNotifierProvider<BlockProvider>(
            create: (_) => BlockProvider(
              apiService: apiService,
              authProvider: authProvider,
            ),
          ),
          Provider<StreamableService>.value(value: StreamableService()),
          Provider<PostChangeBroadcast>.value(value: broadcast),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: cardShown == null
                ? PostCard(post: _myPost(), sessionStamp: null)
                : ValueListenableBuilder<bool>(
                    valueListenable: cardShown,
                    builder: (context, shown, _) => shown
                        ? PostCard(post: _myPost(), sessionStamp: null)
                        : const SizedBox.shrink(),
                  ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Opens "Post options", taps "Delete post", and waits on the dialog.
  Future<void> openDeleteDialog(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Post options'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete post'));
    await tester.pumpAndSettle();

    expect(find.text('Delete Post'), findsOneWidget);
  }

  testWidgets('B8 confirmed delete publishes once after the request succeeds', (
    tester,
  ) async {
    final deleteRequest = Completer<void>();
    when(apiService.deletePost(uri: postUri))
        .thenAnswer((_) => deleteRequest.future);

    await pumpMyPostCard(tester);
    await openDeleteDialog(tester);

    await tester.tap(find.text('Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    verify(apiService.deletePost(uri: postUri)).called(1);
    expect(changes, isEmpty);
    deleteRequest.complete();
    await tester.pumpAndSettle();
    expect(changes, hasLength(1));
    expect(changes.single, isA<PostRemoved>());
    expect((changes.single as PostRemoved).uri, postUri);
    expect(tester.takeException(), isNull);
  });

  testWidgets('B8 cancelling the dialog neither deletes nor publishes', (
    tester,
  ) async {
    await pumpMyPostCard(tester);
    await openDeleteDialog(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Delete Post'), findsNothing);
    verifyNever(apiService.deletePost(uri: anyNamed('uri')));
    expect(changes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  group('B8 a failed delete does not publish', () {
    final failures = <String, Exception Function()>{
      'network error': () => NetworkException('Connection refused'),
      'forbidden (403)': () => ApiException('Forbidden', statusCode: 403),
      'not found': () => NotFoundException('Post not found'),
    };

    for (final MapEntry(key: description, value: failure) in failures.entries) {
      testWidgets(description, (tester) async {
        final deleteRequest = Completer<void>();
        when(apiService.deletePost(uri: postUri))
            .thenAnswer((_) => deleteRequest.future);

        await pumpMyPostCard(tester);
        await openDeleteDialog(tester);

        await tester.tap(find.text('Delete'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        verify(apiService.deletePost(uri: postUri)).called(1);
        expect(changes, isEmpty);
        deleteRequest.completeError(failure());
        await tester.pumpAndSettle();
        expect(changes, isEmpty);
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('a failed delete shows the shared delete-post copy', (
    tester,
  ) async {
    for (final row in errorCopyRows(
      'Could not delete post. Please try again.',
    )) {
      when(apiService.deletePost(uri: postUri))
          .thenAnswer((_) async => throw row.error);

      await pumpMyPostCard(tester);
      await openDeleteDialog(tester);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(row.expected),
        ),
        findsOneWidget,
        reason: row.name,
      );
      if (row.rawText != null) {
        expect(
          find.textContaining(row.rawText!),
          findsNothing,
          reason: row.name,
        );
      }
      await tester.pumpWidget(const SizedBox());
    }
  });

  group('B8 the card leaves the tree while deletePost is in flight', () {
    /// Confirms the delete, then removes the card while the request is
    /// still pending. Returns the pending request.
    ///
    /// The Completer is created here, inside the test body: one created in
    /// setUp lives outside testWidgets' fake-async zone, and its completion
    /// would never reach the awaiting delete flow during the test.
    Future<Completer<void>> confirmDeleteThenRemoveCard(
      WidgetTester tester,
    ) async {
      final deleteRequest = Completer<void>();
      when(apiService.deletePost(uri: postUri))
          .thenAnswer((_) => deleteRequest.future);
      final cardShown = ValueNotifier<bool>(true);
      addTearDown(cardShown.dispose);

      await pumpMyPostCard(tester, cardShown: cardShown);
      await openDeleteDialog(tester);

      await tester.tap(find.text('Delete'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      verify(apiService.deletePost(uri: postUri)).called(1);
      expect(deleteRequest.isCompleted, isFalse);
      expect(changes, isEmpty);

      cardShown.value = false;
      await tester.pumpAndSettle();
      expect(find.byType(PostCard), findsNothing);

      return deleteRequest;
    }

    testWidgets('success still publishes exactly once', (tester) async {
      final deleteRequest = await confirmDeleteThenRemoveCard(tester);

      deleteRequest.complete();
      await tester.pumpAndSettle();

      expect(changes, hasLength(1));
      expect(changes.single, isA<PostRemoved>());
      expect((changes.single as PostRemoved).uri, postUri);
      expect(tester.takeException(), isNull);
    });

    testWidgets('failure publishes nothing', (tester) async {
      final deleteRequest = await confirmDeleteThenRemoveCard(tester);

      deleteRequest.completeError(NetworkException('Connection refused'));
      await tester.pumpAndSettle();

      expect(changes, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });
}
