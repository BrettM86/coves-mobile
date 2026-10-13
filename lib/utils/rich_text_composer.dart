import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/facet.dart';
import 'url_policy.dart';
import 'utf8_offsets.dart';

/// Content ready to send, with the link facets and mentions detected in it
class ComposedRichText {
  const ComposedRichText._({
    required this.content,
    this.facets,
    required this.mentions,
  });

  /// Canonical content to send
  final String content;

  /// Facets over [content], or null when there are none
  final List<RichTextFacet>? facets;

  /// Mentions detected in [content], not yet resolved to DIDs
  final List<PendingMention> mentions;
}

/// What a mention names
enum MentionKind { user, community }

/// A mention detected in composed content, awaiting resolution to a DID
class PendingMention {
  const PendingMention({
    required this.kind,
    required this.identifier,
    required this.index,
  });

  final MentionKind kind;

  /// The handle or community, without its sigil
  final String identifier;

  /// The UTF-8 byte range of the mention, covering its sigil
  final ByteSlice index;
}

/// Looks up the DIDs that mentions name
abstract interface class MentionResolver {
  /// DID for [handle], or null when no such handle exists. Throws on any
  /// other failure.
  Future<String?> resolveHandle(String handle);

  /// DID for [community] (name or name@origin), or null when no such
  /// community exists. Throws otherwise.
  Future<String?> resolveCommunity(String community);
}

/// The most distinct mentions looked up for one piece of content, keeping a
/// post well under the AppView's per-IP limit of 100 requests a minute
const int maxMentionLookups = 20;

/// [composed] with its mentions resolved into #mention facets merged into its
/// link facets
///
/// Each distinct identifier is looked up once, all lookups at the same time,
/// and only the first [maxMentionLookups] distinct identifiers are looked up;
/// the rest stay plain text. A mention that is not found, or whose DID is not
/// a valid DID, stays plain text. Any lookup that fails for another reason
/// makes this throw as soon as it fails. The result has no pending mentions.
Future<ComposedRichText> resolveMentions(
  ComposedRichText composed,
  MentionResolver resolver,
) async {
  if (composed.mentions.isEmpty) {
    return composed;
  }

  // The same name under a different sigil is a different lookup
  final lookups = <(MentionKind, String), Future<String?>>{};
  for (final PendingMention(:kind, :identifier) in composed.mentions) {
    if (lookups.length == maxMentionLookups) {
      break;
    }
    lookups.putIfAbsent(
      _lookupKey(kind, identifier),
      () => switch (kind) {
        MentionKind.user => resolver.resolveHandle(identifier),
        MentionKind.community => resolver.resolveCommunity(identifier),
      },
    );
  }
  final dids = await Future.wait(lookups.values, eagerError: true);
  final resolved = Map.fromIterables(lookups.keys, dids);

  final facets = [...?composed.facets];
  for (final PendingMention(:kind, :identifier, :index) in composed.mentions) {
    final did = resolved[_lookupKey(kind, identifier)];
    if (did == null) {
      continue;
    }
    if (!_didPattern.hasMatch(did)) {
      if (kDebugMode) {
        debugPrint(
          'resolveMentions: ${kind.name} lookup returned invalid DID $did',
        );
      }
      continue;
    }
    facets.add(
      RichTextFacet(
        index: index,
        features: [MentionFacetFeature(did: did)],
      ),
    );
  }
  facets.sort((a, b) => a.index.byteStart.compareTo(b.index.byteStart));
  final kept = facets.take(maxFacetsPerRecord).toList();

  return ComposedRichText._(
    content: composed.content,
    facets: kept.isEmpty ? null : kept,
    mentions: const [],
  );
}

/// The key [identifier] is looked up under: handles are case-insensitive (the
/// backend lowercases them), community identifiers are not
(MentionKind, String) _lookupKey(MentionKind kind, String identifier) =>
    switch (kind) {
      MentionKind.user => (kind, identifier.toLowerCase()),
      MentionKind.community => (kind, identifier),
    };

