// Embed inputs for creating posts.
//
// POST /xrpc/social.coves.community.post.create takes one of these as
// `embed`.

import '../constants/embed_types.dart';
import '../utils/url_policy.dart';
import 'post.dart';

/// An embed written into a new post record.
sealed class PostEmbedInput {
  Map<String, dynamic> toJson();
}

/// External link embed input for creating posts
class ExternalEmbedInput implements PostEmbedInput {
  /// Creates an [ExternalEmbedInput] with URI validation.
  ///
  /// Throws [ArgumentError] if [uri] is empty or not a valid URL.
  factory ExternalEmbedInput({
    required String uri,
    String? title,
    String? description,
  }) {
    // Validate URI is not empty
    if (uri.isEmpty) {
      throw ArgumentError.value(uri, 'uri', 'URI cannot be empty');
    }

    // Validate URI is a well-formed URL
    if (!isAllowedWebUrl(uri)) {
      throw ArgumentError.value(
        uri,
        'uri',
        'URI must be a valid HTTP or HTTPS URL',
      );
    }

    return ExternalEmbedInput._(
      uri: uri,
      title: title,
      description: description,
    );
  }

  const ExternalEmbedInput._({required this.uri, this.title, this.description});

  @override
  Map<String, dynamic> toJson() {
    final external = <String, dynamic>{'uri': uri};

    if (title != null) {
      external['title'] = title;
    }
    if (description != null) {
      external['description'] = description;
    }

    // Return proper embed structure expected by backend
    return {r'$type': EmbedTypes.external, 'external': external};
  }

  /// URL of the external link
  final String uri;

  /// Title of the linked content
  final String? title;

  /// Description of the linked content
  final String? description;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExternalEmbedInput &&
          runtimeType == other.runtimeType &&
          uri == other.uri &&
          title == other.title &&
          description == other.description;

  @override
  int get hashCode => Object.hash(uri, title, description);

  @override
  String toString() =>
      'ExternalEmbedInput(uri: $uri, title: $title, description: $description)';
}

/// One image of an [ImagesEmbedInput]: the uploaded blob ref (unchanged),
/// optional alt text and the aspect ratio the upload returned.
class EmbedImageInput {
  const EmbedImageInput({required this.blob, this.alt, this.aspectRatio});

  final Map<String, dynamic> blob;
  final String? alt;
  final EmbedAspectRatio? aspectRatio;
}

/// `social.coves.embed.images`
class ImagesEmbedInput implements PostEmbedInput {
  const ImagesEmbedInput({required this.images});

  final List<EmbedImageInput> images;

  @override
  Map<String, dynamic> toJson() => {
    r'$type': EmbedTypes.images,
    'images': [
      for (final image in images)
        {
          'image': image.blob,
          if (image.alt != null) 'alt': image.alt,
          if (image.aspectRatio case final aspectRatio?)
            'aspectRatio': {
              'width': aspectRatio.width,
              'height': aspectRatio.height,
            },
        },
    ],
  };
}

/// `social.coves.embed.imagesWithAttachment`
class ImagesWithAttachmentInput implements PostEmbedInput {
  const ImagesWithAttachmentInput({
    required this.images,
    required this.attachment,
  });

  final ImagesEmbedInput images;
  final ExternalEmbedInput attachment;

  @override
  Map<String, dynamic> toJson() => {
    r'$type': EmbedTypes.imagesWithAttachment,
    'images': images.toJson(),
    'attachment': attachment.toJson(),
  };
}

/// The embed for a post with [images] and an optional link [external]
/// (PRD_IMAGES_MOBILE §3.4): none, `embed.external`, `embed.images`, or
/// `embed.imagesWithAttachment` with the link as its attachment.
PostEmbedInput? buildPostEmbed({
  List<EmbedImageInput> images = const [],
  ExternalEmbedInput? external,
}) {
  if (images.isEmpty) {
    return external;
  }
  final imagesEmbed = ImagesEmbedInput(images: List.unmodifiable(images));
  if (external == null) {
    return imagesEmbed;
  }
  return ImagesWithAttachmentInput(images: imagesEmbed, attachment: external);
}
