import 'dart:async';

import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/comments_provider.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'comments_provider_test.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CommentsProvider disposed during load', () {
    late MockCovesApiService apiService;
    late CommentsProvider provider;
    late Completer<CommentsResponse> response;
    var notificationCount = 0;

    setUp(() {
      apiService = MockCovesApiService();
      response = Completer<CommentsResponse>();
      notificationCount = 0;
      when(
        apiService.getComments(
          postUri: anyNamed('postUri'),
          sort: anyNamed('sort'),
          timeframe: anyNamed('timeframe'),
          cursor: anyNamed('cursor'),
        ),
      ).thenAnswer((_) => response.future);
      provider = CommentsProvider(
        MockAuthProvider(),
        postUri: 'at://did:plc:test/social.coves.community.post/123',
        postCid: 'test-post-cid',
        apiService: apiService,
      )..addListener(() => notificationCount++);
    });

    void expectNoNotificationOrReload() {
      expect(notificationCount, 1);
      verify(
        apiService.getComments(
          postUri: anyNamed('postUri'),
          sort: anyNamed('sort'),
          timeframe: anyNamed('timeframe'),
          cursor: anyNamed('cursor'),
        ),
      ).called(1);
      expect(provider.error, isNull);
      expect(provider.comments, isEmpty);
    }

    test(
      'an unexpected Error landing after dispose neither throws nor reloads',
      () async {
        final failure = StateError('Unexpected response processing failure');
        final load = provider.loadComments(refresh: true);
        provider.dispose();

        response.completeError(failure);
        await expectLater(load, completes);

        expectNoNotificationOrReload();
      },
    );

    test('an ordinary Exception landing after dispose neither throws nor '
        'reloads', () async {
      final load = provider.loadComments(refresh: true);
      provider.dispose();

      response.completeError(Exception('Connection interrupted'));
      await expectLater(load, completes);

      expectNoNotificationOrReload();
    });

    test('superseded and current refreshes landing after dispose neither '
        'throw, notify, nor start another fetch', () async {
      final responses = <Completer<CommentsResponse>>[];
      when(
        apiService.getComments(
          postUri: anyNamed('postUri'),
          sort: anyNamed('sort'),
          timeframe: anyNamed('timeframe'),
          cursor: anyNamed('cursor'),
        ),
      ).thenAnswer((_) {
        final next = Completer<CommentsResponse>();
        responses.add(next);
        return next.future;
      });

      final superseded = provider.loadComments(refresh: true);
      await pumpEventQueue();
      final current = provider.loadComments(refresh: true);
      await pumpEventQueue();
      final fetchesBeforeDispose = responses.length;
      final notificationsBeforeDispose = notificationCount;
      provider.dispose();

      for (final pending in responses) {
        pending.completeError(
          StateError('Unexpected response processing failure'),
        );
      }
      await expectLater(superseded, completes);
      await expectLater(current, completes);
      await pumpEventQueue();

      expect(notificationCount, notificationsBeforeDispose);
      expect(responses, hasLength(fetchesBeforeDispose));
      expect(provider.error, isNull);
      expect(provider.comments, isEmpty);
    });
  });

  group('CommentsProvider after dispose', () {
    late MockCovesApiService apiService;
    late CommentsProvider provider;
    late int requestCount;

    /// When set, next-page requests (those with a cursor) fail.
    var failNextPage = false;

    Future<void> createLoadedProvider() async {
      apiService = MockCovesApiService();
      requestCount = 0;
      when(
        apiService.getComments(
          postUri: anyNamed('postUri'),
          sort: anyNamed('sort'),
          timeframe: anyNamed('timeframe'),
          depth: anyNamed('depth'),
          limit: anyNamed('limit'),
          cursor: anyNamed('cursor'),
          parentRkey: anyNamed('parentRkey'),
        ),
      ).thenAnswer((invocation) async {
        requestCount++;
        if (failNextPage && invocation.namedArguments[#cursor] != null) {
          throw ApiException('Failed to load comments', statusCode: 500);
        }
        return CommentsResponse(
          post: {},
          comments: [_createThreadComment('comment-1')],
          cursor: 'C1',
        );
      });
      final authProvider = MockAuthProvider();
      when(authProvider.isAuthenticated).thenReturn(false);
      provider = CommentsProvider(
        authProvider,
        postUri: 'at://did:plc:test/social.coves.community.post/123',
        postCid: 'test-post-cid',
        apiService: apiService,
      );

      // A loaded thread with a next page, so every entry point has
      // something it would fetch on a live provider.
      await provider.loadComments(refresh: true);
      expect(provider.comments, hasLength(1));
      expect(provider.hasMore, isTrue);
    }

    /// Disposes the provider and forgets every request made so far.
    void disposeAndResetRequests() {
      provider.dispose();
      requestCount = 0;
      clearInteractions(apiService);
    }

    setUp(() async {
      failNextPage = false;
      await createLoadedProvider();
    });

    /// Runs [call] on the disposed provider and checks no getComments
    /// request went out, then that the call completes without throwing.
    Future<void> expectNoRequest(Future<Object?> Function() call) async {
      final pending = call();
      await pumpEventQueue();

      expect(
        requestCount,
        0,
        reason: 'a disposed provider must not send any request',
      );
      verifyNever(
        apiService.getComments(
          postUri: anyNamed('postUri'),
          sort: anyNamed('sort'),
          timeframe: anyNamed('timeframe'),
          depth: anyNamed('depth'),
          limit: anyNamed('limit'),
          cursor: anyNamed('cursor'),
          parentRkey: anyNamed('parentRkey'),
        ),
      );
      await expectLater(pending, completes);
    }

    test('loadComments(refresh: true) sends no request', () async {
      disposeAndResetRequests();
      await expectNoRequest(() => provider.loadComments(refresh: true));
    });

    test('refreshComments sends no request', () async {
      disposeAndResetRequests();
      await expectNoRequest(provider.refreshComments);
    });

    test('loadMoreComments sends no request', () async {
      disposeAndResetRequests();
      await expectNoRequest(provider.loadMoreComments);
    });

    test('setSortOption sends no request', () async {
      disposeAndResetRequests();
      await expectNoRequest(() => provider.setSortOption('new'));
    });

    test('retryLoadMore sends no request', () async {
      // Rebuild the loaded thread with a failing next page, so a live
      // provider's retryLoadMore would refetch it.
      provider.dispose();
      failNextPage = true;
      await createLoadedProvider();
      await provider.loadMoreComments();
      expect(provider.loadMoreError, isNotNull);

      disposeAndResetRequests();
      await expectNoRequest(provider.retryLoadMore);
    });
  });
}

ThreadViewComment _createThreadComment(String id) {
  return ThreadViewComment(
    comment: CommentView(
      uri: id,
      cid: 'cid-$id',
      record: CommentRecord(content: 'Comment $id'),
      createdAt: DateTime(2025),
      indexedAt: DateTime(2025),
      author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
      post: CommentRef(
        uri: 'at://did:plc:test/social.coves.community.post/123',
        cid: 'test-post-cid',
      ),
      stats: const CommentStats(),
    ),
  );
}
