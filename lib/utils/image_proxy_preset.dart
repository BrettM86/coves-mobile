/// The path segment the AppView's image proxy uses for list-size avatars.
/// Feed, comment, notification and community-list views carry these, sized
/// for avatars drawn at list size.
const _listAvatarSegment = '/img/avatar_small/plain/';

/// The path segment of the full-size avatar preset (1000px).
const _fullAvatarSegment = '/img/avatar/plain/';

/// Returns the full-size version of a list-size proxy avatar URL, for a
/// screen that draws a list view's avatar larger than about 64 logical
/// pixels. Any other URL, including Bluesky CDN avatars, is returned as is.
String? fullSizeAvatarUrl(String? url) {
  if (url == null || !url.contains(_listAvatarSegment)) {
    return url;
  }
  return url.replaceFirst(_listAvatarSegment, _fullAvatarSegment);
}
