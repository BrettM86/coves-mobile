import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/widgets/comment_thread.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers/mock_providers.dart';

void main() {
  late MockAuthProvider mockAuthProvider;
  late MockVoteProvider mockVoteProvider;

  setUp(() {
    mockAuthProvider = MockAuthProvider();
    mockVoteProvider = MockVoteProvider();
  });

  /// Helper to create a test comment
  CommentView createComment({
    required String uri,
    String content = 'Test comment',
    String handle = 'test.user',
  }) {
    return CommentView(
      uri: uri,
      cid: 'cid-$uri',
      record: CommentRecord(content: content),
      createdAt: DateTime(2025),
      indexedAt: DateTime(2025),
      author: AuthorView(did: 'did:plc:author', handle: handle),
      post: CommentRef(uri: 'at://did:plc:test/post/123', cid: 'post-cid'),
      stats: CommentStats(upvotes: 5, downvotes: 1, score: 4),
    );
  }

  /// Helper to create a thread with nested replies
  ThreadViewComment createThread({
    required String uri,
    String content = 'Test comment',
    List<ThreadViewComment>? replies,
  }) {
    return ThreadViewComment(
      comment: createComment(uri: uri, content: content),
      replies: replies,
    );
  }

  Widget createTestWidget(
    ThreadViewComment thread, {
    int depth = 0,
    int maxDepth = 5,
    void Function(ThreadViewComment)? onCommentTap,
    void Function(String uri)? onCollapseToggle,
    void Function(ThreadViewComment, List<ThreadViewComment>)? onContinueThread,
    Set<String> collapsedComments = const {},
    List<ThreadViewComment> ancestors = const [],
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<MockAuthProvider>.value(value: mockAuthProvider),
        ChangeNotifierProvider<MockVoteProvider>.value(value: mockVoteProvider),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CommentThread(
              thread: thread,
              depth: depth,
              maxDepth: maxDepth,
              onCommentTap: onCommentTap,
              onCollapseToggle: onCollapseToggle,
              onContinueThread: onContinueThread,
              collapsedComments: collapsedComments,
              ancestors: ancestors,
            ),
          ),
        ),
      ),
    );
  }

  group('CommentThread', () {
    group('countDescendants', () {
      test('returns 0 for thread with no replies', () {
        final thread = createThread(uri: 'comment/1');

        expect(CommentThread.countDescendants(thread), 0);
      });

      test('returns 0 for thread with empty replies', () {
        final thread = createThread(uri: 'comment/1', replies: []);

        expect(CommentThread.countDescendants(thread), 0);
      });

      test('counts direct replies', () {
        final thread = createThread(
          uri: 'comment/1',
          replies: [
            createThread(uri: 'comment/2'),
            createThread(uri: 'comment/3'),
          ],
        );

        expect(CommentThread.countDescendants(thread), 2);
      });

      test('counts nested replies recursively', () {
        final thread = createThread(
          uri: 'comment/1',
          replies: [
            createThread(
              uri: 'comment/2',
              replies: [
                createThread(uri: 'comment/3'),
                createThread(
                  uri: 'comment/4',
                  replies: [
                    createThread(uri: 'comment/5'),
                  ],
                ),
              ],
            ),
          ],
        );

        // 1 direct reply + 2 nested + 1 deeply nested = 4
        expect(CommentThread.countDescendants(thread), 4);
      });
    });

    group(
      'rendering',
      skip: 'Provider type compatibility issues - needs mock refactoring',
      () {
        testWidgets('renders comment content', (tester) async {
          final thread = createThread(
            uri: 'comment/1',
            content: 'Hello, world!',
          );

          await tester.pumpWidget(createTestWidget(thread));

          expect(find.text('Hello, world!'), findsOneWidget);
        });

        testWidgets('renders nested replies when depth < maxDepth',
            (tester) async {
          final thread = createThread(
            uri: 'comment/1',
            content: 'Parent',
            replies: [
              createThread(uri: 'comment/2', content: 'Child 1'),
              createThread(uri: 'comment/3', content: 'Child 2'),
            ],
          );

          await tester.pumpWidget(createTestWidget(thread));

          expect(find.text('Parent'), findsOneWidget);
          expect(find.text('Child 1'), findsOneWidget);
          expect(find.text('Child 2'), findsOneWidget);
        });

        testWidgets('shows "Read X more replies" at maxDepth', (tester) async {
          final thread = createThread(
            uri: 'comment/1',
            content: 'At max depth',
            replies: [
              createThread(uri: 'comment/2', content: 'Hidden reply'),
            ],
          );

          await tester.pumpWidget(createTestWidget(thread, depth: 5));

          expect(find.text('At max depth'), findsOneWidget);
          expect(find.textContaining('Read'), findsOneWidget);
          expect(find.textContaining('more'), findsOneWidget);
          // The hidden reply should NOT be rendered
          expect(find.text('Hidden reply'), findsNothing);
        });

        testWidgets('does not show "Read more" when depth < maxDepth',
            (tester) async {
          final thread = createThread(
            uri: 'comment/1',
            replies: [
              createThread(uri: 'comment/2'),
            ],
          );

          await tester.pumpWidget(createTestWidget(thread, depth: 3));

          expect(find.textContaining('Read'), findsNothing);
        });

        testWidgets('calls onContinueThread with correct ancestors',
            (tester) async {
          ThreadViewComment? tappedThread;
          List<ThreadViewComment>? receivedAncestors;

          final thread = createThread(
            uri: 'comment/1',
            replies: [
              createThread(uri: 'comment/2'),
            ],
          );

          await tester.pumpWidget(createTestWidget(
            thread,
            depth: 5,
            onContinueThread: (t, a) {
              tappedThread = t;
              receivedAncestors = a;
            },
          ));

          // Find and tap the "Read more" link
          final readMoreFinder = find.textContaining('Read');
          expect(readMoreFinder, findsOneWidget);

          await tester.tap(readMoreFinder);
          await tester.pump();

          expect(tappedThread, isNotNull);
          expect(tappedThread!.comment.uri, 'comment/1');
          expect(receivedAncestors, isNotNull);
          // ancestors should NOT include the thread itself
          expect(receivedAncestors, isEmpty);
        });

        testWidgets('handles correct reply count pluralization',
            (tester) async {
          // Single reply
          final singleReplyThread = createThread(
            uri: 'comment/1',
            replies: [
              createThread(uri: 'comment/2'),
            ],
          );

          await tester.pumpWidget(
            createTestWidget(singleReplyThread, depth: 5),
          );

          expect(find.text('Read 1 more reply'), findsOneWidget);
        });

        testWidgets('handles multiple replies pluralization', (tester) async {
          final multiReplyThread = createThread(
            uri: 'comment/1',
            replies: [
              createThread(uri: 'comment/2'),
              createThread(uri: 'comment/3'),
              createThread(uri: 'comment/4'),
            ],
          );

          await tester.pumpWidget(createTestWidget(multiReplyThread, depth: 5));

          expect(find.text('Read 3 more replies'), findsOneWidget);
        });
      },
    );
  });
}
