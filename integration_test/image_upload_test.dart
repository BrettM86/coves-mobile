// Device-tier check that post images upload to the local stack and a post
// with three images plus a link is created.
//
// Requires the real local stack with the uploadImage endpoint (coves B1)
// and an existing signed-in dev app session on a local account. On Android,
// configure adb reverse through `make mobile-setup` in coves. Pass the DID of
// a local community the signed-in account can post to:
//
//   flutter test integration_test/image_upload_test.dart -d <device-id> \
//     --flavor dev --dart-define=ENVIRONMENT=local --no-uninstall \
//     --dart-define=IMAGE_POST_COMMUNITY_DID=<community DID>
//
// Each run uploads three small blobs and creates one post, like e1/h1 seed
// a post per run. The record's imagesWithAttachment embed with three blob
// refs is checked on the local PDS by the device checker.
import 'dart:async';
import 'dart:typed_data';

import 'package:coves_flutter/config/environment_config.dart';
import 'package:coves_flutter/models/post_embed_input.dart';
import 'package:coves_flutter/models/upload_image_response.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/test_helpers/image_fixtures.dart';

const _communityDid = String.fromEnvironment('IMAGE_POST_COMMUNITY_DID');

const _requestTimeout = Duration(seconds: 60);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('uploads a JPEG, a PNG and an animated GIF, then creates a post '
      'with the three images and a link', (tester) async {
    expect(
      EnvironmentConfig.current.isLocal,
      isTrue,
      reason: 'Run with --flavor dev --dart-define=ENVIRONMENT=local.',
    );
    expect(
      _communityDid,
      startsWith('did:'),
      reason:
          'Pass a local community with '
          '--dart-define=IMAGE_POST_COMMUNITY_DID=<community DID>.',
    );

    // Existing debug app diagnostics include identity values. Silence their
    // console output during this live check.
    await runZoned(
      () async {
        final authProvider = AuthProvider();
        CovesApiService? apiService;
        try {
          await authProvider.initialize();
          expect(
            authProvider.isAuthenticated && authProvider.session != null,
            isTrue,
            reason:
                'Sign into the dev app on this device using a local account '
                'before running this test. Do not clear its app data.',
          );
          final api = apiService = CovesApiService(
            sessionKeyOf: () {
              final session = authProvider.session;
              return session == null
                  ? null
                  : (did: session.did, sessionId: session.sessionId);
            },
            tokenGetter: authProvider.getAccessToken,
            tokenRefresher: authProvider.refreshToken,
          );

          final rows = <({String name, Uint8List bytes, String mimeType})>[
            (name: 'JPEG', bytes: tinyJpeg4x3, mimeType: 'image/jpeg'),
            (name: 'PNG', bytes: tinyPng4x3, mimeType: 'image/png'),
            (
              name: 'animated GIF',
              bytes: animatedGif3x2,
              mimeType: 'image/gif',
            ),
          ];

          final uploaded = <UploadImageResponse>[];
          for (final row in rows) {
            final response = await api
                .uploadImage(row.bytes, row.mimeType)
                .timeout(_requestTimeout);
            expect(response.mimeType, row.mimeType, reason: row.name);
            expect(response.size, greaterThan(0), reason: row.name);
            expect(response.blob[r'$type'], 'blob', reason: row.name);
            expect(response.blob['mimeType'], row.mimeType, reason: row.name);
            final ref = response.blob['ref'];
            expect(ref, isA<Map<String, dynamic>>(), reason: row.name);
            expect(
              (ref as Map<String, dynamic>)[r'$link'],
              isA<String>().having((link) => link, 'link', isNotEmpty),
              reason: row.name,
            );
            uploaded.add(response);
          }

          final created = await api
              .createPost(
                community: _communityDid,
                title: 'Image upload test ${DateTime.now().toIso8601String()}',
                embed: buildPostEmbed(
                  images: [
                    for (final response in uploaded)
                      EmbedImageInput(
                        blob: response.blob,
                        aspectRatio: response.aspectRatio,
                      ),
                  ],
                  external: ExternalEmbedInput(
                    uri: 'https://example.com/coves-image-upload-test',
                  ),
                ),
                langs: const ['en'],
              )
              .timeout(_requestTimeout);

          expect(
            created.uri,
            startsWith('at://'),
            reason: 'createPost returns the record URI',
          );
          expect(created.uri, contains('/social.coves.community.post/'));
          expect(created.cid, isNotEmpty);
        } finally {
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
