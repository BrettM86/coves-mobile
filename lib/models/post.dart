// Post data models for Coves timeline feed
//
// These models match the backend response structure from:
// /xrpc/social.coves.feed.getTimeline
// /xrpc/social.coves.feed.getDiscover

import 'package:flutter/foundation.dart';

import '../constants/embed_types.dart';
import 'bluesky_post.dart';
import 'facet.dart';

export 'facet.dart' show RichTextFacet, parseFacetsFromRecord;

class TimelineResponse {
  TimelineResponse({required this.feed, this.cursor});

  factory TimelineResponse.fromJson(Map<String, dynamic> json) {
    // Handle a null or non-list feed array from the backend
    final feedData = json['feed'];
    final feedList = <FeedViewPost>[];

    if (feedData is List) {
      // Parse feed items, skipping any that fail to parse. One bad post
      // must never cost the reader the whole feed, so the guard is broad:
      // items are type-checked rather than cast, and the catch is
      // `on Object` because an unchecked cast deep in a federated record
      // raises a TypeError, which is an Error and would otherwise escape.
      for (final item in feedData) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        try {
          feedList.add(FeedViewPost.fromJson(item));
        } on Object catch (e) {
          // Skip malformed posts (e.g., deleted posts with missing data)
          if (kDebugMode) {
            debugPrint('⚠️ Skipping malformed feed item: $e');
          }
        }
      }
    }

    // The cursor comes from the AppView's response envelope rather than a
    // federated record, but a wrong-typed value must degrade like every
    // other field here, not abort the whole feed parse.
    final cursor = json['cursor'];
    return TimelineResponse(
      feed: feedList,
      cursor: cursor is String ? cursor : null,
    );
  }
  final List<FeedViewPost> feed;
  final String? cursor;
}

class FeedViewPost {
  FeedViewPost({required this.post, this.reason});

  factory FeedViewPost.fromJson(Map<String, dynamic> json) {
    return FeedViewPost(
      post: PostView.fromJson(json['post'] as Map<String, dynamic>),
      reason:
          json['reason'] != null
              ? FeedReason.fromJson(json['reason'] as Map<String, dynamic>)
              : null,
    );
  }
  final PostView post;
  final FeedReason? reason;

  /// Returns a copy with the given fields replaced.
  ///
  /// Omitted fields are carried over; passing null does not clear a field.
  FeedViewPost copyWith({PostView? post, FeedReason? reason}) {
    return FeedViewPost(post: post ?? this.post, reason: reason ?? this.reason);
  }
}

class ViewerState {
  ViewerState({
    this.vote,
    this.voteUri,
    this.saved = false,
    this.savedUri,
    this.tags,
  });

  factory ViewerState.fromJson(Map<String, dynamic> json) {
    return ViewerState(
      vote: json['vote'] as String?,
      voteUri: json['voteUri'] as String?,
      saved: json['saved'] as bool? ?? false,
      savedUri: json['savedUri'] as String?,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>(),
    );
  }

  /// Vote direction: "up", "down", or null if not voted
  final String? vote;

  /// AT-URI of the vote record
  final String? voteUri;

  /// Whether the post is saved/bookmarked
  final bool saved;

  /// AT-URI of the saved record
  final String? savedUri;

  /// User-applied tags
  final List<String>? tags;
}

/// Record data for a post, containing the actual content.
///
/// This matches the backend's `social.coves.community.post` record type.
/// When a post is deleted, this record will be null and PostView.isDeleted
/// will be true.
class PostRecord {
  const PostRecord({this.title, this.content, this.facets});

  factory PostRecord.fromJson(Map<String, dynamic> json) {
    return PostRecord(
      title: json['title'] as String?,
      content: json['content'] as String?,
      facets: parseFacetsFromRecord(json),
    );
  }

  final String? title;
  final String? content;
  final List<RichTextFacet>? facets;
}

class PostView {
  PostView({
    required this.uri,
    required this.cid,
    required this.rkey,
    required this.author,
    required this.community,
    required this.createdAt,
    required this.indexedAt,
    this.record,
    this.isDeleted = false,
    this.deletionReason,
    required this.stats,
    this.embed,
    this.viewer,
  }) : assert(
         !isDeleted || record == null,
         'Deleted posts must have null record',
       );

