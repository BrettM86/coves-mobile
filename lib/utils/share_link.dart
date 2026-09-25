import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../services/link_sharer.dart';

/// Hands [url] to the ambient [LinkSharer] and reports the two ways that
/// fails: no link could be built, or the share itself did not go through.
///
/// [sharePositionOrigin] is the global rect of the control the share started
/// from, which iPad anchors the share popover to. Every share action shares
/// this one implementation so the surfaces cannot drift apart.
Future<void> shareLinkFrom(
  BuildContext context,
  String? url,
  Rect sharePositionOrigin,
) {
  // Do not hold the share sheet behind non-essential haptics: the reply only
  // ever confirms a buzz, and where no platform answers it never arrives at
  // all.
  HapticFeedback.lightImpact().ignore();

  if (url == null) {
    _showFailure(context, "Couldn't create link");
    return Future<void>.value();
  }

  // Looked up here rather than while building: call sites that are never
  // tapped must not require a LinkSharer above them. Synchronously, ahead of
  // the dispatch, so a screen that forgot the provider throws out of the tap
  // it happened on — a wiring mistake, not a share that failed, and reporting
  // it as one would leave the button permanently dead with nothing pointing
  // at the cause.
  final sharer = context.read<LinkSharer>();

  return _dispatchShare(context, sharer, url, sharePositionOrigin);
}

/// Awaits the share and turns the one failure the platform is entitled to
/// into a message for the viewer.
Future<void> _dispatchShare(
  BuildContext context,
  LinkSharer sharer,
  String url,
  Rect sharePositionOrigin,
) async {
  try {
    await sharer.shareLink(url, sharePositionOrigin: sharePositionOrigin);
  } on PlatformException catch (e, stackTrace) {
    await Sentry.captureException(e, stackTrace: stackTrace);
    // The share sheet outlives the control that opened it when the screen
    // goes away, so the failure can arrive with nowhere left to report it.
    if (context.mounted) {
      _showFailure(context, "Couldn't share link");
    }
  } on Object catch (error, stackTrace) {
    // Anything but the platform channel is a bug in the sharer rather than a
    // share that did not go through, so it is not reported to the viewer as
    // one. A tap handler's future has no caller to throw back to, and an
    // error left unhandled there is only whatever the embedder does with it,
    // so it is handed to the framework's error handler instead — the app's
    // one path for a bug it did not expect, and where crash reporting
    // listens.
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'coves share link',
        context: ErrorDescription('sharing a link'),
      ),
    );
  }
}

/// The global bounds of the widget [context] is mounted under, which iPad
/// anchors a share popover to, or [Rect.zero] when there is nothing to
/// measure.
///
/// A [GlobalKey]'s context is null once its widget leaves the tree, and an
/// overlaid menu outlives the card that opened it. A share sheet in the
/// middle of the screen beats a crash.
Rect globalRectOf(BuildContext? context) {
  final renderObject = context?.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.hasSize) {
    return Rect.zero;
  }
  return renderObject.localToGlobal(Offset.zero) & renderObject.size;
}

void _showFailure(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
