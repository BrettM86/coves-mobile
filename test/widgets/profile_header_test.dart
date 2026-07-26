import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/widgets/profile_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Geometry regression tests for [ProfileHeader].
///
/// The header previously drifted across devices because its height was
/// hardcoded while its content started below a SafeArea whose top inset
/// varies per device. These tests pin the relationship between the
/// status-bar inset and where the banner, avatar, and identity block land,
/// at insets spanning a plain phone (0), a notch (44), and a Dynamic
/// Island (59).
void main() {
  const insets = <double>[0, 20, 44, 59];

  UserProfile buildProfile() => UserProfile(
        did: 'did:plc:abcdefghijklmnopqrstuvwx',
        handle: 'someone.example.com',
        bio: 'A bio that is long enough to wrap onto more than one line.',
      );

  /// Pumps a profile screen skeleton at [topInset] and returns the tester.
  Future<void> pumpAt(WidgetTester tester, double topInset) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(padding: EdgeInsets.only(top: topInset)),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: CustomScrollView(
                slivers: [
                  SliverAppBar(
                    pinned: true,
                    expandedHeight: ProfileHeader.expandedHeightFor(context),
                    flexibleSpace: ProfileHeader(profile: buildProfile()),
                  ),
                  SliverToBoxAdapter(
                    child: ProfileDetails(profile: buildProfile()),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 2000)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('ProfileHeader geometry', () {
    testWidgets(
      'expandedHeightFor excludes the status-bar inset so SliverAppBar '
      'does not count it twice',
      (tester) async {
        final heights = <double>[];
        for (final inset in insets) {
          await pumpAt(tester, inset);
          final context = tester.element(find.byType(ProfileHeader));
          heights.add(ProfileHeader.expandedHeightFor(context));
        }
        // The value handed to SliverAppBar must not vary with the inset —
        // SliverAppBar adds padding.top to it internally.
        expect(heights.toSet(), hasLength(1));
      },
    );

    testWidgets('maxExtentFor equals inset + expandedHeightFor', (
      tester,
    ) async {
      for (final inset in insets) {
        await pumpAt(tester, inset);
        final context = tester.element(find.byType(ProfileHeader));
        expect(
          ProfileHeader.maxExtentFor(context),
          ProfileHeader.expandedHeightFor(context) + inset,
          reason: 'maxExtent must mirror SliverAppBar for inset $inset',
        );
      }
    });

    testWidgets(
      'avatar sits at a constant offset below the collapsed app bar on '
      'every inset',
      (tester) async {
        final offsets = <double>[];
        for (final inset in insets) {
          await pumpAt(tester, inset);
          final context = tester.element(find.byType(ProfileHeader));
          final avatarTop = tester
              .getTopLeft(
                find.descendant(
                  of: find.byType(ProfileHeader),
                  matching: find.byType(ClipOval),
                ),
              )
              .dy;
          offsets.add(avatarTop - ProfileHeader.collapsedExtentFor(context));
        }
        // Same distance below the app bar regardless of device inset —
        // this is the cross-device consistency the header guarantees.
        expect(offsets.toSet(), hasLength(1));
      },
    );

    testWidgets(
      'avatar never rises above the collapsed app bar, so it cannot show '
      'through the frosted overlay',
      (tester) async {
        for (final inset in insets) {
          await pumpAt(tester, inset);
          final context = tester.element(find.byType(ProfileHeader));
          final avatarTop = tester
              .getTopLeft(
                find.descendant(
                  of: find.byType(ProfileHeader),
                  matching: find.byType(ClipOval),
                ),
              )
              .dy;
          expect(
            avatarTop,
            greaterThanOrEqualTo(ProfileHeader.collapsedExtentFor(context)),
            reason: 'avatar pokes into the collapsed bar at inset $inset',
          );
        }
      },
    );

    testWidgets('DID is rendered and stays inside the viewport width', (
      tester,
    ) async {
      for (final inset in insets) {
        await pumpAt(tester, inset);
        final did = find.textContaining('did:plc:');
        expect(did, findsOneWidget, reason: 'DID missing at inset $inset');
        final rect = tester.getRect(did);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(
          rect.right,
          lessThanOrEqualTo(tester.view.physicalSize.width /
              tester.view.devicePixelRatio),
        );
      }
    });
  });
}
