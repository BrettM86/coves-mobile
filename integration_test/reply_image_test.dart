// Device-tier check that an image-only reply is written with empty content
// and an images embed, and that the served comment renders its image grid.
//
// Requires the real local stack with the uploadImage endpoint (coves B1) and
// image comments (coves B2), and an existing dev app session on a local
// PLC/PDS account, signed in through the app on this device. On Android,
// configure adb reverse through `make mobile-setup` in coves. Pass the URI of
// a seeded local post the account can reply to:
//
//   flutter test integration_test/reply_image_test.dart -d <device-id> \
//     --flavor dev --dart-define=ENVIRONMENT=local --no-uninstall \
//     --dart-define=REPLY_IMAGE_POST_URI=<at:// post URI>
//
// The test opens the reply screen on that post, attaches one image through
// the reply toolbar (the system picker is replaced by a fake that hands back
// a small JPEG, as device tests cannot drive the system photo picker), types
// nothing and sends. It then reads the comment record from the local PDS
// and renders the comment the AppView serves. Each run uploads one blob and
// creates one comment, like e4/e10 seed one per run. It fails, never skips,
// when a define is missing or any endpoint is not on the local stack.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:coves_flutter/config/environment_config.dart';
import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/post_embed_input.dart';
import 'package:coves_flutter/models/post_get_result.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
import 'package:coves_flutter/providers/comments_provider.dart';
import 'package:coves_flutter/providers/viewer_authority_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/screens/compose/reply_screen.dart';
import 'package:coves_flutter/services/comment_service.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/vote_service.dart';
import 'package:coves_flutter/widgets/comment_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import '../test/test_helpers/image_fixtures.dart';
import '../test/test_helpers/image_picking_fakes.dart';

const _postUri = String.fromEnvironment('REPLY_IMAGE_POST_URI');

const _requestTimeout = Duration(seconds: 60);
const _pollInterval = Duration(milliseconds: 250);

/// Hosts the local stack is reached on: the emulator loopback forwarded by
/// adb reverse, or the host itself from an emulator.
const _localHosts = {'localhost', '127.0.0.1', '10.0.2.2'};

/// The comment service the app uses, recording the comment it created.
class _RecordingCommentService extends CommentService {
  _RecordingCommentService({
    required super.sessionKeyOf,
    super.sessionGetter,
    super.tokenRefresher,
  });

  CreateCommentResponse? created;

  @override
  Future<CreateCommentResponse> createComment({
    required String rootUri,
    required String rootCid,
    required String parentUri,
    required String parentCid,
    required String content,
    List<RichTextFacet>? contentFacets,
    ImagesEmbedInput? embed,
  }) async {
    final response = await super.createComment(
      rootUri: rootUri,
      rootCid: rootCid,
      parentUri: parentUri,
      parentCid: parentCid,
      content: content,
      contentFacets: contentFacets,
      embed: embed,
    );
    created = response;
    return response;
  }
}

/// Pumps until [done] holds, failing after [_requestTimeout].
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done,
  String what,
) async {
  final deadline = DateTime.now().add(_requestTimeout);
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for $what.');
    }
    await tester.pump(_pollInterval);
  }
}

