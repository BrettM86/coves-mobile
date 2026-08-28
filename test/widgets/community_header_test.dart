import 'package:coves_flutter/models/community.dart';
import 'package:coves_flutter/widgets/community_header.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/theme_pump.dart';

/// Pins the handle line of [CommunityHeader]: it renders the resolved
/// `!name@origin`, falls back to the raw handle, and is omitted entirely
/// (never an empty line) when there is nothing to show.
void main() {
  Future<void> pump(WidgetTester tester, CommunityView? community) =>
      pumpUnderAppTheme(tester, CommunityHeader(community: community));

  group('CommunityHeader handle line', () {
    testWidgets('renders !name@origin when only origin is served', (
      tester,
    ) async {
      await pump(
        tester,
        CommunityView(
          did: 'did:plc:c',
          name: 'comicstrips',
          origin: 'lemmy.world',
        ),
      );
      expect(find.text('!comicstrips@lemmy.world'), findsOneWidget);
    });

    testWidgets('origin wins over a bridged handle', (tester) async {
      await pump(
        tester,
        CommunityView(
          did: 'did:plc:c',
          name: 'comicstrips',
          origin: 'lemmy.world',
          handle: 'comicstrips.lemmy-world.tdpl.io',
        ),
      );
      expect(find.text('!comicstrips@lemmy.world'), findsOneWidget);
      expect(find.text('comicstrips.lemmy-world.tdpl.io'), findsNothing);
    });

    testWidgets('derives from a DNS handle when origin is absent', (
      tester,
    ) async {
      await pump(
        tester,
        CommunityView(
          did: 'did:plc:c',
          name: 'gaming',
          handle: 'c-gaming.coves.social',
        ),
      );
      expect(find.text('!gaming@coves.social'), findsOneWidget);
    });

    testWidgets('falls back to the raw handle when unrecognised', (
      tester,
    ) async {
      await pump(
        tester,
        CommunityView(
          did: 'did:plc:c',
          name: 'weird',
          handle: 'weird.example.org',
        ),
      );
      expect(find.text('weird.example.org'), findsOneWidget);
      expect(find.text(''), findsNothing);
    });

    testWidgets('renders no handle line for an empty handle', (tester) async {
      await pump(
        tester,
        CommunityView(did: 'did:plc:c', name: 'weird', handle: ''),
      );
      expect(find.text(''), findsNothing);
    });

    testWidgets('renders no handle line while loading', (tester) async {
      await pump(tester, null);
      expect(find.text('Loading...'), findsOneWidget);
      expect(find.text(''), findsNothing);
    });
  });
}