  factory PostView.fromJson(Map<String, dynamic> json) {
    // Parse record if present (will be null for deleted posts)
    PostRecord? record;
    if (json['record'] != null && json['record'] is Map<String, dynamic>) {
      record = PostRecord.fromJson(json['record'] as Map<String, dynamic>);
    }

    return PostView(
      uri: json['uri'] as String,
      cid: json['cid'] as String,
      rkey: json['rkey'] as String,
      author: AuthorView.fromJson(json['author'] as Map<String, dynamic>),
      community: CommunityRef.fromJson(
        json['community'] as Map<String, dynamic>,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      indexedAt: DateTime.parse(json['indexedAt'] as String),
      record: record,
      isDeleted: json['isDeleted'] as bool? ?? false,
      deletionReason: json['deletionReason'] as String?,
      stats: PostStats.fromJson(json['stats'] as Map<String, dynamic>),
      embed:
          json['embed'] != null
              ? PostEmbed.fromJson(json['embed'] as Map<String, dynamic>)
              : null,
      viewer:
          json['viewer'] != null
              ? ViewerState.fromJson(json['viewer'] as Map<String, dynamic>)
              : null,
    );
  }
  final String uri;
  final String cid;
  final String rkey;
  final AuthorView author;
  final CommunityRef community;
  final DateTime createdAt;
  final DateTime indexedAt;
  final PostRecord? record;

  /// Whether this post has been deleted
  final bool isDeleted;

  /// Reason for deletion (e.g., "author", "moderator"), null if not deleted
  final String? deletionReason;
  final PostStats stats;
  final PostEmbed? embed;
  final ViewerState? viewer;

  /// The post title.
  ///
  /// This is a convenience getter for backwards compatibility after the
  /// refactor to use nested [PostRecord]. Previously title was a top-level
  /// field; now it lives inside [record].
  ///
  /// Returns null when [record] is null (e.g., for deleted posts) or when
  /// the post has no title.
  String? get title => record?.title;

  /// The post text content.
  ///
  /// This is a convenience getter for backwards compatibility after the
  /// refactor to use nested [PostRecord]. Previously content was a top-level
  /// field; now it lives inside [record].
  ///
  /// Returns empty string when [record] is null (e.g., for deleted posts).
  /// Check [isDeleted] to distinguish between deleted posts and posts that
  /// genuinely have no content.
  String get text => record?.content ?? '';

  /// Rich text facets for the post content (links, mentions, hashtags).
  ///
  /// This is a convenience getter for backwards compatibility after the
  /// refactor to use nested [PostRecord]. Previously facets were a top-level
  /// field; now they live inside [record].
  ///
  /// Returns null when [record] is null or when the post has no facets.
  List<RichTextFacet>? get facets => record?.facets;

  /// Returns a copy with the given fields replaced.
  ///
  /// Omitted fields are carried over; passing null does not clear a field
  /// (nothing needs to null out a field, and rebuilding a post while
  /// silently dropping [viewer] or the deletion flags is the bug this
  /// exists to prevent).
  PostView copyWith({
    String? uri,
    String? cid,
    String? rkey,
    AuthorView? author,
    CommunityRef? community,
    DateTime? createdAt,
    DateTime? indexedAt,
    PostRecord? record,
    bool? isDeleted,
    String? deletionReason,
    PostStats? stats,
    PostEmbed? embed,
    ViewerState? viewer,
  }) {
    return PostView(
      uri: uri ?? this.uri,
      cid: cid ?? this.cid,
      rkey: rkey ?? this.rkey,
      author: author ?? this.author,
      community: community ?? this.community,
      createdAt: createdAt ?? this.createdAt,
      indexedAt: indexedAt ?? this.indexedAt,
      record: record ?? this.record,
      isDeleted: isDeleted ?? this.isDeleted,
      deletionReason: deletionReason ?? this.deletionReason,
      stats: stats ?? this.stats,
      embed: embed ?? this.embed,
      viewer: viewer ?? this.viewer,
    );
  }
}

class AuthorView {
  AuthorView({
    required this.did,
    required this.handle,
    this.displayName,
    this.avatar,
  });

