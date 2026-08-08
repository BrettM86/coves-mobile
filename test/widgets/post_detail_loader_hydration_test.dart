// Characterization net for the single-post viewer-state hydration in
// PostDetailLoader (site 6 of the eight hydration sites).
//
// Two properties are pinned here, both through public surfaces only:
//
//  * the fresh viewer snapshot is applied when signed in and skipped when
//    signed out (positive-control pair on identical input), and
//  * the VoteProvider lookup itself happens INSIDE the auth gate. A
//    signed-out, VoteProvider-less tree must not blow up in the loader -
//    provider-less widget trees rely on that. Moving the lookup out of the
//    gate (e.g. resolving a hydrator unconditionally at the top of the
//    method) breaks the first assertion below, and the signed-in control
//    proves the assertion has teeth.

import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/post_get_result.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/home/post_detail_loader.dart';
import 'package:coves_flutter/screens/home/post_detail_screen.dart';
import 'package:coves_flutter/services/comment_service.dart';
import 'package:coves_flutter/services/comments_provider_cache.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/vote_service.dart';
import 'package:coves_flutter/widgets/loading_error_states.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _FakeAuthProvider extends AuthProvider {
  _FakeAuthProvider({required bool authenticated})
    : _isAuthenticated = authenticated;

  final bool _isAuthenticated;

  @override
  bool get isAuthenticated => _isAuthenticated;

  @override
  bool get isLoading => false;
}

void main() {
  const testUri = 'at://did:plc:test/social.coves.community.post/abc123';
  const coldVoteUri = 'at://did:plc:me/social.coves.feed.vote/cold1';

  PostView buildPost({ViewerState? viewer}) {
    return PostView(
      viewer: viewer,
      uri: testUri,
      cid: 'test-cid',
      rkey: 'abc123',
      author: AuthorView(did: 'did:plc:author', handle: 'test.user'),
      community: CommunityRef(
        did: 'did:plc:community',
        name: 'test-community',
      ),
      createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
      indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
      record: const PostRecord(content: 'Test body', title: 'Cold Loaded'),
      stats: PostStats(score: 42, upvotes: 50, downvotes: 8, commentCount: 5),
    );
  }

  VoteProvider buildVoteProvider(AuthProvider auth) {
    final provider = VoteProvider(
      voteService: VoteService(
        sessionGetter: () async => null,
        didGetter: () => null,
      ),
      authProvider: auth,
    );
    addTearDown(provider.dispose);
    return provider;
  }

  /// The full provider set PostDetailScreen needs to build.
  Future<void> pumpWithProviders(
    WidgetTester tester, {
    required AuthProvider auth,
    required VoteProvider votes,
  }) async {
    final apiService = CovesApiService(tokenGetter: () async => null);
    addTearDown(apiService.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<VoteProvider>.value(value: votes),
          Provider<CommentsProviderCache>.value(
            value: CommentsProviderCache(
              authProvider: auth,
              voteProvider: votes,
              commentService: CommentService(),
              apiService: apiService,
            ),
          ),
        ],
        child: MaterialApp(
          home: PostDetailLoader(
            postUri: testUri,
            fetchPost: (_) async => PostGetSuccess(
              buildPost(
                viewer: ViewerState(vote: 'up', voteUri: coldVoteUri),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('C10 applies the fresh post viewer snapshot when signed in', (
    tester,
  ) async {
    final auth = _FakeAuthProvider(authenticated: true);
    final votes = buildVoteProvider(auth);

    await pumpWithProviders(tester, auth: auth, votes: votes);

    expect(find.byType(PostDetailScreen), findsOneWidget);
    expect(votes.isLiked(testUri), true);
    expect(votes.getVoteState(testUri)?.uri, coldVoteUri);

    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.pumpAndSettle();
  });

  testWidgets('C10 applies nothing when signed out, on identical input', (
    tester,
  ) async {
    final auth = _FakeAuthProvider(authenticated: false);
    final votes = buildVoteProvider(auth);

    await pumpWithProviders(tester, auth: auth, votes: votes);

    expect(find.byType(PostDetailScreen), findsOneWidget);
    expect(votes.isLiked(testUri), false);
    expect(votes.getVoteState(testUri), isNull);

    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.pumpAndSettle();
  });

  group('C13 the VoteProvider lookup stays inside the auth gate', () {
    /// Pumps the loader with NO Provider<VoteProvider> in the tree.
    ///
    /// If the loader resolves the vote surface before checking auth, the
    /// resulting ProviderNotFoundException is swallowed by _fetch's broad
    /// catch and the loader lands in its terminal error state - which is
    /// exactly what the signed-in control below demonstrates.
    Future<void> pumpWithoutVoteProvider(
      WidgetTester tester, {
      required bool authenticated,
    }) async {
      final auth = _FakeAuthProvider(authenticated: authenticated);

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: auth,
          child: MaterialApp(
            home: PostDetailLoader(
              postUri: testUri,
              fetchPost: (_) async => PostGetSuccess(
                buildPost(
                  viewer: ViewerState(vote: 'up', voteUri: coldVoteUri),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('a signed-out provider-less tree gets past hydration', (
      tester,
    ) async {
      await pumpWithoutVoteProvider(tester, authenticated: false);

      // The loader itself never errored: it handed the post on. (What the
      // downstream screen then does with a provider-less tree is its own
      // business and is drained below.)
      expect(find.byType(FullScreenError), findsNothing);
      tester.takeException();
    });

    testWidgets('the same signed-in tree does error, proving the gate is '
        'what protects the signed-out case', (tester) async {
      await pumpWithoutVoteProvider(tester, authenticated: true);

      expect(find.byType(FullScreenError), findsOneWidget);
      tester.takeException();
    });
  });
}
