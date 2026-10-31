import 'package:flutter/foundation.dart';

import '../models/comment.dart';

typedef CommentChangeListener = void Function(CommentView comment);

/// App-owned channel that carries a saved comment edit to every provider
/// holding a copy of that comment (post threads, profile lists).
class CommentChangeBroadcast {
  final List<CommentChangeListener> _listeners = [];

  void replaceComment(CommentView comment) => _dispatch(comment);

  void addCommentChangeListener(CommentChangeListener listener) {
    _listeners.add(listener);
  }

  void removeCommentChangeListener(CommentChangeListener listener) {
    _listeners.remove(listener);
  }

  void _dispatch(CommentView comment) {
    // Copied so a listener may remove itself while being notified. A
    // throwing listener is reported and must not stop the ones after it.
    for (final listener in List<CommentChangeListener>.of(_listeners)) {
      try {
        listener(comment);
      } on Object catch (error, stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'comment change broadcast',
            context: ErrorDescription(
              'while notifying a comment change listener',
            ),
          ),
        );
      }
    }
  }
}
