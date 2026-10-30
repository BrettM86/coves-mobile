import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/community.dart';
import 'package:coves_flutter/models/facet.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/home/create_post_screen.dart';
import 'package:coves_flutter/services/comments_provider_cache.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:coves_flutter/widgets/composer/facet_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/fake_providers.dart' show postCardProviders;
import '../../test_helpers/test_mocks.dart';

/// The body field's hint
const bodyHint = 'What are your thoughts?';

// Fake AuthProvider for testing
class FakeAuthProvider extends AuthProvider {
  bool _isAuthenticated = true;
  String? _did = 'did:plc:testuser';
  String? _handle = 'testuser.coves.social';

  @override
  bool get isAuthenticated => _isAuthenticated;

  @override
  String? get did => _did;

  @override
  String? get handle => _handle;

  void setAuthenticated({required bool value, String? did, String? handle}) {
    _isAuthenticated = value;
    _did = did;
    _handle = handle;
    notifyListeners();
  }

  @override
  Future<String?> getAccessToken() async {
    return _isAuthenticated ? 'mock_access_token' : null;
  }

  @override
  Future<bool> refreshToken() async {
    return _isAuthenticated;
  }

  @override
  Future<void> signOut() async {
    _isAuthenticated = false;
    _did = null;
    _handle = null;
    notifyListeners();
  }
}

/// The community picker lists one community, Test Cove
void stubOneCommunity(MockCovesApiService api) {
  when(
    api.listCommunities(
      limit: anyNamed('limit'),
      cursor: anyNamed('cursor'),
      sort: anyNamed('sort'),
      subscribed: anyNamed('subscribed'),
    ),
  ).thenAnswer(
    (_) async => CommunitiesResponse(
      communities: [
        CommunityView(
          did: 'did:plc:community',
          name: 'testcove',
          displayName: 'Test Cove',
        ),
      ],
    ),
  );
}

/// createPost succeeds, so the screen opens the optimistic post
void stubCreatePostSucceeds(MockCovesApiService api) {
  when(
    api.createPost(
      community: anyNamed('community'),
      title: anyNamed('title'),
      content: anyNamed('content'),
      facets: anyNamed('facets'),
      embed: anyNamed('embed'),
      langs: anyNamed('langs'),
      labels: anyNamed('labels'),
    ),
  ).thenAnswer(
    (_) async => const CreatePostResponse(
      uri: 'at://did:plc:testuser/social.coves.community.post/created',
      cid: 'created-cid',
    ),
  );
}

/// Opens the community picker and selects the single stubbed community,
/// which is the only way to make the form (and the Post button) valid.
Future<void> selectCommunity(WidgetTester tester) async {
  await tester.tap(find.text('Select a community'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Test Cove'));
  await tester.pumpAndSettle();
}

/// Pumps CreatePostScreen with the providers PostDetailScreen resolves,
/// with the mocked API last so CreatePostScreen submits through it
Future<void> pumpCreatePostWithPostDetailProviders(
  WidgetTester tester, {
  required AuthProvider auth,
  required MockCovesApiService api,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ...postCardProviders(auth: auth),
        Provider<CovesApiService>.value(value: api),
        Provider<CommentsProviderCache>(
          create: (context) => CommentsProviderCache(
            authProvider: auth,
            voteProvider: context.read<VoteProvider>(),
            commentService: MockCommentService(),
            apiService: api,
          ),
          dispose: (_, cache) => cache.dispose(),
        ),
      ],
      child: MaterialApp(theme: AppTheme.dark, home: const CreatePostScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

/// The body's editable text, found by the body's hint so the title and URL
/// fields never match
final Finder bodyEditable = find.descendant(
  of: find.widgetWithText(TextField, bodyHint),
  matching: find.byType(EditableText),
);

/// The body field, which must be the screen's only [FacetTextField]
FacetTextField bodyFacetField(WidgetTester tester) {
  expect(
    find.byType(FacetTextField),
    findsOneWidget,
    reason: 'the body field is a FacetTextField',
  );
  expect(
    find.descendant(
      of: find.byType(FacetTextField),
      matching: find.widgetWithText(TextField, bodyHint),
    ),
    findsOneWidget,
    reason: 'the FacetTextField is the body',
  );
  return tester.widget<FacetTextField>(find.byType(FacetTextField));
}

/// The body field's controller; the body must be a [FacetTextField]
FacetEditingController bodyController(WidgetTester tester) =>
    bodyFacetField(tester).controller;

/// The (content, facets) arguments of the single createPost call
(Object?, List<RichTextFacet>?) captureCreatePostContentAndFacets(
  MockCovesApiService api,
) {
  final captured = verify(
    api.createPost(
      community: anyNamed('community'),
      title: anyNamed('title'),
      content: captureAnyNamed('content'),
      facets: captureAnyNamed('facets'),
      embed: anyNamed('embed'),
      langs: anyNamed('langs'),
      labels: anyNamed('labels'),
    ),
  ).captured;
  expect(captured, hasLength(2), reason: 'createPost called once');
  return (captured[0], captured[1] as List<RichTextFacet>?);
}
