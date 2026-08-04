import 'package:coves_flutter/constants/embed_types.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:flutter_test/flutter_test.dart';

const _thumbUrl = 'https://cdn.test/thumb.jpg';
const _fullUrl = 'https://cdn.test/full.jpg';
const _videoUrl = 'https://cdn.test/video.mp4';

void main() {
  group('PostEmbed.fromJson', () {
    final externalPayload = {
      'external': {
        'uri': 'https://example.com/article',
        'title': 'Example article',
        'thumb': 'https://pds.example/xrpc/com.atproto.sync.getBlob?cid=abc',
      },
    };

    final postPayload = {
      'post': {
        'uri': 'at://did:plc:xyz/app.bsky.feed.post/abc',
        'cid': 'bafyrei123',
      },
    };

    test('parses record-form external embed', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.external,
        ...externalPayload,
      });

      expect(embed, isA<ExternalPostEmbed>());
      expect(embed.external, isNotNull);
      expect(embed.external!.uri, 'https://example.com/article');
      expect(embed.blueskyPost, isNull);
    });

    test('parses view-form external embed served by the appview', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.externalView,
        ...externalPayload,
      });

      expect(embed, isA<ExternalPostEmbed>());
      expect(embed.external, isNotNull);
      expect(embed.external!.uri, 'https://example.com/article');
      expect(embed.external!.thumb, contains('getBlob'));
      expect(embed.blueskyPost, isNull);
      expect(embed.type, EmbedTypes.externalView);
    });

    test('parses record-form post embed', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.post,
        ...postPayload,
      });

      expect(embed, isA<QuotePostEmbed>());
      expect(embed.blueskyPost, isNotNull);
      expect(embed.blueskyPost!.uri, 'at://did:plc:xyz/app.bsky.feed.post/abc');
      expect(embed.external, isNull);
    });

    test('parses view-form post embed served by the appview', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.postView,
        ...postPayload,
      });

      expect(embed, isA<QuotePostEmbed>());
      expect(embed.blueskyPost, isNotNull);
      expect(embed.blueskyPost!.uri, 'at://did:plc:xyz/app.bsky.feed.post/abc');
      expect(embed.external, isNull);
      expect(embed.type, EmbedTypes.postView);
    });

    test('falls back to external for unrecognized type with top-level uri', () {
      final embed = PostEmbed.fromJson({
        r'$type': 'social.coves.embed.unknown',
        'uri': 'https://example.com/bare-link',
      });

      expect(embed, isA<ExternalPostEmbed>());
      expect(embed.external, isNotNull);
      expect(embed.external!.uri, 'https://example.com/bare-link');
    });
  });

  group('PostEmbed.fromJson images#view', () {
    test('parses a single image with every field populated', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.imagesView,
        'images': [
          {
            'thumb': _thumbUrl,
            'fullsize': _fullUrl,
            'alt': 'A red barn at dusk',
            'aspectRatio': {'width': 3, 'height': 2},
          },
        ],
      });

      expect(embed, isA<ImagesPostEmbed>());
      expect(embed.type, EmbedTypes.imagesView);

      final image = (embed as ImagesPostEmbed).images.single;
      expect(image.thumb, _thumbUrl);
      expect(image.fullsize, _fullUrl);
      expect(image.alt, 'A red barn at dusk');
      expect(image.aspectRatio, isNotNull);
      expect(image.aspectRatio!.width, 3);
      expect(image.aspectRatio!.height, 2);
    });

    test('preserves the order of a multi-image embed', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.imagesView,
        'images': [
          {'thumb': 'https://cdn.test/t1.jpg', 'fullsize': _fullUrl},
          {'thumb': 'https://cdn.test/t2.jpg', 'fullsize': _fullUrl},
          {'thumb': 'https://cdn.test/t3.jpg', 'fullsize': _fullUrl},
        ],
      });

      expect(embed, isA<ImagesPostEmbed>());

      final images = (embed as ImagesPostEmbed).images;
      expect(images, hasLength(3));
      expect(images.map((image) => image.thumb).toList(), const [
        'https://cdn.test/t1.jpg',
        'https://cdn.test/t2.jpg',
        'https://cdn.test/t3.jpg',
      ]);
    });

    test('parses a minimal image with only thumb and fullsize', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.imagesView,
        'images': [
          {'thumb': _thumbUrl, 'fullsize': _fullUrl},
        ],
      });

      expect(embed, isA<ImagesPostEmbed>());

      final image = (embed as ImagesPostEmbed).images.single;
      expect(image.thumb, _thumbUrl);
      expect(image.fullsize, _fullUrl);
      expect(image.alt, isNull);
      expect(image.aspectRatio, isNull);
    });

    test('drops a malformed aspectRatio but keeps the image', () {
      const malformedRatios = <Map<String, dynamic>>[
        {'width': 3},
        {'height': 2},
        {'width': '3', 'height': 2},
        {'width': 3, 'height': '2'},
        {'width': 3, 'height': 0},
        {'width': 0, 'height': 2},
        {'width': -3, 'height': 2},
        <String, dynamic>{},
      ];

      for (final ratio in malformedRatios) {
        final embed = PostEmbed.fromJson({
          r'$type': EmbedTypes.imagesView,
          'images': [
            {'thumb': _thumbUrl, 'fullsize': _fullUrl, 'aspectRatio': ratio},
          ],
        });

        expect(embed, isA<ImagesPostEmbed>(), reason: 'ratio: $ratio');

        final image = (embed as ImagesPostEmbed).images.single;
        expect(image.aspectRatio, isNull, reason: 'ratio: $ratio');
        expect(image.thumb, _thumbUrl, reason: 'ratio: $ratio');
        expect(image.fullsize, _fullUrl, reason: 'ratio: $ratio');
      }
    });

    test('drops a non-map aspectRatio but keeps the image', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.imagesView,
        'images': [
          {'thumb': _thumbUrl, 'fullsize': _fullUrl, 'aspectRatio': '3:2'},
        ],
      });

      expect(embed, isA<ImagesPostEmbed>());
      expect((embed as ImagesPostEmbed).images.single.aspectRatio, isNull);
    });

    test('ignores a non-String alt rather than dropping the image', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.imagesView,
        'images': [
          {'thumb': _thumbUrl, 'fullsize': _fullUrl, 'alt': 42},
        ],
      });

      expect(embed, isA<ImagesPostEmbed>());
      expect((embed as ImagesPostEmbed).images.single.alt, isNull);
    });
  });

  group('PostEmbed.fromJson images#view is all-or-nothing', () {
    test('rejects the whole embed when one entry carries a blob map', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.imagesView,
        'images': [
          {'thumb': _thumbUrl, 'fullsize': _fullUrl},
          {'image': _blobRef('bafyimage2'), 'alt': 'unhydrated'},
        ],
      });

      expect(embed, isA<UnknownPostEmbed>());
      expect(embed.type, EmbedTypes.imagesView);
      expect(embed.data['images'], hasLength(2));
    });

    test('rejects the whole embed when fullsize is a blob map', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.imagesView,
        'images': [
          {'thumb': _thumbUrl, 'fullsize': _blobRef('bafyfull')},
        ],
      });

      expect(embed, isA<UnknownPostEmbed>());
    });

    test('rejects the whole embed when thumb is missing', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.imagesView,
        'images': [
          {'fullsize': _fullUrl, 'alt': 'no thumb'},
        ],
      });

      expect(embed, isA<UnknownPostEmbed>());
    });

    test('rejects the whole embed when an entry is not a map', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.imagesView,
        'images': [
          {'thumb': _thumbUrl, 'fullsize': _fullUrl},
          _fullUrl,
        ],
      });

      expect(embed, isA<UnknownPostEmbed>());
    });

    test('treats an empty images list as unknown', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.imagesView,
        'images': <dynamic>[],
      });

      expect(embed, isA<UnknownPostEmbed>());
      expect(embed.type, EmbedTypes.imagesView);
    });

    test('treats a missing images key as unknown', () {
      final embed = PostEmbed.fromJson({r'$type': EmbedTypes.imagesView});

      expect(embed, isA<UnknownPostEmbed>());
      expect(embed.type, EmbedTypes.imagesView);
    });

    test('treats a non-list images value as unknown', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.imagesView,
        'images': {'thumb': _thumbUrl, 'fullsize': _fullUrl},
      });

      expect(embed, isA<UnknownPostEmbed>());
    });
  });

  group('PostEmbed.fromJson images record shape', () {
    test('treats the unhydrated images record as unknown', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.images,
        'images': [
          {
            'image': _blobRef('bafyimage1'),
            'alt': 'A red barn at dusk',
            'aspectRatio': {'width': 3, 'height': 2},
          },
        ],
      });

      expect(embed, isA<UnknownPostEmbed>());
      expect(embed.type, EmbedTypes.images);
      expect(embed.external, isNull);
      expect(embed.blueskyPost, isNull);
    });

    test('treats an images record with url strings as unknown', () {
      // The record shape never carries rendered URLs; even if it did, the
      // client must not render it because the $type lacks #view.
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.images,
        'images': [
          {'thumb': _thumbUrl, 'fullsize': _fullUrl},
        ],
      });

      expect(embed, isA<UnknownPostEmbed>());
    });
  });

  group('PostEmbed.fromJson video#view', () {
    test('parses a video with every field populated', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.videoView,
        'video': _videoUrl,
        'thumbnail': _thumbUrl,
        'alt': 'A timelapse of the harbour',
        'duration': 42,
      });

      expect(embed, isA<VideoPostEmbed>());
      expect(embed.type, EmbedTypes.videoView);

      final video = embed as VideoPostEmbed;
      expect(video.video, _videoUrl);
      expect(video.thumbnail, _thumbUrl);
      expect(video.alt, 'A timelapse of the harbour');
      expect(video.duration, 42);
    });

    test('parses a minimal video with only the video url', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.videoView,
        'video': _videoUrl,
      });

      expect(embed, isA<VideoPostEmbed>());

      final video = embed as VideoPostEmbed;
      expect(video.video, _videoUrl);
      expect(video.thumbnail, isNull);
      expect(video.alt, isNull);
      expect(video.duration, isNull);
    });

    test('treats a blob map video field as unknown', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.videoView,
        'video': _blobRef('bafyvideo'),
        'thumbnail': _thumbUrl,
      });

      expect(embed, isA<UnknownPostEmbed>());
      expect(embed.type, EmbedTypes.videoView);
    });

    test('treats a missing video field as unknown', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.videoView,
        'thumbnail': _thumbUrl,
        'duration': 42,
      });

      expect(embed, isA<UnknownPostEmbed>());
    });

    test('treats a blob map thumbnail as unknown', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.videoView,
        'video': _videoUrl,
        'thumbnail': _blobRef('bafythumb'),
      });

      expect(embed, isA<UnknownPostEmbed>());
      expect(embed.type, EmbedTypes.videoView);
    });

    test('ignores a non-int duration rather than rejecting the embed', () {
      const durations = <Object>['long', 42.5, true];

      for (final duration in durations) {
        late PostEmbed embed;

        expect(
          () =>
              embed = PostEmbed.fromJson({
                r'$type': EmbedTypes.videoView,
                'video': _videoUrl,
                'duration': duration,
              }),
          returnsNormally,
          reason: 'duration: $duration',
        );

        expect(embed, isA<VideoPostEmbed>(), reason: 'duration: $duration');

        final video = embed as VideoPostEmbed;
        expect(video.video, _videoUrl, reason: 'duration: $duration');
        expect(video.duration, isNull, reason: 'duration: $duration');
      }
    });

    test('ignores a non-String alt rather than rejecting the embed', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.videoView,
        'video': _videoUrl,
        'alt': 42,
      });

      expect(embed, isA<VideoPostEmbed>());

      final video = embed as VideoPostEmbed;
      expect(video.video, _videoUrl);
      expect(video.alt, isNull);
    });
  });

  group('PostEmbed.fromJson video record shape', () {
    test('treats the unhydrated video record as unknown', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.video,
        'video': _blobRef('bafyvideo'),
        'thumbnail': _blobRef('bafythumb'),
        'alt': 'A timelapse of the harbour',
        'duration': 42,
      });

      expect(embed, isA<UnknownPostEmbed>());
      expect(embed.type, EmbedTypes.video);
      expect(embed.external, isNull);
      expect(embed.blueskyPost, isNull);
    });

    test('treats a video record with a url string as unknown', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.video,
        'video': _videoUrl,
      });

      expect(embed, isA<UnknownPostEmbed>());
    });
  });

  group('PostEmbed bridge getters', () {
    test('are both null on an images embed', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.imagesView,
        'images': [
          {'thumb': _thumbUrl, 'fullsize': _fullUrl},
        ],
      });

      expect(embed, isA<ImagesPostEmbed>());
      expect(embed.external, isNull);
      expect(embed.blueskyPost, isNull);
    });

    test('are both null on a video embed', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.videoView,
        'video': _videoUrl,
      });

      expect(embed, isA<VideoPostEmbed>());
      expect(embed.external, isNull);
      expect(embed.blueskyPost, isNull);
    });

    test('are both null on an unknown embed', () {
      final embed = PostEmbed.fromJson({
        r'$type': 'social.coves.embed.somethingNew',
        'payload': {'a': 1},
      });

      expect(embed, isA<UnknownPostEmbed>());
      expect(embed.external, isNull);
      expect(embed.blueskyPost, isNull);
    });

    test('expose only the matching payload on external and quote embeds', () {
      final external = PostEmbed.fromJson({
        r'$type': EmbedTypes.externalView,
        'external': {'uri': 'https://example.com/article'},
      });
      final quote = PostEmbed.fromJson({
        r'$type': EmbedTypes.postView,
        'post': {
          'uri': 'at://did:plc:xyz/app.bsky.feed.post/abc',
          'cid': 'bafyrei123',
        },
      });

      expect(external.external, isNotNull);
      expect(external.blueskyPost, isNull);
      expect(quote.blueskyPost, isNotNull);
      expect(quote.external, isNull);
    });
  });

  group('PostEmbed legacy uri fallback', () {
    test('fires for a truly unknown type carrying a top-level uri', () {
      final embed = PostEmbed.fromJson({
        r'$type': 'social.coves.embed.somethingNew',
        'uri': 'https://example.com/bare-link',
        'title': 'Bare link',
      });

      expect(embed, isA<ExternalPostEmbed>());
      expect(embed.external!.uri, 'https://example.com/bare-link');
      expect(embed.external!.title, 'Bare link');
    });

    test('does not fire for a malformed images#view carrying a uri', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.imagesView,
        'uri': 'https://example.com/not-a-link-embed',
        'images': [
          {'image': _blobRef('bafyimage1')},
        ],
      });

      expect(embed, isA<UnknownPostEmbed>());
      expect(embed.external, isNull);
      expect(embed.type, EmbedTypes.imagesView);
    });

    test('does not fire for a malformed video#view carrying a uri', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.videoView,
        'uri': 'https://example.com/not-a-link-embed',
        'video': _blobRef('bafyvideo'),
      });

      expect(embed, isA<UnknownPostEmbed>());
      expect(embed.external, isNull);
    });

    test('does not fire for an images record carrying a uri', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.images,
        'uri': 'https://example.com/not-a-link-embed',
        'images': [
          {'image': _blobRef('bafyimage1')},
        ],
      });

      expect(embed, isA<UnknownPostEmbed>());
      expect(embed.external, isNull);
    });

    test('does not fire for a video record carrying a uri', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.video,
        'uri': 'https://example.com/not-a-link-embed',
        'video': _blobRef('bafyvideo'),
      });

      expect(embed, isA<UnknownPostEmbed>());
      expect(embed.external, isNull);
    });
  });

  group('PostEmbed.fromJson never throws', () {
    test('returns unknown for an unrecognized type with no uri', () {
      final embed = PostEmbed.fromJson({
        r'$type': 'social.coves.embed.somethingNew',
        'payload': {'a': 1},
      });

      expect(embed, isA<UnknownPostEmbed>());
      expect(embed.type, 'social.coves.embed.somethingNew');
      expect(embed.data['payload'], {'a': 1});
    });

    test('returns unknown with type "unknown" when the type is missing', () {
      final embed = PostEmbed.fromJson({'stray': 'value'});

      expect(embed, isA<UnknownPostEmbed>());
      expect(embed.type, 'unknown');
      expect(embed.data['stray'], 'value');
    });

    test('returns unknown for an empty map', () {
      final embed = PostEmbed.fromJson(<String, dynamic>{});

      expect(embed, isA<UnknownPostEmbed>());
      expect(embed.type, 'unknown');
      expect(embed.data, isEmpty);
    });

    test('returns unknown when a post embed is missing its post ref', () {
      late PostEmbed embed;

      expect(
        () => embed = PostEmbed.fromJson({r'$type': EmbedTypes.postView}),
        returnsNormally,
      );
      expect(embed, isA<UnknownPostEmbed>());
      expect(embed.blueskyPost, isNull);
    });

    test('preserves the raw json in data on a parsed variant', () {
      final json = <String, dynamic>{
        r'$type': EmbedTypes.videoView,
        'video': _videoUrl,
        'duration': 42,
      };
      final embed = PostEmbed.fromJson(json);

      expect(embed, isA<VideoPostEmbed>());
      expect(embed.data, same(json));
    });
  });

  group('H2 media url scheme allowlist', () {
    // The AppView's HydrateView no-ops on `#view` $types and the firehose
    // consumer stores embeds verbatim, so a federated repo can publish a
    // pre-stamped view carrying arbitrary URLs. The model is the last line
    // of defence: anything that is not a non-empty http(s) URI poisons the
    // whole embed, mirroring UrlLauncher's allowlist.
    const rejectedUrls = <String>[
      'file:///etc/passwd',
      'content://com.android.providers/media/1',
      'javascript:alert(1)',
      'data:image/png;base64,iVBORw0KGgo=',
      'ftp://cdn.test/f1.jpg',
      'at://did:plc:xyz/blob/bafy',
      '/relative/path.jpg',
      'cdn.test/no-scheme.jpg',
      '',
    ];

    test('rejects the embed when an image thumb is not http(s)', () {
      for (final url in rejectedUrls) {
        final embed = PostEmbed.fromJson({
          r'$type': EmbedTypes.imagesView,
          'images': [
            {'thumb': url, 'fullsize': 'https://cdn.test/f1.jpg'},
          ],
        });

        expect(embed, isA<UnknownPostEmbed>(), reason: 'thumb: "$url"');
        expect(embed.type, EmbedTypes.imagesView, reason: 'thumb: "$url"');
      }
    });

    test('rejects the embed when an image fullsize is not http(s)', () {
      for (final url in rejectedUrls) {
        final embed = PostEmbed.fromJson({
          r'$type': EmbedTypes.imagesView,
          'images': [
            {'thumb': 'https://cdn.test/t1.jpg', 'fullsize': url},
          ],
        });

        expect(embed, isA<UnknownPostEmbed>(), reason: 'fullsize: "$url"');
      }
    });

    test('rejects the whole gallery when only one entry is bad', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.imagesView,
        'images': [
          {'thumb': 'https://cdn.test/t1.jpg', 'fullsize': _fullUrl},
          {'thumb': 'https://cdn.test/t2.jpg', 'fullsize': _fullUrl},
          {'thumb': 'file:///etc/passwd', 'fullsize': _fullUrl},
        ],
      });

      expect(
        embed,
        isA<UnknownPostEmbed>(),
        reason: 'all-or-nothing: one hostile url poisons the gallery',
      );
    });

    test('accepts http and https image urls', () {
      const acceptedUrls = <String>[
        'https://cdn.test/f1.jpg',
        'http://cdn.test/f1.jpg',
        'HTTPS://cdn.test/f1.jpg',
        'https://cdn.test/f1.jpg?sig=abc&w=1600',
      ];

      for (final url in acceptedUrls) {
        final embed = PostEmbed.fromJson({
          r'$type': EmbedTypes.imagesView,
          'images': [
            {'thumb': url, 'fullsize': url},
          ],
        });

        expect(embed, isA<ImagesPostEmbed>(), reason: 'url: "$url"');
        expect(
          (embed as ImagesPostEmbed).images.single.thumb,
          url,
          reason: 'the url is preserved verbatim, not rewritten',
        );
      }
    });

    test('rejects the embed when the video url is not http(s)', () {
      for (final url in rejectedUrls) {
        final embed = PostEmbed.fromJson({
          r'$type': EmbedTypes.videoView,
          'video': url,
        });

        expect(embed, isA<UnknownPostEmbed>(), reason: 'video: "$url"');
        expect(embed.type, EmbedTypes.videoView, reason: 'video: "$url"');
      }
    });

    test('rejects the embed when a present thumbnail is not http(s)', () {
      for (final url in rejectedUrls) {
        final embed = PostEmbed.fromJson({
          r'$type': EmbedTypes.videoView,
          'video': _videoUrl,
          'thumbnail': url,
        });

        expect(embed, isA<UnknownPostEmbed>(), reason: 'thumbnail: "$url"');
      }
    });

    test('accepts a video with no thumbnail at all', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.videoView,
        'video': _videoUrl,
      });

      expect(embed, isA<VideoPostEmbed>());
      expect((embed as VideoPostEmbed).thumbnail, isNull);
    });

    test('accepts http and https video urls', () {
      const acceptedUrls = <String>[
        'https://cdn.test/video.mp4',
        'http://cdn.test/video.mp4',
      ];

      for (final url in acceptedUrls) {
        final embed = PostEmbed.fromJson({
          r'$type': EmbedTypes.videoView,
          'video': url,
          'thumbnail': url,
        });

        expect(embed, isA<VideoPostEmbed>(), reason: 'url: "$url"');
        expect((embed as VideoPostEmbed).video, url);
      }
    });

    test('still never throws on a hostile url', () {
      late PostEmbed embed;

      expect(
        () =>
            embed = PostEmbed.fromJson({
              r'$type': EmbedTypes.imagesView,
              'images': [
                {'thumb': 'ht tp://bad url', 'fullsize': _fullUrl},
              ],
            }),
        returnsNormally,
      );
      expect(embed, isA<UnknownPostEmbed>());
    });
  });

  group('H7 fromJson never throws on the legacy branches', () {
    // ExternalEmbed.fromJson and EmbedSource.fromJson are full of unchecked
    // casts. A federated record only has to disagree about one field's type
    // for a TypeError — an Error, not an Exception — to escape.

    test('degrades an external embed with no uri', () {
      late PostEmbed embed;

      expect(
        () =>
            embed = PostEmbed.fromJson({
              r'$type': EmbedTypes.externalView,
              'external': <String, dynamic>{},
            }),
        returnsNormally,
      );
      expect(embed, isA<UnknownPostEmbed>());
      expect(embed.external, isNull);
    });

    test('degrades an external embed whose fields have the wrong types', () {
      const hostileExternals = <Map<String, dynamic>>[
        {'uri': 42},
        {'uri': 'https://example.com/a', 'title': 42},
        {'uri': 'https://example.com/a', 'description': 42},
        {'uri': 'https://example.com/a', 'thumb': 42},
        {'uri': 'https://example.com/a', 'domain': 42},
        {'uri': 'https://example.com/a', 'totalCount': 'x'},
      ];

      for (final external in hostileExternals) {
        late PostEmbed embed;

        expect(
          () =>
              embed = PostEmbed.fromJson({
                r'$type': EmbedTypes.externalView,
                'external': external,
              }),
          returnsNormally,
          reason: 'external: $external',
        );
        expect(embed, isA<UnknownPostEmbed>(), reason: 'external: $external');
      }
    });

    test('degrades an external embed with a malformed source', () {
      late PostEmbed embed;

      expect(
        () =>
            embed = PostEmbed.fromJson({
              r'$type': EmbedTypes.externalView,
              'external': {
                'uri': 'https://example.com/megathread',
                'sources': [
                  {'uri': 'https://example.com/ok', 'title': 'Fine'},
                  {'title': 'No uri at all'},
                ],
              },
            }),
        returnsNormally,
        reason: 'EmbedSource.fromJson throws FormatException on a bad source',
      );
      expect(embed, isA<UnknownPostEmbed>());
    });

    test('degrades a legacy uri-fallback payload with a bad field', () {
      late PostEmbed embed;

      expect(
        () =>
            embed = PostEmbed.fromJson({
              r'$type': 'social.coves.embed.somethingNew',
              'uri': 'https://example.com/bare-link',
              'title': 42,
            }),
        returnsNormally,
        reason: 'the fallback branch casts just as unsafely as the typed one',
      );
      expect(embed, isA<UnknownPostEmbed>());
    });

    test('degrades a quote embed whose resolved post is not a map', () {
      late PostEmbed embed;

      expect(
        () =>
            embed = PostEmbed.fromJson({
              r'$type': EmbedTypes.postView,
              'post': {
                'uri': 'at://did:plc:xyz/app.bsky.feed.post/abc',
                'cid': 'bafyrei123',
              },
              'resolved': 'not-a-map',
            }),
        returnsNormally,
        reason: '`resolved as Map` throws TypeError past on FormatException',
      );
      expect(embed, isA<UnknownPostEmbed>());
    });
  });

  group('H7 TimelineResponse survives a hostile feed item', () {
    Map<String, dynamic> feedItem({Map<String, dynamic>? embed}) {
      return {
        'post': {
          'uri': 'at://did:example/post/123',
          'cid': 'cid123',
          'rkey': '123',
          'author': {'did': 'did:plc:author', 'handle': 'author.test'},
          'community': {'did': 'did:plc:community', 'name': 'test-community'},
          'createdAt': '2024-01-01T00:00:00.000Z',
          'indexedAt': '2024-01-01T00:00:00.000Z',
          'stats': {
            'upvotes': 0,
            'downvotes': 0,
            'score': 0,
            'commentCount': 0,
          },
          if (embed != null) 'embed': embed,
        },
      };
    }

    test('keeps the good post when a sibling embed is hostile', () {
      late TimelineResponse response;

      expect(
        () =>
            response = TimelineResponse.fromJson({
              'feed': [
                feedItem(),
                feedItem(
                  embed: {
                    r'$type': EmbedTypes.externalView,
                    'external': {'uri': 42},
                  },
                ),
              ],
            }),
        returnsNormally,
        reason: 'one hostile federated record must not blank the feed',
      );
      expect(
        response.feed,
        hasLength(greaterThanOrEqualTo(1)),
        reason: 'the valid post survives whatever happens to its neighbour',
      );
    });

    test('treats a non-list feed as empty', () {
      late TimelineResponse response;

      expect(
        () => response = TimelineResponse.fromJson({'feed': 'not-a-list'}),
        returnsNormally,
      );
      expect(response.feed, isEmpty);
    });

    test('skips a non-map feed item', () {
      late TimelineResponse response;

      expect(
        () =>
            response = TimelineResponse.fromJson({
              'feed': ['not-a-map', feedItem()],
            }),
        returnsNormally,
      );
      expect(response.feed, hasLength(1));
    });

    test('preserves the cursor alongside a hostile item', () {
      late TimelineResponse response;

      expect(
        () =>
            response = TimelineResponse.fromJson({
              'feed': [
                feedItem(
                  embed: {
                    r'$type': EmbedTypes.postView,
                    'post': {'uri': 'at://x/y/z', 'cid': 'c'},
                    'resolved': 'not-a-map',
                  },
                ),
              ],
              'cursor': 'next-page',
            }),
        returnsNormally,
      );
      expect(response.cursor, 'next-page');
    });

    test('treats a non-String cursor as absent rather than throwing', () {
      late TimelineResponse response;

      expect(
        () => response = TimelineResponse.fromJson({'feed': [], 'cursor': 42}),
        returnsNormally,
      );
      expect(response.cursor, isNull);
    });
  });

  group('H8 release-mode invariants', () {
    test('ImagesPostEmbed rejects an empty image list', () {
      expect(
        () => ImagesPostEmbed(
          type: EmbedTypes.imagesView,
          images: const [],
          data: const {},
        ),
        throwsArgumentError,
        reason: 'asserts are stripped in release; this must always throw',
      );
    });

    test('EmbedAspectRatio rejects dimensions below 1', () {
      expect(() => EmbedAspectRatio(width: 0, height: 2), throwsArgumentError);
      expect(() => EmbedAspectRatio(width: 3, height: 0), throwsArgumentError);
      expect(() => EmbedAspectRatio(width: -3, height: 2), throwsArgumentError);
    });

    test('a parsed images list cannot be mutated', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.imagesView,
        'images': [
          {'thumb': _thumbUrl, 'fullsize': _fullUrl},
        ],
      });

      expect(embed, isA<ImagesPostEmbed>());
      expect(
        () => (embed as ImagesPostEmbed).images.clear(),
        throwsUnsupportedError,
      );
    });
  });

  group('H9 media urls need a real host', () {
    const hostlessUrls = <String>[
      'http:foo',
      'https:///path.jpg',
      'http://',
      'https://',
    ];

    test('rejects an image whose url has no authority', () {
      for (final url in hostlessUrls) {
        final embed = PostEmbed.fromJson({
          r'$type': EmbedTypes.imagesView,
          'images': [
            {'thumb': url, 'fullsize': _fullUrl},
          ],
        });

        expect(embed, isA<UnknownPostEmbed>(), reason: 'thumb: "$url"');
      }
    });

    test('rejects a fullsize whose url has no authority', () {
      for (final url in hostlessUrls) {
        final embed = PostEmbed.fromJson({
          r'$type': EmbedTypes.imagesView,
          'images': [
            {'thumb': _thumbUrl, 'fullsize': url},
          ],
        });

        expect(embed, isA<UnknownPostEmbed>(), reason: 'fullsize: "$url"');
      }
    });

    test('rejects a video whose url has no authority', () {
      for (final url in hostlessUrls) {
        final embed = PostEmbed.fromJson({
          r'$type': EmbedTypes.videoView,
          'video': url,
        });

        expect(embed, isA<UnknownPostEmbed>(), reason: 'video: "$url"');
      }
    });
  });

  group('H10 anti-DoS caps', () {
    List<Map<String, dynamic>> gallery(int count) {
      return List.generate(
        count,
        (index) => {
          'thumb': 'https://cdn.test/t$index.jpg',
          'fullsize': 'https://cdn.test/f$index.jpg',
        },
      );
    }

    test('accepts the lexicon maximum of 8 images', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.imagesView,
        'images': gallery(8),
      });

      expect(embed, isA<ImagesPostEmbed>());
      expect((embed as ImagesPostEmbed).images, hasLength(8));
    });

    test('rejects a gallery of 9 images outright', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.imagesView,
        'images': gallery(9),
      });

      expect(
        embed,
        isA<UnknownPostEmbed>(),
        reason: 'the appview never serves >8, so >8 is a hostile record',
      );
    });

    test('rejects an absurd gallery without hanging', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.imagesView,
        'images': gallery(5000),
      });

      expect(embed, isA<UnknownPostEmbed>());
    });

    test('truncates an oversized image alt to 10000 chars', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.imagesView,
        'images': [
          {'thumb': _thumbUrl, 'fullsize': _fullUrl, 'alt': 'a' * 20000},
        ],
      });

      expect(embed, isA<ImagesPostEmbed>());
      expect((embed as ImagesPostEmbed).images.single.alt, hasLength(10000));
    });

    test('truncates an oversized video alt to 10000 chars', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.videoView,
        'video': _videoUrl,
        'alt': 'a' * 20000,
      });

      expect(embed, isA<VideoPostEmbed>());
      expect((embed as VideoPostEmbed).alt, hasLength(10000));
    });

    test('leaves an alt at the limit untouched', () {
      final alt = 'a' * 10000;
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.imagesView,
        'images': [
          {'thumb': _thumbUrl, 'fullsize': _fullUrl, 'alt': alt},
        ],
      });

      expect(embed, isA<ImagesPostEmbed>());
      expect((embed as ImagesPostEmbed).images.single.alt, alt);
    });
  });

  group('PostEmbed sealed union', () {
    test('supports an exhaustive switch over all five variants', () {
      final embeds = <PostEmbed>[
        PostEmbed.fromJson({
          r'$type': EmbedTypes.imagesView,
          'images': [
            {'thumb': _thumbUrl, 'fullsize': _fullUrl},
            {'thumb': _thumbUrl, 'fullsize': _fullUrl},
          ],
        }),
        PostEmbed.fromJson({
          r'$type': EmbedTypes.videoView,
          'video': _videoUrl,
        }),
        PostEmbed.fromJson({
          r'$type': EmbedTypes.externalView,
          'external': {'uri': 'https://example.com/article'},
        }),
        PostEmbed.fromJson({
          r'$type': EmbedTypes.postView,
          'post': {
            'uri': 'at://did:plc:xyz/app.bsky.feed.post/abc',
            'cid': 'bafyrei123',
          },
        }),
        PostEmbed.fromJson({r'$type': 'social.coves.embed.somethingNew'}),
      ];

      expect(embeds.map(_describeEmbed).toList(), [
        'images:2',
        'video:$_videoUrl',
        'external',
        'quote',
        'unknown',
      ]);
    });
  });
}

/// Exhaustive switch over the sealed [PostEmbed] hierarchy.
///
/// This deliberately omits a default clause: it only compiles while
/// [PostEmbed] is sealed and these five variants are its only subtypes.
String _describeEmbed(PostEmbed embed) => switch (embed) {
  ImagesPostEmbed(:final images) => 'images:${images.length}',
  VideoPostEmbed(:final video) => 'video:$video',
  ExternalPostEmbed() => 'external',
  QuotePostEmbed() => 'quote',
  UnknownPostEmbed() => 'unknown',
};

/// An atproto blob reference, as served when appview hydration fails.
Map<String, dynamic> _blobRef(String link) => {
  r'$type': 'blob',
  'ref': {r'$link': link},
  'mimeType': 'image/jpeg',
  'size': 123456,
};
