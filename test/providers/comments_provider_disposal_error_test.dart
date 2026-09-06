import 'dart:async';

import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/providers/comments_provider.dart';
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
      'propagates unexpected Error without running queued refresh',
      () async {
        final failure = StateError('Unexpected response processing failure');
        final load = provider.loadComments(refresh: true);
        final outcome = expectLater(load, throwsA(same(failure)));
        await provider.loadComments(refresh: true);
        provider.dispose();

        response.completeError(failure);
        await outcome;

        expectNoNotificationOrReload();
      },
    );

    test('ignores ordinary Exception without running queued refresh', () async {
      final load = provider.loadComments(refresh: true);
      await provider.loadComments(refresh: true);
      provider.dispose();

      response.completeError(Exception('Connection interrupted'));
      await load;

      expectNoNotificationOrReload();
    });
  });
}
