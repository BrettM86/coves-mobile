import 'package:coves_flutter/utils/image_proxy_preset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fullSizeAvatarUrl', () {
    test('swaps the list-size preset for the full avatar preset', () {
      expect(
        fullSizeAvatarUrl(
          'https://img.coves.social/img/avatar_small/plain/did:plc:abc/bafkreicid',
        ),
        'https://img.coves.social/img/avatar/plain/did:plc:abc/bafkreicid',
      );
    });

    test('leaves a URL that is not a list-size proxy avatar unchanged', () {
      for (final url in [
        'https://img.coves.social/img/avatar/plain/did:plc:abc/bafkreicid',
        'https://cdn.bsky.app/img/avatar_thumbnail/plain/did:plc:abc/cid@jpeg',
        'https://example.com/avatar_small/plain/x',
      ]) {
        expect(fullSizeAvatarUrl(url), url);
      }
    });

    test('passes null through', () {
      expect(fullSizeAvatarUrl(null), isNull);
    });
  });
}
