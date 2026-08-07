// Behavioural spec for the Streamable launch flow that the feed card and the
// detail view are about to share (see the media extraction brief, bugs 1-3).
//
// These tests run against the CURRENT widgets — `PostCard` and
// `DetailedPostView` — deliberately, not against the not-yet-extracted shared
// widget: they pin behaviour the user can observe, so they must keep passing
// once `StreamableVideoEmbed` takes over both call sites.
//
// Red-phase expectations (see the report):
//   M1  feed treats `embedType` case-insensitively            — currently FAILS
//   M2  feed's failure snackbar reads 'Could not load video'  — currently FAILS
//   M3b detail's play button reports `enabled: false` while loading — FAILS
// The remaining cases characterise behaviour that already holds and must
// survive the extraction.

import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/services/streamable_service.dart';
import 'package:coves_flutter/widgets/detailed_post_view.dart';
import 'package:coves_flutter/widgets/fullscreen_video_player.dart';
import 'package:coves_flutter/widgets/post_card.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/fake_providers.dart';

const _streamableUri = 'https://streamable.com/abc123';
const _streamableApi = 'https://api.streamable.com/videos/abc123';
const _thumb = 'https://cdn.test/video-thumb.jpg';
const _resolvedVideoUrl = 'https://cdn.test/resolved.mp4';

/// The one snackbar the app shows when a Streamable URL cannot be resolved.
/// The two call sites disagree today ('Failed to load video' on the feed);
/// the shared widget standardises on this string.
const _failureCopy = 'Could not load video';

/// Records routes pushed onto the navigator so a `Navigator.push` can be
/// inspected *without* mounting the pushed page: mounting
/// [FullscreenVideoPlayer] hits the video_player platform channel, which
/// throws UnimplementedError under flutter_test.
class _RecordingObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    super.didPush(route, previousRoute);
  }

  /// Routes pushed by a user interaction. MaterialApp's own initial route is
  /// a `MaterialPageRoute<dynamic>` and Dart treats `dynamic` and `void` as
  /// mutual subtypes, so callers reset() after the initial pump.
  List<MaterialPageRoute<void>> get pushedPages =>
      pushed.whereType<MaterialPageRoute<void>>().toList();

  void reset() => pushed.clear();
}

/// A Streamable service whose one request resolves after [delay].
///
/// With [videoUrl] null the reply carries no `files` entry, so `getVideoUrl`
/// resolves to null and the widget takes the snackbar branch. The delay is
/// what makes the loading state observable before the request settles.
StreamableService mockedStreamable({
  String? videoUrl,
  Duration delay = const Duration(milliseconds: 500),
}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.streamable.com'));

  DioAdapter(dio: dio).onGet(
    _streamableApi,
    (server) => server.reply(
      200,
      videoUrl == null
          ? <String, dynamic>{}
          : <String, dynamic>{
            'files': <String, dynamic>{
              'mp4': <String, dynamic>{'url': videoUrl},
            },
          },
      delay: delay,
    ),
  );

  return StreamableService(dio: dio);
}

FeedViewPost makePost({required ExternalEmbed external}) {
  return FeedViewPost(
    post: PostView(
      uri: 'at://did:example/post/123',
      cid: 'cid123',
      rkey: '123',
      author: AuthorView(did: 'did:plc:author', handle: 'author.test'),
      community: CommunityRef(did: 'did:plc:community', name: 'test-community'),
      createdAt: DateTime(2024),
      indexedAt: DateTime(2024),
      record: const PostRecord(title: 'Test Post Title'),
      stats: PostStats(upvotes: 0, downvotes: 0, score: 0, commentCount: 0),
      embed: ExternalPostEmbed(
        type: 'social.coves.embed.external',
        external: external,
        data: const {},
      ),
    ),
  );
}

ExternalEmbed streamableEmbed({
  String? embedType = 'video',
  String? provider = 'streamable',
  String? thumb = _thumb,
}) {
  return ExternalEmbed(
    uri: _streamableUri,
    thumb: thumb,
    embedType: embedType,
    provider: provider,
  );
}

