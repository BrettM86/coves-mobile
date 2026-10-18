import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/moderation_subject_state.dart';
import 'package:coves_flutter/providers/comments_provider.dart';
import 'package:coves_flutter/utils/removal_copy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/comment_removal_fixtures.dart';
import '../test_helpers/test_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'B6 clearCommentRemoval evicts only that comment from the removal overlay',
    () async {
      final auth = MockAuthProvider();
      final api = MockCovesApiService();
      when(auth.isAuthenticated).thenReturn(true);
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
      ).thenAnswer(
        (_) async => CommentsResponse(post: null, comments: liveThreads()),
      );
      final provider = CommentsProvider(
        auth,
        postUri: removalPostUri,
        postCid: removalPostCid,
        apiService: api,
      );
      try {
        await provider.loadComments(refresh: true);

        final removed = ModerationMutationResult.fromJson(removeContentJson());
        for (final uri in [targetUri, siblingUri]) {
          provider.markCommentRemoved(
            commentUri: uri,
            state: removed.state,
            action: removed.action,
          );
        }

        provider.clearCommentRemoval(targetUri);

        final target = provider.applyRemovalOverlay(liveTarget()).comment;
        expect(target.isDeleted, isFalse);
        expect(target.record?.content, 'Comment C to remove');

        final sibling = provider.applyRemovalOverlay(liveSibling()).comment;
        expect(sibling.isDeleted, isTrue);
        expect(sibling.record, isNull);
        expect(
          RemovalCopy.forComment(
            deletionReason: sibling.deletionReason,
            moderation: sibling.moderation,
          ),
          '[Removed by server admin]',
        );
      } finally {
        provider.dispose();
      }
    },
  );
}
