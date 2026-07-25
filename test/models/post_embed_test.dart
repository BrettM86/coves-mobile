import 'package:coves_flutter/constants/embed_types.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:flutter_test/flutter_test.dart';

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

      expect(embed.external, isNotNull);
      expect(embed.external!.uri, 'https://example.com/article');
      expect(embed.blueskyPost, isNull);
    });

    test('parses view-form external embed served by the appview', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.externalView,
        ...externalPayload,
      });

      expect(embed.external, isNotNull);
      expect(embed.external!.uri, 'https://example.com/article');
      expect(embed.external!.thumb, contains('getBlob'));
      expect(embed.blueskyPost, isNull);
    });

    test('parses record-form post embed', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.post,
        ...postPayload,
      });

      expect(embed.blueskyPost, isNotNull);
      expect(embed.blueskyPost!.uri, 'at://did:plc:xyz/app.bsky.feed.post/abc');
      expect(embed.external, isNull);
    });

    test('parses view-form post embed served by the appview', () {
      final embed = PostEmbed.fromJson({
        r'$type': EmbedTypes.postView,
        ...postPayload,
      });

      expect(embed.blueskyPost, isNotNull);
      expect(embed.blueskyPost!.uri, 'at://did:plc:xyz/app.bsky.feed.post/abc');
      expect(embed.external, isNull);
    });

    test('falls back to external for unrecognized type with top-level uri', () {
      final embed = PostEmbed.fromJson({
        r'$type': 'social.coves.embed.unknown',
        'uri': 'https://example.com/bare-link',
      });

      expect(embed.external, isNotNull);
      expect(embed.external!.uri, 'https://example.com/bare-link');
    });
  });
}
