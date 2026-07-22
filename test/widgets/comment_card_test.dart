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
      // Backend omits author entirely for deleted comments to avoid
      // leaking the author's identity.
      author:
          isDeleted ? null : AuthorView(did: 'did:plc:author', handle: handle),
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

    test('deleted comment has no author info', () {
      // The backend omits the author for deleted comments so the UI can
      // never link to the author's profile or expose their DID.
      final deletedComment = createComment(isDeleted: true);

      expect(deletedComment.author, isNull);
    });

    test('empty content string is different from deleted', () {
      final emptyComment = createComment(content: '');

      expect(emptyComment.isDeleted, isFalse);
      expect(emptyComment.content, '');
      expect(emptyComment.record, isNotNull);
    });

    test('isTombstoned is set for deleted comments only', () {
      // CommentCard renders the tombstone placeholder off this getter.
      // (The author == null arm is defensive: CommentView asserts that
      // non-deleted comments always carry an author.)
      expect(createComment(isDeleted: true).isTombstoned, isTrue);
      expect(createComment().isTombstoned, isFalse);
    });
  });

  // CommentCard rendering (including the tombstone placeholder for deleted
  // comments) is covered by the widget tests in comment_thread_test.dart,
  // which drive CommentCard through real providers over shared generated
  // mocks (test/test_helpers/test_mocks.dart).
}
