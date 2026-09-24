// A ProfileScreen owns its profile state, including the Comments tab.
//
// The tree provides only app-level dependencies (the same set main.dart
// registers), so the comment card's delete flow must reach the provider the
// screen itself created: the deleted comment disappears from that screen
// and the other comment stays.

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/screens/home/profile_screen.dart';
import 'package:coves_flutter/widgets/comment_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/pump_helpers.dart';
import '../test_helpers/test_mocks.dart';

const String myDid = 'did:plc:me';
const String myHandle = 'me.coves.test';
const String keptCommentText = 'Comment that stays';
const String deletedCommentText = 'Comment to delete';

CommentView _myComment(String rkey, String content) {
  return CommentView(
    uri: 'at://$myDid/social.coves.community.comment/$rkey',
    cid: 'cid-$rkey',
    record: CommentRecord(content: content),
    createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
    indexedAt: DateTime.parse('2025-01-01T12:00:00Z'),
    author: AuthorView(did: myDid, handle: myHandle),
    post: CommentRef(
      uri: 'at://did:plc:community/social.coves.community.post/parent',
      cid: 'cid-parent',
    ),
    stats: const CommentStats(score: 1, upvotes: 1),
  );
}

void main() {
  late FakeAuthProvider authProvider;
  late MockCovesApiService apiService;
  late MockCommentService commentService;

  final keptComment = _myComment('kept', keptCommentText);
  final deletedComment = _myComment('deleted', deletedCommentText);

  setUp(() {
    authProvider = FakeAuthProvider(
      signedInDid: myDid,
      signedInHandle: myHandle,
    );
    apiService = MockCovesApiService();
    commentService = MockCommentService();

    when(apiService.getProfile(actor: myDid))
        .thenAnswer((_) async => UserProfile(did: myDid, handle: myHandle));
    when(
      apiService.getAuthorPosts(
        actor: myDid,
        filter: anyNamed('filter'),
        community: anyNamed('community'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer((_) async => TimelineResponse(feed: []));
    when(
      apiService.getActorComments(
        actor: myDid,
        community: anyNamed('community'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).thenAnswer(
      (_) async =>
          ActorCommentsResponse(comments: [keptComment, deletedComment]),
    );
    when(commentService.deleteComment(uri: deletedComment.uri))
        .thenAnswer((_) async {});
  });

  tearDown(() {
    authProvider.dispose();
  });

  testWidgets('deleting a comment from the Comments tab removes it from '
      'that profile screen', (tester) async {
    // Phone layout
    tester.view.physicalSize = const Size(540, 960);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // The delete flow awaits HapticFeedback; without a handler the
    // platform channel call never completes in tests.
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

    // App-level dependencies only: the screen owns its profile state.
    await tester.pumpWidget(
      MultiProvider(
        providers: profileScreenProviders(
          auth: authProvider,
          apiService: apiService,
          commentService: commentService,
        ),
        child: MaterialApp(theme: AppTheme.dark, home: const ProfileScreen()),
      ),
    );
    await pumpFrames(tester);

    expect(find.text('@$myHandle'), findsWidgets);

    await tester.tap(find.text('Comments'));
    await pumpFrames(tester);

    verify(
      apiService.getActorComments(
        actor: myDid,
        community: anyNamed('community'),
        limit: anyNamed('limit'),
        cursor: anyNamed('cursor'),
      ),
    ).called(1);
    expect(find.text(keptCommentText), findsOneWidget);
    expect(find.text(deletedCommentText), findsOneWidget);

    // Open the actions menu on the comment's card and delete it
    final deletedCard = find.ancestor(
      of: find.text(deletedCommentText),
      matching: find.byType(CommentCard),
    );
    await tester.tap(
      find.descendant(of: deletedCard, matching: find.byIcon(Icons.more_horiz)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete comment'));
    await tester.pumpAndSettle();

    // Confirm in the dialog
    expect(find.text('Delete Comment'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    // Dialog dismissed after confirming
    expect(find.text('Delete Comment'), findsNothing);

    verify(commentService.deleteComment(uri: deletedComment.uri)).called(1);
    expect(find.text(deletedCommentText), findsNothing);
    expect(find.text(keptCommentText), findsOneWidget);
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
