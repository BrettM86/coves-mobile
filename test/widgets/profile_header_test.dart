import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/widgets/profile_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  UserProfile buildProfile({String handle = 'someone.example.com'}) =>
      UserProfile(
        did: 'did:plc:abcdefghijklmnopqrstuvwx',
        handle: handle,
        bio: 'A bio that is long enough to wrap onto more than one line.',
      );

  /// Pumps a profile screen skeleton at [topInset] and returns the tester.
  Future<void> pumpAt(
    WidgetTester tester,
    double topInset, {
    String handle = 'someone.example.com',
  }) async {
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
                    flexibleSpace: ProfileHeader(
                      profile: buildProfile(handle: handle),
                    ),
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

  /// atProto handles are full domains of unbounded length, and the identity
  /// column beside the avatar is only ~236pt wide here. The handle shrinks
  /// to fit rather than ellipsizing the user's identity away.
  ///
  /// The test font renders every glyph a full em wide, so far fewer
  /// characters fit than with the app's real font — these fixtures are
  /// chosen for their behaviour under that font (fits outright / shrinks and
  /// fits / bottoms out at the floor), not for their literal length.
  group('ProfileHeader handle fitting', () {
    const fitsHandle = 'a.bsky.co';
    const shrinksHandle = 'alice.bsky.io';
    const overlongHandle = 'absurdly.long.custom.domain.example.coves.social';
    const allHandles = [fitsHandle, shrinksHandle, overlongHandle];

    double fontSizeOf(WidgetTester tester, String handle) {
      final text = tester.widget<Text>(find.text('@$handle'));
      return text.style!.fontSize!;
    }

    bool isTruncated(WidgetTester tester, String handle) {
      final paragraph =
          tester.renderObject<RenderParagraph>(find.text('@$handle'));
      return paragraph.didExceedMaxLines;
    }

    testWidgets('a handle that fits keeps the full 20pt type size', (
      tester,
    ) async {
      await pumpAt(tester, 44, handle: fitsHandle);
      expect(fontSizeOf(tester, fitsHandle), 20);
      expect(isTruncated(tester, fitsHandle), isFalse);
    });

    testWidgets('a longer handle shrinks instead of being cut off', (
      tester,
    ) async {
      await pumpAt(tester, 44, handle: shrinksHandle);
      final size = fontSizeOf(tester, shrinksHandle);
      expect(size, lessThan(20));
      expect(size, greaterThan(14));
      expect(
        isTruncated(tester, shrinksHandle),
        isFalse,
        reason: 'the whole handle should fit once shrunk',
      );
    });

    testWidgets('shrinking stops at the 14pt floor', (tester) async {
      await pumpAt(tester, 44, handle: overlongHandle);
      // Past the floor the handle ellipsizes rather than shrinking into
      // illegibility — it must never render below 14pt.
      expect(fontSizeOf(tester, overlongHandle), 14);
      expect(isTruncated(tester, overlongHandle), isTrue);
    });

    testWidgets('type size stays within bounds and never grows with length', (
      tester,
    ) async {
      var previous = double.infinity;
      for (final handle in allHandles) {
        await pumpAt(tester, 44, handle: handle);
        final size = fontSizeOf(tester, handle);
        expect(
          size,
          inInclusiveRange(14, 20),
          reason: 'out of bounds: $handle',
        );
        expect(
          size,
          lessThanOrEqualTo(previous),
          reason: '$handle should not render larger than a shorter handle',
        );
        previous = size;
      }
    });

    testWidgets('a handle is only ever truncated at the floor', (tester) async {
      for (final handle in allHandles) {
        await pumpAt(tester, 44, handle: handle);
        if (fontSizeOf(tester, handle) > 14) {
          expect(
            isTruncated(tester, handle),
            isFalse,
            reason: '$handle was cut off with room left to shrink',
          );
        }
      }
    });

    testWidgets('the handle never overflows its column', (tester) async {
      for (final handle in allHandles) {
        await pumpAt(tester, 44, handle: handle);
        final rect = tester.getRect(find.text('@$handle'));
        final screenWidth =
            tester.view.physicalSize.width / tester.view.devicePixelRatio;
        expect(
          rect.right,
          lessThanOrEqualTo(screenWidth),
          reason: '$handle spills past the screen edge',
        );
      }
    });

    testWidgets('a changed handle is re-fitted, not served from cache', (
      tester,
    ) async {
      // The fitted size is memoised across rebuilds so scrolling does not
      // re-measure. Swapping the profile in place must still invalidate it —
      // the same widget position keeps its State across pumps.
      await pumpAt(tester, 44, handle: overlongHandle);
      expect(fontSizeOf(tester, overlongHandle), 14);

      await pumpAt(tester, 44, handle: fitsHandle);
      expect(
        fontSizeOf(tester, fitsHandle),
        20,
        reason: 'stale fitted size survived a handle change',
      );
    });

    testWidgets('handle length does not change the header geometry', (
      tester,
    ) async {
      final heights = <double>[];
      for (final handle in allHandles) {
        await pumpAt(tester, 44, handle: handle);
        final context = tester.element(find.byType(ProfileHeader));
        heights.add(ProfileHeader.expandedHeightFor(context));
      }
      // Shrinking happens within the line box reserved at 20pt, so the
      // header's deterministic geometry is unaffected by handle length.
      expect(heights.toSet(), hasLength(1));
    });
  });
}
