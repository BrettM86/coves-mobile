import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../models/post.dart';

/// The `/post/:postUri` route extra for in-app navigation: the post to show
/// and the session key it was loaded under.
class PostDetailRouteExtra {
  const PostDetailRouteExtra({
    required this.post,
    required this.sessionStamp,
    this.initialImageIndex = 0,
  });

  final FeedViewPost post;

  /// The session the opening surface loaded [post] under; null denies admin
  /// tools.
  final Object? sessionStamp;

  /// The gallery page the opening surface was showing, so the detail view
  /// opens on the same image.
  final int initialImageIndex;
}

/// Opens [post]'s detail, handing it over with the session it was loaded
/// under.
void pushPostDetail(
  BuildContext context, {
  required FeedViewPost post,
  required Object? sessionStamp,
  int initialImageIndex = 0,
}) {
  final encodedUri = Uri.encodeComponent(post.post.uri);
  context.push(
    '/post/$encodedUri',
    extra: PostDetailRouteExtra(
      post: post,
      sessionStamp: sessionStamp,
      initialImageIndex: initialImageIndex,
    ),
  );
}
