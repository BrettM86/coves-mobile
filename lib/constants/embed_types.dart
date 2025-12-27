/// Constants for Coves embed type identifiers.
///
/// These type strings are used in the $type field of embed objects
/// to identify the kind of embedded content in posts.
class EmbedTypes {
  EmbedTypes._();

  /// External link embed (URLs, articles, etc.)
  static const external = 'social.coves.embed.external';

  /// Embedded Bluesky post
  static const post = 'social.coves.embed.post';
}
