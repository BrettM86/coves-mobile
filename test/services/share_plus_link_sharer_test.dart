import 'package:coves_flutter/services/link_sharer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

/// Records the [ShareParams] share_plus hands to the platform.
///
/// One instance is reused for the whole file: `SharePlus.instance` is a lazy
/// `static final` that captures whichever [SharePlatform] is installed when it
/// is first read, so a fresh fake per test would be ignored after the first.
class RecordingSharePlatform extends SharePlatform {
  final List<ShareParams> calls = <ShareParams>[];

  ShareResult resultToReturn = const ShareResult(
    'com.example.share',
    ShareResultStatus.success,
  );

  Exception? errorToThrow;

  @override
  Future<ShareResult> share(ShareParams params) async {
    calls.add(params);
    final error = errorToThrow;
    if (error != null) {
      throw error;
    }
    return resultToReturn;
  }
}

void main() {
  final recordingPlatform = RecordingSharePlatform();
  final originalPlatform = SharePlatform.instance;

  setUp(() {
    recordingPlatform
      ..calls.clear()
      ..errorToThrow = null
      ..resultToReturn = const ShareResult(
        'com.example.share',
        ShareResultStatus.success,
      );
    SharePlatform.instance = recordingPlatform;
  });

  tearDown(() {
    SharePlatform.instance = originalPlatform;
  });

  group('SharePlusLinkSharer', () {
    test('shares the URL once as a uri, anchored at the given rect', () async {
      const sharer = SharePlusLinkSharer();

      await sharer.shareLink(
        'https://coves.social/c/gaming',
        sharePositionOrigin: const Rect.fromLTWH(10, 20, 30, 40),
      );

      expect(recordingPlatform.calls, hasLength(1));
      final params = recordingPlatform.calls.single;
      expect(params.uri, Uri.parse('https://coves.social/c/gaming'));
      expect(params.sharePositionOrigin, const Rect.fromLTWH(10, 20, 30, 40));
      // URL only: no title, subject or extra text alongside the link.
      expect(params.text, isNull);
      expect(params.title, isNull);
      expect(params.subject, isNull);
      expect(params.files, isNull);
    });

    test('completes normally when the user dismisses the sheet', () async {
      recordingPlatform.resultToReturn = const ShareResult(
        '',
        ShareResultStatus.dismissed,
      );
      const sharer = SharePlusLinkSharer();

      await expectLater(
        sharer.shareLink(
          'https://coves.social/c/gaming',
          sharePositionOrigin: Rect.zero,
        ),
        completes,
      );
    });

    test('lets a platform failure propagate to the caller', () async {
      recordingPlatform.errorToThrow = PlatformException(code: 'share_failed');
      const sharer = SharePlusLinkSharer();

      await expectLater(
        sharer.shareLink(
          'https://coves.social/c/gaming',
          sharePositionOrigin: Rect.zero,
        ),
        throwsA(isA<PlatformException>()),
      );
    });
  });
}
