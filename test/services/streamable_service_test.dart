import 'package:coves_flutter/services/streamable_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  group('StreamableService', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late StreamableService service;

    setUp(() {
      dio = Dio();
      dioAdapter = DioAdapter(dio: dio);
      service = StreamableService(dio: dio);
    });

    group('extractShortcode', () {
      test('extracts shortcode from standard URL', () {
        expect(
          StreamableService.extractShortcode('https://streamable.com/abc123'),
          'abc123',
        );
      });

      test('extracts shortcode from /e/ URL', () {
        expect(
          StreamableService.extractShortcode('https://streamable.com/e/abc123'),
          'abc123',
        );
      });

      test('extracts shortcode from URL without scheme', () {
        expect(
          StreamableService.extractShortcode('streamable.com/xyz789'),
          'xyz789',
        );
      });

      test('extracts shortcode from /e/ URL without scheme', () {
        expect(
          StreamableService.extractShortcode('streamable.com/e/xyz789'),
          'xyz789',
        );
      });

      test('returns null for empty path', () {
        expect(
          StreamableService.extractShortcode('https://streamable.com/'),
          null,
        );
      });

      test('returns null for invalid URL', () {
        expect(StreamableService.extractShortcode('not a url'), null);
      });

      test('handles URL with query parameters', () {
        expect(
          StreamableService.extractShortcode(
            'https://streamable.com/abc123?autoplay=1',
          ),
          'abc123',
        );
      });

      test('handles /e/ URL with query parameters', () {
        expect(
          StreamableService.extractShortcode(
            'https://streamable.com/e/abc123?autoplay=1',
          ),
          'abc123',
        );
      });
    });

    group('getVideoUrl', () {
      test('fetches and returns MP4 URL successfully', () async {
        const shortcode = 'abc123';
        const videoUrl = '//cdn.streamable.com/video/mp4/abc123.mp4';

        dioAdapter.onGet(
          'https://api.streamable.com/videos/$shortcode',
          (server) => server.reply(200, {
            'files': {
              'mp4': {'url': videoUrl},
            },
          }),
        );

        final result = await service.getVideoUrl(
          'https://streamable.com/$shortcode',
        );

        expect(result, 'https:$videoUrl');
      });

      test('handles /e/ URL format', () async {
        const shortcode = 'xyz789';
        const videoUrl = '//cdn.streamable.com/video/mp4/xyz789.mp4';

        dioAdapter.onGet(
          'https://api.streamable.com/videos/$shortcode',
          (server) => server.reply(200, {
            'files': {
              'mp4': {'url': videoUrl},
            },
          }),
        );

        final result = await service.getVideoUrl(
          'https://streamable.com/e/$shortcode',
        );

        expect(result, 'https:$videoUrl');
      });

      test('caches video URLs', () async {
        const shortcode = 'cached123';
        const videoUrl = '//cdn.streamable.com/video/mp4/cached123.mp4';

        dioAdapter.onGet(
          'https://api.streamable.com/videos/$shortcode',
          (server) => server.reply(200, {
            'files': {
              'mp4': {'url': videoUrl},
            },
          }),
        );

        // First call - should hit the API
        final result1 = await service.getVideoUrl(
          'https://streamable.com/$shortcode',
        );
        expect(result1, 'https:$videoUrl');

        // Second call - should use cache (no additional network request)
        final result2 = await service.getVideoUrl(
          'https://streamable.com/$shortcode',
        );
        expect(result2, 'https:$videoUrl');
      });

      test('returns null for invalid shortcode', () async {
        const shortcode = 'invalid';

        dioAdapter.onGet(
          'https://api.streamable.com/videos/$shortcode',
          (server) => server.reply(404, {'error': 'Not found'}),
        );

        final result = await service.getVideoUrl(
          'https://streamable.com/$shortcode',
        );

        expect(result, null);
      });

      test('returns null when files field is missing', () async {
        const shortcode = 'nofiles123';

        dioAdapter.onGet(
          'https://api.streamable.com/videos/$shortcode',
          (server) => server.reply(200, {'status': 'ok'}),
        );

        final result = await service.getVideoUrl(
          'https://streamable.com/$shortcode',
        );

        expect(result, null);
      });

      test('returns null when mp4 field is missing', () async {
        const shortcode = 'nomp4123';

        dioAdapter.onGet(
          'https://api.streamable.com/videos/$shortcode',
          (server) => server.reply(200, {
            'files': {'webm': {}},
          }),
        );

        final result = await service.getVideoUrl(
          'https://streamable.com/$shortcode',
        );

        expect(result, null);
      });

      test('returns null when URL field is missing', () async {
        const shortcode = 'nourl123';

        dioAdapter.onGet(
          'https://api.streamable.com/videos/$shortcode',
          (server) => server.reply(200, {
            'files': {
              'mp4': {'status': 'processing'},
            },
          }),
        );

        final result = await service.getVideoUrl(
          'https://streamable.com/$shortcode',
        );

        expect(result, null);
      });

      test('returns null on network error', () async {
        const shortcode = 'error500';

        dioAdapter.onGet(
          'https://api.streamable.com/videos/$shortcode',
          (server) => server.throws(
            500,
            DioException(
              requestOptions: RequestOptions(
                path: 'https://api.streamable.com/videos/$shortcode',
              ),
            ),
          ),
        );

        final result = await service.getVideoUrl(
          'https://streamable.com/$shortcode',
        );

        expect(result, null);
      });

      test('returns null when shortcode extraction fails', () async {
        final result = await service.getVideoUrl('invalid-url');
        expect(result, null);
      });

      test('prepends https to protocol-relative URLs', () async {
        const shortcode = 'protocol123';
        const videoUrl = '//cdn.streamable.com/video/mp4/protocol123.mp4';

        dioAdapter.onGet(
          'https://api.streamable.com/videos/$shortcode',
          (server) => server.reply(200, {
            'files': {
              'mp4': {'url': videoUrl},
            },
          }),
        );

        final result = await service.getVideoUrl(
          'https://streamable.com/$shortcode',
        );

        expect(result, startsWith('https://'));
        expect(result, 'https:$videoUrl');
      });

      test('does not modify URLs that already have protocol', () async {
        const shortcode = 'hasprotocol123';
        const videoUrl =
            'https://cdn.streamable.com/video/mp4/hasprotocol123.mp4';

        dioAdapter.onGet(
          'https://api.streamable.com/videos/$shortcode',
          (server) => server.reply(200, {
            'files': {
              'mp4': {'url': videoUrl},
            },
          }),
        );

        final result = await service.getVideoUrl(
          'https://streamable.com/$shortcode',
        );

        expect(result, videoUrl);
      });
    });
  });
}
