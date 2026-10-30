import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../models/facet.dart';
import 'url_policy.dart';
import 'utf8_offsets.dart';

/// Content ready to send, with the link facets and mentions detected in it
class ComposedRichText {
  const ComposedRichText._({
    required this.content,
    this.facets,
    required this.mentions,
    this._formattingFacets = const [],
    List<RichTextFacet>? separateFacets,
  }) : _separateFacets = separateFacets ?? facets ?? const [];

  /// [formattingFacets] (each kept) and [separateFacets] (truncated, in byte
  /// order, to the slots of [maxFacetsPerRecord] the formatting facets
  /// leave) merged and sorted by byte start
  factory ComposedRichText._merged({
    required String content,
    required List<RichTextFacet> formattingFacets,
    required List<RichTextFacet> separateFacets,
    required List<PendingMention> mentions,
  }) {
    final kept = (separateFacets..sort(_byByteStart))
        .take(math.max(0, maxFacetsPerRecord - formattingFacets.length))
        .toList();
    final facets = [...formattingFacets, ...kept]..sort(_byByteStart);
    return ComposedRichText._(
      content: content,
      facets: facets.isEmpty ? null : facets,
      mentions: mentions,
      formattingFacets: formattingFacets,
      separateFacets: kept,
    );
  }

  /// Canonical content to send
  final String content;

  /// Facets over [content], or null when there are none
  final List<RichTextFacet>? facets;

  /// Mentions detected in [content], not yet resolved to DIDs
  final List<PendingMention> mentions;

  /// The formatting facets among [facets], with any link or mention grouped
  /// into them; never truncated by the facet cap
  final List<RichTextFacet> _formattingFacets;

  /// The link and mention facets among [facets] that stand alone
  final List<RichTextFacet> _separateFacets;
}

/// Orders facets by byte start, then byte end
int _byByteStart(RichTextFacet a, RichTextFacet b) =>
    a.index.byteStart != b.index.byteStart
    ? a.index.byteStart.compareTo(b.index.byteStart)
    : a.index.byteEnd.compareTo(b.index.byteEnd);

