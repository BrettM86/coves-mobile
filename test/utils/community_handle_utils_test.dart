import 'package:coves_flutter/utils/community_handle_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommunityHandleUtils.resolveDisplayHandle', () {
    group('origin precedence', () {
      test('uses origin when present, ignoring the handle', () {
        final result = CommunityHandleUtils.resolveDisplayHandle(
          name: 'comicstrips',
          origin: 'lemmy.world',
          handle: 'comicstrips.lemmy-world.tdpl.io',
        );
        expect(
          result,
          const CommunityDisplayHandle(
            name: 'comicstrips',
            instance: 'lemmy.world',
          ),
        );
        expect(result.toString(), '!comicstrips@lemmy.world');
      });

      test('uses origin with no handle at all', () {
        expect(
          CommunityHandleUtils.resolveDisplayHandle(
            name: 'nba',
            origin: 'coves.social',
          ).toString(),
          '!nba@coves.social',
        );
      });

      test('treats empty origin as absent and derives from handle', () {
        expect(
          CommunityHandleUtils.resolveDisplayHandle(
            name: 'gaming',
            origin: '',
            handle: 'c-gaming.coves.social',
          ).toString(),
          '!gaming@coves.social',
        );
      });
    });

    group('handle fallback', () {
      test('derives from new c- DNS format', () {
        expect(
          CommunityHandleUtils.resolveDisplayHandle(
            name: 'gaming',
            handle: 'c-gaming.coves.social',
          ),
          const CommunityDisplayHandle(
            name: 'gaming',
            instance: 'coves.social',
          ),
        );
      });

      test('derives from legacy .community. DNS format', () {
        expect(
          CommunityHandleUtils.resolveDisplayHandle(
            name: 'gaming',
            handle: 'gaming.community.coves.social',
          ),
          const CommunityDisplayHandle(
            name: 'gaming',
            instance: 'coves.social',
          ),
        );
      });

      test('handles multi-part instance domains', () {
        expect(
          CommunityHandleUtils.resolveDisplayHandle(
            name: 'tech',
            handle: 'tech.community.test.coves.social',
          ).toString(),
          '!tech@test.coves.social',
        );
        expect(
          CommunityHandleUtils.resolveDisplayHandle(
            name: 'tech',
            handle: 'c-tech.test.coves.social',
          ).toString(),
          '!tech@test.coves.social',
        );
      });

      test('handles hyphenated community names', () {
        expect(
          CommunityHandleUtils.resolveDisplayHandle(
            name: 'world-news',
            handle: 'world-news.community.coves.social',
          ).toString(),
          '!world-news@coves.social',
        );
      });

      test('derives from a four-label Tidepool-bridged handle', () {
        expect(
          CommunityHandleUtils.resolveDisplayHandle(
            name: 'comicstrips',
            handle: 'comicstrips.lemmy-world.tdpl.io',
          ),
          const CommunityDisplayHandle(
            name: 'comicstrips',
            instance: 'lemmy-world.tdpl.io',
          ),
        );
      });

      test('does not apply the tdpl.io rule to other label counts', () {
        expect(
          CommunityHandleUtils.resolveDisplayHandle(
            name: 'x',
            handle: 'a.b.c.tdpl.io',
          ),
          null,
        );
        expect(
          CommunityHandleUtils.resolveDisplayHandle(
            name: 'x',
            handle: 'a.tdpl.io',
          ),
          null,
        );
      });
    });

    group('null cases', () {
      test('returns null with no origin and no handle', () {
        expect(CommunityHandleUtils.resolveDisplayHandle(name: 'gaming'), null);
      });

      test('returns null for empty handle', () {
        expect(
          CommunityHandleUtils.resolveDisplayHandle(name: 'gaming', handle: ''),
          null,
        );
      });

      test('returns null for unrecognised handle formats', () {
        for (final handle in const [
          'gaming.coves.social',
          'gaming.community',
          'gaming.other.coves.social',
          'c-gaming.social',
        ]) {
          expect(
            CommunityHandleUtils.resolveDisplayHandle(
              name: 'gaming',
              handle: handle,
            ),
            null,
            reason: handle,
          );
        }
      });
    });
  });

  group('CommunityDisplayHandle', () {
    test('exposes prefixed parts', () {
      const handle = CommunityDisplayHandle(
        name: 'nba',
        instance: 'coves.social',
      );
      expect(handle.namePart, '!nba');
      expect(handle.instancePart, '@coves.social');
      expect(handle.toString(), '!nba@coves.social');
    });
  });
}