/// Reads [uri]'s record from the local PDS at [pdsOrigin].
Future<Map<String, dynamic>> _readRecord(Uri pdsOrigin, String uri) async {
  final parts = Uri.parse(uri);
  final segments = parts.pathSegments;
  final request = pdsOrigin.replace(
    path: '/xrpc/com.atproto.repo.getRecord',
    queryParameters: {
      'repo': parts.host,
      'collection': segments[0],
      'rkey': segments[1],
    },
  );
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(request))
        .close()
        .timeout(_requestTimeout);
    final body = await response.transform(utf8.decoder).join();
    expect(response.statusCode, 200, reason: 'getRecord for the comment');
    return (jsonDecode(body) as Map<String, dynamic>)['value']
        as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an image-only reply is written with empty content, no facets '
      'and one image, and the served comment renders the image grid', (
    tester,
  ) async {
    expect(
      EnvironmentConfig.current.isLocal,
      isTrue,
      reason: 'Run with --flavor dev --dart-define=ENVIRONMENT=local.',
    );
    expect(
      _postUri,
      startsWith('at://'),
      reason:
          'Pass a seeded local post with '
          '--dart-define=REPLY_IMAGE_POST_URI=<at:// post URI>.',
    );
    final apiOrigin = Uri.parse(EnvironmentConfig.current.apiUrl);
    // The local handle resolver is the local PDS.
    final resolver = Uri.parse(EnvironmentConfig.current.handleResolverUrl);
    final pdsOrigin = Uri(
      scheme: resolver.scheme,
      host: resolver.host,
      port: resolver.port,
    );
    for (final origin in [apiOrigin, pdsOrigin]) {
      expect(
        _localHosts,
        contains(origin.host),
        reason: '$origin is not on the local stack.',
      );
    }

    final imageDirectory = Directory.systemTemp.createTempSync('reply_image');
    addTearDown(() => imageDirectory.deleteSync(recursive: true));
    final imagePath = '${imageDirectory.path}/reply.jpg';
    File(imagePath).writeAsBytesSync(tinyJpeg4x3);
    final originalPicker = ImagePickerPlatform.instance;
    addTearDown(() => ImagePickerPlatform.instance = originalPicker);
    ImagePickerPlatform.instance = FakePostImagePicker()
      ..nextMulti = [XFile(imagePath)];

    // Existing debug app diagnostics include identity values. Silence their
    // console output during this live check.
    await runZoned(
      () async {
        final authProvider = AuthProvider();
        CovesApiService? apiService;
        VoteProvider? voteProvider;
        BlockProvider? blockProvider;
        ViewerAuthorityProvider? authority;
        CommentsProvider? commentsProvider;
        try {
          await authProvider.initialize();
          expect(
            authProvider.isAuthenticated && authProvider.session != null,
            isTrue,
            reason:
                'Sign into the dev app on this device using a local account '
                'before running this test. Do not clear its app data.',
          );
          Object? sessionKey() {
            final session = authProvider.session;
            return session == null
                ? null
                : (did: session.did, sessionId: session.sessionId);
          }

          final api = apiService = CovesApiService(
            sessionKeyOf: sessionKey,
            tokenGetter: authProvider.getAccessToken,
            tokenRefresher: authProvider.refreshToken,
          );
          final commentService = _RecordingCommentService(
            sessionKeyOf: sessionKey,
            sessionGetter: () async => authProvider.session,
            tokenRefresher: authProvider.refreshToken,
          );
          final votes = voteProvider = VoteProvider(
            voteService: VoteService(
              sessionKeyOf: sessionKey,
              sessionGetter: () async => authProvider.session,
              didGetter: () => authProvider.did,
              tokenRefresher: authProvider.refreshToken,
            ),
            authProvider: authProvider,
          );
          final blocks = blockProvider = BlockProvider(
            apiService: api,
            authProvider: authProvider,
          );
          final viewerAuthority = authority = ViewerAuthorityProvider(
            apiService: api,
            authProvider: authProvider,
          );

          final fetched = await api.getPost(_postUri).timeout(_requestTimeout);
          expect(fetched, isA<PostGetSuccess>(), reason: 'the seeded post');
          final post = (fetched as PostGetSuccess).post;
          final comments = commentsProvider = CommentsProvider(
            authProvider,
            postUri: post.uri,
            postCid: post.cid,
            apiService: api,
            voteProvider: votes,
            commentService: commentService,
          );

          final navigatorKey = GlobalKey<NavigatorState>();
          Widget app(Widget home) => MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
              ChangeNotifierProvider<VoteProvider>.value(value: votes),
              ChangeNotifierProvider<BlockProvider>.value(value: blocks),
              ChangeNotifierProvider<ViewerAuthorityProvider>.value(
                value: viewerAuthority,
              ),
              ChangeNotifierProvider<CommentsProvider>.value(value: comments),
              Provider<CovesApiService>.value(value: api),
            ],
            child: MaterialApp(
              theme: AppTheme.dark,
              navigatorKey: navigatorKey,
              home: home,
            ),
          );

          Object? submitFailure;
          // ReplyScreen pops itself after a send, so it sits over a base
          // route as it does over the post screen in the app.
          await tester.pumpWidget(
            app(const Scaffold(body: Text('base route'))),
          );
          unawaited(
            navigatorKey.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => ReplyScreen(
                  post: FeedViewPost(post: post),
                  commentsProvider: comments,
                  onSubmit: (content, facets, embed) async {
                    try {
                      await comments.createComment(
                        content: content,
                        contentFacets: facets,
                        embed: embed,
                      );
                    } on Exception catch (error) {
                      submitFailure = error;
                      rethrow;
                    }
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          await tester.tap(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics && widget.properties.label == 'Add image',
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Choose from Gallery'));
          await _pumpUntil(
            tester,
            () => find
                .byKey(const Key('image-attachment-tile-0'))
                .evaluate()
                .isNotEmpty,
            'the attached image tile',
          );

          await tester.tap(find.text('Send'));
          await _pumpUntil(
            tester,
            () => commentService.created != null || submitFailure != null,
            'the reply to be created',
          );
          expect(submitFailure, isNull, reason: 'the reply was sent');
          final created = commentService.created!;
          expect(created.uri, contains('/social.coves.community.comment/'));

          final record = await _readRecord(pdsOrigin, created.uri);
          expect(record['content'], '');
          expect(record.containsKey('facets'), isFalse);
          final embed = record['embed'] as Map<String, dynamic>;
          expect(embed[r'$type'], 'social.coves.embed.images');
          final images = embed['images'] as List<dynamic>;
          expect(images, hasLength(1));
          final blob =
              (images.single as Map<String, dynamic>)['image']
                  as Map<String, dynamic>;
          expect(blob[r'$type'], 'blob');
          expect(
            (blob['ref'] as Map<String, dynamic>)[r'$link'],
            isA<String>().having((link) => link, 'link', isNotEmpty),
          );

          // The AppView indexes new comments asynchronously.
          CommentView? served;
          final deadline = DateTime.now().add(_requestTimeout);
          while (served == null) {
            final response = await api
                .getComments(postUri: post.uri, sort: 'new')
                .timeout(_requestTimeout);
            for (final thread in response.comments) {
              served ??= thread.findByUri(created.uri)?.comment;
            }
            if (served == null) {
              if (DateTime.now().isAfter(deadline)) {
                fail('The AppView did not serve the reply in time.');
              }
              await tester.pump(_pollInterval);
            }
          }
          final servedEmbed = served.parsedEmbed;
          expect(servedEmbed, isA<ImagesPostEmbed>());
          for (final image in (servedEmbed! as ImagesPostEmbed).images) {
            expect(
              _localHosts,
              contains(Uri.parse(image.thumb).host),
              reason: '${image.thumb} is not served by the local stack.',
            );
          }

          await tester.pumpWidget(
            app(
              Scaffold(body: CommentCard(comment: served, sessionStamp: null)),
            ),
          );
          await tester.pump();
          expect(find.byKey(const Key('comment-images-grid')), findsOneWidget);
        } finally {
          commentsProvider?.dispose();
          authority?.dispose();
          blockProvider?.dispose();
          voteProvider?.dispose();
          apiService?.dispose();
          authProvider.dispose();
        }
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) {},
      ),
    );
  });
}
