import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/models/post_embed_input.dart';
import 'package:flutter_test/flutter_test.dart';

/// buildPostEmbed for every row of the PRD_IMAGES_MOBILE §3.4 table.
void main() {
  group('buildPostEmbed', () {
    // Blob refs as uploadImage returns them, including a key the client
    // does not know about, which must pass through unchanged.
    Map<String, dynamic> blobA() => <String, dynamic>{
      r'$type': 'blob',
      'ref': <String, dynamic>{
        r'$link': 'bafkreiaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      },
      'mimeType': 'image/jpeg',
      'size': 482113,
    };
    Map<String, dynamic> blobB() => <String, dynamic>{
      r'$type': 'blob',
      'ref': <String, dynamic>{
        r'$link': 'bafkreibbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      },
      'mimeType': 'image/gif',
      'size': 90210,
      'futureField': 'kept',
    };

    List<EmbedImageInput> twoImages() => [
      EmbedImageInput(
        blob: blobA(),
        aspectRatio: EmbedAspectRatio(width: 1200, height: 800),
      ),
      EmbedImageInput(blob: blobB(), alt: 'A cat on a keyboard'),
    ];

    ExternalEmbedInput link() => ExternalEmbedInput(
      uri: 'https://example.com/article',
      title: 'An article',
    );

    const externalJson = <String, dynamic>{
      r'$type': 'social.coves.embed.external',
      'external': {'uri': 'https://example.com/article', 'title': 'An article'},
    };

    const imagesJson = <String, dynamic>{
      r'$type': 'social.coves.embed.images',
      'images': [
        {
          'image': {
            r'$type': 'blob',
            'ref': {
              r'$link':
                  'bafkreiaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            },
            'mimeType': 'image/jpeg',
            'size': 482113,
          },
          'aspectRatio': {'width': 1200, 'height': 800},
        },
        {
          'image': {
            r'$type': 'blob',
            'ref': {
              r'$link':
                  'bafkreibbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            },
            'mimeType': 'image/gif',
            'size': 90210,
            'futureField': 'kept',
          },
          'alt': 'A cat on a keyboard',
        },
      ],
    };

    final rows =
        <
          ({
            String name,
            PostEmbedInput? Function() build,
            Map<String, dynamic>? expected,
          })
        >[
          (
            name: '0 images, no URL: no embed',
            build: buildPostEmbed,
            expected: null,
          ),
          (
            name: '0 images, URL: embed.external exactly as today',
            build: () => buildPostEmbed(external: link()),
            expected: externalJson,
          ),
          (
            name: '2 images, no URL: embed.images',
            build: () => buildPostEmbed(images: twoImages()),
            expected: imagesJson,
          ),
          (
            name: '2 images, URL: embed.imagesWithAttachment',
            build: () => buildPostEmbed(images: twoImages(), external: link()),
            expected: <String, dynamic>{
              r'$type': 'social.coves.embed.imagesWithAttachment',
              'images': imagesJson,
              'attachment': externalJson,
            },
          ),
        ];

    for (final row in rows) {
      test(row.name, () {
        final embed = row.build();

        if (row.expected == null) {
          expect(embed, isNull);
        } else {
          expect(embed?.toJson(), row.expected);
        }
      });
    }
  });
}
