import 'package:coves_flutter/config/environment_config.dart';

/// Builds canonical Coves web URLs for sharing.
class WebLinkBuilder {
  const WebLinkBuilder({required this.webUrl});

  /// A builder for the web client this build points at, so shared links lead
  /// back to the same instance the app is reading from.
  factory WebLinkBuilder.current() =>
      WebLinkBuilder(webUrl: EnvironmentConfig.current.webUrl);

  /// Origin of the web client, e.g. `https://coves.social`.
  final String webUrl;

  /// Web URL for a community: `/c/gaming` for a community of this instance,
  /// `/c/comicstrips@lemmy.world` for a remote one, and `/c/<did>` whenever
  /// the canonical form cannot be built. The web route matcher accepts a bare
  /// DID and redirects it to the canonical form once the community loads.
  ///
  /// A remote origin carrying a port is outside the hostname grammar, so it
  /// falls back to the DID as well.
  ///
  /// Null when neither segment addresses anything: no canonical param and a
  /// [did] the web's matcher would not accept either.
  String? community({
    required String did,
    required String name,
    String? origin,
  }) {
    final param =
        _canonicalCommunityParam(name: name, origin: origin) ?? _usableDid(did);
    if (param == null) {
      return null;
    }
    return '$_base/c/${_encodeCommunityParam(param)}';
  }

  /// Web URL for a user profile: `/profile/alice.coves.social` when the
  /// handle resolves, `/profile/<did>` otherwise. The web's actor matcher
  /// accepts either form.
  ///
  /// Null when it accepts neither: no usable handle and a [did] that is not
  /// a DID.
  String? profile({required String did, String? handle}) {
    final segment = _usableHandle(handle) ?? _usableDid(did);
    if (segment == null) {
      return null;
    }
    return '$_base/profile/${Uri.encodeComponent(segment)}';
  }

  /// Web URL for a post: `/c/<community>/post/<owner>/<rkey>`, or null when
  /// [postUri] is not a well-formed at-URI or the community has no
  /// addressable segment.
  String? post({
    required String postUri,
    required String authorDid,
    String? authorHandle,
    required String communityDid,
    required String communityName,
    String? communityOrigin,
  }) {
    final record = _parseAtUri(postUri);
    if (record == null) {
      return null;
    }
    final communityUrl = community(
      did: communityDid,
      name: communityName,
      origin: communityOrigin,
    );
    if (communityUrl == null) {
      return null;
    }
    final owner = _repoSegment(
      record.authority,
      did: authorDid,
      handle: authorHandle,
    );
    return '$communityUrl/post/${Uri.encodeComponent(owner)}'
        '/${Uri.encodeComponent(record.rkey)}';
  }

  /// Web URL for a comment: the post link plus
  /// `/comment/<commenter>/<rkey>`, or null whenever the post link is null or
  /// [commentUri] is malformed.
  String? comment({
    required String commentUri,
    String? commenterDid,
    String? commenterHandle,
    required String postUri,
    required String postAuthorDid,
    String? postAuthorHandle,
    required String communityDid,
    required String communityName,
    String? communityOrigin,
  }) {
    final record = _parseAtUri(commentUri);
    if (record == null) {
      return null;
    }
    final postUrl = post(
      postUri: postUri,
      authorDid: postAuthorDid,
      authorHandle: postAuthorHandle,
      communityDid: communityDid,
      communityName: communityName,
      communityOrigin: communityOrigin,
    );
    if (postUrl == null) {
      return null;
    }
    final commenter = _repoSegment(
      record.authority,
      did: commenterDid,
      handle: commenterHandle,
    );
    return '$postUrl/comment/${Uri.encodeComponent(commenter)}'
        '/${Uri.encodeComponent(record.rkey)}';
  }

  /// [webUrl] without its trailing slash, so joined paths never double up.
  String get _base =>
      webUrl.endsWith('/') ? webUrl.substring(0, webUrl.length - 1) : webUrl;

  /// Domain this client serves; a community from it uses the bare name.
  /// The port stays in the URL but plays no part in the comparison.
  String get _localDomain => Uri.parse(webUrl).host.toLowerCase();

  /// The canonical `/c/<param>` route param, following Lemmy's convention:
  /// the bare `name` for a community of this instance, `name@origin` for
  /// every remote origin. Both halves are lower-cased so there is exactly
  /// one canonical spelling.
  ///
  /// Null when the pair would not survive the web route matcher — no origin,
  /// a name that is not a DNS label, or a remote origin that is not a
  /// hostname — so the caller falls back to the DID param.
  String? _canonicalCommunityParam({required String name, String? origin}) {
    final normalizedOrigin = origin?.trim().toLowerCase();
    final normalizedName = name.trim().toLowerCase();
    if (normalizedOrigin == null || normalizedOrigin.isEmpty) {
      return null;
    }
    if (!_communityNamePattern.hasMatch(normalizedName)) {
      return null;
    }
    if (normalizedOrigin == _localDomain) {
      return normalizedName;
    }
    if (!_hostnamePattern.hasMatch(normalizedOrigin)) {
      return null;
    }
    return '$normalizedName@$normalizedOrigin';
  }

