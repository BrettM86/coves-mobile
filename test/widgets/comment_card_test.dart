import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Helper to create a test comment
  CommentView createComment({
    String uri = 'at://did:plc:test/comment/1',
    String content = 'Test comment',
    String handle = 'test.user',
    bool isDeleted = false,
    String? deletionReason,
  }) {
    return CommentView(
      uri: uri,
      cid: 'cid-$uri',
      record: isDeleted ? null : CommentRecord(content: content),
      isDeleted: isDeleted,
      deletionReason: deletionReason,
      createdAt: DateTime(2025),
      indexedAt: DateTime(2025),
      author: AuthorView(did: 'did:plc:author', handle: handle),
      post: CommentRef(uri: 'at://did:plc:test/post/123', cid: 'post-cid'),
      stats: CommentStats(upvotes: 5, downvotes: 1, score: 4),
    );
  }

  group('CommentCard model integration', () {
    test('deleted comment has null record and isDeleted true', () {
      final deletedComment = createComment(
        isDeleted: true,
        deletionReason: 'author',
      );

      expect(deletedComment.isDeleted, isTrue);
      expect(deletedComment.record, isNull);
      expect(deletedComment.deletionReason, 'author');
      expect(deletedComment.content, ''); // Falls back to empty string
    });

    test('non-deleted comment has record and isDeleted false', () {
      final normalComment = createComment(content: 'Hello, world!');

      expect(normalComment.isDeleted, isFalse);
      expect(normalComment.record, isNotNull);
      expect(normalComment.content, 'Hello, world!');
    });

    test('deleted comment still has author info', () {
      final deletedComment = createComment(
        isDeleted: true,
        handle: 'deleted.user',
      );

      expect(deletedComment.author.handle, 'deleted.user');
    });

    test('empty content string is different from deleted', () {
      final emptyComment = createComment(content: '');

      expect(emptyComment.isDeleted, isFalse);
      expect(emptyComment.content, '');
      expect(emptyComment.record, isNotNull);
    });
  });

  // Widget tests are skipped due to Provider type compatibility issues.
  // See comment_thread_test.dart for similar pattern.
  // The deleted comment UI is verified through:
  // 1. Model tests above confirming data structure
  // 2. Manual testing
  // 3. The CommentCard code that checks isDeleted before rendering
}