/// [formattingFacets] with [facet]'s single link or mention feature grouped
/// into the formatting facet over exactly the same byte range, or null when
/// no formatting facet has that range
///
/// A link or mention comes first in the lexicon's union order, and a
/// formatting facet holds neither, so the feature goes in front.
List<RichTextFacet>? _groupedInto(
  List<RichTextFacet> formattingFacets,
  RichTextFacet facet,
) {
  final index = formattingFacets.indexWhere(
    (formatting) =>
        formatting.index.byteStart == facet.index.byteStart &&
        formatting.index.byteEnd == facet.index.byteEnd,
  );
  if (index == -1) {
    return null;
  }
  final formatting = formattingFacets[index];
  return [...formattingFacets]
    ..[index] = RichTextFacet(
      index: formatting.index,
      features: [...facet.features, ...formatting.features],
    );
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
/// A resolved mention whose byte range exactly equals a formatting facet's
/// joins that facet. Every formatting facet is kept; separate link and
/// mention facets fill only the slots of [maxFacetsPerRecord] the formatting
/// facets leave, in byte order.
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

  var formattingFacets = composed._formattingFacets;
  final separateFacets = [...composed._separateFacets];
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
    final mention = RichTextFacet(
      index: index,
      features: [MentionFacetFeature(did: did)],
    );
    final grouped = _groupedInto(formattingFacets, mention);
    if (grouped != null) {
      formattingFacets = grouped;
    } else {
      separateFacets.add(mention);
    }
  }

  return ComposedRichText._merged(
    content: composed.content,
    formattingFacets: formattingFacets,
    separateFacets: separateFacets,
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

/// What a detected span of text is
enum RichTextSpanKind { link, mention }

/// A link or mention detected in text, as UTF-16 offsets into that text
typedef DetectedRichTextSpan = ({RichTextSpanKind kind, int start, int end});

/// The links and mentions [composeRichText] would detect in [text], in text
/// order, as UTF-16 offsets into [text]
///
/// Synchronous and lookup-free: a mention is detected by its shape alone. A
/// link or mention that overlaps any of [excludedRanges] (UTF-16 offsets into
/// [text]) is dropped whole.
List<DetectedRichTextSpan> detectRichTextSpans(
  String text, {
  List<TextRange> excludedRanges = const [],
}) {
  final (:links, :mentions) = _detect(
    text,
    excludedRanges,
    0,
    linkLimit: maxFacetsPerRecord,
  );
  return [
    for (final link in links)
      (kind: RichTextSpanKind.link, start: link.start, end: link.end),
    for (final mention in mentions)
      (kind: RichTextSpanKind.mention, start: mention.start, end: mention.end),
  ]..sort((a, b) => a.start.compareTo(b.start));
}

/// A structurally valid atproto DID
final _didPattern = RegExp(r'^did:[a-z]+:[a-zA-Z0-9._:%-]*[a-zA-Z0-9._-]$');

/// Whether [did] is a structurally valid atproto DID, the check a mention
/// facet's DID must pass to be submitted.
bool isValidDid(String did) => _didPattern.hasMatch(did);

/// Trims [text], detects the bare http(s) URLs in it as link facets and finds
/// the @handle and !community mentions in it
///
/// Produces the canonical content and link facets the backend validates: the
/// facet and mention byte ranges are UTF-8 offsets into the trimmed
/// [ComposedRichText.content], so trimming must happen before any range is
/// measured. Its mentions are only candidates: the result must go through
/// [resolveMentions] before it is sent, or its mentions stay plain text.
///
/// No link facet or mention overlaps any of [excludedRanges], which are
/// UTF-16 offsets into the untrimmed [text].
ComposedRichText composeRichText(
  String text, {
  List<TextRange> excludedRanges = const [],
}) {
  final content = text.trim();
  final leadingTrim = text.length - text.trimLeft().length;
  final offsets = Utf8Offsets(content);
  final (:links, :mentions) = _detect(
    content,
    excludedRanges,
    leadingTrim,
    linkLimit: maxFacetsPerRecord,
  );

  ByteSlice slice(int start, int end) => ByteSlice(
    byteStart: offsets.byteOffsetOf(start),
    byteEnd: offsets.byteOffsetOf(end),
  );

  return ComposedRichText._(
    content: content,
    facets: links.isEmpty
        ? null
        : [
            for (final (:start, :end, :uri) in links)
              RichTextFacet(
                index: slice(start, end),
                features: [LinkFacetFeature(uri: uri)],
              ),
          ],
    mentions: [
      for (final (:kind, :identifier, :start, :end) in mentions)
        PendingMention(
          kind: kind,
          identifier: identifier,
          index: slice(start, end),
        ),
    ],
  );
}

/// [content] with its link facets detected and merged with
/// [formattingFacets], and its mentions found, ready for [resolveMentions]
///
/// [content] is already trimmed, [formattingFacets] are UTF-8 byte ranges
/// into it and [excludedRanges] are UTF-16 offsets into it; no link or
/// mention overlapping an excluded range is detected. A formatting facet
/// carrying a link or mention is a kept loaded one, and no link or mention
/// overlapping its byte range is detected. A link whose byte range
/// exactly equals a formatting facet's joins that facet. Every formatting
/// facet is kept; separate link and mention facets fill only the slots of
/// [maxFacetsPerRecord] the formatting facets leave, in byte order.
ComposedRichText composeFormattedRichText(
  String content, {
  List<RichTextFacet> formattingFacets = const [],
  List<TextRange> excludedRanges = const [],
}) {
  final offsets = Utf8Offsets(content);
  // Uncapped: a link past the first 200 may still group into a formatting
  // facet, and the cap is applied once grouping is known
  final (:links, :mentions) = _detect(content, excludedRanges, 0);

  ByteSlice slice(int start, int end) => ByteSlice(
    byteStart: offsets.byteOffsetOf(start),
    byteEnd: offsets.byteOffsetOf(end),
  );

  // A formatting facet carrying a link or mention is a kept loaded one: its
  // text is not detected again
  final loaded = [
    for (final facet in formattingFacets)
      if (facet.features.any(
        (feature) =>
            feature is LinkFacetFeature || feature is MentionFacetFeature,
      ))
        facet.index,
  ];
  bool overlapsLoaded(ByteSlice index) => loaded.any(
    (kept) => kept.byteStart < index.byteEnd && index.byteStart < kept.byteEnd,
  );

  var grouped = formattingFacets;
  final separateFacets = <RichTextFacet>[];
  for (final (:start, :end, :uri) in links) {
    final index = slice(start, end);
    if (overlapsLoaded(index)) {
      continue;
    }
    final link = RichTextFacet(
      index: index,
      features: [LinkFacetFeature(uri: uri)],
    );
    final withLink = _groupedInto(grouped, link);
    if (withLink != null) {
      grouped = withLink;
    } else {
      separateFacets.add(link);
    }
  }

  return ComposedRichText._merged(
    content: content,
    formattingFacets: grouped,
    separateFacets: separateFacets,
    mentions: [
      for (final (:kind, :identifier, :start, :end) in mentions)
        if (slice(start, end) case final index when !overlapsLoaded(index))
          PendingMention(kind: kind, identifier: identifier, index: index),
    ],
  );
}

/// The links and mentions in [content], each in text order with UTF-16
/// offsets, the detection rules [composeRichText] and [detectRichTextSpans]
/// share
///
/// A link or mention overlapping any of [excludedRanges] is dropped whole;
/// the ranges are offsets into a text in which [content] starts at
/// [excludedRangesOffset]. URL candidates are found over all of [content],
/// so a sigil inside an excluded URL is still not a mention. Links past
/// [linkLimit], when given, are left as plain text.
({
  List<({int start, int end, String uri})> links,
  List<_DetectedMention> mentions,
})
_detect(
  String content,
  List<TextRange> excludedRanges,
  int excludedRangesOffset, {
  int? linkLimit,
}) {
  // Compared without building shifted TextRanges, whose constructor asserts
  // offsets >= -1
  bool isExcluded(int start, int end) => excludedRanges.any(
    (range) =>
        range.start - excludedRangesOffset < end &&
        start < range.end - excludedRangesOffset,
  );

  final urlCandidates = _urlCandidate.allMatches(content).toList();
  final links = <({int start, int end, String uri})>[];
  for (final match in urlCandidates) {
    if (links.length == linkLimit) {
      break;
    }
    final link = _acceptedLink(content, match.start, match.end);
    if (link != null && !isExcluded(link.start, link.end)) {
      links.add(link);
    }
  }

  return (
    links: links,
    mentions: [
      for (final mention in _mentionsIn(content, urlCandidates))
        if (!isExcluded(mention.start, mention.end)) mention,
    ],
  );
}

typedef _DetectedMention = ({
  MentionKind kind,
  String identifier,
  int start,
  int end,
});

/// The mentions in [content], skipping any that overlap a URL candidate
/// (linked or not), so a sigil in a URL is never a mention
List<_DetectedMention> _mentionsIn(
  String content,
  List<RegExpMatch> urlCandidates,
) {
  final mentions = <_DetectedMention>[];
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
    mentions.add((
      kind: mention.kind,
      identifier: mention.identifier,
      start: index,
      end: mention.end,
    ));
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
