import 'package:flutter/foundation.dart';

import '../models/post.dart';

sealed class PostChange {
  const PostChange();
}

final class PostRemoved extends PostChange {
  const PostRemoved(this.uri);

  final String uri;
}

final class PostReplaced extends PostChange {
  const PostReplaced(this.post);

  final PostView post;
}

typedef PostChangeListener = void Function(PostChange change);

class PostChangeBroadcast {
  final List<PostChangeListener> _listeners = [];

  void removePost(String uri) => _dispatch(PostRemoved(uri));

  void replacePost(PostView post) => _dispatch(PostReplaced(post));

  void addPostChangeListener(PostChangeListener listener) {
    _listeners.add(listener);
  }

  void removePostChangeListener(PostChangeListener listener) {
    _listeners.remove(listener);
  }

  void _dispatch(PostChange change) {
    // Copied so a listener may remove itself while being notified. A
    // throwing listener is reported and must not stop the ones after it.
    for (final listener in List<PostChangeListener>.of(_listeners)) {
      try {
        listener(change);
      } on Object catch (error, stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'post change broadcast',
            context: ErrorDescription('while notifying a post change listener'),
          ),
        );
      }
    }
  }
}
