import 'package:coves_flutter/models/community.dart';
import 'package:coves_flutter/models/moderation_action.dart';
import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/providers/viewer_authority_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../test_helpers/fake_providers.dart';
import '../../test_helpers/modlog_fixtures.dart';
import '../../test_helpers/test_mocks.dart';

void main() {
  testWidgets('Modlog redesign A a public removal row reads as a sentence with '
      'its snapshot title and community under a Today header', (tester) async {
    final api = MockCovesApiService();
    final now = DateTime(2026, 10, 15, 12);
    when(
      api.listModerationActions(
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
        action: anyNamed('action'),
        community: anyNamed('community'),
        subject: anyNamed('subject'),
      ),
    ).thenAnswer(
      (_) async => ModerationActionPage(
        actions: [
          action(
            'did:web:coves.social',
            'steam-keys',
            actorDid: 'did:plc:nova',
            createdAt: now.subtract(const Duration(hours: 1)),
            subject: const ModerationSubjectRef(
              uri: 'at://did:plc:author/social.coves.community.post/p1',
              cid: 'bafy-post',
              communityDid: 'did:plc:gaming',
            ),
            contentSnapshot: const ModerationContentSnapshot(
              title: 'Free Steam keys',
              capturedCid: 'bafy-post',
            ),
          ),
        ],
      ),
    );
    when(api.getProfile(actor: 'did:plc:nova')).thenAnswer(
      (_) async =>
          UserProfile(did: 'did:plc:nova', handle: 'nova.coves.social'),
    );
    when(api.getCommunity(community: 'did:plc:gaming')).thenAnswer(
      (_) async => CommunityView(
        did: 'did:plc:gaming',
        name: 'gaming',
        origin: 'coves.social',
      ),
    );
    final auth = FakeAuthProvider();
    final authority = ViewerAuthorityProvider(
      apiService: api,
      authProvider: auth,
    );

    await pumpModlog(
      tester,
      api: api,
      auth: auth,
      authority: authority,
      clock: () => now,
    );

    final row = tile('did:web:coves.social', 'steam-keys');
    expect(row, findsOneWidget);
    for (final text in [
      '@nova.coves.social removed a post',
      'Free Steam keys',
      '!gaming@coves.social',
    ]) {
      expect(
        find.descendant(of: row, matching: renderedText(text)),
        findsOneWidget,
        reason: text,
      );
    }
    final header = renderedText('Today');
    expect(header, findsOneWidget);
    expect(
      tester.getBottomLeft(header).dy,
      lessThanOrEqualTo(tester.getTopLeft(row).dy),
    );
  });
}