  factory AuthorView.fromJson(Map<String, dynamic> json) {
    return AuthorView(
      did: json['did'] as String,
      handle: json['handle'] as String,
      displayName: json['displayName'] as String?,
      avatar: json['avatar'] as String?,
    );
  }
  final String did;
  final String handle;
  final String? displayName;
  final String? avatar;
}

class CommunityRef {
  CommunityRef({
    required this.did,
    required this.name,
    this.handle,
    this.avatar,
    this.viewer,
  });

  factory CommunityRef.fromJson(Map<String, dynamic> json) {
    return CommunityRef(
      did: json['did'] as String,
      name: json['name'] as String,
      handle: json['handle'] as String?,
      avatar: json['avatar'] as String?,
      viewer:
          json['viewer'] != null
              ? CommunityRefViewerState.fromJson(
                json['viewer'] as Map<String, dynamic>,
              )
              : null,
    );
  }
  final String did;
  final String name;
  final String? handle;
  final String? avatar;

  /// Current user's relationship with this community (if available)
  final CommunityRefViewerState? viewer;
}

/// Viewer state for community ref embedded in posts
class CommunityRefViewerState {
  CommunityRefViewerState({this.subscribed});

  factory CommunityRefViewerState.fromJson(Map<String, dynamic> json) {
    return CommunityRefViewerState(subscribed: json['subscribed'] as bool?);
  }

  /// Whether the current user is subscribed to this community
  final bool? subscribed;
}

class PostStats {
  PostStats({
    required this.upvotes,
    required this.downvotes,
    required this.score,
    required this.commentCount,
  });

  factory PostStats.fromJson(Map<String, dynamic> json) {
    return PostStats(
      upvotes: json['upvotes'] as int,
      downvotes: json['downvotes'] as int,
      score: json['score'] as int,
      commentCount: json['commentCount'] as int,
    );
  }
  final int upvotes;
  final int downvotes;
  final int score;
  final int commentCount;

  /// Returns a copy with the given fields replaced.
  ///
  /// Omitted fields are carried over; passing null does not clear a field.
  PostStats copyWith({
    int? upvotes,
    int? downvotes,
    int? score,
    int? commentCount,
  }) {
    return PostStats(
      upvotes: upvotes ?? this.upvotes,
      downvotes: downvotes ?? this.downvotes,
      score: score ?? this.score,
      commentCount: commentCount ?? this.commentCount,
    );
  }
}

/// An embed attached to a post, discriminated by its lexicon `$type`.
///
/// The appview serves embeds as a `$type`-tagged union. Hydration is
/// all-or-nothing: when it fails, the *record* shape (no `#view` suffix) is
/// served with atproto blob refs instead of URLs. Those are unrenderable, so
/// they parse to [UnknownPostEmbed] — the client must never build blob URLs
/// itself, media has to flow through the appview's proxied URLs.
sealed class PostEmbed {
  const PostEmbed({required this.type, required this.data});

