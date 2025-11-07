import 'package:coves_flutter/utils/community_handle_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommunityHandleUtils', () {
    group('formatHandleForDisplay', () {
      test('converts DNS format to display format', () {
        expect(
          CommunityHandleUtils.formatHandleForDisplay(
            'gaming.community.coves.social',
          ),
          '!gaming@coves.social',
        );
      });

      test('handles multi-part instance domains', () {
        expect(
          CommunityHandleUtils.formatHandleForDisplay(
            'tech.community.test.coves.social',
          ),
          '!tech@test.coves.social',
        );
      });

      test('handles hyphenated community names', () {
        expect(
          CommunityHandleUtils.formatHandleForDisplay(
            'world-news.community.coves.social',
          ),
          '!world-news@coves.social',
        );
      });

      test('returns null for null input', () {
        expect(CommunityHandleUtils.formatHandleForDisplay(null), null);
      });

      test('returns null for empty string', () {
        expect(CommunityHandleUtils.formatHandleForDisplay(''), null);
      });

      test('returns null for invalid format (missing .community.)', () {
        expect(
          CommunityHandleUtils.formatHandleForDisplay('gaming.coves.social'),
          null,
        );
      });

      test('returns null for too few parts', () {
        expect(
          CommunityHandleUtils.formatHandleForDisplay('gaming.community'),
          null,
        );
      });

      test('returns null if second part is not "community"', () {
        expect(
          CommunityHandleUtils.formatHandleForDisplay(
            'gaming.other.coves.social',
          ),
          null,
        );
      });
    });

    group('formatHandleForDNS', () {
      test('converts display format to DNS format', () {
        expect(
          CommunityHandleUtils.formatHandleForDNS('!gaming@coves.social'),
          'gaming.community.coves.social',
        );
      });

      test('handles handles without leading !', () {
        expect(
          CommunityHandleUtils.formatHandleForDNS('gaming@coves.social'),
          'gaming.community.coves.social',
        );
      });

      test('handles multi-part instance domains', () {
        expect(
          CommunityHandleUtils.formatHandleForDNS('!tech@test.coves.social'),
          'tech.community.test.coves.social',
        );
      });

      test('handles hyphenated community names', () {
        expect(
          CommunityHandleUtils.formatHandleForDNS('!world-news@coves.social'),
          'world-news.community.coves.social',
        );
      });

      test('returns null for null input', () {
        expect(CommunityHandleUtils.formatHandleForDNS(null), null);
      });

      test('returns null for empty string', () {
        expect(CommunityHandleUtils.formatHandleForDNS(''), null);
      });

      test('returns null for invalid format (no @)', () {
        expect(CommunityHandleUtils.formatHandleForDNS('!gaming'), null);
      });

      test('returns null for multiple @ symbols', () {
        expect(
          CommunityHandleUtils.formatHandleForDNS('!gaming@coves@social'),
          null,
        );
      });
    });

    group('round-trip conversions', () {
      test('DNS → display → DNS preserves value', () {
        const original = 'gaming.community.coves.social';
        final display = CommunityHandleUtils.formatHandleForDisplay(original);
        final dnsFormat = CommunityHandleUtils.formatHandleForDNS(display);
        expect(dnsFormat, original);
      });

      test('display → DNS → display preserves value', () {
        const original = '!gaming@coves.social';
        final dnsFormat = CommunityHandleUtils.formatHandleForDNS(original);
        final display = CommunityHandleUtils.formatHandleForDisplay(dnsFormat);
        expect(display, original);
      });
    });
  });
}