/// A structurally valid atproto DID
final _didPattern = RegExp(r'^did:[a-z]+:[a-zA-Z0-9._:%-]*[a-zA-Z0-9._-]$');

/// Trims [text], detects the bare http(s) URLs in it as link facets and finds
/// the @handle and !community mentions in it
///
/// Produces the canonical content and link facets the backend validates: the
/// facet and mention byte ranges are UTF-8 offsets into the trimmed
/// [ComposedRichText.content], so trimming must happen before any range is
/// measured. Its mentions are only candidates: the result must go through
/// [resolveMentions] before it is sent, or its mentions stay plain text.
ComposedRichText composeRichText(String text) {
  final content = text.trim();
  final offsets = Utf8Offsets(content);

  final urlCandidates = _urlCandidate.allMatches(content).toList();
  final facets = <RichTextFacet>[];
  for (final match in urlCandidates) {
    // Links past the backend's facet cap are left as plain text
    if (facets.length == maxFacetsPerRecord) {
      break;
    }
    final link = _acceptedLink(content, match.start, match.end);
    if (link == null) {
      continue;
    }
    final (:start, :end, :uri) = link;
    facets.add(
      RichTextFacet(
        index: ByteSlice(
          byteStart: offsets.byteOffsetOf(start),
          byteEnd: offsets.byteOffsetOf(end),
        ),
        features: [LinkFacetFeature(uri: uri)],
      ),
    );
  }

  return ComposedRichText._(
    content: content,
    facets: facets.isEmpty ? null : facets,
    mentions: _mentionsIn(content, offsets, urlCandidates),
  );
}

/// The mentions in [content], skipping any that overlap a URL candidate
/// (linked or not), so a sigil in a URL is never a mention
List<PendingMention> _mentionsIn(
  String content,
  Utf8Offsets offsets,
  List<RegExpMatch> urlCandidates,
) {
  final mentions = <PendingMention>[];
  // Candidates are in text order and never overlap, so one pass finds the
  // first candidate that ends after the current index
  var candidate = 0;
  // The run of identifier characters after the last sigil looked at, and
  // where it ends once trailing punctuation is trimmed. A later sigil inside
  // the run has the same run end, so each run is scanned once and detection
  // stays linear in the length of the content.
  var runEnd = 0;
  var trimmedRunEnd = 0;
  var index = 0;
  while (index < content.length) {
    final unit = content.codeUnitAt(index);
    if (unit != _atSign && unit != _exclamationMark) {
      index++;
      continue;
    }
    while (candidate < urlCandidates.length &&
        urlCandidates[candidate].end <= index) {
      candidate++;
    }
    if (index + 1 > runEnd) {
      runEnd = index + 1;
      while (runEnd < content.length &&
          _isMentionBodyUnit(content.codeUnitAt(runEnd))) {
        runEnd++;
      }
      // Sentence punctuation after a mention reads as prose, as after a URL
      trimmedRunEnd = runEnd;
      while (trimmedRunEnd > index + 1 &&
          _trailingPunctuation.contains(content[trimmedRunEnd - 1])) {
        trimmedRunEnd--;
      }
    }
    final mention = _mentionAt(
      content,
      index,
      math.max(index + 1, trimmedRunEnd),
    );
    if (mention == null ||
        (candidate < urlCandidates.length &&
            urlCandidates[candidate].start < mention.end)) {
      index++;
      continue;
    }
    mentions.add(
      PendingMention(
        kind: mention.kind,
        identifier: mention.identifier,
        index: ByteSlice(
          byteStart: offsets.byteOffsetOf(index),
          byteEnd: offsets.byteOffsetOf(mention.end),
        ),
      ),
    );
    index = mention.end;
  }
  return mentions;
}

