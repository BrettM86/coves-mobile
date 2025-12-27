// Community data models for Coves
//
// These models match the backend API structure from:
// GET /xrpc/social.coves.community.list
// POST /xrpc/social.coves.community.post.create

import '../constants/embed_types.dart';

/// Response from GET /xrpc/social.coves.community.list
class CommunitiesResponse {
  CommunitiesResponse({required this.communities, this.cursor});

  factory CommunitiesResponse.fromJson(Map<String, dynamic> json) {
    // Handle null communities array from backend
    final communitiesData = json['communities'];
    final List<CommunityView> communitiesList;

    if (communitiesData == null) {
      // Backend returned null, use empty list
      communitiesList = [];
    } else {
      // Parse community items
      communitiesList = (communitiesData as List<dynamic>)
          .map(
            (item) => CommunityView.fromJson(item as Map<String, dynamic>),
          )
          .toList();
    }

    return CommunitiesResponse(
      communities: communitiesList,
      cursor: json['cursor'] as String?,
    );
  }

  final List<CommunityView> communities;
  final String? cursor;
}

/// Full community view data
class CommunityView {
  CommunityView({
    required this.did,
    required this.name,
    this.handle,
    this.displayName,
    this.description,
    this.avatar,
    this.visibility,
    this.subscriberCount,
    this.memberCount,
    this.postCount,
    this.viewer,
  });

  factory CommunityView.fromJson(Map<String, dynamic> json) {
    return CommunityView(
      did: json['did'] as String,
      name: json['name'] as String,
      handle: json['handle'] as String?,
      displayName: json['displayName'] as String?,
      description: json['description'] as String?,
      avatar: json['avatar'] as String?,
      visibility: json['visibility'] as String?,
      subscriberCount: json['subscriberCount'] as int?,
      memberCount: json['memberCount'] as int?,
      postCount: json['postCount'] as int?,
      viewer: json['viewer'] != null
          ? CommunityViewerState.fromJson(
              json['viewer'] as Map<String, dynamic>,
            )
          : null,
    );
  }

  /// Community DID (decentralized identifier)
  final String did;

  /// Community name (unique identifier)
  final String name;

  /// Community handle
  final String? handle;

  /// Display name for UI
  final String? displayName;

  /// Community description
  final String? description;

  /// Avatar URL
  final String? avatar;

  /// Visibility setting (e.g., "public", "private")
  final String? visibility;

  /// Number of subscribers
  final int? subscriberCount;

  /// Number of members
  final int? memberCount;

  /// Number of posts
  final int? postCount;

  /// Current user's relationship with this community
  final CommunityViewerState? viewer;
}

/// Current user's relationship with a community
class CommunityViewerState {
  CommunityViewerState({this.subscribed, this.member});

  factory CommunityViewerState.fromJson(Map<String, dynamic> json) {
    return CommunityViewerState(
      subscribed: json['subscribed'] as bool?,
      member: json['member'] as bool?,
    );
  }

  /// Whether the user is subscribed to this community
  final bool? subscribed;

  /// Whether the user is a member of this community
  final bool? member;
}

/// Request body for POST /xrpc/social.coves.community.post.create
class CreatePostRequest {
  CreatePostRequest({
    required this.community,
    this.title,
    this.content,
    this.embed,
    this.langs,
    this.labels,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'community': community,
    };

    if (title != null) {
      json['title'] = title;
    }
    if (content != null) {
      json['content'] = content;
    }
    if (embed != null) {
      json['embed'] = embed!.toJson();
    }
    if (langs != null && langs!.isNotEmpty) {
      json['langs'] = langs;
    }
    if (labels != null) {
      json['labels'] = labels!.toJson();
    }

    return json;
  }

  /// Community DID or handle
  final String community;

  /// Post title
  final String? title;

  /// Post content/text
  final String? content;

  /// External link embed
  final ExternalEmbedInput? embed;

  /// Language codes (e.g., ["en", "es"])
  final List<String>? langs;

  /// Self-applied content labels
  final SelfLabels? labels;
}

/// Response from POST /xrpc/social.coves.community.post.create
class CreatePostResponse {
  const CreatePostResponse({required this.uri, required this.cid});

