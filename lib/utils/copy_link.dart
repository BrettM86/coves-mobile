import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Copies a web link to the clipboard and reports the outcome in a snackbar.
///
/// [url] is null when no canonical link could be built for the subject; the
/// clipboard is then left untouched. Every "Copy link" action shares this one
/// implementation so the surfaces cannot drift apart.
Future<void> copyLinkToClipboard(BuildContext context, String? url) async {
  final messenger = ScaffoldMessenger.of(context);

  if (url == null) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text("Couldn't create link"),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }

  try {
    await Clipboard.setData(ClipboardData(text: url));
  } on PlatformException {
    if (context.mounted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Failed to copy link to clipboard'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return;
  }

  if (context.mounted) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Link copied to clipboard'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