void main() {
  late FakeAuthProvider auth;
  late _RecordingObserver observer;

  setUp(() {
    auth = FakeAuthProvider();
    observer = _RecordingObserver();
  });

  /// A phone-sized surface: the default 800x600 test view is too short for a
  /// media block plus header and actions, and the resulting RenderFlex
  /// overflow would fail tests for the wrong reason.
  void useMediaSizedSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  // PostCard's subtree navigates with go_router (TappableAuthor,
  // TappableCommunity, _navigateToDetail), so it needs a router rather than
  // a bare MaterialApp.
  Widget feedHarness(FeedViewPost post, {StreamableService? streamable}) {
    final router = GoRouter(
      observers: [observer],
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(body: PostCard(post: post)),
        ),
        GoRoute(
          path: '/post/:uri',
          builder: (context, state) => const Scaffold(body: Text('DETAIL')),
        ),
      ],
    );
    addTearDown(router.dispose);

    return MultiProvider(
      providers: postCardProviders(auth: auth, streamableService: streamable),
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Widget detailHarness(FeedViewPost post, {StreamableService? streamable}) {
    return MultiProvider(
      providers: [
        Provider<StreamableService>.value(
          value: streamable ?? StreamableService(),
        ),
      ],
      child: MaterialApp(
        navigatorObservers: [observer],
        home: Scaffold(
          body: SingleChildScrollView(child: DetailedPostView(post: post)),
        ),
      ),
    );
  }

  group('M1 feed Streamable detection is case-insensitive', () {
    testWidgets('shows the play button for embedType "Video"', (tester) async {
      useMediaSizedSurface(tester);

      await tester.pumpWidget(
        feedHarness(makePost(external: streamableEmbed(embedType: 'Video'))),
      );
      await tester.pump();

      expect(
        find.byIcon(Icons.play_arrow),
        findsOneWidget,
        reason:
            'embedType casing is provider-supplied metadata; "Video" is the '
            'same embed as "video"',
      );
    });

    testWidgets('shows the play button for embedType "VIDEO-STREAM"', (
      tester,
    ) async {
      useMediaSizedSurface(tester);

      await tester.pumpWidget(
        feedHarness(
          makePost(external: streamableEmbed(embedType: 'VIDEO-STREAM')),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('shows the play button for provider "Streamable"', (
      tester,
    ) async {
      useMediaSizedSurface(tester);

      await tester.pumpWidget(
        feedHarness(
          makePost(external: streamableEmbed(provider: 'Streamable')),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('still shows the play button for lowercase "video"', (
      tester,
    ) async {
      useMediaSizedSurface(tester);

      await tester.pumpWidget(
        feedHarness(makePost(external: streamableEmbed())),
      );
      await tester.pump();

      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('leaves a non-video embed alone whatever its casing', (
      tester,
    ) async {
      useMediaSizedSurface(tester);

      await tester.pumpWidget(
        feedHarness(makePost(external: streamableEmbed(embedType: 'Article'))),
      );
      await tester.pump();

      expect(find.byIcon(Icons.play_arrow), findsNothing);
    });

    testWidgets('leaves a non-Streamable video provider alone', (tester) async {
      useMediaSizedSurface(tester);

      await tester.pumpWidget(
        feedHarness(
          makePost(
            external: streamableEmbed(embedType: 'Video', provider: 'YouTube'),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byIcon(Icons.play_arrow),
        findsNothing,
        reason: 'only Streamable URLs can be resolved to an MP4 in-app',
      );
    });
  });

  group('M2 feed Streamable launch', () {
    testWidgets('reports a failed resolve with the shared copy', (
      tester,
    ) async {
      useMediaSizedSurface(tester);

      await tester.pumpWidget(
        feedHarness(
          makePost(external: streamableEmbed()),
          streamable: mockedStreamable(),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(
        find.text(_failureCopy),
        findsOneWidget,
        reason: 'both surfaces must say the same thing when a resolve fails',
      );

      // Drain the snackbar so no timer is left pending at teardown.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('marks the play button disabled while resolving', (
      tester,
    ) async {
      useMediaSizedSurface(tester);
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        feedHarness(
          makePost(external: streamableEmbed()),
          streamable: mockedStreamable(),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();

      expect(
        tester.getSemantics(find.bySemanticsLabel('Play video')),
        containsSemantics(
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
        ),
        reason: 'a tap handler that is null must not advertise as actionable',
      );

      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      handle.dispose();
    });
  });

  group('M3 detail Streamable launch', () {
    testWidgets('shows a loading indicator while resolving', (tester) async {
      await tester.pumpWidget(
        detailHarness(
          makePost(external: streamableEmbed()),
          streamable: mockedStreamable(),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);

      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('marks the play button disabled while resolving', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        detailHarness(
          makePost(external: streamableEmbed()),
          streamable: mockedStreamable(),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump();

      expect(
        tester.getSemantics(find.bySemanticsLabel('Play video')),
        containsSemantics(
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
        ),
        reason:
            'the detail view drops its tap handler while loading but still '
            'advertises an enabled button',
      );

      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      handle.dispose();
    });

    testWidgets('shows the shared failure copy when the resolve returns null', (
      tester,
    ) async {
      await tester.pumpWidget(
        detailHarness(
          makePost(external: streamableEmbed()),
          streamable: mockedStreamable(),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.text(_failureCopy), findsOneWidget);

      // The button comes back: a failed resolve is retryable.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('pushes the fullscreen player with the resolved url', (
      tester,
    ) async {
      await tester.pumpWidget(
        detailHarness(
          makePost(external: streamableEmbed()),
          streamable: mockedStreamable(videoUrl: _resolvedVideoUrl),
        ),
      );
      await tester.pump();
      observer.reset();

      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      // One pump to enter the loading state, one timed pump to settle the
      // mocked request. The route is recorded on push; deliberately not
      // pumping again, which would mount FullscreenVideoPlayer and hit the
      // video_player platform channel.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final routes = observer.pushedPages;
      expect(routes, hasLength(1));

      final page = routes.single.builder(tester.element(find.byType(Scaffold)));
      expect(page, isA<FullscreenVideoPlayer>());
      expect((page as FullscreenVideoPlayer).videoUrl, _resolvedVideoUrl);

      expect(
        find.text(_failureCopy),
        findsNothing,
        reason: 'a successful resolve must not also report an error',
      );
    });
  });
}