/// The mention whose sigil is at [start] in [content] and whose identifier,
/// trimmed of trailing punctuation, ends at [end], or null when the sigil
/// there does not start a mention
({MentionKind kind, String identifier, int end})? _mentionAt(
  String content,
  int start,
  int end,
) {
  final isHandle = content.codeUnitAt(start) == _atSign;
  // Rejected before any copy or validation, so the work per sigil is bounded
  if (end - start - 1 >
          (isHandle ? _maxHandleLength : _maxCommunityAddressLength) ||
      !_startsAtWordBoundary(content, start, _wordContinuation) ||
      !_endsAtWordBoundary(content, end)) {
    return null;
  }
  final identifier = content.substring(start + 1, end);
  final kind = isHandle
      ? (_isValidHandle(identifier) ? MentionKind.user : null)
      : (_isValidCommunity(identifier) ? MentionKind.community : null);
  if (kind == null) {
    return null;
  }
  return (kind: kind, identifier: identifier, end: end);
}

/// Whether [unit] is one of the characters a mention's identifier is drawn
/// from: an ASCII letter or digit, `.`, `-` or `@`
bool _isMentionBodyUnit(int unit) =>
    (unit >= 0x61 && unit <= 0x7A) ||
    (unit >= 0x41 && unit <= 0x5A) ||
    (unit >= 0x30 && unit <= 0x39) ||
    unit == 0x2E ||
    unit == 0x2D ||
    unit == _atSign;

/// The longest handle, a DNS hostname
const _maxHandleLength = 253;

/// The longest community name
const _maxCommunityNameLength = 63;

/// The longest name@origin community address
const _maxCommunityAddressLength =
    _maxCommunityNameLength + 1 + _maxHandleLength;

/// A DNS hostname with at least one dot whose last label starts with a
/// letter, the atproto handle shape the AppView resolves
final _handlePattern = RegExp(
  r'^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]([a-zA-Z0-9-]*[a-zA-Z0-9])?$',
);

/// A community name: 1 to 63 letters, digits or inner hyphens
final _communityNamePattern = RegExp(
  r'^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$',
);

bool _isValidHandle(String identifier) =>
    identifier.length <= _maxHandleLength &&
    _handlePattern.hasMatch(identifier);

/// Whether [identifier] is a community name or a name@origin address whose
/// origin is a handle
bool _isValidCommunity(String identifier) {
  final at = identifier.indexOf('@');
  if (at == -1) {
    return _communityNamePattern.hasMatch(identifier);
  }
  return _communityNamePattern.hasMatch(identifier.substring(0, at)) &&
      _isValidHandle(identifier.substring(at + 1));
}

const _atSign = 0x40;
const _exclamationMark = 0x21;

/// An http(s) scheme, in any case, followed by everything up to the next
/// whitespace, angle bracket or backtick
final _urlCandidate = RegExp(r'https?://[^\s<>`]+', caseSensitive: false);

/// Characters that, directly before a scheme, make it part of a longer word
final _wordCharacter = RegExp(r'[\p{L}\p{N}_]', unicode: true);

/// The longest link URI the backend accepts once it has percent-encoded every
/// byte outside printable ASCII, mirroring its maxURILength
const _maxEncodedUriLength = 8192;

/// The UTF-16 span of the link within the candidate [start]..[end] of
/// [content] and the URI to emit for it, or null when the candidate is not a
/// link the backend would accept
({int start, int end, String uri})? _acceptedLink(
  String content,
  int start,
  int end,
) {
  if (!_startsAtWordBoundary(content, start, _wordCharacter)) {
    return null;
  }
  // Trailing punctuation is almost always sentence text, not part of the URL,
  // but a closing paren that balances the URL belongs to it (Foo_(bar)). The
  // URL is balanced when its depth is zero and it holds no `)` that closed
  // nothing; one scan finds both, and trimming a `)` only raises the depth.
  var depth = 0;
  var firstUnmatchedClose = end;
  for (var index = start; index < end; index++) {
    final unit = content.codeUnitAt(index);
    if (unit == _openParenthesis) {
      depth++;
    } else if (unit == _closeParenthesis) {
      depth--;
      if (depth < 0 && firstUnmatchedClose == end) {
        firstUnmatchedClose = index;
      }
    }
  }
  var trimmedEnd = end;
  while (trimmedEnd > start &&
      _trailingPunctuation.contains(content[trimmedEnd - 1])) {
    if (content.codeUnitAt(trimmedEnd - 1) == _closeParenthesis) {
      if (depth == 0 && firstUnmatchedClose >= trimmedEnd) {
        break;
      }
      depth++;
    }
    trimmedEnd--;
  }
  // The scheme is emitted lowercase; the rest of the URL stays as typed
  final typed = content.substring(start, trimmedEnd);
  final schemeEnd = typed.indexOf(':');
  final uri =
      typed.substring(0, schemeEnd).toLowerCase() + typed.substring(schemeEnd);
  if (!isAllowedWebUrl(uri) ||
      !_isPrintableAscii(_hostAndPortOf(uri)) ||
      _encodedLength(uri) > _maxEncodedUriLength) {
    return null;
  }
  return (start: start, end: trimmedEnd, uri: uri);
}

