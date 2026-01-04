// User profile data models for Coves
//
// These models match the backend response structure from:
// /xrpc/social.coves.actor.getprofile

/// User profile with display information and stats
class UserProfile {
  /// Creates a UserProfile with validation.
  ///
  /// Throws [ArgumentError] if [did] doesn't start with 'did:'.
  factory UserProfile({
    required String did,
    String? handle,
    String? displayName,
    String? bio,
    String? avatar,
    String? banner,
    DateTime? createdAt,
    ProfileStats? stats,
    ProfileViewerState? viewer,
  }) {
    if (!did.startsWith('did:')) {
      throw ArgumentError.value(did, 'did', 'Must start with "did:" prefix');
    }
    return UserProfile._(
      did: did,
      handle: handle,
      displayName: displayName,
      bio: bio,
      avatar: avatar,
      banner: banner,
      createdAt: createdAt,
      stats: stats,
      viewer: viewer,
    );
  }

  /// Private constructor - validation happens in factory
  const UserProfile._({
    required this.did,
    this.handle,
    this.displayName,
    this.bio,
    this.avatar,
    this.banner,
    this.createdAt,
    this.stats,
    this.viewer,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final did = json['did'] as String?;
    if (did == null || !did.startsWith('did:')) {
      throw FormatException('Invalid or missing DID in profile: $did');
    }

    // Handle can be at top level or nested inside 'profile' object
    // (backend returns nested structure)
    final profileData = json['profile'] as Map<String, dynamic>?;
    final handle =
        json['handle'] as String? ?? profileData?['handle'] as String?;
    final createdAtStr =
        json['createdAt'] as String? ?? profileData?['createdAt'] as String?;

    return UserProfile._(
      did: did,
      handle: handle,
      displayName: json['displayName'] as String?,
      bio: json['bio'] as String?,
      avatar: json['avatar'] as String?,
      banner: json['banner'] as String?,
      createdAt: createdAtStr != null ? DateTime.tryParse(createdAtStr) : null,
      stats:
          json['stats'] != null
              ? ProfileStats.fromJson(json['stats'] as Map<String, dynamic>)
              : null,
      viewer:
          json['viewer'] != null
              ? ProfileViewerState.fromJson(
                json['viewer'] as Map<String, dynamic>,
              )
              : null,
    );
  }

  final String did;
  final String? handle;
  final String? displayName;
  final String? bio;
  final String? avatar;
  final String? banner;
  final DateTime? createdAt;
  final ProfileStats? stats;
  final ProfileViewerState? viewer;

  /// Returns display name if available, otherwise handle, otherwise DID
  String get displayNameOrHandle => displayName ?? handle ?? did;

  /// Returns handle with @ prefix if available
  String? get formattedHandle => handle != null ? '@$handle' : null;

  /// Creates a copy with the given fields replaced.
  ///
  /// Note: [did] cannot be changed to an invalid value - validation still
  /// applies via the factory constructor.
  UserProfile copyWith({
    String? did,
    String? handle,
    String? displayName,
    String? bio,
    String? avatar,
    String? banner,
    DateTime? createdAt,
    ProfileStats? stats,
    ProfileViewerState? viewer,
  }) {
    return UserProfile(
      did: did ?? this.did,
      handle: handle ?? this.handle,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      avatar: avatar ?? this.avatar,
      banner: banner ?? this.banner,
      createdAt: createdAt ?? this.createdAt,
      stats: stats ?? this.stats,
      viewer: viewer ?? this.viewer,
    );
  }

  Map<String, dynamic> toJson() => {
    'did': did,
    if (handle != null) 'handle': handle,
    if (displayName != null) 'displayName': displayName,
    if (bio != null) 'bio': bio,
    if (avatar != null) 'avatar': avatar,
    if (banner != null) 'banner': banner,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (stats != null) 'stats': stats!.toJson(),
    if (viewer != null) 'viewer': viewer!.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfile &&
          runtimeType == other.runtimeType &&
          did == other.did &&
          handle == other.handle &&
          displayName == other.displayName &&
          bio == other.bio &&
          avatar == other.avatar &&
          banner == other.banner &&
          createdAt == other.createdAt &&
          stats == other.stats &&
          viewer == other.viewer;

  @override
  int get hashCode => Object.hash(
    did,
    handle,
    displayName,
    bio,
    avatar,
    banner,
    createdAt,
    stats,
    viewer,
  );
}

/// User profile statistics
///
/// Contains counts for posts, comments, communities, and reputation.
/// All count fields are guaranteed to be non-negative.
class ProfileStats {
  /// Creates ProfileStats with non-negative count validation.
  const ProfileStats({
    this.postCount = 0,
    this.commentCount = 0,
    this.communityCount = 0,
    this.reputation,
    this.membershipCount = 0,
  });

  factory ProfileStats.fromJson(Map<String, dynamic> json) {
    // Clamp values to ensure non-negative (defensive parsing)
    const maxInt = 0x7FFFFFFF; // Max 32-bit signed int
    return ProfileStats(
      postCount: (json['postCount'] as int? ?? 0).clamp(0, maxInt),
      commentCount: (json['commentCount'] as int? ?? 0).clamp(0, maxInt),
      communityCount: (json['communityCount'] as int? ?? 0).clamp(0, maxInt),
      reputation: json['reputation'] as int?,
      membershipCount: (json['membershipCount'] as int? ?? 0).clamp(0, maxInt),
    );
  }

  final int postCount;
  final int commentCount;
  final int communityCount;
  final int? reputation;
  final int membershipCount;

  ProfileStats copyWith({
    int? postCount,
    int? commentCount,
    int? communityCount,
    int? reputation,
    int? membershipCount,
  }) {
    return ProfileStats(
      postCount: postCount ?? this.postCount,
      commentCount: commentCount ?? this.commentCount,
      communityCount: communityCount ?? this.communityCount,
      reputation: reputation ?? this.reputation,
      membershipCount: membershipCount ?? this.membershipCount,
    );
  }

  Map<String, dynamic> toJson() => {
    'postCount': postCount,
    'commentCount': commentCount,
    'communityCount': communityCount,
    if (reputation != null) 'reputation': reputation,
    'membershipCount': membershipCount,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProfileStats &&
          runtimeType == other.runtimeType &&
          postCount == other.postCount &&
          commentCount == other.commentCount &&
          communityCount == other.communityCount &&
          reputation == other.reputation &&
          membershipCount == other.membershipCount;

  @override
  int get hashCode => Object.hash(
    postCount,
    commentCount,
    communityCount,
    reputation,
    membershipCount,
  );
}

/// Viewer-specific state for a profile (block status)
///
/// Represents the relationship between the viewer and the profile owner.
/// Invariant: if [blocked] is true, [blockUri] must be non-null.
class ProfileViewerState {
  /// Creates ProfileViewerState.
  ///
  /// Note: The factory enforces that blocked requires blockUri.
  factory ProfileViewerState({
    bool blocked = false,
    bool blockedBy = false,
    String? blockUri,
  }) {
    // Enforce invariant: if blocked, must have blockUri
    // Defensive: treat as not blocked if no URI
    final effectiveBlocked = blocked && blockUri != null;
    return ProfileViewerState._(
      blocked: effectiveBlocked,
      blockedBy: blockedBy,
      blockUri: blockUri,
    );
  }

  const ProfileViewerState._({
    required this.blocked,
    required this.blockedBy,
    this.blockUri,
  });

  factory ProfileViewerState.fromJson(Map<String, dynamic> json) {
    final blocked = json['blocked'] as bool? ?? false;
    final blockUri = json['blockUri'] as String?;

    return ProfileViewerState._(
      // If blocked but no blockUri, treat as not blocked (defensive)
      blocked: blocked && blockUri != null,
      blockedBy: json['blockedBy'] as bool? ?? false,
      blockUri: blockUri,
    );
  }

  final bool blocked;
  final bool blockedBy;
  final String? blockUri;

  ProfileViewerState copyWith({
    bool? blocked,
    bool? blockedBy,
    String? blockUri,
  }) {
    return ProfileViewerState(
      blocked: blocked ?? this.blocked,
      blockedBy: blockedBy ?? this.blockedBy,
      blockUri: blockUri ?? this.blockUri,
    );
  }

  Map<String, dynamic> toJson() => {
    'blocked': blocked,
    'blockedBy': blockedBy,
    if (blockUri != null) 'blockUri': blockUri,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProfileViewerState &&
          runtimeType == other.runtimeType &&
          blocked == other.blocked &&
          blockedBy == other.blockedBy &&
          blockUri == other.blockUri;

  @override
  int get hashCode => Object.hash(blocked, blockedBy, blockUri);
}
