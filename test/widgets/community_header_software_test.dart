import 'package:coves_flutter/models/community.dart';
import 'package:coves_flutter/providers/display_preferences_provider.dart';
import 'package:coves_flutter/widgets/community_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../test_helpers/mock_url_launcher_platform.dart';
import '../test_helpers/theme_pump.dart';

/// The community header's origin software: the logo after the handle and
/// the "View on `host`" button, both following the Show software logos
/// setting (the button keeps its text when logos are off).
void main() {
  late MockUrlLauncherPlatform launcher;

  setUp(() {
    launcher = MockUrlLauncherPlatform();
    UrlLauncherPlatform.instance = launcher;
  });

  CommunityView bridged({
    String name = 'selfhosted',
    String software = 'lemmy',
    String? originUrl = 'https://lemmy.world/c/selfhosted',
  }) => CommunityView(
    did: 'did:plc:c',
    name: name,
    origin: 'lemmy.world',
    originSoftware: software,
    originUrl: originUrl,
    subscriberCount: 1200,
  );

  Future<DisplayPreferencesProvider> pump(
    WidgetTester tester,
    CommunityView community, {
    bool showSoftwareLogos = true,
  }) async {
    SharedPreferences.setMockInitialValues({
      DisplayPreferencesProvider.showSoftwareLogosKey: showSoftwareLogos,
    });
    final display = DisplayPreferencesProvider();
    await display.initialize();
    await pumpUnderAppTheme(
      tester,
      ChangeNotifierProvider<DisplayPreferencesProvider>.value(
        value: display,
        // The header fills the 220-tall expanded app bar on the real screen.
        child: SizedBox(
          height: 220,
          child: CommunityHeader(community: community),
        ),
      ),
    );
    return display;
  }

  Finder viewOnButton(String host) => find.ancestor(
    of: find.text('View on $host'),
    matching: find.byType(InkWell),
  );

  group('handle logo', () {
    testWidgets('a Lemmy community shows the Lemmy logo after its handle', (
      tester,
    ) async {
      await pump(tester, bridged(originUrl: null));

      expect(find.text('!selfhosted@lemmy.world'), findsOneWidget);
      expect(find.bySemanticsLabel('Lemmy'), findsOneWidget);
      final handleRight = tester
          .getTopRight(find.text('!selfhosted@lemmy.world'))
          .dx;
      expect(
        tester.getTopLeft(find.bySemanticsLabel('Lemmy')).dx,
        greaterThanOrEqualTo(handleRight),
      );
      expect(
        tester.getSize(find.bySemanticsLabel('Lemmy')),
        const Size(19, 19),
      );
    });

    testWidgets('a PieFed community shows the PieFed logo', (tester) async {
      await pump(tester, bridged(software: 'piefed', originUrl: null));
      expect(find.bySemanticsLabel('PieFed'), findsOneWidget);
    });

    testWidgets('a native community shows no logo and no button', (
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
      expect(find.bySemanticsLabel('Lemmy'), findsNothing);
      expect(find.bySemanticsLabel('PieFed'), findsNothing);
      expect(find.textContaining('View on'), findsNothing);
    });

    testWidgets('a long handle ellipsizes and keeps the logo on screen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const name = 'averyveryverylongcommunitynamethatcannotfitonscreen';

      await pump(tester, bridged(name: name, originUrl: null));

      final handle = tester.renderObject<RenderParagraph>(
        find.text('!$name@lemmy.world'),
      );
      expect(handle.didExceedMaxLines, isTrue);
      final logo = tester.getRect(find.bySemanticsLabel('Lemmy'));
      expect(logo.right, lessThanOrEqualTo(360));
      expect(tester.takeException(), isNull);
    });

    // A handle that fits is never cut short, with or without a logo.
    for (final (label, community, handleText) in [
      (
        'native',
        CommunityView(
          did: 'did:plc:c',
          name: 'mediumnative',
          handle: 'c-mediumnative.coves.social',
        ),
        '!mediumnative@coves.social',
      ),
      (
        'bridged',
        bridged(name: 'mediumbridged', originUrl: null),
        '!mediumbridged@lemmy.world',
      ),
    ]) {
      testWidgets('a $label handle that fits is shown in full', (tester) async {
        tester.view.physicalSize = const Size(800, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await pump(tester, community);

        final handle = tester.renderObject<RenderParagraph>(
          find.text(handleText),
        );
        expect(handle.didExceedMaxLines, isFalse);
      });
    }

    testWidgets('turning logos off hides the handle logo', (tester) async {
      await pump(tester, bridged(originUrl: null), showSoftwareLogos: false);
      expect(find.text('!selfhosted@lemmy.world'), findsOneWidget);
      expect(find.bySemanticsLabel('Lemmy'), findsNothing);
    });
  });

  group('View on button', () {
    testWidgets('names the originUrl host and carries the logo', (
      tester,
    ) async {
      await pump(tester, bridged());

      expect(find.text('View on lemmy.world'), findsOneWidget);
      expect(
        find.descendant(
          of: viewOnButton('lemmy.world'),
          matching: find.bySemanticsLabel('Lemmy'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the host comes from originUrl, not origin', (tester) async {
      await pump(
        tester,
        bridged(
          software: 'piefed',
          originUrl: 'https://piefed.social/c/selfhosted',
        ),
      );
      expect(find.text('View on piefed.social'), findsOneWidget);
    });

    testWidgets('opens originUrl in the external browser', (tester) async {
      await pump(tester, bridged());

      await tester.tap(find.text('View on lemmy.world'));
      await tester.pumpAndSettle();

      expect(launcher.launchedUrls, ['https://lemmy.world/c/selfhosted']);
      expect(launcher.lastLaunchMode, PreferredLaunchMode.externalApplication);
    });

    testWidgets('a long host fits a phone-width header beside the counts', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const host = 'a-very-long-lemmy-instance-hostname.example.org';

      await pump(tester, bridged(originUrl: 'https://$host/c/selfhosted'));

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Subscribers', findRichText: true),
        findsOneWidget,
      );
      final button = tester.getRect(viewOnButton(host));
      expect(button.right, lessThanOrEqualTo(360));
      expect(
        tester.getRect(find.bySemanticsLabel('Lemmy').last).right,
        lessThanOrEqualTo(360),
      );
    });

    testWidgets('keeps both counts on one line ahead of the button', (
      tester,
    ) async {
      // The test font draws every glyph a full em wide, so 600 here is a
      // phone-width row in real text.
      tester.view.physicalSize = const Size(600, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pump(
        tester,
        CommunityView(
          did: 'did:plc:c',
          name: 'selfhosted',
          origin: 'lemmy.world',
          originSoftware: 'lemmy',
          originUrl: 'https://lemmy.world/c/selfhosted',
          description:
              'A place to share alternatives to popular online services '
              'that can be self-hosted without giving up privacy.',
          subscriberCount: 12345,
          memberCount: 678,
        ),
      );

      final subscribers = tester.getRect(
        find.textContaining('Subscribers', findRichText: true),
      );
      final members = tester.getRect(
        find.textContaining('Members', findRichText: true),
      );
      expect(members.top, subscribers.top);
      expect(
        tester.getRect(viewOnButton('lemmy.world')).right,
        lessThanOrEqualTo(600),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('is absent without an originUrl', (tester) async {
      await pump(tester, bridged(originUrl: null));
      expect(find.textContaining('View on'), findsNothing);
    });

    for (final url in [
      'javascript:alert(1)',
      'ftp://lemmy.world/c/selfhosted',
      'file:///etc/hosts',
    ]) {
      testWidgets('is absent for the non-http(s) originUrl $url', (
        tester,
      ) async {
        await pump(tester, bridged(originUrl: url));
        expect(find.textContaining('View on'), findsNothing);
      });
    }

    testWidgets('is absent when originUrl has no host', (tester) async {
      await pump(tester, bridged(originUrl: 'not a url'));
      expect(find.textContaining('View on'), findsNothing);
    });

    testWidgets('stays as plain text when logos are off', (tester) async {
      await pump(tester, bridged(), showSoftwareLogos: false);

      expect(find.text('View on lemmy.world'), findsOneWidget);
      expect(find.bySemanticsLabel('Lemmy'), findsNothing);
    });

    testWidgets('follows a setting change while shown', (tester) async {
      final display = await pump(tester, bridged());
      expect(find.bySemanticsLabel('Lemmy'), findsNWidgets(2));

      await display.setShowSoftwareLogos(false);
      await tester.pump();

      expect(find.bySemanticsLabel('Lemmy'), findsNothing);
      expect(find.text('View on lemmy.world'), findsOneWidget);
    });
  });
}
