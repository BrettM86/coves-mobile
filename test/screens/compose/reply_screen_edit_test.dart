import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/facet.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/screens/compose/reply_screen.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/widgets/composer/composer_draft.dart';
import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../widgets/composer/formatting_toolbar_test_helpers.dart';
import 'reply_screen_test_harness.dart';

/// The namespace every Coves facet feature type is under
const _facet = 'social.coves.richtext.facet';

const _editedUri = 'at://did:plc:testuser/social.coves.community.comment/e1';

/// The stored record: padded, non-ASCII, with "Café" bold. UTF-8: the two
/// spaces are bytes [0,2), "Café" is bytes [2,7) ('é' is two bytes).
const _storedContent = '  Café is great  ';

/// The sent bold facet over "Café" once the padding is trimmed
const _sentBold = '[0,5) [{"\$type":"$_facet#bold"}]';

CommentView _cafeComment() => CommentView(
  uri: _editedUri,
  cid: 'cid-e1',
  record: const CommentRecord(
    content: _storedContent,
    facets: [
      RichTextFacet(
        index: ByteSlice(byteStart: 2, byteEnd: 7),
        features: [BoldFacetFeature()],
      ),
    ],
  ),
  createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
  indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
  author: AuthorView(did: 'did:plc:testuser', handle: 'testuser.coves.test'),
  post: CommentRef(uri: testPostUri, cid: testPostCid),
  stats: const CommentStats(score: 1, upvotes: 1),
);

void main() {
  late ReplyScreenHarness harness;

  setUp(() => harness = ReplyScreenHarness());
  tearDown(() => harness.dispose());

  /// Opens the edit screen on [_cafeComment] with no CommentsProvider,
  /// recording every submission as its content and described facets
  /// (joined into one string: records compare List fields by identity)
  Future<List<(String, String)>> openEdit(WidgetTester tester) async {
    final submissions = <(String, String)>[];
    await harness.pumpBase(tester);
    await harness.pushEdit(
      tester,
      comment: _cafeComment(),
      onSubmit: (content, facets) async {
        submissions.add((content, facets.map(describeFacet).join(' | ')));
      },
    );
    return submissions;
  }

  Future<void> tapSave(WidgetTester tester) async {
    expect(find.text('Save'), findsOneWidget, reason: 'the Save button');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
  }

  void expectSeededField(WidgetTester tester) {
    final controller = fieldController(tester);
    expect(controller.text, _storedContent);
    expect(controller.inlineRanges, const [
      InlineRange(InlineFormat.bold, 2, 6),
    ]);
    expect(controller.blockRanges, isEmpty);
    expect(controller.featureRanges, isEmpty);
  }

  group('ReplyScreen edit mode', () {
    testWidgets('opens seeded with the comment\'s text and formatting', (
      tester,
    ) async {
      await openEdit(tester);
      expectSeededField(tester);
    });

    testWidgets('the header says Edit comment and the send button Save', (
      tester,
    ) async {
      await openEdit(tester);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Edit comment'),
        ),
        findsOneWidget,
      );
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Send'), findsNothing);
    });

    toolbarTest('Save without changes sends the trimmed content with the '
        'bold at its byte offsets and closes', (tester) async {
      final submissions = await openEdit(tester);
      await tapSave(tester);

      expect(submissions, [('Café is great', _sentBold)]);
      expect(find.byType(ReplyScreen), findsNothing);
    });

    toolbarTest('Save after editing the text sends the new content', (
      tester,
    ) async {
      final submissions = await openEdit(tester);
      await tester.enterText(find.byType(EditableText), 'Café is fine');
      await tester.pump();
      await tapSave(tester);

      expect(submissions, hasLength(1));
      expect(submissions.single.$1, 'Café is fine');
    });

    toolbarTest('removing the bold from the toolbar and saving sends no '
        'facets', (tester) async {
      final submissions = await openEdit(tester);
      expectSeededField(tester);
      await focusField(
        tester,
        const TextSelection(baseOffset: 2, extentOffset: 6),
      );
      await tapButton(tester, 'Bold');
      expect(fieldController(tester).inlineRanges, isEmpty);
      await tapSave(tester);

      expect(submissions, [('Café is great', '')]);
    });

    toolbarTest('a rejected save keeps the screen open with the text and '
        'formatting, and a retry that succeeds sends and closes', (
      tester,
    ) async {
      final submissions = <(String, String)>[];
      var attempts = 0;
      await harness.pumpBase(tester);
      await harness.pushEdit(
        tester,
        comment: _cafeComment(),
        onSubmit: (content, facets) async {
          attempts++;
          submissions.add((content, facets.map(describeFacet).join(' | ')));
          if (attempts == 1) {
            throw ApiException('Comment changed', statusCode: 409);
          }
        },
      );

      await tapSave(tester);
      expect(find.byType(ReplyScreen), findsOneWidget);
      expectSeededField(tester);

      await tapSave(tester);
      expect(find.byType(ReplyScreen), findsNothing);
      expect(submissions, [
        ('Café is great', _sentBold),
        ('Café is great', _sentBold),
      ]);
    });
  });

  group('ReplyScreen edit mode leaves reply drafts alone', () {
    const commentDraftText = 'my reply to the comment';
    const postDraftText = 'my reply to the post';

    final closes = <({String name, Future<void> Function(WidgetTester) act})>[
      (name: 'opening', act: (tester) async {}),
      (
        name: 'Cancel',
        act: (tester) async {
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
        },
      ),
      (
        name: 'system back',
        act: (tester) async {
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
        },
      ),
      (name: 'a failed save', act: tapSave),
      (name: 'a successful save', act: tapSave),
    ];

    for (final close in closes) {
      toolbarTest('${close.name} keeps the existing reply drafts', (
        tester,
      ) async {
        harness.commentsProvider
          ..saveDraft(
            ComposerDraft(
              text: commentDraftText,
              inlineRanges: const [InlineRange(InlineFormat.bold, 0, 2)],
            ),
            parentUri: _editedUri,
          )
          ..saveDraft(ComposerDraft(text: postDraftText));
        await harness.pumpBase(tester);
        await harness.pushEdit(
          tester,
          comment: _cafeComment(),
          withCommentsProvider: true,
          onSubmit: (content, facets) async {
            if (close.name == 'a failed save') {
              throw ApiException('Comment changed', statusCode: 409);
            }
          },
        );
        expectSeededField(tester);

        await close.act(tester);

        final commentDraft = harness.commentsProvider.getDraft(
          parentUri: _editedUri,
        );
        expect(commentDraft?.text, commentDraftText);
        expect(commentDraft?.inlineRanges, const [
          InlineRange(InlineFormat.bold, 0, 2),
        ]);
        expect(harness.commentsProvider.getDraft()?.text, postDraftText);
      });
    }
  });
}