  /// The authority and record key of `at://<authority>/<collection>/<rkey>`,
  /// or null for anything else.
  ///
  /// Hand-parsed: an at-URI cannot go through Uri.parse, which reads the
  /// colons of a DID authority as a port. Since nothing else validates the
  /// parts, each one is checked here: a query, a fragment or any further
  /// segment leaves the authority or the record key outside its grammar, and
  /// a URI that is not exactly a record's yields no link rather than one
  /// addressing something else.
  ({String authority, String rkey})? _parseAtUri(String uri) {
    const scheme = 'at://';
    if (!uri.startsWith(scheme)) {
      return null;
    }
    final segments = uri.substring(scheme.length).split('/');
    if (segments.length != 3) {
      return null;
    }
    final [authority, collection, recordKey] = segments;
    if (!_didPattern.hasMatch(authority) ||
        collection.isEmpty ||
        !_isRecordKey(recordKey)) {
      return null;
    }
    return (authority: authority, rkey: recordKey);
  }

  /// Whether [value] is an ATProto record key. `.` and `..` match the
  /// character grammar but are reserved as relative path segments.
  bool _isRecordKey(String value) =>
      _recordKeyPattern.hasMatch(value) && value != '.' && value != '..';

  /// The segment naming the repo a record lives in, which is its at-URI
  /// [authority]. The prettier handle replaces it only when [did] proves the
  /// handle belongs to that same repo, so the segment always addresses the
  /// record that actually exists. A null [did] — a deleted or unhydrated
  /// author — leaves the authority as the only identity there is.
  String _repoSegment(
    String authority, {
    required String? did,
    String? handle,
  }) =>
      (did == authority ? _usableHandle(handle) : null) ?? authority;

  /// The handle when it is present, resolvable, and a hostname the web's
  /// handle matcher accepts, null otherwise, so the caller falls back to the
  /// DID. `handle.invalid` is ATProto's sentinel for a handle that could not
  /// be resolved; a link built from it always 404s. A value outside the
  /// hostname grammar — `..`, an undotted or underscored label, anything with
  /// a space — either 404s there or addresses a different route entirely.
  String? _usableHandle(String? handle) {
    final trimmed = handle?.trim();
    if (trimmed == null ||
        trimmed == _invalidHandle ||
        !_hostnamePattern.hasMatch(trimmed)) {
      return null;
    }
    return trimmed;
  }

  /// [did] when it is a DID, null otherwise. A DID segment is only a link
  /// because the web's matchers accept a bare DID and redirect it; a value
  /// that is not one matches no route there, so there is nothing to link to.
  String? _usableDid(String did) => _didPattern.hasMatch(did) ? did : null;

  /// Percent-encodes a community route param for a path segment while keeping
  /// the `@` of `name@origin` literal — `@` is a legal path character and
  /// `%40` would make the canonical URL unreadable.
  String _encodeCommunityParam(String param) =>
      Uri.encodeComponent(param).replaceAll('%40', '@');

  /// ATProto's sentinel for a handle that could not be resolved.
  static const String _invalidHandle = 'handle.invalid';

  /// A community name is one DNS label (RFC 1035): alphanumeric with
  /// interior hyphens, at most 63 characters. No dots — a dotted value is a
  /// handle — and no underscores: the AppView resolves names with the same
  /// rule, so either would only build a URL it rejects.
  static final RegExp _communityNamePattern =
      RegExp(r'^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$');

  /// An at-URI authority must be a DID, `did:<method>:<identifier>`. The
  /// AppView only ever emits DID authorities; a handle there would name a
  /// repo the record may not live in once the handle moves.
  static final RegExp _didPattern = RegExp(r'^did:[a-z]+:[a-zA-Z0-9._:%-]+$');

  /// ATProto's record-key grammar: 1 to 512 characters of the unreserved set
  /// plus `:` and `~`.
  static final RegExp _recordKeyPattern = RegExp(r'^[a-zA-Z0-9._:~-]{1,512}$');

  /// A remote origin and a handle must both be a DNS hostname: at least one
  /// dot, alphanumeric labels with interior hyphens. Anything else fails the
  /// web's `name@origin` and handle route matchers.
  static final RegExp _hostnamePattern = RegExp(
    '^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?'
    r'(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)+$',
  );
}