  /// Parses any embed json. Never throws on map input: anything unrecognized
  /// or malformed degrades to [UnknownPostEmbed].
  factory PostEmbed.fromJson(Map<String, dynamic> json) {
    final rawType = json[r'$type'];
    final embedType = rawType is String ? rawType : 'unknown';

    if (embedType == EmbedTypes.imagesView) {
      final images = _parseEmbedImages(json['images']);
      if (images == null) {
        return UnknownPostEmbed(type: embedType, data: json);
      }
      return ImagesPostEmbed(type: embedType, images: images, data: json);
    }

    if (embedType == EmbedTypes.videoView) {
      final video = json['video'];
      final thumbnail = json['thumbnail'];
      if (video is! String ||
          !_isRenderableMediaUrl(video) ||
          thumbnail is! String? ||
          (thumbnail != null && !_isRenderableMediaUrl(thumbnail))) {
        return UnknownPostEmbed(type: embedType, data: json);
      }
      final duration = json['duration'];
      return VideoPostEmbed(
        type: embedType,
        video: video,
        thumbnail: thumbnail,
        alt: _parseAltText(json['alt']),
        duration: duration is int ? duration : null,
        data: json,
      );
    }

    // Unhydrated record shapes carry blob refs, never renderable URLs.
    if (embedType == EmbedTypes.images || embedType == EmbedTypes.video) {
      return UnknownPostEmbed(type: embedType, data: json);
    }

    if (embedType == EmbedTypes.post || embedType == EmbedTypes.postView) {
      try {
        return QuotePostEmbed(
          type: embedType,
          post: BlueskyPostEmbed.fromJson(json),
          data: json,
        );
        // Broader than FormatException: BlueskyPostEmbed casts `resolved`
        // to a Map, so a hostile record raises a TypeError instead.
      } on Object catch (e) {
        if (kDebugMode) {
          debugPrint('PostEmbed: unparseable $embedType embed: $e');
        }
        return UnknownPostEmbed(type: embedType, data: json);
      }
    }

    if (embedType == EmbedTypes.external ||
        embedType == EmbedTypes.externalView) {
      final external = json['external'];
      if (external is Map<String, dynamic>) {
        // ExternalEmbed.fromJson casts its fields without checking, and
        // EmbedSource.fromJson throws outright on a bad source url. Wrap
        // the whole branch so any of that — including future drift —
        // degrades to an unrenderable embed instead of escaping.
        try {
          return ExternalPostEmbed(
            type: embedType,
            external: ExternalEmbed.fromJson(external),
            data: json,
          );
        } on Object {
          if (kDebugMode) {
            debugPrint('PostEmbed: unparseable $embedType external payload');
          }
          return UnknownPostEmbed(type: embedType, data: json);
        }
      }
    }

    // Fallback: if no typed embed was parsed but we have a uri field at the
    // top level, treat it as an external link embed. This handles cases where
    // the backend returns simple link embeds without the full $type wrapper.
    // Media embeds are excluded above so a malformed images/video embed that
    // happens to carry a uri stays unknown rather than rendering as a link.
    if (json['uri'] is String) {
      if (kDebugMode) {
        debugPrint(
          'PostEmbed fallback: treating unrecognized embed as external link. '
          'Type was: ${json[r'$type']}, keys: ${json.keys.toList()}',
        );
      }
      // Guarded for the same reason as the typed branch above: the fallback
      // hands the whole embed to the same unchecked casts.
      try {
        return ExternalPostEmbed(
          type: embedType,
          external: ExternalEmbed.fromJson(json),
          data: json,
        );
      } on Object {
        if (kDebugMode) {
          debugPrint('PostEmbed fallback: payload was not a usable link');
        }
        return UnknownPostEmbed(type: embedType, data: json);
      }
    }

    return UnknownPostEmbed(type: embedType, data: json);
  }

  /// The raw `$type`, or `'unknown'` when the embed carried no usable one.
  final String type;

  /// The raw embed json, preserved so unrecognized shapes are not lost.
  final Map<String, dynamic> data;

  /// The link payload — non-null only on [ExternalPostEmbed].
  ExternalEmbed? get external => null;

  /// The quoted Bluesky post — non-null only on [QuotePostEmbed].
  BlueskyPostEmbed? get blueskyPost => null;
}

/// An external link card.
final class ExternalPostEmbed extends PostEmbed {
  const ExternalPostEmbed({
    required super.type,
    required this.external,
    required super.data,
  });

  @override
  final ExternalEmbed external;
}

/// A quoted Bluesky post.
final class QuotePostEmbed extends PostEmbed {
  const QuotePostEmbed({
    required super.type,
    required this.post,
    required super.data,
  });

  /// Reference to the quoted post, with resolved data when the appview
  /// managed to fetch it.
  final BlueskyPostEmbed post;

  @override
  BlueskyPostEmbed get blueskyPost => post;
}

/// A hydrated image gallery. [images] is guaranteed non-empty and every entry
/// has renderable urls — a partially hydrated gallery parses as unknown.
final class ImagesPostEmbed extends PostEmbed {
  /// Throws [ArgumentError] when [images] is empty. Checked rather than
  /// asserted because asserts are stripped in release, and an empty gallery
  /// would reach the widgets as a `first` on an empty list.
  ImagesPostEmbed({
    required super.type,
    required List<EmbedImage> images,
    required super.data,
  }) : images = List.unmodifiable(images) {
    if (images.isEmpty) {
      throw ArgumentError.value(
        images,
        'images',
        'ImagesPostEmbed requires at least one image',
      );
    }
  }