/// The host and port of the http(s) [uri]: its authority, which ends at the
/// first `/`, `?` or `#`, after the last `@`
///
/// The backend's encodeAuthority punycodes this part, and can reject the whole
/// post, only when it has a byte outside printable ASCII, so a URL is linked
/// only when this part is printable ASCII.
String _hostAndPortOf(String uri) {
  final authorityStart = uri.indexOf('://') + 3;
  final authorityEnd = uri.indexOf(RegExp('[/?#]'), authorityStart);
  final authority = uri.substring(
    authorityStart,
    authorityEnd == -1 ? uri.length : authorityEnd,
  );
  return authority.substring(authority.lastIndexOf('@') + 1);
}

/// Whether every character of [text] is printable ASCII (0x21..0x7E)
bool _isPrintableAscii(String text) =>
    text.codeUnits.every(_isPrintableAsciiUnit);

bool _isPrintableAsciiUnit(int unit) => unit >= 0x21 && unit <= 0x7E;

/// The length of [uri] after the backend percent-encodes each UTF-8 byte
/// outside printable ASCII into three characters
int _encodedLength(String uri) => utf8
    .encode(uri)
    .fold(0, (length, byte) => length + (_isPrintableAsciiUnit(byte) ? 1 : 3));

/// Characters trimmed from the end of a URL candidate
const _trailingPunctuation = {'.', ',', '!', '?', ';', ':', ')', '"', "'"};

const _openParenthesis = 0x28;
const _closeParenthesis = 0x29;

/// Whether the code point before [start] in [content], if any, does not match
/// [wordCharacter]
bool _startsAtWordBoundary(String content, int start, RegExp wordCharacter) {
  if (start == 0) {
    return true;
  }
  // Step back over a whole surrogate pair so astral letters are seen whole
  var previousStart = start - 1;
  if (previousStart > 0 &&
      _isLowSurrogate(content.codeUnitAt(previousStart)) &&
      _isHighSurrogate(content.codeUnitAt(previousStart - 1))) {
    previousStart--;
  }
  return !wordCharacter.hasMatch(content.substring(previousStart, start));
}

/// Whether the code point at [end] in [content], if any, neither is a word
/// character nor a combining mark that would extend the identifier's last
/// letter
bool _endsAtWordBoundary(String content, int end) {
  if (end == content.length) {
    return true;
  }
  // Take a whole surrogate pair so astral letters are seen whole
  var nextEnd = end + 1;
  if (nextEnd < content.length &&
      _isHighSurrogate(content.codeUnitAt(end)) &&
      _isLowSurrogate(content.codeUnitAt(nextEnd))) {
    nextEnd++;
  }
  return !_wordContinuation.hasMatch(content.substring(end, nextEnd));
}

/// Characters that, directly before or after a mention, make it part of a
/// longer word
final _wordContinuation = RegExp(r'[\p{L}\p{M}\p{N}_]', unicode: true);

bool _isHighSurrogate(int codeUnit) => codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

bool _isLowSurrogate(int codeUnit) => codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;
