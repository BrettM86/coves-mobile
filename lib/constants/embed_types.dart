/// Constants for Coves embed type identifiers.
///
/// These type strings are used in the $type field of embed objects
/// to identify the kind of embedded content in posts.
class EmbedTypes {
  EmbedTypes._();

  /// External link embed (URLs, articles, etc.)
  static const external = 'social.coves.embed.external';

  /// External link embed as served by the appview (thumb resolved to a URL).
  static const externalView = 'social.coves.embed.external#view';

  /// Embedded Bluesky post
  static const post = 'social.coves.embed.post';

  /// Embedded Bluesky post as served by the appview (with resolved data).
  static const postView = 'social.coves.embed.post#view';

  /// Image gallery record (unhydrated: carries atproto blob refs).
  static const images = 'social.coves.embed.images';

  /// Image gallery as served by the appview (blobs resolved to URLs).
  static const imagesView = 'social.coves.embed.images#view';

  /// Video record (unhydrated: carries atproto blob refs).
  static const video = 'social.coves.embed.video';

  /// Video as served by the appview (blobs resolved to URLs).
  static const videoView = 'social.coves.embed.video#view';
}