  final List<EmbedImage> images;
}

/// A hydrated video with a playable url.
final class VideoPostEmbed extends PostEmbed {
  const VideoPostEmbed({
    required super.type,
    required this.video,
    required super.data,
    this.thumbnail,
    this.alt,
    this.duration,
  });

  /// Playable video url served by the appview.
  final String video;

  /// Poster image url, when the appview provided one.
  final String? thumbnail;

  /// Alt text supplied by the author.
  final String? alt;

  /// Video length in seconds, when known.
  final int? duration;
}

/// An embed this client cannot render: an unknown `$type`, an unhydrated
/// record shape, or a malformed payload. Renders as no media.
final class UnknownPostEmbed extends PostEmbed {
  const UnknownPostEmbed({required super.type, required super.data});
}

/// A single image from a hydrated gallery embed.
class EmbedImage {
  const EmbedImage({
    required this.thumb,
    required this.fullsize,
    this.alt,
    this.aspectRatio,
  });

  /// Feed-sized rendering url (800w).
  final String thumb;

  /// Lightbox-sized rendering url (1600w).
  final String fullsize;

  /// Alt text supplied by the author.
  final String? alt;

  /// Intrinsic dimensions, used to reserve layout space before load.
  final EmbedAspectRatio? aspectRatio;
}

/// Intrinsic dimensions of an embedded image.
class EmbedAspectRatio {
  /// Throws [ArgumentError] on a dimension below 1. Checked rather than
  /// asserted: asserts are stripped in release, and a zero height would
  /// reach the layout as a division by zero.
  EmbedAspectRatio({required this.width, required this.height}) {
    if (width < 1) {
      throw ArgumentError.value(width, 'width', 'must be at least 1');
    }
    if (height < 1) {
      throw ArgumentError.value(height, 'height', 'must be at least 1');
    }
  }

  final int width;
  final int height;
}

/// Whether a hydrated media url is safe to hand to the image/video stack.
///
/// The appview's hydration no-ops on `#view` types and the firehose consumer
/// stores embeds verbatim, so a federated repo can publish a pre-stamped view
/// carrying `file://`, `content://` or `javascript:` urls. The model is the
/// last line of defence, so the allowlist here is the same one
/// `UrlLauncher` enforces for outbound links: http and https only.
bool _isRenderableMediaUrl(String url) {
  if (url.isEmpty) {
    return false;
  }

  final parsed = Uri.tryParse(url);
  if (parsed == null) {
    return false;
  }

  // Uri lowercases the scheme while parsing, but compare case-insensitively
  // anyway so 'HTTPS://…' cannot turn on a future refactor. The host check
  // matters too: 'http:foo' and 'https:///path' carry an allowed scheme
  // with no authority at all.
  final scheme = parsed.scheme.toLowerCase();
  return (scheme == 'http' || scheme == 'https') && parsed.host.isNotEmpty;
}

/// Lexicon caps for a hydrated gallery: at most 8 images, alt text at most
/// 10000 characters.
const int _maxGalleryImages = 8;
const int _maxAltLength = 10000;

/// Reads alt text, truncated to the lexicon's limit.
///
/// Lenient about type — alt is decorative enough that a malformed one is
/// dropped rather than poisoning the embed — but not about length: nothing
/// downstream bounds it before it reaches the semantics tree.
String? _parseAltText(Object? raw) {
  if (raw is! String) {
    return null;
  }
  return raw.length > _maxAltLength ? raw.substring(0, _maxAltLength) : raw;
}

/// Parses the `images` list of a hydrated gallery embed.
///
/// Returns null when the gallery must not be rendered at all: a missing,
/// non-list or empty value, or any entry lacking a String `thumb` and
/// `fullsize` (e.g. one still carrying a blob ref) or carrying one that is
/// not an http(s) url. This mirrors the appview's all-or-nothing hydration —
/// half a gallery is never shown, and one hostile url poisons the rest.
List<EmbedImage>? _parseEmbedImages(Object? raw) {
  // The lexicon caps a gallery at 8 and the appview never serves more, so a
  // longer list is a malformed or hostile record rather than something to
  // render partially. Checked before the loop so an absurd list costs a
  // length read, not a walk.
  if (raw is! List || raw.isEmpty || raw.length > _maxGalleryImages) {
    return null;
  }

  final images = <EmbedImage>[];
  for (final entry in raw) {
    if (entry is! Map<String, dynamic>) {
      return null;
    }

    final thumb = entry['thumb'];
    final fullsize = entry['fullsize'];
    if (thumb is! String ||
        fullsize is! String ||
        !_isRenderableMediaUrl(thumb) ||
        !_isRenderableMediaUrl(fullsize)) {
      return null;
    }

    images.add(
      EmbedImage(
        thumb: thumb,
        fullsize: fullsize,
        alt: _parseAltText(entry['alt']),
        aspectRatio: _parseEmbedAspectRatio(entry['aspectRatio']),
      ),
    );
  }

  return images;
}

/// Parses an image `aspectRatio`, or null when it is absent or malformed.
///
/// A bad ratio only costs layout hinting, so it is dropped without
/// rejecting the image itself.
EmbedAspectRatio? _parseEmbedAspectRatio(Object? raw) {
  if (raw is! Map) {
    return null;
  }

  final width = raw['width'];
  final height = raw['height'];
  if (width is! int || height is! int || width < 1 || height < 1) {
    return null;
  }

  return EmbedAspectRatio(width: width, height: height);
}

class ExternalEmbed {
  ExternalEmbed({
    required this.uri,
    this.title,
    this.description,
    this.thumb,
    this.domain,
    this.embedType,
    this.provider,
    this.images,
    this.totalCount,
    this.sources,
  });

