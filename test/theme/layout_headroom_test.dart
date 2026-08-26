import 'dart:io';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/constants/app_typography.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/community.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/widgets/comment_card.dart';
import 'package:coves_flutter/widgets/community_list_tile.dart';
import 'package:coves_flutter/widgets/post_action_bar.dart';
import 'package:coves_flutter/widgets/post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_providers.dart';

/// Widths swept, widest first. Real phones start around 320dp logical
/// (iPhone SE) and the narrowest thing anyone ships to is about 240dp (a
/// small Android in display-size-large accessibility mode). 440 is above any
/// phone, so a subject that breaks there breaks everywhere.
const _widths = [
  440,
  420,
  400,
  380,
  360,
  340,
  320,
  300,
  280,
  260,
  240,
  220,
  200,
];

/// The narrowest width the app claims to support.
const _narrowestSupported = 320;

/// Content picked to be the worst case a real account can produce, not the
/// worst case imaginable: a long real-looking display name, a full handle, a
/// hyphenated community name, six-figure counts and a timestamp old enough
/// to take the formatters' longest branch.
const _displayName = 'Bartholomew Featherstonehaugh-Wellington III';
const _handle = 'bartholomew.featherstonehaugh.example.social';
const _communityName = 'photography-and-street-art-enthusiasts';
const _title =
    'A reasonably long post title of the kind people actually write when '
    'they are annoyed about something';

/// A short, boring alternative, to tell "this widget is tight" apart from
/// "this widget cannot survive a real name".
const _shortDisplayName = 'Bob';
const _shortHandle = 'bob.test';

DateTime get _now => DateTime(2026, 8, 7, 12);
DateTime get _longAgo => DateTime(2025, 9, 7, 12);

FeedViewPost _post({bool long = true}) => FeedViewPost(
  post: PostView(
    uri: 'at://did:plc:author/app.coves.post/123',
    cid: 'cid123',
    rkey: '123',
    author: AuthorView(
      did: 'did:plc:author',
      handle: long ? _handle : _shortHandle,
      displayName: long ? _displayName : _shortDisplayName,
    ),
    community: CommunityRef(
      did: 'did:plc:community',
      name: long ? _communityName : 'photos',
    ),
    createdAt: _longAgo,
    indexedAt: _longAgo,
    record: PostRecord(content: 'Body text.', title: long ? _title : 'A title'),
    stats:
        long
            ? PostStats(
              upvotes: 123456,
              downvotes: 7890,
              score: 115566,
              commentCount: 98765,
            )
            : PostStats(upvotes: 3, downvotes: 0, score: 3, commentCount: 1),
  ),
);

CommentView _comment({bool long = true}) => CommentView(
  uri: 'at://did:plc:author/app.coves.comment/1',
  cid: 'cid-1',
  record: const CommentRecord(
    content: 'A comment body of the length people actually write.',
  ),
  createdAt: _longAgo,
  indexedAt: _longAgo,
  author: AuthorView(
    did: 'did:plc:author',
    handle: long ? _handle : _shortHandle,
    displayName: long ? _displayName : _shortDisplayName,
  ),
  post: CommentRef(uri: 'at://did:plc:author/post/123', cid: 'post-cid'),
  stats:
      long
          ? const CommentStats(upvotes: 123456, downvotes: 7890, score: 115566)
          : const CommentStats(upvotes: 3, score: 3),
);

CommunityView _community({bool long = true}) => CommunityView(
  did: 'did:plc:community',
  name: long ? _communityName : 'photos',
  displayName: long ? 'Photography and Street Art Enthusiasts' : 'Photos',
  description: 'A community for people who photograph walls.',
  memberCount: long ? 123456 : 12,
  subscriberCount: long ? 98765 : 3,
  postCount: long ? 45678 : 7,
);

/// One subject's result under one theme.
typedef Headroom = ({int? cleanTo, int? breaksAt, String? worst});

