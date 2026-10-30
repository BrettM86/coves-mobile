import 'package:coves_flutter/models/facet.dart';
import 'package:coves_flutter/providers/comments_provider.dart';
import 'package:coves_flutter/widgets/composer/composer_draft.dart';
import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/test_mocks.dart';

const _parentP = 'at://did:plc:author/social.coves.comment/p';
const _parentQ = 'at://did:plc:author/social.coves.comment/q';

void main() {
  late CommentsProvider provider;

  setUp(() {
    provider = CommentsProvider(
      MockAuthProvider(),
      postUri: 'at://did:plc:test/social.coves.post.record/123',
      postCid: 'test-post-cid',
      apiService: MockCovesApiService(),
      voteProvider: MockVoteProvider(),
    );
  });

  tearDown(() => provider.dispose());

  group('CommentsProvider drafts with ranges', () {
    test('a saved draft comes back with its text and every range', () {
      provider.saveDraft(
        ComposerDraft(
          text: '  hello @alice.test  ',
          inlineRanges: const [InlineRange(InlineFormat.bold, 2, 7)],
          blockRanges: const [BlockRange(BlockFormat.blockquote, 0, 21)],
          featureRanges: const [
            FeatureRange(MentionFacetFeature(did: 'did:plc:alice'), 8, 19),
          ],
        ),
        parentUri: _parentP,
      );

      final draft = provider.getDraft(parentUri: _parentP);

      expect(draft, isNotNull);
      expect(draft!.text, '  hello @alice.test  ');
      expect(draft.inlineRanges, const [InlineRange(InlineFormat.bold, 2, 7)]);
      expect(draft.blockRanges, const [
        BlockRange(BlockFormat.blockquote, 0, 21),
      ]);
      expect(draft.featureRanges, const [
        FeatureRange(MentionFacetFeature(did: 'did:plc:alice'), 8, 19),
      ]);
    });

    test('saving a draft for one parent leaves the other parent and the '
        'top-level draft unchanged', () {
      provider
        ..saveDraft(
          ComposerDraft(
            text: 'reply to q',
            inlineRanges: const [InlineRange(InlineFormat.italic, 0, 5)],
            blockRanges: const [BlockRange(BlockFormat.heading, 0, 10)],
          ),
          parentUri: _parentQ,
        )
        ..saveDraft(
          ComposerDraft(
            text: 'top level',
            inlineRanges: const [InlineRange(InlineFormat.code, 4, 9)],
          ),
        )
        ..saveDraft(
          ComposerDraft(
            text: 'reply to p',
            inlineRanges: const [InlineRange(InlineFormat.bold, 0, 5)],
          ),
          parentUri: _parentP,
        )
        ..saveDraft(
          ComposerDraft(
            text: 'reply to p, edited',
            blockRanges: const [BlockRange(BlockFormat.codeBlock, 0, 18)],
          ),
          parentUri: _parentP,
        );

      final q = provider.getDraft(parentUri: _parentQ);
      expect(q?.text, 'reply to q');
      expect(q?.inlineRanges, const [InlineRange(InlineFormat.italic, 0, 5)]);
      expect(q?.blockRanges, const [BlockRange(BlockFormat.heading, 0, 10)]);
      expect(q?.featureRanges, isEmpty);

      final topLevel = provider.getDraft();
      expect(topLevel?.text, 'top level');
      expect(topLevel?.inlineRanges, const [
        InlineRange(InlineFormat.code, 4, 9),
      ]);
      expect(topLevel?.blockRanges, isEmpty);
      expect(topLevel?.featureRanges, isEmpty);

      // The second save for P replaces the first; the stale bold range
      // must not survive against the edited text.
      final p = provider.getDraft(parentUri: _parentP);
      expect(p?.text, 'reply to p, edited');
      expect(p?.inlineRanges, isEmpty);
      expect(p?.blockRanges, const [BlockRange(BlockFormat.codeBlock, 0, 18)]);
      expect(p?.featureRanges, isEmpty);
    });

    test('a whitespace-only draft is not stored and removes the stored '
        'one', () {
      provider.saveDraft(
        ComposerDraft(
          text: 'keep me',
          inlineRanges: const [InlineRange(InlineFormat.bold, 0, 4)],
        ),
        parentUri: _parentP,
      );
      expect(provider.getDraft(parentUri: _parentP)?.text, 'keep me');

      provider
        ..saveDraft(
          ComposerDraft(
            text: ' \n\t ',
            inlineRanges: const [InlineRange(InlineFormat.bold, 0, 2)],
            blockRanges: const [BlockRange(BlockFormat.blockquote, 0, 4)],
          ),
          parentUri: _parentP,
        )
        ..saveDraft(
          ComposerDraft(
            text: '   ',
            inlineRanges: const [InlineRange(InlineFormat.italic, 0, 3)],
          ),
          parentUri: _parentQ,
        );

      expect(provider.getDraft(parentUri: _parentP), isNull);
      expect(provider.getDraft(parentUri: _parentQ), isNull);
    });

    test('a draft owns its ranges: later changes to the lists it was built '
        'from do not reach it, and its lists cannot be changed', () {
      final inline = [const InlineRange(InlineFormat.bold, 0, 5)];
      final block = [const BlockRange(BlockFormat.blockquote, 0, 11)];
      final feature = [
        const FeatureRange(MentionFacetFeature(did: 'did:plc:alice'), 6, 11),
      ];
      final draft = ComposerDraft(
        text: 'hello @a.co',
        inlineRanges: inline,
        blockRanges: block,
        featureRanges: feature,
      );
      provider.saveDraft(draft, parentUri: _parentP);

      inline.add(const InlineRange(InlineFormat.italic, 0, 11));
      block.clear();
      feature.add(
        const FeatureRange(LinkFacetFeature(uri: 'https://x.com'), 0, 5),
      );

      expect(draft.inlineRanges, const [InlineRange(InlineFormat.bold, 0, 5)]);
      expect(draft.blockRanges, const [
        BlockRange(BlockFormat.blockquote, 0, 11),
      ]);
      expect(draft.featureRanges, const [
        FeatureRange(MentionFacetFeature(did: 'did:plc:alice'), 6, 11),
      ]);

      final stored = provider.getDraft(parentUri: _parentP)!;
      expect(stored.inlineRanges, const [InlineRange(InlineFormat.bold, 0, 5)]);
      expect(stored.blockRanges, const [
        BlockRange(BlockFormat.blockquote, 0, 11),
      ]);
      expect(stored.featureRanges, const [
        FeatureRange(MentionFacetFeature(did: 'did:plc:alice'), 6, 11),
      ]);
      expect(
        () =>
            stored.inlineRanges.add(const InlineRange(InlineFormat.code, 0, 1)),
        throwsUnsupportedError,
      );
      expect(stored.blockRanges.clear, throwsUnsupportedError);
      expect(
        () => stored.featureRanges.add(
          const FeatureRange(MentionFacetFeature(did: 'did:plc:bob'), 0, 1),
        ),
        throwsUnsupportedError,
      );
    });
  });
}
