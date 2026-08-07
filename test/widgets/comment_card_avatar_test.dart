import 'package:cached_network_image/cached_network_image.dart';
import 'package:coves_flutter/constants/app_colors.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/utils/display_utils.dart';
import 'package:coves_flutter/widgets/comment_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/test_mocks.dart';

/// RED: CommentCard's hand-rolled author avatar.
///
/// The avatar image is built at 14x14 while its own fallback is 24x24, so the
/// header row reflows the moment an avatar fails to load. The fallback also
/// takes its initial from `handle` even when a displayName exists, and paints
/// AppColors.primary instead of the shared hash color.
void main() {
  // Hashes onto a non-coral palette slot, so "shared hash color" and the
  // legacy AppColors.primary are distinguishable.
  const authorHandle = 'commenter.test';


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
    when(mockVoteProvider.getAdjustedScore(any, any)).thenAnswer(
      (invocation) => invocation.positionalArguments[1] as int,
    );
  });

  CommentView createComment({
    required String handle,
    String? displayName,
    String? avatar,
  }) {
    return CommentView(
      uri: 'at://did:plc:test/comment/1',
      cid: 'cid-1',
      record: const CommentRecord(content: 'Test comment'),
      createdAt: DateTime(2025),
      indexedAt: DateTime(2025),
      author: AuthorView(
        did: 'did:plc:author',
        handle: handle,
        displayName: displayName,
        avatar: avatar,
      ),
      post: CommentRef(uri: 'at://did:plc:test/post/123', cid: 'post-cid'),
      stats: const CommentStats(upvotes: 5, downvotes: 1, score: 4),
    );
  }

  Widget createTestWidget(CommentView comment) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: mockAuthProvider),
        ChangeNotifierProvider<VoteProvider>.value(value: mockVoteProvider),
        ChangeNotifierProvider<BlockProvider>.value(value: blockProvider),
      ],
      child: MaterialApp(
        home: Scaffold(body: CommentCard(comment: comment)),
      ),
    );
  }

  Size boxSizeAround(WidgetTester tester, Finder inner) => tester.getSize(
    find.ancestor(of: inner, matching: find.byType(DecoratedBox)).first,
  );

  Color paintedColorBehind(WidgetTester tester, Finder inner) {
    final decorated = tester.widget<DecoratedBox>(
      find.ancestor(of: inner, matching: find.byType(DecoratedBox)).first,
    );
    return (decorated.decoration as BoxDecoration).color!;
  }

  group('CommentCard author avatar', () {
    testWidgets('fallback occupies a 24x24 box', (tester) async {
      // Characterization: this is the size the image path must match.
      await tester.pumpWidget(
        createTestWidget(createComment(handle: authorHandle)),
      );

      expect(boxSizeAround(tester, find.text('C')), const Size(24, 24));
    });

    testWidgets('image is requested at the same 24x24 box as the fallback', (
      tester,
    ) async {
      // Asserting on the requested width/height rather than the rendered size
      // is deliberate: under flutter_test the network image never resolves,
      // so the *rendered* widget is the placeholder (the 24x24 fallback) in
      // both cases and the mismatch would be invisible. The declared size is
      // what reflows the row on a real device once the image arrives.
      await tester.pumpWidget(
        createTestWidget(
          createComment(
            handle: authorHandle,
            avatar: 'https://example.com/avatar.jpg',
          ),
        ),
      );

      final image = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      expect(image.width, 24, reason: 'avatar image must not shrink to 14');
      expect(image.height, 24, reason: 'avatar image must not shrink to 14');
    });

    testWidgets('fallback initial prefers displayName over handle', (
      tester,
    ) async {
      await tester.pumpWidget(
        createTestWidget(
          createComment(handle: authorHandle, displayName: 'Ada Lovelace'),
        ),
      );

      expect(find.text('A'), findsOneWidget);
      expect(find.text('C'), findsNothing);
    });

    testWidgets('fallback uses the shared hash color, not AppColors.primary', (
      tester,
    ) async {
      expect(
        DisplayUtils.getFallbackColor(authorHandle).toARGB32(),
        isNot(AppColors.primary.toARGB32()),
        reason: 'fixture handle must hash away from the legacy color',
      );

      await tester.pumpWidget(
        createTestWidget(createComment(handle: authorHandle)),
      );

      expect(
        paintedColorBehind(tester, find.text('C')).toARGB32(),
        DisplayUtils.getFallbackColor(authorHandle).toARGB32(),
      );
    });
  });
}