/// Drains pending exceptions, returning the first overflow among them.
///
/// Overflow is detected as a thrown [FlutterError], and that is the same
/// event as the yellow stripe: every render object that paints the stripe
/// routes through `paintOverflowIndicator`, which calls
/// `FlutterError.reportError` on the frame it paints. So "no exception" and
/// "no stripe" are the same claim.
///
/// What this canNOT see: text that silently clips or ellipsizes because it
/// carries `maxLines` with `TextOverflow.ellipsis`. That paints no stripe and
/// throws nothing, so it is invisible here - yet a wider font eating a name
/// down to "Bartholomew Feath..." is still a regression. Nothing in this file
/// covers that; it would need a golden.
///
/// Anything that is not an overflow fails the test rather than being read as
/// a clean render.
String? _overflowIn(WidgetTester tester) {
  String? first;
  for (var error = tester.takeException(); error != null;) {
    final text = error.toString();
    if (text.toLowerCase().contains('overflow')) {
      first ??= text.split('\n').first;
    } else {
      fail('unexpected exception while measuring: $error');
    }
    error = tester.takeException();
  }
  return first;
}

/// Sweeps [build] from the widest width down, stopping at the first overflow.
Future<Headroom> _sweep(WidgetTester tester, Widget Function() build) async {
  addTearDown(tester.view.reset);
  tester.view.devicePixelRatio = 3;

  int? cleanTo;
  for (final width in _widths) {
    tester.view.physicalSize = Size(width * 3, 900 * 3);
    // Clear the tree so each width is a fresh build, not a relayout.
    await tester.pumpWidget(const SizedBox.shrink());
    _overflowIn(tester);

    await tester.pumpWidget(build());
    await tester.pump();

    final overflow = _overflowIn(tester);
    if (overflow != null) {
      return (cleanTo: cleanTo, breaksAt: width, worst: overflow);
    }
    cleanTo = width;
  }
  return (cleanTo: cleanTo, breaksAt: null, worst: null);
}

Widget _wrap(Widget child, ThemeData theme) =>
    MaterialApp(theme: theme, home: Scaffold(body: child));

Widget _wrapRouted(Widget child, ThemeData theme) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => Scaffold(body: child)),
      GoRoute(
        path: '/post/:uri',
        builder: (context, state) => const Scaffold(body: Text('detail')),
      ),
      GoRoute(
        path: '/profile/:actor',
        builder: (context, state) => const Scaffold(body: Text('profile')),
      ),
      GoRoute(
        path: '/community/:identifier',
        builder: (context, state) => const Scaffold(body: Text('community')),
      ),
    ],
  );
  addTearDown(router.dispose);
  return MaterialApp.router(theme: theme, routerConfig: router);
}

/// Registers a bundled font with the test engine.
///
/// Without this the whole exercise is theatre. `flutter test` does not load
/// an app's font assets: every family resolves to the built-in test font,
/// whose glyphs are uniform boxes one em wide. That makes a 44-character
/// name about twice as wide as real Inter renders it, so an unloaded sweep
/// measures the test font's metrics and reports overflows that cannot happen
/// on a device. Loading the real file is what makes these numbers mean
/// anything.
Future<void> _loadFont(String family, String asset) async {
  final loader = FontLoader(family)..addFont(rootBundle.load(asset));
  await loader.load();
}

/// The family the sweep measures in place of the device's own font.
///
/// The app bundles no body font - it renders in whatever the platform
/// provides - so there is no "app font" for a host test to load. Roboto is
/// the stand-in: it is stock Android's face and the closest thing to a
/// neutral baseline. Treat the numbers as indicative, not exact, because the
/// real face varies by platform and OEM (Samsung ships One UI Sans, iOS
/// renders SF Pro) and each has its own metrics.
const _platformProxyFamily = 'RobotoPlatformProxy';

/// Loads a font from a file on disk rather than the asset bundle.
///
/// The proxy font is deliberately NOT declared in `pubspec.yaml`: it exists
/// to measure with and must not ship in the APK. `rootBundle` can only see
/// declared assets, so it is read from `test/fixtures/` directly.
Future<void> _loadFontFromFile(String family, String path) async {
  final bytes = await File(path).readAsBytes();
  final loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

/// The app's theme, forced into the proxy family so text has real metrics.
///
/// `AppTheme.dark` sets no family (that is the design), which under
/// `flutter test` means the built-in test font - uniform one-em boxes, about
/// twice real width. Pinning the proxy here is what makes the sweep measure
/// something a device would actually render.
ThemeData get _proxyTheme {
  final base = AppTheme.dark;
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: _platformProxyFamily),
  );
}

/// A theme whose family is deliberately NOT loaded, so text falls back to the
/// test font. This is what the rest of the suite measures - every other
/// widget test pumps a bare `MaterialApp` and sees these metrics, not the
/// ones production renders. The gap between the two columns IS the fidelity
/// gap this file exists to quantify.
ThemeData get _testFontTheme => ThemeData.light();

