import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/moderation.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/widgets/comment_card.dart';
import 'package:coves_flutter/widgets/icons/animated_heart_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/test_mocks.dart';

/// CommentCard's placeholder for a deleted or removed comment: the copy
/// names who removed it, the placeholder author (`handle.invalid`) never
/// renders, and the card is inert (no reply on tap, no votes).
void main() {
  const placeholderDid = 'did:plc:author';
  const placeholderHandle = 'handle.invalid';

  late MockAuthProvider mockAuthProvider;
  late MockVoteProvider mockVoteProvider;
  late MockCovesApiService mockApiService;
  late BlockProvider blockProvider;

  setUp(() {
    mockAuthProvider = MockAuthProvider();
    mockVoteProvider = MockVoteProvider();
    mockApiService = MockCovesApiService();
    blockProvider = BlockProvider(
      apiService: mockApiService,
      authProvider: mockAuthProvider,
    );

    when(mockAuthProvider.isAuthenticated).thenReturn(false);
    when(mockVoteProvider.isLiked(any)).thenReturn(false);
    when(mockVoteProvider.getVoteState(any)).thenReturn(null);
    when(mockVoteProvider.isPending(any)).thenReturn(false);
    when(mockVoteProvider.getAdjustedScore(any, any))
        .thenAnswer((invocation) => invocation.positionalArguments[1] as int);
  });

  /// A removal with one source per entry of [kinds], in that order.
  ModerationView removedInAll(List<ModerationScopeKind> kinds) =>
      ModerationView(
        state: ModerationState.removed,
        sources: [
          for (final kind in kinds)
            ModerationSource(
              authorityDid: 'did:web:coves.social',
              scope: ModerationScope(
                kind: kind,
                communityDid: kind == ModerationScopeKind.community
                    ? 'did:plc:community'
                    : null,
              ),
            ),
        ],
      );

  ModerationView removedIn(ModerationScopeKind kind) => removedInAll([kind]);

  /// A placeholder as the AppView serves it: no record, the
  /// `handle.invalid` author, zero votes, replies kept.
  CommentView placeholder({
    required String? deletionReason,
    ModerationView? moderation,
  }) {
    return CommentView(
      uri: 'at://did:plc:author/social.coves.community.comment/gone',
      cid: 'cid-gone',
      isDeleted: true,
      deletionReason: deletionReason,
      moderation: moderation,
      createdAt: DateTime(2025),
      indexedAt: DateTime(2025),
      author: AuthorView(did: placeholderDid, handle: placeholderHandle),
      post: CommentRef(uri: 'at://did:plc:test/post/123', cid: 'post-cid'),
      stats: const CommentStats(replyCount: 2),
    );
  }

  CommentView liveComment() {
    return CommentView(
      uri: 'at://did:plc:author/social.coves.community.comment/live',
      cid: 'cid-live',
      record: const CommentRecord(content: 'A live comment'),
      createdAt: DateTime(2025),
      indexedAt: DateTime(2025),
      author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
      post: CommentRef(uri: 'at://did:plc:test/post/123', cid: 'post-cid'),
      stats: const CommentStats(upvotes: 5, downvotes: 1, score: 4),
    );
  }

  Widget createTestWidget(CommentView comment, {VoidCallback? onTap}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: mockAuthProvider),
        ChangeNotifierProvider<VoteProvider>.value(value: mockVoteProvider),
        ChangeNotifierProvider<BlockProvider>.value(value: blockProvider),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: CommentCard(comment: comment, sessionStamp: null, onTap: onTap),
        ),
      ),
    );
  }

  testWidgets('the placeholder names who removed the comment', (tester) async {
    final cases = <(String, CommentView, String)>[
      (
        'server admin removal',
        placeholder(
          deletionReason: 'moderator',
          moderation: removedIn(ModerationScopeKind.instance),
        ),
        '[Removed by server admin]',
      ),
      (
        'community moderator removal',
        placeholder(
          deletionReason: 'moderator',
          moderation: removedIn(ModerationScopeKind.community),
        ),
        '[Removed by community moderator]',
      ),
      (
        'moderator removal without moderation',
        placeholder(deletionReason: 'moderator'),
        '[Removed by moderator]',
      ),
      (
        'moderator removal with an unknown scope',
        placeholder(
          deletionReason: 'moderator',
          moderation: removedIn(ModerationScopeKind.unknown),
        ),
        '[Removed by moderator]',
      ),
      (
        'author deletion that an admin also removed',
        placeholder(
          deletionReason: 'author',
          moderation: removedIn(ModerationScopeKind.instance),
        ),
        '[Deleted by user]',
      ),
      (
        'author deletion',
        placeholder(deletionReason: 'author'),
        '[Deleted by user]',
      ),
      // An instance source wins wherever it sits in the list.
      (
        'moderator removal listing a community source before an instance one',
        placeholder(
          deletionReason: 'moderator',
          moderation: removedInAll([
            ModerationScopeKind.community,
            ModerationScopeKind.instance,
          ]),
        ),
        '[Removed by server admin]',
      ),
      // The removal state, not deletionReason, says a moderator removed it.
      (
        'no deletion reason with an admin removal',
        placeholder(
          deletionReason: null,
          moderation: removedIn(ModerationScopeKind.instance),
        ),
        '[Removed by server admin]',
      ),
      (
        'unknown deletion reason with an admin removal',
        placeholder(
          deletionReason: 'admin',
          moderation: removedIn(ModerationScopeKind.instance),
        ),
        '[Removed by server admin]',
      ),
      // Legacy rows carry neither a reason nor moderation.
      (
        'no deletion reason and no moderation',
        placeholder(deletionReason: null),
        '[Deleted by user]',
      ),
    ];

    for (final (description, comment, expectedCopy) in cases) {
      await tester.pumpWidget(createTestWidget(comment));

      expect(find.text(expectedCopy), findsOneWidget, reason: description);
    }
  });

  // Guard: the placeholder header must keep hiding the placeholder author
  // while its copy is rewritten.
  testWidgets('the placeholder never shows the placeholder author', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    for (final deletionReason in ['moderator', 'author']) {
      await tester.pumpWidget(
        createTestWidget(
          placeholder(
            deletionReason: deletionReason,
            moderation: removedIn(ModerationScopeKind.instance),
          ),
        ),
      );

      for (final identity in [placeholderHandle, placeholderDid]) {
        final reason = '$deletionReason placeholder shows $identity';
        expect(
          find.textContaining(identity, findRichText: true),
          findsNothing,
          reason: reason,
        );
        expect(
          find.bySemanticsLabel(RegExp(RegExp.escape(identity))),
          findsNothing,
          reason: reason,
        );
      }
    }

    semantics.dispose();
  });

  testWidgets('a placeholder ignores taps and has no votes; a live comment '
      'still opens reply on tap', (tester) async {
    // The card awaits a haptic before calling onTap; answer the platform
    // channel so that await completes under the test binding.
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

    final cases = <(String, CommentView, bool)>[
      // (description, comment, tap opens reply)
      ('live comment', liveComment(), true),
      (
        'admin-removed placeholder',
        placeholder(
          deletionReason: 'moderator',
          moderation: removedIn(ModerationScopeKind.instance),
        ),
        false,
      ),
      (
        'author-deleted placeholder',
        placeholder(deletionReason: 'author'),
        false,
      ),
    ];

    for (final (description, comment, opensReply) in cases) {
      var replyOpened = false;
      await tester.pumpWidget(
        createTestWidget(comment, onTap: () => replyOpened = true),
      );

      // Tap the card's own top-right padding, clear of the author link,
      // the body text and the vote controls.
      await tester.tapAt(
        tester.getTopRight(find.byType(CommentCard)) + const Offset(-4, 4),
      );
      await tester.pumpAndSettle();

      expect(replyOpened, opensReply, reason: description);
      expect(
        find.byType(AnimatedHeartIcon),
        opensReply ? findsOneWidget : findsNothing,
        reason: '$description vote control',
      );
    }
  });

  testWidgets('a placeholder is not announced as a button; a live comment '
      'with onTap is', (tester) async {
    final semantics = tester.ensureSemantics();

    final cases = <(String, CommentView, bool)>[
      // (description, comment, announced as a button)
      ('live comment', liveComment(), true),
      (
        'admin-removed placeholder',
        placeholder(
          deletionReason: 'moderator',
          moderation: removedIn(ModerationScopeKind.instance),
        ),
        false,
      ),
    ];

    for (final (description, comment, isButton) in cases) {
      await tester.pumpWidget(createTestWidget(comment, onTap: () {}));

      expect(
        tester.getSemantics(find.byType(CommentCard)),
        isSemantics(isButton: isButton),
        reason: description,
      );
    }

    semantics.dispose();
  });
}