  factory CreatePostResponse.fromJson(Map<String, dynamic> json) {
    return CreatePostResponse(
      uri: json['uri'] as String,
      cid: json['cid'] as String,
    );
  }

  /// AT-URI of the created post
  final String uri;

  /// Content identifier (CID) of the created post
  final String cid;
}

/// External link embed input for creating posts
class ExternalEmbedInput {
  /// Creates an [ExternalEmbedInput] with URI validation.
  ///
  /// Throws [ArgumentError] if [uri] is empty or not a valid URL.
  factory ExternalEmbedInput({
    required String uri,
    String? title,
    String? description,
    String? thumb,
  }) {
    // Validate URI is not empty
    if (uri.isEmpty) {
      throw ArgumentError.value(uri, 'uri', 'URI cannot be empty');
    }

    // Validate URI is a well-formed URL
    final parsedUri = Uri.tryParse(uri);
    if (parsedUri == null ||
        !parsedUri.hasScheme ||
        (!parsedUri.isScheme('http') && !parsedUri.isScheme('https'))) {
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
      thumb: thumb,
    );
  }

  const ExternalEmbedInput._({
    required this.uri,
    this.title,
    this.description,
    this.thumb,
  });

  Map<String, dynamic> toJson() {
    final external = <String, dynamic>{
      'uri': uri,
    };

    if (title != null) {
      external['title'] = title;
    }
    if (description != null) {
      external['description'] = description;
    }
    if (thumb != null) {
      external['thumb'] = thumb;
    }

    // Return proper embed structure expected by backend
    return {
      r'$type': EmbedTypes.external,
      'external': external,
    };
  }

  /// URL of the external link
  final String uri;

  /// Title of the linked content
  final String? title;

  /// Description of the linked content
  final String? description;

  /// Thumbnail URL
  final String? thumb;
}

/// Self-applied content labels
class SelfLabels {
  const SelfLabels({required this.values});

  Map<String, dynamic> toJson() {
    return {
      'values': values.map((label) => label.toJson()).toList(),
    };
  }

  /// List of self-applied labels
  final List<SelfLabel> values;
}

/// Individual self-applied label
class SelfLabel {
  const SelfLabel({required this.val});

  Map<String, dynamic> toJson() {
    return {
      'val': val,
    };
  }

  /// Label value (e.g., "nsfw", "spoiler")
  final String val;
}

/// Response from POST /xrpc/social.coves.community.create
class CreateCommunityResponse {
  const CreateCommunityResponse({
    required this.uri,
    required this.cid,
    required this.did,
    required this.handle,
  });

  /// Parse response from JSON with defensive validation.
  ///
  /// Throws [FormatException] if required fields are missing or invalid.
  factory CreateCommunityResponse.fromJson(Map<String, dynamic> json) {
    final uri = json['uri'];
    final cid = json['cid'];
    final did = json['did'];
    final handle = json['handle'];

    if (uri == null || uri is! String) {
      throw const FormatException('Missing or invalid "uri" in response');
    }
    if (cid == null || cid is! String) {
      throw const FormatException('Missing or invalid "cid" in response');
    }
    if (did == null || did is! String) {
      throw const FormatException('Missing or invalid "did" in response');
    }
    if (handle == null || handle is! String) {
      throw const FormatException('Missing or invalid "handle" in response');
    }

    return CreateCommunityResponse(
      uri: uri,
      cid: cid,
      did: did,
      handle: handle,
    );
  }

  /// AT-URI of the created community profile
  final String uri;

  /// Content identifier (CID) of the created community profile
  final String cid;

  /// DID of the created community
  final String did;

  /// Scoped handle of the created community
  final String handle;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is CreateCommunityResponse &&
        other.uri == uri &&
        other.cid == cid &&
        other.did == did &&
        other.handle == handle;
  }

  @override
  int get hashCode => Object.hash(uri, cid, did, handle);

  @override
  String toString() {
    return 'CreateCommunityResponse(uri: $uri, cid: $cid, did: $did, '
        'handle: $handle)';
  }
}