void main() {
  // Characterization, and a baseline rather than a bound. Most of this
  // suite's widget tests pump a bare MaterialApp - Material's default light
  // theme, in Roboto - while production renders Inter, a wider face. A dense
  // row that is tight-but-clean under Roboto can overflow under Inter, and
  // nothing else here would notice.
  //
  // Each subject records the narrowest width it survives, under both fonts.
  // The point is the NUMBER: a bare "clean at 360dp" says nothing about how
  // close to the edge it was, and headroom is exactly what a font swap
  // spends. Overflow is a tripwire, not a gradient - "no stripe today" is
  // not evidence of room to spare.
  Future<void> report(
    WidgetTester tester,
    String subject,
    Widget Function(ThemeData) build,
  ) async {
    final proxy = await _sweep(tester, () => build(_proxyTheme));
    final testFont = await _sweep(tester, () => build(_testFontTheme));

    final summary =
        'HEADROOM $subject | platform-proxy: clean to ${proxy.cleanTo}dp, '
        'breaks at ${proxy.breaksAt}dp | '
        'test-font: clean to ${testFont.cleanTo}dp, '
        'breaks at ${testFont.breaksAt}dp | ${proxy.worst ?? ''}';
    printOnFailure(summary);
    debugPrint(summary);

    expect(
      proxy.cleanTo,
      isNotNull,
      reason: '$subject overflows at every width tried: ${proxy.worst}',
    );
    expect(
      proxy.cleanTo,
      lessThanOrEqualTo(_narrowestSupported),
      reason:
          '$subject overflows at ${proxy.breaksAt}dp, above the narrowest '
          'supported width of ${_narrowestSupported}dp: ${proxy.worst}',
    );
  }

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFontFromFile(
      _platformProxyFamily,
      'test/fixtures/Roboto-Variable.ttf',
    );
    await _loadFont(
      AppTypography.displayFamily,
      'assets/fonts/Shrikhand-Regular.ttf',
    );
  });

  group('layout headroom under the real theme', () {
    testWidgets('PostCard', (tester) async {
      await report(
        tester,
        'PostCard',
        (theme) => MultiProvider(
          providers: postCardProviders(auth: FakeAuthProvider()),
          child: _wrapRouted(PostCard(post: _post()), theme),
        ),
      );
    });

    testWidgets('CommentCard', (tester) async {
      await report(
        tester,
        'CommentCard',
        (theme) => MultiProvider(
          providers: postCardProviders(auth: FakeAuthProvider()),
          child: _wrap(
            CommentCard(comment: _comment(), currentTime: _now),
            theme,
          ),
        ),
      );
    });

    testWidgets('CommentCard at depth 5', (tester) async {
      // Depth eats horizontal space, so a deep reply is the real worst case
      // rather than a top-level comment.
      await report(
        tester,
        'CommentCard(depth: 5)',
        (theme) => MultiProvider(
          providers: postCardProviders(auth: FakeAuthProvider()),
          child: _wrap(
            CommentCard(comment: _comment(), depth: 5, currentTime: _now),
            theme,
          ),
        ),
      );
    });

    testWidgets('PostActionBar', (tester) async {
      await report(
        tester,
        'PostActionBar',
        (theme) => _wrap(PostActionBar(post: _post()), theme),
      );
    });

    testWidgets('CommunityListTile', (tester) async {
      await report(
        tester,
        'CommunityListTile',
        (theme) => _wrap(CommunityListTile(community: _community()), theme),
      );
    });

    // The same subjects with short, boring content. Any gap between these
    // numbers and the ones above is the cost of a real name rather than the
    // cost of the layout.
    testWidgets('PostCard with short content', (tester) async {
      await report(
        tester,
        'PostCard(short)',
        (theme) => MultiProvider(
          providers: postCardProviders(auth: FakeAuthProvider()),
          child: _wrapRouted(PostCard(post: _post(long: false)), theme),
        ),
      );
    });

    testWidgets('CommentCard with short content', (tester) async {
      await report(
        tester,
        'CommentCard(short)',
        (theme) => MultiProvider(
          providers: postCardProviders(auth: FakeAuthProvider()),
          child: _wrap(
            CommentCard(comment: _comment(long: false), currentTime: _now),
            theme,
          ),
        ),
      );
    });
  });
}