  factory ExternalEmbed.fromJson(Map<String, dynamic> json) {
    // Thumb is always a string URL (backend transforms blob refs
    // before sending)

    // Handle images array if present
    List<Map<String, dynamic>>? imagesList;
    if (json['images'] != null && json['images'] is List) {
      imagesList =
          (json['images'] as List).whereType<Map<String, dynamic>>().toList();
    }

    // Handle sources array if present
    List<EmbedSource>? sourcesList;
    if (json['sources'] != null && json['sources'] is List) {
      sourcesList =
          (json['sources'] as List)
              .whereType<Map<String, dynamic>>()
              .map(EmbedSource.fromJson)
              .toList();
    }

    return ExternalEmbed(
      uri: json['uri'] as String,
      title: json['title'] as String?,
      description: json['description'] as String?,
      thumb: json['thumb'] as String?,
      domain: json['domain'] as String?,
      embedType: json['embedType'] as String?,
      provider: json['provider'] as String?,
      images: imagesList,
      totalCount: json['totalCount'] as int?,
      sources: sourcesList,
    );
  }
  final String uri;
  final String? title;
  final String? description;
  final String? thumb;
  final String? domain;
  final String? embedType;
  final String? provider;
  final List<Map<String, dynamic>>? images;
  final int? totalCount;
  final List<EmbedSource>? sources;
}

/// A source link aggregated into a megathread
class EmbedSource {
  EmbedSource({required this.uri, this.title, this.domain});

  factory EmbedSource.fromJson(Map<String, dynamic> json) {
    final uri = json['uri'];
    if (uri == null || uri is! String || uri.isEmpty) {
      throw const FormatException(
        'EmbedSource: Required field "uri" is missing or invalid',
      );
    }

    // Validate URI scheme for security
    final parsedUri = Uri.tryParse(uri);
    if (parsedUri == null ||
        !parsedUri.hasScheme ||
        !['http', 'https'].contains(parsedUri.scheme.toLowerCase())) {
      throw FormatException(
        'EmbedSource: URI has invalid or unsupported scheme: $uri',
      );
    }

    return EmbedSource(
      uri: uri,
      title: json['title'] as String?,
      domain: json['domain'] as String?,
    );
  }

  final String uri;
  final String? title;
  final String? domain;

  @override
  String toString() => 'EmbedSource(uri: $uri, title: $title, domain: $domain)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmbedSource &&
          runtimeType == other.runtimeType &&
          uri == other.uri &&
          title == other.title &&
          domain == other.domain;

  @override
  int get hashCode => Object.hash(uri, title, domain);
}

class FeedReason {
  FeedReason({required this.type, required this.data});

  factory FeedReason.fromJson(Map<String, dynamic> json) {
    return FeedReason(type: json[r'$type'] as String? ?? 'unknown', data: json);
  }
  final String type;
  final Map<String, dynamic> data;
}
