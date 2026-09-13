import 'package:cached_network_image/cached_network_image.dart';
import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/widgets/post_card.dart';
import 'package:coves_flutter/widgets/post_card_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_providers.dart';

const _bannerKey = Key('sensitive-content-banner');
const _placeholderKey = Key('sensitive-image-placeholder');
const _imagesKey = Key('post-images-embed');

const _thumb = 'https://cdn.test/nsfw-thumb.jpg';
const _fullsize = 'https://cdn.test/nsfw-fullsize.jpg';
const _alt = 'A photograph the author marked as sensitive';
const _title = 'A post behind the NSFW gate';
const _body = 'Body text that must stay hidden while concealed';

const _detailMarker = 'DETAIL SCREEN';

/// The timeline envelope exactly as the appview serves it: a self-labelled
/// `nsfw` record plus a hydrated `images#view` embed. Parsing through
/// [TimelineResponse.fromJson] keeps this test outside the units it exercises
/// — the label has to survive real json parsing, not a hand-built model.
Map<String, dynamic> sensitiveTimelineJson() {
  return <String, dynamic>{
    'feed': <dynamic>[
      <String, dynamic>{
        'post': <String, dynamic>{
          'uri': 'at://did:plc:author/social.coves.community.post/nsfw1',
          'cid': 'bafynsfwcid',
          'rkey': 'nsfw1',
          'author': <String, dynamic>{
            'did': 'did:plc:author',
            'handle': 'author.test',
          },
          'community': <String, dynamic>{
            'did': 'did:plc:community',
            'name': 'test-community',
          },
          'createdAt': '2025-01-01T12:00:00Z',
          'indexedAt': '2025-01-01T12:00:05Z',
          'record': <String, dynamic>{
            'title': _title,
            'content': _body,
            'labels': <String, dynamic>{
              r'$type': 'com.atproto.label.defs#selfLabels',
              'values': <dynamic>[
                <String, dynamic>{'val': 'nsfw'},
              ],
            },
          },
          'stats': <String, dynamic>{
            'upvotes': 3,
            'downvotes': 1,
            'score': 2,
            'commentCount': 0,
          },
          'embed': <String, dynamic>{
            r'$type': 'social.coves.embed.images#view',
            'images': <dynamic>[
              <String, dynamic>{
                'thumb': _thumb,
                'fullsize': _fullsize,
                'alt': _alt,
                'aspectRatio': <String, dynamic>{'width': 3, 'height': 2},
              },
            ],
          },
        },
      },
    ],
  };
}

void main() {
  testWidgets(
    'a self-labelled nsfw timeline post is concealed until the banner is '
    'tapped',
    (tester) async {
      // Phone-sized surface: the default 800x600 view is too short for a
      // media block plus header and actions, and the overflow would fail this
      // test for the wrong reason.
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final semantics = tester.ensureSemantics();

      final timeline = TimelineResponse.fromJson(sensitiveTimelineJson());
      expect(
        timeline.feed,
        hasLength(1),
        reason:
            'TimelineResponse.fromJson must keep a self-labelled post: a '
            'throw in label parsing would silently drop it from the feed',
      );
      final post = timeline.feed.single;

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(body: PostCard(post: post)),
          ),
          GoRoute(
            path: '/post/:uri',
            builder: (context, state) =>
                const Scaffold(body: Text(_detailMarker)),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: postCardProviders(auth: FakeAuthProvider()),
          child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
        ),
      );
      await tester.pump();

      Finder inBanner(Finder matching) =>
          find.descendant(of: find.byKey(_bannerKey), matching: matching);

      // Concealed: the post is still identifiable, but nothing sensitive
      // has been rendered.
      expect(
        find.text(_title),
        findsOneWidget,
        reason: 'the title stays readable so the reader can judge the post',
      );
      expect(
        find.byKey(_bannerKey),
        findsOneWidget,
        reason: 'a sensitive post must announce itself with a reveal banner',
      );
      expect(inBanner(find.text('NSFW Content')), findsOneWidget);
      expect(inBanner(find.text('Show')), findsOneWidget);
      expect(
        find.byKey(_placeholderKey),
        findsOneWidget,
        reason: 'a native image embed gets a blurred placeholder',
      );
      expect(
        find.text(_body),
        findsNothing,
        reason: 'body text is concealed along with the media',
      );
      expect(find.byKey(_imagesKey), findsNothing);
      expect(
        tester
            .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
            .map((image) => image.imageUrl),
        isNot(contains(_fullsize)),
        reason: 'the fullsize rendering must never be fetched while concealed',
      );
      expect(
        find.bySemanticsLabel(_alt),
        findsNothing,
        reason: 'alt text describes the concealed image and must not leak',
      );
      expect(
        find.byType(PostCardActions),
        findsOneWidget,
        reason: 'voting and commenting stay available on a concealed post',
      );

      await tester.tap(find.byKey(_bannerKey));
      await tester.pump();

      // Revealed: the post renders as any other post, and the banner offers
      // the way back.
      expect(find.text(_body), findsOneWidget);
      expect(find.byKey(_imagesKey), findsOneWidget);
      expect(find.byKey(_placeholderKey), findsNothing);
      expect(inBanner(find.text('Hide')), findsOneWidget);

      semantics.dispose();
    },
  );
}
