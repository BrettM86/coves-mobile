import 'dart:ui';

import 'package:share_plus/share_plus.dart';

/// Dispatches a link to the platform share sheet.
///
/// Provided through the widget tree so tests can record share calls instead
/// of opening a native sheet.
abstract interface class LinkSharer {
  /// Shares [url], anchoring the sheet at [sharePositionOrigin] (iPad).
  Future<void> shareLink(String url, {required Rect sharePositionOrigin});
}

/// The [LinkSharer] the app runs on: the platform share sheet via share_plus.
///
/// Shares the URL as a `uri` and nothing else, so iOS can fetch link metadata
/// for the preview instead of showing a bare string. A dismissed sheet is a
/// normal completion; a platform failure propagates to the caller.
class SharePlusLinkSharer implements LinkSharer {
  const SharePlusLinkSharer();

  @override
  Future<void> shareLink(
    String url, {
    required Rect sharePositionOrigin,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        uri: Uri.parse(url),
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }
}
